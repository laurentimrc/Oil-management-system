-- Vetrina personalizzabile, bacheca degli annunci, notifiche e tempo reale per i clienti.
-- I punti oliva non hanno tabelle: si calcolano dagli ordini consegnati, che il cliente non può modificare.

alter table public.negozi
  add column if not exists vetrina jsonb not null default '{}'::jsonb,   -- titolo, sottotitolo, storia, annata, colore, opzioni, premi per livello
  add column if not exists copertina_url text,
  add column if not exists galleria text[] not null default '{}';
alter table public.formati
  add column if not exists descrizione text,
  add column if not exists foto_url text;

-- ===== Bacheca degli annunci del produttore =====
create table public.annunci (
  id uuid primary key default gen_random_uuid(),
  negozio_id uuid not null references public.negozi(id) on delete cascade,
  emoji text not null default '📣',
  titolo text not null check (length(titolo) between 1 and 120),
  testo text check (length(testo) <= 2000),
  autore uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index on public.annunci (negozio_id, created_at desc);
create index on public.annunci (autore);
alter table public.annunci enable row level security;
create policy annunci_gestore on public.annunci for all to authenticated
  using (public.e_gestore(negozio_id)) with check (public.e_gestore(negozio_id));
create policy annunci_clienti on public.annunci for select to authenticated using (public.e_cliente_approvato(negozio_id));

-- ===== Vetrina pubblica (anche senza account): niente dati personali, prezzi solo se il gestore lo consente =====
create or replace function public.vetrina_pubblica(p_slug text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', n.id, 'nome', n.nome, 'descrizione', n.descrizione, 'attivo', n.attivo, 'note_consegna', n.note_consegna,
    'vetrina', n.vetrina, 'copertina', n.copertina_url, 'galleria', to_jsonb(n.galleria),
    'formati', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'litri', f.litri, 'descrizione', f.descrizione, 'foto', f.foto_url,
                          'prezzo', case when coalesce((n.vetrina ->> 'prezzi_pubblici')::boolean, false) then f.prezzo end) order by f.ordine, f.litri)
                        from public.formati f where f.negozio_id = n.id and f.attivo), '[]'::jsonb),
    'disponibili', case when coalesce((n.vetrina ->> 'mostra_disponibilita')::boolean, true) and n.litri_in_vendita is not null
      then n.litri_in_vendita - coalesce((select sum(r.litri * r.quantita) from public.ordine_righe r join public.ordini o on o.id = r.ordine_id
                                          where o.negozio_id = n.id and o.stato <> 'annullato'), 0) end)
  from public.negozi n where n.slug = lower(p_slug);
$$;
revoke all on function public.vetrina_pubblica(text) from public;
grant execute on function public.vetrina_pubblica(text) to anon, authenticated;

-- ===== Notifiche ai clienti (categoria "vendite" = aggiornamenti sugli ordini) =====
create or replace function public.notifica_cliente_ordine() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_litri numeric; v_titolo text; v_testo text;
begin
  if new.stato is not distinct from old.stato or new.stato not in ('confermato','in_consegna','consegnato','annullato') then return new; end if;
  select coalesce(sum(litri * quantita), 0) into v_litri from public.ordine_righe where ordine_id = new.id;
  v_titolo := case new.stato when 'confermato' then '✅ Ordine confermato' when 'in_consegna' then '🚚 Il tuo olio è in consegna'
                             when 'consegnato' then '🫒 Consegnato! +' || (20 + round(v_litri * 10))::int || ' punti oliva' else 'Ordine annullato' end;
  v_testo := case new.stato
    when 'confermato' then 'Totale ' || coalesce(replace(trim_scale(new.totale)::text, '.', ','), '—') || ' €' || coalesce(' · ' || nullif(new.nota_gestore, ''), '')
    when 'in_consegna' then coalesce(nullif(new.nota_gestore, ''), 'Il produttore sta arrivando a ' || new.comune)
    when 'consegnato' then 'Grazie! I punti sono già nel tuo profilo.'
    else coalesce(nullif(new.nota_gestore, ''), 'Contatta il produttore per informazioni.') end;
  insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
  values (new.user_id, 'vendite', v_titolo, v_testo, '#ordini', 'ord:' || new.id || ':' || new.stato)
  on conflict (destinatario, chiave) do nothing;
  return new;
end $$;
create trigger notifica_cliente_ordine after update on public.ordini for each row execute function public.notifica_cliente_ordine();

create or replace function public.notifica_cliente_approvato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_nome text;
begin
  if new.stato = 'approvato' and old.stato is distinct from 'approvato' then
    select nome into v_nome from public.negozi where id = new.negozio_id;
    insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
    values (new.user_id, 'vendite', '🎉 Sei stato autorizzato', 'Ora puoi prenotare l''olio di ' || v_nome || '. Hai già 50 punti oliva di benvenuto!', '#prenota', 'ok:' || new.id)
    on conflict (destinatario, chiave) do nothing;
  end if;
  return new;
end $$;
create trigger notifica_cliente_approvato after update on public.clienti for each row execute function public.notifica_cliente_approvato();

create or replace function public.notifica_annuncio() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
  select c.user_id, 'vendite', new.emoji || ' ' || new.titolo, left(coalesce(new.testo, ''), 180), '#bacheca', 'ann:' || new.id
  from public.clienti c where c.negozio_id = new.negozio_id and c.stato = 'approvato'
  on conflict (destinatario, chiave) do nothing;
  return new;
end $$;
create trigger notifica_annuncio after insert on public.annunci for each row execute function public.notifica_annuncio();

revoke all on function public.notifica_cliente_ordine(), public.notifica_cliente_approvato(), public.notifica_annuncio() from public, anon, authenticated;

-- ===== Solo su Supabase (non nei test locali): foto e tempo reale =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vetrine', 'vetrine', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy vetrine_carica on storage.objects for insert to authenticated
  with check (bucket_id = 'vetrine' and public.e_gestore(((storage.foldername(name))[1])::uuid));
create policy vetrine_modifica on storage.objects for update to authenticated
  using (bucket_id = 'vetrine' and public.e_gestore(((storage.foldername(name))[1])::uuid))
  with check (bucket_id = 'vetrine' and public.e_gestore(((storage.foldername(name))[1])::uuid));
create policy vetrine_elimina on storage.objects for delete to authenticated
  using (bucket_id = 'vetrine' and public.e_gestore(((storage.foldername(name))[1])::uuid));
alter publication supabase_realtime add table public.ordini, public.annunci, public.clienti;
