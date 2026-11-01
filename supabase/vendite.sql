-- Vendita olio: negozio del gestore, clienti autorizzati, ordini con consegna.
-- I clienti non scrivono mai direttamente nelle tabelle: passano dalle funzioni
-- "security definer" qui sotto, che controllano autorizzazione e disponibilità.

create table public.negozi (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() unique references auth.users(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,40}$'),
  nome text not null,
  descrizione text,
  note_consegna text,
  litri_in_vendita numeric check (litri_in_vendita >= 0),
  attivo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.formati (
  id uuid primary key default gen_random_uuid(),
  negozio_id uuid not null references public.negozi(id) on delete cascade,
  nome text not null,
  litri numeric not null check (litri > 0),
  prezzo numeric check (prezzo >= 0),          -- indicativo: il prezzo finale si decide sull'ordine
  attivo boolean not null default true,
  ordine int not null default 0,
  created_at timestamptz not null default now()
);

create table public.clienti (
  id uuid primary key default gen_random_uuid(),
  negozio_id uuid not null references public.negozi(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  nome text not null,
  telefono text,
  indirizzo text not null,
  comune text not null,
  cap text,
  provincia text,
  note_indirizzo text,
  stato text not null default 'in_attesa' check (stato in ('in_attesa','approvato','rifiutato','bloccato')),
  privacy_at timestamptz,
  created_at timestamptz not null default now(),
  unique (negozio_id, user_id)
);

create table public.ordini (
  id uuid primary key default gen_random_uuid(),
  negozio_id uuid not null references public.negozi(id) on delete cascade,
  cliente_id uuid not null references public.clienti(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  stato text not null default 'richiesta' check (stato in ('richiesta','confermato','in_consegna','consegnato','annullato')),
  indirizzo text not null,
  comune text not null,
  cap text,
  provincia text,
  note_indirizzo text,
  data_preferita date,
  note text,
  spese_consegna numeric check (spese_consegna >= 0),
  totale numeric check (totale >= 0),
  nota_gestore text,
  movimento_id uuid references public.movimenti(id) on delete set null,
  created_at timestamptz not null default now(),
  aggiornato_at timestamptz not null default now()
);

create table public.ordine_righe (
  id uuid primary key default gen_random_uuid(),
  ordine_id uuid not null references public.ordini(id) on delete cascade,
  formato_id uuid references public.formati(id) on delete set null,
  nome text not null,
  litri numeric not null,
  quantita int not null check (quantita > 0 and quantita <= 200),
  prezzo_unitario numeric check (prezzo_unitario >= 0)
);

create index on public.formati (negozio_id);
create index on public.clienti (negozio_id, stato);
create index on public.clienti (user_id);
create index on public.ordini (negozio_id, stato);
create index on public.ordini (user_id);
create index on public.ordini (cliente_id);
create index on public.ordini (movimento_id);
create index on public.ordine_righe (ordine_id);
create index on public.ordine_righe (formato_id);

-- Funzioni di supporto per le policy (evitano ricorsioni tra tabelle)
create or replace function public.e_gestore(p_negozio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.negozi n where n.id = p_negozio and n.owner_id = (select auth.uid()));
$$;
create or replace function public.e_cliente_approvato(p_negozio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.clienti c where c.negozio_id = p_negozio and c.user_id = (select auth.uid()) and c.stato = 'approvato');
$$;

alter table public.negozi enable row level security;
alter table public.formati enable row level security;
alter table public.clienti enable row level security;
alter table public.ordini enable row level security;
alter table public.ordine_righe enable row level security;

-- Negozi: il gestore fa tutto sul suo; il cliente approvato lo legge
create policy negozi_gestore on public.negozi for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy negozi_cliente_lettura on public.negozi for select to authenticated
  using (public.e_cliente_approvato(id));

-- Formati: gestore tutto; cliente approvato legge
create policy formati_gestore on public.formati for all to authenticated
  using (public.e_gestore(negozio_id)) with check (public.e_gestore(negozio_id));
create policy formati_cliente_lettura on public.formati for select to authenticated
  using (public.e_cliente_approvato(negozio_id));

-- Clienti: il gestore legge e cambia lo stato; il cliente legge solo la propria scheda
create policy clienti_gestore_lettura on public.clienti for select to authenticated using (public.e_gestore(negozio_id));
create policy clienti_gestore_modifica on public.clienti for update to authenticated
  using (public.e_gestore(negozio_id)) with check (public.e_gestore(negozio_id));
create policy clienti_gestore_elimina on public.clienti for delete to authenticated using (public.e_gestore(negozio_id));
create policy clienti_propri on public.clienti for select to authenticated using (user_id = (select auth.uid()));

-- Ordini e righe: il gestore legge e aggiorna; il cliente legge i propri
create policy ordini_gestore_lettura on public.ordini for select to authenticated using (public.e_gestore(negozio_id));
create policy ordini_gestore_modifica on public.ordini for update to authenticated
  using (public.e_gestore(negozio_id)) with check (public.e_gestore(negozio_id));
create policy ordini_propri on public.ordini for select to authenticated using (user_id = (select auth.uid()));

create policy righe_gestore_lettura on public.ordine_righe for select to authenticated
  using (exists (select 1 from public.ordini o where o.id = ordine_id and public.e_gestore(o.negozio_id)));
create policy righe_gestore_modifica on public.ordine_righe for update to authenticated
  using (exists (select 1 from public.ordini o where o.id = ordine_id and public.e_gestore(o.negozio_id)))
  with check (exists (select 1 from public.ordini o where o.id = ordine_id and public.e_gestore(o.negozio_id)));
create policy righe_proprie on public.ordine_righe for select to authenticated
  using (exists (select 1 from public.ordini o where o.id = ordine_id and o.user_id = (select auth.uid())));

-- ===== Funzioni chiamate dall'app =====

-- Nome del negozio dal link pubblico (anche prima del login)
create or replace function public.negozio_pubblico(p_slug text)
returns table (id uuid, nome text, descrizione text, attivo boolean)
language sql stable security definer set search_path = '' as $$
  select n.id, n.nome, n.descrizione, n.attivo from public.negozi n where n.slug = lower(p_slug);
$$;

-- Litri ancora prenotabili (null = disponibilità non indicata dal gestore)
create or replace function public.disponibilita(p_negozio uuid) returns numeric
language plpgsql stable security definer set search_path = '' as $$
declare v numeric;
begin
  if not (public.e_gestore(p_negozio) or public.e_cliente_approvato(p_negozio)) then
    raise exception 'Non autorizzato';
  end if;
  select n.litri_in_vendita into v from public.negozi n where n.id = p_negozio;
  if v is null then return null; end if;
  return v - coalesce((select sum(r.litri * r.quantita) from public.ordine_righe r join public.ordini o on o.id = r.ordine_id
                       where o.negozio_id = p_negozio and o.stato <> 'annullato'), 0);
end $$;

-- Il cliente chiede l'accesso (o aggiorna i propri recapiti); lo stato lo decide solo il gestore
create or replace function public.richiedi_accesso(p_negozio uuid, p_nome text, p_telefono text, p_indirizzo text,
  p_comune text, p_cap text, p_provincia text, p_note_indirizzo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  if not exists (select 1 from public.negozi where id = p_negozio and attivo) then raise exception 'Negozio non disponibile'; end if;
  if coalesce(trim(p_nome),'') = '' or coalesce(trim(p_indirizzo),'') = '' or coalesce(trim(p_comune),'') = '' then
    raise exception 'Nome, indirizzo e comune sono obbligatori';
  end if;
  insert into public.clienti (negozio_id, user_id, email, nome, telefono, indirizzo, comune, cap, provincia, note_indirizzo, privacy_at)
  values (p_negozio, v_uid, auth.jwt() ->> 'email', trim(p_nome), p_telefono, trim(p_indirizzo), trim(p_comune), p_cap, upper(p_provincia), p_note_indirizzo, now())
  on conflict (negozio_id, user_id) do update set
    nome = excluded.nome, telefono = excluded.telefono, indirizzo = excluded.indirizzo, comune = excluded.comune,
    cap = excluded.cap, provincia = excluded.provincia, note_indirizzo = excluded.note_indirizzo
  returning id into v_id;
  return v_id;
end $$;

-- Il cliente approvato crea un ordine. p_righe = [{"formato_id": "...", "quantita": 2}, ...]
create or replace function public.crea_ordine(p_negozio uuid, p_righe jsonb, p_indirizzo text, p_comune text,
  p_cap text, p_provincia text, p_note_indirizzo text, p_data date, p_note text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_cliente uuid; v_ordine uuid; v_litri numeric := 0; v_disp numeric; r jsonb; f record; q int;
begin
  select c.id into v_cliente from public.clienti c where c.negozio_id = p_negozio and c.user_id = v_uid and c.stato = 'approvato';
  if v_cliente is null then raise exception 'Non sei ancora autorizzato a ordinare'; end if;
  if not exists (select 1 from public.negozi where id = p_negozio and attivo) then raise exception 'Le prenotazioni sono chiuse'; end if;
  if jsonb_typeof(p_righe) <> 'array' or jsonb_array_length(p_righe) = 0 then raise exception 'Ordine vuoto'; end if;
  if coalesce(trim(p_indirizzo),'') = '' or coalesce(trim(p_comune),'') = '' then raise exception 'Indirizzo di consegna obbligatorio'; end if;
  if p_data is not null and p_data < current_date then raise exception 'La data di consegna è già passata'; end if;

  insert into public.ordini (negozio_id, cliente_id, user_id, indirizzo, comune, cap, provincia, note_indirizzo, data_preferita, note)
  values (p_negozio, v_cliente, v_uid, trim(p_indirizzo), trim(p_comune), p_cap, upper(p_provincia), p_note_indirizzo, p_data, p_note)
  returning id into v_ordine;

  for r in select * from jsonb_array_elements(p_righe) loop
    q := (r ->> 'quantita')::int;
    if q is null or q <= 0 or q > 200 then raise exception 'Quantità non valida'; end if;
    select fo.* into f from public.formati fo where fo.id = (r ->> 'formato_id')::uuid and fo.negozio_id = p_negozio and fo.attivo;
    if f.id is null then raise exception 'Formato non disponibile'; end if;
    insert into public.ordine_righe (ordine_id, formato_id, nome, litri, quantita) values (v_ordine, f.id, f.nome, f.litri, q);
    v_litri := v_litri + f.litri * q;
  end loop;

  v_disp := public.disponibilita(p_negozio);   -- già include questo ordine
  if v_disp is not null and v_disp < 0 then
    raise exception 'Disponibilità insufficiente: restano % litri', round(v_disp + v_litri, 1);
  end if;
  return v_ordine;
end $$;

-- Il cliente può annullare solo finché l'ordine non è confermato
create or replace function public.annulla_ordine(p_ordine uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.ordini set stato = 'annullato', aggiornato_at = now()
  where id = p_ordine and user_id = auth.uid() and stato = 'richiesta';
  if not found then raise exception 'Ordine non annullabile'; end if;
end $$;

revoke all on function public.e_gestore(uuid), public.e_cliente_approvato(uuid), public.negozio_pubblico(text), public.disponibilita(uuid),
  public.richiedi_accesso(uuid,text,text,text,text,text,text,text), public.crea_ordine(uuid,jsonb,text,text,text,text,text,date,text),
  public.annulla_ordine(uuid) from public, anon;
grant execute on function public.e_gestore(uuid), public.e_cliente_approvato(uuid), public.disponibilita(uuid),
  public.richiedi_accesso(uuid,text,text,text,text,text,text,text), public.crea_ordine(uuid,jsonb,text,text,text,text,text,date,text),
  public.annulla_ordine(uuid) to authenticated;
grant execute on function public.negozio_pubblico(text) to anon, authenticated;
