-- Accesso condiviso: il titolare invita un manager o un agricoltore.
--   owner        tutto
--   manager      tutto tranne la gestione dei collaboratori
--   agricoltore  legge l'uliveto; registra lavori e raccolte; aggiorna le piante;
--                niente conti, vendite, creazione/cancellazione di appezzamenti e piante, moliture

create table public.collaboratori (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  email text not null check (email = lower(trim(email)) and email like '%_@_%'),
  nome text,
  azienda text,
  ruolo text not null check (ruolo in ('manager','agricoltore')),
  user_id uuid references auth.users(id) on delete cascade,
  stato text not null default 'invitato' check (stato in ('invitato','attivo','revocato')),
  created_at timestamptz not null default now(),
  accettato_at timestamptz,
  unique (owner_id, email),
  check (stato = 'invitato' or user_id is not null)
);
create index on public.collaboratori (user_id);
create index on public.collaboratori (email) where stato = 'invitato';

-- Ruolo dell'utente collegato sui dati di un titolare (null = nessun accesso)
create or replace function public.ruolo_su(p_owner uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when p_owner = (select auth.uid()) then 'owner'
    else (select c.ruolo from public.collaboratori c
          where c.owner_id = p_owner and c.user_id = (select auth.uid()) and c.stato = 'attivo' limit 1) end;
$$;

alter table public.collaboratori enable row level security;
create policy collab_owner_lettura on public.collaboratori for select to authenticated using (owner_id = (select auth.uid()));
create policy collab_owner_invito on public.collaboratori for insert to authenticated
  with check (owner_id = (select auth.uid()) and user_id is null and stato = 'invitato' and email <> lower(coalesce(auth.jwt() ->> 'email','')));
create policy collab_owner_modifica on public.collaboratori for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy collab_owner_elimina on public.collaboratori for delete to authenticated using (owner_id = (select auth.uid()));
create policy collab_proprio on public.collaboratori for select to authenticated using (user_id = (select auth.uid()));

-- Il titolare non può collegare a mano un utente né cambiare email a un invito già accettato
create or replace function public.collab_guard() returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user = 'authenticated' then
    if new.user_id is distinct from old.user_id then raise exception 'Non si può cambiare l''utente collegato'; end if;
    if new.email is distinct from old.email and old.user_id is not null then raise exception 'Non si può cambiare l''email di un invito accettato'; end if;
  end if;
  return new;
end $$;
create trigger collab_guard before update on public.collaboratori for each row execute function public.collab_guard();

-- Accetta gli inviti destinati alla propria email (solo se l'email è stata confermata)
create or replace function public.accetta_inviti() returns int
language plpgsql security definer set search_path = '' as $$
declare v_email text; n int;
begin
  select lower(u.email) into v_email from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null;
  if v_email is null then return 0; end if;
  update public.collaboratori set user_id = auth.uid(), stato = 'attivo', accettato_at = now()
   where email = v_email and stato = 'invitato' and user_id is null and owner_id <> auth.uid();
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.accetta_inviti(), public.ruolo_su(uuid) from public, anon;
grant execute on function public.accetta_inviti(), public.ruolo_su(uuid) to authenticated;

-- Nuove regole sulle tabelle dell'uliveto
do $$
declare
  t text;
  lettura text;
  scrittura text;
  regole jsonb := '{
    "appezzamenti":      ["owner,manager,agricoltore", "owner,manager",             "owner,manager",             "owner,manager"],
    "piante":            ["owner,manager,agricoltore", "owner,manager",             "owner,manager,agricoltore", "owner,manager"],
    "interventi":        ["owner,manager,agricoltore", "owner,manager,agricoltore", "owner,manager,agricoltore", "owner,manager,agricoltore"],
    "intervento_piante": ["owner,manager,agricoltore", "owner,manager,agricoltore", "owner,manager,agricoltore", "owner,manager,agricoltore"],
    "raccolte":          ["owner,manager,agricoltore", "owner,manager,agricoltore", "owner,manager,agricoltore", "owner,manager,agricoltore"],
    "moliture":          ["owner,manager,agricoltore", "owner,manager",             "owner,manager",             "owner,manager"],
    "movimenti":         ["owner,manager",             "owner,manager",             "owner,manager",             "owner,manager"]
  }';
  r jsonb;
  cond text;
begin
  for t, r in select * from jsonb_each(regole) loop
    -- Le regole "proprietario_*" esistenti restano (coprono il titolare); queste si aggiungono.
    cond := 'public.ruolo_su(user_id) = any (string_to_array(%L, '',''))';
    execute format('create policy accesso_select on public.%I for select to authenticated using (' || cond || ')', t, r->>0);
    execute format('create policy accesso_insert on public.%I for insert to authenticated with check (' || cond || ')', t, r->>1);
    execute format('create policy accesso_update on public.%I for update to authenticated using (' || cond || ') with check (' || cond || ')', t, r->>2, r->>2);
    execute format('create policy accesso_delete on public.%I for delete to authenticated using (' || cond || ')', t, r->>3);
  end loop;
end $$;

-- Vendite: anche il manager gestisce il negozio del titolare
create policy negozi_manager on public.negozi for all to authenticated
  using (public.ruolo_su(owner_id) in ('owner','manager')) with check (public.ruolo_su(owner_id) in ('owner','manager'));
create or replace function public.e_gestore(p_negozio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.negozi n where n.id = p_negozio and public.ruolo_su(n.owner_id) in ('owner','manager'));
$$;
