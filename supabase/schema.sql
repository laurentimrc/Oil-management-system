-- Schema del database di "Il mio Uliveto" (Supabase / PostgreSQL).
-- Già applicato al progetto Supabase "Uliveto"; serve per ricreare il database da zero.

create table public.appezzamenti (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome text not null,
  superficie_mq numeric,
  note text,
  created_at timestamptz not null default now()
);

create table public.piante (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  codice text not null,
  appezzamento_id uuid references public.appezzamenti(id) on delete set null,
  varieta text,
  anno_impianto int,
  stato text not null default 'sana' check (stato in ('sana','sotto osservazione','malata','giovane','morta')),
  lat double precision,
  lng double precision,
  note text,
  created_at timestamptz not null default now(),
  unique (user_id, codice)
);

create table public.interventi (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data date not null default current_date,
  tipo text not null check (tipo in ('potatura','concimazione','trattamento','irrigazione','lavorazione terreno','sfalcio','altro')),
  descrizione text,
  prodotto text,
  dose numeric,
  unita text,
  giorni_carenza int,
  ore numeric,
  costo numeric,
  appezzamento_id uuid references public.appezzamenti(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.intervento_piante (
  intervento_id uuid not null references public.interventi(id) on delete cascade,
  pianta_id uuid not null references public.piante(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  primary key (intervento_id, pianta_id)
);

create table public.raccolte (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data date not null default current_date,
  pianta_id uuid references public.piante(id) on delete set null,
  appezzamento_id uuid references public.appezzamenti(id) on delete set null,
  kg_olive numeric not null check (kg_olive >= 0),
  note text,
  created_at timestamptz not null default now()
);

create table public.moliture (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data date not null default current_date,
  frantoio text,
  kg_olive numeric not null check (kg_olive > 0),
  litri_olio numeric,
  kg_olio numeric,
  costo numeric,
  note text,
  created_at timestamptz not null default now()
);

create table public.movimenti (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data date not null default current_date,
  tipo text not null check (tipo in ('spesa','entrata')),
  categoria text not null,
  descrizione text,
  importo numeric not null check (importo >= 0),
  created_at timestamptz not null default now()
);

create index on public.appezzamenti (user_id);
create index on public.piante (user_id);
create index on public.piante (appezzamento_id);
create index on public.interventi (user_id, data);
create index on public.interventi (appezzamento_id);
create index on public.intervento_piante (pianta_id);
create index on public.intervento_piante (user_id);
create index on public.raccolte (user_id, data);
create index on public.raccolte (pianta_id);
create index on public.raccolte (appezzamento_id);
create index on public.moliture (user_id, data);
create index on public.movimenti (user_id, data);

-- Row Level Security: ogni utente vede e modifica solo i propri dati
do $$
declare t text;
begin
  foreach t in array array['appezzamenti','piante','interventi','intervento_piante','raccolte','moliture','movimenti'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "proprietario_select" on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t);
    execute format('create policy "proprietario_insert" on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t);
    execute format('create policy "proprietario_update" on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
    execute format('create policy "proprietario_delete" on public.%I for delete to authenticated using ((select auth.uid()) = user_id)', t);
  end loop;
end $$;
