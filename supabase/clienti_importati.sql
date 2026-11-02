-- Clienti importati (vecchi acquirenti da Excel/CSV o inseriti a mano dal gestore).
-- Non hanno ancora un account: sono già autorizzati e ricevono un invito personale.
-- Quando si registrano, il profilo viene collegato al loro account solo con il codice dell'invito
-- oppure con la stessa email già confermata. Il telefono da solo non basta (non è verificato).

alter table public.clienti alter column user_id drop not null;
alter table public.clienti
  add column if not exists invito text unique,          -- codice casuale nel link d'invito; si cancella quando viene usato
  add column if not exists importato_at timestamptz,
  add column if not exists invitato_at timestamptz;
create index if not exists clienti_negozio_email_idx on public.clienti (negozio_id, lower(email));

-- Le notifiche non devono partire per chi non ha ancora un account
create or replace function public.notifica_nuovo_cliente() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  if new.user_id is null then return new; end if;
  select owner_id into v_owner from public.negozi where id = new.negozio_id;
  perform public.accoda(v_owner, array['manager'], 'vendite', '🙋 Nuova richiesta di accesso',
    new.nome || ' (' || new.comune || ') vuole prenotare l''olio', '#tab=vendite', 'cliente:' || new.id, null);
  return new;
end $$;

create or replace function public.notifica_cliente_approvato() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_nome text;
begin
  if new.user_id is not null and new.stato = 'approvato' and old.stato is distinct from 'approvato' then
    select nome into v_nome from public.negozi where id = new.negozio_id;
    insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
    values (new.user_id, 'vendite', '🎉 Sei stato autorizzato', 'Ora puoi prenotare l''olio di ' || v_nome || '. Hai già 50 punti oliva di benvenuto!', '#prenota', 'ok:' || new.id)
    on conflict (destinatario, chiave) do nothing;
  end if;
  return new;
end $$;

create or replace function public.notifica_annuncio() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.coda_notifiche (destinatario, categoria, titolo, testo, url, chiave)
  select c.user_id, 'vendite', new.emoji || ' ' || new.titolo, left(coalesce(new.testo, ''), 180), '#bacheca', 'ann:' || new.id
  from public.clienti c where c.negozio_id = new.negozio_id and c.stato = 'approvato' and c.user_id is not null
  on conflict (destinatario, chiave) do nothing;
  return new;
end $$;

-- Il gestore importa un elenco: [{"nome":"…","telefono":"…","email":"…","indirizzo":"…","comune":"…","cap":"…","provincia":"…","note":"…"}]
-- Salta chi è già presente (stessa email o stesso telefono) e chi non ha un nome.
create or replace function public.importa_clienti(p_negozio uuid, p_righe jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r jsonb; v_nome text; v_email text; v_tel text; v_cifre text; n_ok int := 0; n_doppi int := 0; n_vuoti int := 0;
begin
  if not public.e_gestore(p_negozio) then raise exception 'Solo titolare e manager possono importare clienti'; end if;
  if jsonb_typeof(p_righe) <> 'array' then raise exception 'Elenco non valido'; end if;
  if jsonb_array_length(p_righe) > 2000 then raise exception 'Massimo 2000 clienti per volta'; end if;
  for r in select * from jsonb_array_elements(p_righe) loop
    v_nome := left(nullif(trim(r ->> 'nome'), ''), 120);
    if v_nome is null then n_vuoti := n_vuoti + 1; continue; end if;
    v_email := lower(nullif(trim(r ->> 'email'), ''));
    if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_email := null; end if;
    v_tel := left(nullif(trim(r ->> 'telefono'), ''), 40);
    v_cifre := nullif(regexp_replace(coalesce(v_tel, ''), '\D', '', 'g'), '');
    if exists (select 1 from public.clienti c where c.negozio_id = p_negozio and (
         (v_email is not null and lower(c.email) = v_email) or
         (v_cifre is not null and length(v_cifre) >= 6 and right(regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g'), 9) = right(v_cifre, 9)))) then
      n_doppi := n_doppi + 1; continue;
    end if;
    insert into public.clienti (negozio_id, user_id, email, nome, telefono, indirizzo, comune, cap, provincia, note_indirizzo, stato, invito, importato_at)
    values (p_negozio, null, v_email, v_nome, v_tel, left(coalesce(trim(r ->> 'indirizzo'), ''), 200), left(coalesce(trim(r ->> 'comune'), ''), 80),
            left(nullif(trim(r ->> 'cap'), ''), 10), upper(left(nullif(trim(r ->> 'provincia'), ''), 4)), left(nullif(trim(r ->> 'note'), ''), 500),
            'approvato', replace(gen_random_uuid()::text, '-', ''), now());
    n_ok := n_ok + 1;
  end loop;
  return jsonb_build_object('importati', n_ok, 'gia_presenti', n_doppi, 'senza_nome', n_vuoti);
end $$;

-- Cerca il profilo importato che spetta a chi è collegato: con il codice d'invito o con la sua email confermata
create or replace function public.cliente_invitato(p_negozio uuid, p_invito text)
returns uuid language sql stable security definer set search_path = '' as $$
  select c.id from public.clienti c
  where c.negozio_id = p_negozio and c.user_id is null and auth.uid() is not null and (
    (nullif(p_invito, '') is not null and c.invito = p_invito) or
    (c.email is not null and lower(c.email) = (select lower(u.email) from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null)))
  order by (c.invito = p_invito) desc nulls last, c.created_at
  limit 1;
$$;

-- Dati per precompilare il modulo del cliente invitato (solo i suoi)
create or replace function public.invito_cliente(p_negozio uuid, p_invito text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('nome', c.nome, 'telefono', c.telefono, 'indirizzo', c.indirizzo, 'comune', c.comune,
                            'cap', c.cap, 'provincia', c.provincia, 'note_indirizzo', c.note_indirizzo)
  from public.clienti c where c.id = public.cliente_invitato(p_negozio, p_invito);
$$;

-- Il cliente invitato conferma i suoi dati e accetta l'informativa: il profilo diventa suo, già autorizzato
create or replace function public.accetta_invito_cliente(p_negozio uuid, p_invito text, p_nome text, p_telefono text, p_indirizzo text,
  p_comune text, p_cap text, p_provincia text, p_note_indirizzo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_owner uuid;
begin
  if v_uid is null then raise exception 'Accesso richiesto'; end if;
  if coalesce(trim(p_nome),'') = '' or coalesce(trim(p_indirizzo),'') = '' or coalesce(trim(p_comune),'') = '' then
    raise exception 'Nome, indirizzo e comune sono obbligatori';
  end if;
  if exists (select 1 from public.clienti where negozio_id = p_negozio and user_id = v_uid) then
    raise exception 'Hai già un profilo presso questo produttore';
  end if;
  v_id := public.cliente_invitato(p_negozio, p_invito);
  if v_id is null then raise exception 'Invito non valido o già usato'; end if;
  update public.clienti set user_id = v_uid, email = coalesce(auth.jwt() ->> 'email', email), nome = trim(p_nome), telefono = p_telefono,
    indirizzo = trim(p_indirizzo), comune = trim(p_comune), cap = p_cap, provincia = upper(p_provincia), note_indirizzo = p_note_indirizzo,
    privacy_at = now(), invito = null
  where id = v_id and user_id is null;
  select owner_id into v_owner from public.negozi where id = p_negozio;
  perform public.accoda(v_owner, array['manager'], 'vendite', '✅ ' || trim(p_nome) || ' ha accettato l''invito',
    'Ora può prenotare l''olio', '#tab=vendite', 'invito:' || v_id, null);
  return v_id;
end $$;

revoke all on function public.importa_clienti(uuid, jsonb), public.cliente_invitato(uuid, text), public.invito_cliente(uuid, text),
  public.accetta_invito_cliente(uuid, text, text, text, text, text, text, text, text) from public, anon;
revoke execute on function public.cliente_invitato(uuid, text) from authenticated;  -- solo uso interno
grant execute on function public.importa_clienti(uuid, jsonb), public.invito_cliente(uuid, text),
  public.accetta_invito_cliente(uuid, text, text, text, text, text, text, text, text) to authenticated;
