-- Magazzino dell'olio: aggiunte (es. olio degli anni precedenti) e uscite a mano.
-- L'olio delle moliture e quello prenotato si calcolano dalle rispettive tabelle.
-- Accesso: titolare e manager; l'agricoltore non lo vede.
create table public.magazzino_olio (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data date not null default current_date,
  tipo text not null default 'carico' check (tipo in ('carico','scarico')),
  annata integer not null check (annata between 1950 and 2100),
  litri numeric not null check (litri > 0),
  descrizione text,
  note text,
  created_at timestamptz not null default now()
);
create index on public.magazzino_olio (user_id, annata);
alter table public.magazzino_olio enable row level security;
create policy magazzino_gestione on public.magazzino_olio for all to authenticated
  using (public.ruolo_su(user_id) in ('owner','manager'))
  with check (public.ruolo_su(user_id) in ('owner','manager'));
