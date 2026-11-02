-- Termini, privacy e consensi.
-- Registro dei consensi e delle prese visione (solo aggiunte: lo storico non si modifica),
-- consenso separato per le notifiche degli annunci, dati del venditore per i testi ai clienti,
-- chiusura dell'account dall'app e pulizia dei clienti importati che non accettano l'invito.

create table public.consensi (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('termini','informativa_cliente','annunci','import_clienti')),
  versione text not null check (length(versione) between 1 and 20),
  valore boolean not null default true,
  negozio_id uuid references public.negozi(id) on delete cascade,
  dettaglio text check (length(dettaglio) <= 200),
  created_at timestamptz not null default now()
);
create index on public.consensi (user_id, tipo, created_at desc);
create index on public.consensi (negozio_id);
alter table public.consensi enable row level security;
create policy consensi_propri_lettura on public.consensi for select to authenticated using (user_id = (select auth.uid()));
create policy consensi_propri_aggiunta on public.consensi for insert to authenticated with check (user_id = (select auth.uid()));
-- il titolare e il manager vedono le prese visione e i consensi dei clienti del proprio negozio
create policy consensi_gestore_lettura on public.consensi for select to authenticated using (negozio_id is not null and public.e_gestore(negozio_id));

-- Consenso del cliente a ricevere gli annunci come notifica: spento finché non lo attiva lui
alter table public.clienti add column if not exists annunci_ok boolean not null default false;

create or replace function public.imposta_annunci(p_negozio uuid, p_valore boolean, p_versione text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  update public.clienti set annunci_ok = coalesce(p_valore, false) where negozio_id = p_negozio and user_id = v_uid;
  if not found then raise exception 'Non sei cliente di questo produttore'; end if;
  insert into public.consensi (user_id, tipo, versione, valore, negozio_id) values (v_uid, 'annunci', left(coalesce(p_versione, '?'), 20), coalesce(p_valore, false), p_negozio);
  return coalesce(p_valore, false);
end $$;

create or replace function public.notifica_annuncio() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
  select c.user_id, 'vendite', new.emoji || ' ' || new.titolo, left(coalesce(new.testo, ''), 180), '#bacheca', 'ann:' || new.id
  from public.clienti c
  where c.negozio_id = new.negozio_id and c.stato = 'approvato' and c.user_id is not null and c.annunci_ok
  on conflict (destinatario, chiave) do nothing;
  return new;
end $$;

-- Dati del venditore mostrati nelle condizioni e nell'informativa ai clienti
alter table public.negozi add column if not exists dati_legali jsonb not null default '{}'::jsonb;

create or replace function public.vetrina_pubblica(p_slug text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', n.id, 'nome', n.nome, 'descrizione', n.descrizione, 'attivo', n.attivo, 'note_consegna', n.note_consegna,
    'vetrina', n.vetrina, 'copertina', n.copertina_url, 'galleria', to_jsonb(n.galleria),
    'venditore', n.dati_legali,
    'formati', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'litri', f.litri, 'descrizione', f.descrizione, 'foto', f.foto_url,
                          'prezzo', case when coalesce((n.vetrina ->> 'prezzi_pubblici')::boolean, false) then f.prezzo end) order by f.ordine, f.litri)
                        from public.formati f where f.negozio_id = n.id and f.attivo), '[]'::jsonb),
    'disponibili', case when coalesce((n.vetrina ->> 'mostra_disponibilita')::boolean, true) and n.litri_in_vendita is not null
      then n.litri_in_vendita - coalesce((select sum(r.litri * r.quantita) from public.ordine_righe r join public.ordini o on o.id = r.ordine_id
                                          where o.negozio_id = n.id and o.stato <> 'annullato'), 0) end)
  from public.negozi n where n.slug = lower(p_slug);
$$;

-- Chiusura dell'account e pulizia dei clienti importati non registrati entro 12 mesi:
-- le fa la Edge Function "account" (supabase/functions/account) con i permessi del server.
revoke all on function public.imposta_annunci(uuid, boolean, text) from public, anon;
grant execute on function public.imposta_annunci(uuid, boolean, text) to authenticated;

-- ===== Solo su Supabase (pg_cron + pg_net) =====
-- select cron.schedule('uliveto-pulizia-importati', '17 3 * * 1', $$
--   select net.http_post(url := 'https://<progetto>.supabase.co/functions/v1/account',
--     headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select cron_secret from public.config_push where id = 1)),
--     body := '{"azione":"pulizia"}'::jsonb, timeout_milliseconds := 25000) $$);
