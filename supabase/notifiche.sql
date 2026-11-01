-- Notifiche push: promemoria dei lavori, preferenze, iscrizioni dei dispositivi,
-- coda delle notifiche alimentata da trigger e da controlli giornalieri.
-- L'invio vero e proprio lo fa la Edge Function "notifiche" (supabase/functions/notifiche).

-- Richiede le estensioni pg_net e pg_cron (create extension if not exists pg_net; pg_cron;)

-- ===== Promemoria (lavori da fare) =====
create table public.promemoria (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,          -- titolare dell'uliveto
  creato_da uuid default auth.uid() references auth.users(id) on delete set null,
  data date not null,
  tipo text not null check (tipo in ('potatura','concimazione','trattamento','irrigazione','lavorazione terreno','sfalcio','altro')),
  titolo text not null,
  prodotto text,
  appezzamento_id uuid references public.appezzamenti(id) on delete set null,
  note text,
  fatto boolean not null default false,
  fatto_at timestamptz,
  intervento_id uuid references public.interventi(id) on delete set null,
  notificato_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.promemoria (user_id, fatto, data);
create index on public.promemoria (appezzamento_id);
create index on public.promemoria (intervento_id);
create index on public.promemoria (creato_da);
alter table public.promemoria enable row level security;
create policy promemoria_accesso on public.promemoria for all to authenticated
  using (public.ruolo_su(user_id) in ('owner','manager','agricoltore'))
  with check (public.ruolo_su(user_id) in ('owner','manager','agricoltore'));

-- ===== Preferenze di notifica (per persona) =====
create table public.preferenze_notifiche (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  meteo boolean not null default true,
  promemoria boolean not null default true,
  vendite boolean not null default true,
  squadra boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.preferenze_notifiche enable row level security;
create policy pref_proprie on public.preferenze_notifiche for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ===== Dispositivi iscritti alle notifiche =====
create table public.push_iscrizioni (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  dispositivo text,
  created_at timestamptz not null default now(),
  ultimo_invio timestamptz
);
create index on public.push_iscrizioni (user_id);
alter table public.push_iscrizioni enable row level security;
create policy push_proprie_lettura on public.push_iscrizioni for select to authenticated using (user_id = (select auth.uid()));
create policy push_proprie_elimina on public.push_iscrizioni for delete to authenticated using (user_id = (select auth.uid()));

-- Registra (o sposta su questo utente) il dispositivo: un telefono riceve le notifiche di chi vi è collegato
create or replace function public.registra_push(p_endpoint text, p_p256dh text, p_auth text, p_dispositivo text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
  if p_endpoint !~ '^https://' then raise exception 'Endpoint non valido'; end if;
  insert into public.push_iscrizioni (user_id, endpoint, p256dh, auth, dispositivo) values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_dispositivo, 120))
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
    dispositivo = excluded.dispositivo, created_at = now();
end $$;

-- ===== Configurazione privata (chiavi VAPID generate dalla funzione, segreto per i job) =====
create table public.config_push (
  id int primary key default 1 check (id = 1),
  vapid_public text,
  vapid_private text,
  subject text not null default 'https://laurentimrc.github.io/Oil-management-system/',
  cron_secret text not null default encode(extensions.gen_random_bytes(24), 'hex')
);
insert into public.config_push (id) values (1);
alter table public.config_push enable row level security;   -- nessuna policy: leggibile solo lato server

create or replace function public.chiave_push_pubblica() returns text
language sql stable security definer set search_path = '' as $$ select vapid_public from public.config_push where id = 1 $$;

-- ===== Coda delle notifiche =====
create table public.coda_notifiche (
  id bigint generated always as identity primary key,
  destinatario uuid not null references auth.users(id) on delete cascade,
  categoria text not null check (categoria in ('meteo','promemoria','vendite','squadra','prova')),
  titolo text not null,
  testo text,
  url text,
  chiave text not null default gen_random_uuid()::text,
  creata_at timestamptz not null default now(),
  inviata_at timestamptz,
  esito text,
  unique (destinatario, chiave)
);
create index on public.coda_notifiche (inviata_at) where inviata_at is null;
alter table public.coda_notifiche enable row level security;  -- nessuna policy: solo lato server

-- Accoda una notifica al titolare e ai collaboratori attivi con i ruoli indicati (escluso chi ha fatto l'azione)
create or replace function public.accoda(p_owner uuid, p_ruoli text[], p_categoria text, p_titolo text, p_testo text, p_url text, p_chiave text, p_escludi uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
  select m.uid, p_categoria, p_titolo, p_testo, p_url, coalesce(p_chiave, gen_random_uuid()::text)
  from (select p_owner as uid
        union
        select c.user_id from public.collaboratori c
        where c.owner_id = p_owner and c.stato = 'attivo' and c.user_id is not null and c.ruolo = any (p_ruoli)) m
  where m.uid is distinct from p_escludi
  on conflict (destinatario, chiave) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- ===== Trigger: eventi da notificare subito =====
create or replace function public.notifica_nuovo_cliente() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from public.negozi where id = new.negozio_id;
  perform public.accoda(v_owner, array['manager'], 'vendite', '🙋 Nuova richiesta di accesso',
    new.nome || ' (' || new.comune || ') vuole prenotare l''olio', '#tab=vendite', 'cliente:' || new.id, null);
  return new;
end $$;
create trigger notifica_nuovo_cliente after insert on public.clienti for each row execute function public.notifica_nuovo_cliente();

create or replace function public.notifica_nuovo_ordine() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_nome text; v_litri numeric;
begin
  select owner_id into v_owner from public.negozi where id = new.negozio_id;
  select nome into v_nome from public.clienti where id = new.cliente_id;
  select coalesce(sum(litri * quantita), 0) into v_litri from public.ordine_righe where ordine_id = new.id;
  perform public.accoda(v_owner, array['manager'], 'vendite', '📦 Nuovo ordine',
    coalesce(v_nome, 'Un cliente') || ' ha prenotato ' || replace(trim_scale(v_litri)::text, '.', ',') || ' L · consegna a ' || new.comune, '#tab=vendite', 'ordine:' || new.id, null);
  return new;
end $$;
-- a fine transazione, quando le righe dell'ordine esistono già
create constraint trigger notifica_nuovo_ordine after insert on public.ordini deferrable initially deferred
  for each row execute function public.notifica_nuovo_ordine();

create or replace function public.notifica_attivita_squadra() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_chi text; v_testo text;
begin
  if auth.uid() is null or auth.uid() = new.user_id then return new; end if;
  select coalesce(nullif(c.nome, ''), split_part(c.email, '@', 1)) into v_chi
    from public.collaboratori c where c.owner_id = new.user_id and c.user_id = auth.uid() limit 1;
  if tg_table_name = 'interventi' then
    v_testo := coalesce(v_chi, 'Un collaboratore') || ': ' || new.tipo || coalesce(' — ' || nullif(new.descrizione, ''), '');
    perform public.accoda(new.user_id, array[]::text[], 'squadra', '🛠️ Lavoro registrato', v_testo, '#tab=lavori', 'int:' || new.id, null);
  else
    v_testo := coalesce(v_chi, 'Un collaboratore') || ' ha registrato ' || replace(trim_scale(new.kg_olive)::text, '.', ',') || ' kg di olive';
    perform public.accoda(new.user_id, array[]::text[], 'squadra', '🧺 Raccolta registrata', v_testo, '#tab=raccolta', 'racc:' || new.id, null);
  end if;
  return new;
end $$;
create trigger notifica_attivita_squadra after insert on public.interventi for each row execute function public.notifica_attivita_squadra();
create trigger notifica_attivita_squadra after insert on public.raccolte for each row execute function public.notifica_attivita_squadra();

-- ===== Controllo giornaliero dei promemoria =====
create or replace function public.prepara_promemoria() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; v_oggi date := (now() at time zone 'Europe/Rome')::date; n int := 0; v_dove text;
begin
  for r in select * from public.promemoria where not fatto and notificato_at is null and data <= v_oggi loop
    select ' · ' || nome into v_dove from public.appezzamenti where id = r.appezzamento_id;
    n := n + public.accoda(r.user_id, array['manager','agricoltore'], 'promemoria',
      case when r.data < v_oggi then '⏰ Lavoro in ritardo' else '📌 Oggi da fare' end,
      r.titolo || coalesce(v_dove, ''), '#tab=lavori', 'prom:' || r.id, null);
    update public.promemoria set notificato_at = now() where id = r.id;
  end loop;
  return n;
end $$;

-- Luoghi su cui controllare il meteo: appezzamenti localizzati o baricentro delle loro piante
create or replace function public.luoghi_meteo()
returns table (owner_id uuid, luogo text, lat double precision, lng double precision)
language sql stable security definer set search_path = '' as $$
  select a.user_id, a.nome, coalesce(a.lat, avg(p.lat)), coalesce(a.lng, avg(p.lng))
  from public.appezzamenti a left join public.piante p on p.appezzamento_id = a.id and p.lat is not null
  group by a.id
  having coalesce(a.lat, avg(p.lat)) is not null
  union all
  select p.user_id, 'Uliveto', avg(p.lat), avg(p.lng)
  from public.piante p where p.appezzamento_id is null and p.lat is not null
  group by p.user_id;
$$;

-- Permessi sulle funzioni
revoke all on function public.registra_push(text,text,text,text), public.chiave_push_pubblica(), public.accoda(uuid,text[],text,text,text,text,text,uuid),
  public.prepara_promemoria(), public.luoghi_meteo(), public.notifica_nuovo_cliente(), public.notifica_nuovo_ordine(), public.notifica_attivita_squadra()
  from public, anon, authenticated;
grant execute on function public.registra_push(text,text,text,text), public.chiave_push_pubblica() to authenticated;
grant execute on function public.accoda(uuid,text[],text,text,text,text,text,uuid), public.luoghi_meteo(), public.prepara_promemoria() to service_role;
