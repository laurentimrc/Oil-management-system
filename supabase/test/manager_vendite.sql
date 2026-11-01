do $$
declare
  o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); ag uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  neg uuid; f1 uuid; o1 uuid; n int; r text := ''; b boolean; d numeric;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'o3@t.it',now()),(m,'m3@t.it',now()),(ag,'ag3@t.it',now()),(c,'c3@t.it',now());
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o3@t.it')::text, true);
  insert into negozi(slug,nome,litri_in_vendita) values ('neg-m3','Neg',50) returning id into neg;
  insert into formati(negozio_id,nome,litri) values (neg,'Latta 5 L',5) returning id into f1;
  insert into collaboratori(email,ruolo) values ('m3@t.it','manager'),('ag3@t.it','agricoltore');
  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c3@t.it')::text, true);
  perform richiedi_accesso(neg,'Carla','1','Via A','Monza',null,null,null);

  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m3@t.it')::text, true);
  perform accetta_inviti();
  b := e_gestore(neg); r := r||E'\n'||case when b then 'OK' else 'ERRORE' end||' 1) Il manager è riconosciuto come gestore del negozio (anteprima del link)';
  select count(*) into n from clienti; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 2) Il manager vede le richieste dei clienti ('||n||')';
  update clienti set stato='approvato' where negozio_id=neg; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 3) Il manager approva un cliente';
  update formati set prezzo=50 where id=f1; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 4) Il manager modifica il listino';

  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c3@t.it')::text, true);
  o1 := crea_ordine(neg,('[{"formato_id":"'||f1||'","quantita":2}]')::jsonb,'Via A','Monza',null,null,null,null,null);

  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m3@t.it')::text, true);
  select count(*) into n from ordini; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 5) Il manager vede gli ordini ('||n||')';
  update ordine_righe set prezzo_unitario=48 where ordine_id=o1; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 6) Il manager decide il prezzo';
  update ordini set stato='consegnato', totale=96 where id=o1; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 7) Il manager conferma e segna consegnato';
  insert into movimenti(user_id,tipo,categoria,importo) values (o,'entrata','vendita olio',96); r := r||E'\nOK 8) L''incasso va nei conti del titolare';
  d := disponibilita(neg); r := r||E'\n'||case when d=40 then 'OK' else 'ERRORE' end||' 9) Il manager legge la disponibilità ('||d||' L)';

  perform set_config('request.jwt.claims', json_build_object('sub',ag,'email','ag3@t.it')::text, true);
  perform accetta_inviti();
  b := e_gestore(neg); r := r||E'\n'||case when not b then 'OK' else 'ERRORE' end||' 10) L''agricoltore non è gestore del negozio';
  select count(*) into n from clienti; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 11) L''agricoltore non vede i clienti ('||n||')';
  select count(*) into n from ordini; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 12) L''agricoltore non vede gli ordini ('||n||')';

  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o3@t.it')::text, true);
  update collaboratori set stato='revocato' where email='m3@t.it';
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m3@t.it')::text, true);
  select count(*) into n from ordini; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 13) Revocato il manager, non vede più gli ordini ('||n||')';
  b := e_gestore(neg); r := r||E'\n'||case when not b then 'OK' else 'ERRORE' end||' 14) …e non è più gestore del negozio';
  raise notice '%', r;
end $$;
