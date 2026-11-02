-- Clienti importati e inviti: chi può importare, niente notifiche a vuoto, collegamento solo con invito o email confermata.
do $$
declare
  o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); ag uuid := gen_random_uuid();
  x uuid := gen_random_uuid(); lu uuid := gen_random_uuid(); gi uuid := gen_random_uuid(); nc uuid := gen_random_uuid();
  neg uuid; res jsonb; tok text; n int; r text := ''; v uuid; j jsonb;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'ci-o@t.it',now()),(m,'ci-m@t.it',now()),(ag,'ci-a@t.it',now()),
    (x,'ci-x@t.it',now()),(lu,'lucia@t.it',now()),(gi,'gino@t.it',now()),(nc,'nonconf@t.it',null);
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','ci-o@t.it')::text, true);
  insert into negozi(slug,nome) values ('ci-olio','Olio CI') returning id into neg;
  insert into collaboratori(email,ruolo,azienda) values ('ci-m@t.it','manager','U'),('ci-a@t.it','agricoltore','U');
  res := importa_clienti(neg, '[{"nome":"Lucia Bianchi","telefono":"333 111 2222","indirizzo":"Via Roma 1","comune":"Milano"},
     {"nome":"Gino Rossi","email":"GINO@t.it","indirizzo":"Via Po 2","comune":"Monza","provincia":"mb"},
     {"nome":"Lucia doppia","telefono":"+39 3331112222"},
     {"nome":"","telefono":"3400000000"},
     {"nome":"Mario Neri","email":"nonconf@t.it","comune":"Lodi"}]');
  r := r||E'\n'||case when res = '{"importati":3,"gia_presenti":1,"senza_nome":1}'::jsonb then 'OK' else 'ERRORE' end||' 1) Import: 3 nuovi, 1 doppione (stesso telefono), 1 senza nome → '||res;
  select count(*) into n from clienti where negozio_id = neg and user_id is null and stato = 'approvato' and invito is not null;
  r := r||E'\n'||case when n=3 then 'OK' else 'ERRORE' end||' 2) Importati già autorizzati, ognuno con il suo codice d''invito ('||n||')';
  reset role; select count(*) into n from coda_notifiche where chiave like 'cliente:%'; set local role authenticated;
  r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 3) Nessuna notifica "nuova richiesta" per gli importati ('||n||')';
  insert into annunci(negozio_id,titolo) values (neg,'Olio nuovo');
  r := r||E'\nOK 4) Un annuncio si pubblica anche con clienti senza account';
  select invito into tok from clienti where negozio_id = neg and nome = 'Lucia Bianchi';
  -- manager sì, agricoltore ed estraneo no
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','ci-m@t.it')::text, true); perform accetta_inviti();
  res := importa_clienti(neg, '[{"nome":"Dal manager","comune":"Como"}]');
  r := r||E'\n'||case when (res->>'importati')::int=1 then 'OK' else 'ERRORE' end||' 5) Il manager può importare';
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'email','ci-a@t.it')::text, true); perform accetta_inviti();
  begin perform importa_clienti(neg, '[{"nome":"X"}]'); r := r||E'\nERRORE 6) agricoltore importa';
  exception when others then r := r||E'\nOK 6) L''agricoltore non può importare'; end;
  -- estraneo
  perform set_config('request.jwt.claims', json_build_object('sub',x,'email','ci-x@t.it')::text, true);
  begin perform importa_clienti(neg, '[{"nome":"X"}]'); r := r||E'\nERRORE 7) estraneo importa';
  exception when others then r := r||E'\nOK 7) Un estraneo non può importare'; end;
  select count(*) into n from clienti where negozio_id = neg; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 8) Un estraneo non vede i clienti importati ('||n||')';
  j := invito_cliente(neg, 'codice-sbagliato'); r := r||E'\n'||case when j is null then 'OK' else 'ERRORE' end||' 9) Codice sbagliato: nessun dato';
  j := invito_cliente(neg, null); r := r||E'\n'||case when j is null then 'OK' else 'ERRORE' end||' 10) Senza codice e con altra email: nessun dato';
  -- Lucia (stesso telefono, email diversa) senza codice: niente
  perform set_config('request.jwt.claims', json_build_object('sub',lu,'email','lucia@t.it')::text, true);
  j := invito_cliente(neg, null); r := r||E'\n'||case when j is null then 'OK' else 'ERRORE' end||' 11) Il telefono da solo non basta per prendersi un profilo';
  j := invito_cliente(neg, tok); r := r||E'\n'||case when j->>'indirizzo' = 'Via Roma 1' then 'OK' else 'ERRORE' end||' 12) Con il suo invito vede i suoi dati per confermarli';
  v := accetta_invito_cliente(neg, tok, 'Lucia Bianchi', '333 111 2222', 'Via Roma 1', 'Milano', '20100', 'mi', null);
  select count(*) into n from clienti where id = v and user_id = lu and stato = 'approvato' and invito is null and privacy_at is not null;
  r := r||E'\n'||case when n=1 and e_cliente_approvato(neg) then 'OK' else 'ERRORE' end||' 13) Accettato: profilo suo, già autorizzato, informativa registrata, codice consumato';
  -- lo stesso codice non vale per altri
  perform set_config('request.jwt.claims', json_build_object('sub',x,'email','ci-x@t.it')::text, true);
  begin perform accetta_invito_cliente(neg, tok, 'Furbo', null, 'Via X', 'Y', null, null, null); r := r||E'\nERRORE 14) codice riusato';
  exception when others then r := r||E'\nOK 14) Un codice già usato non vale per altri'; end;
  -- Gino: email confermata uguale (anche con maiuscole diverse) basta
  perform set_config('request.jwt.claims', json_build_object('sub',gi,'email','gino@t.it')::text, true);
  v := accetta_invito_cliente(neg, null, 'Gino Rossi', null, 'Via Po 2', 'Monza', null, 'MB', null);
  r := r||E'\n'||case when v is not null then 'OK' else 'ERRORE' end||' 15) Con la stessa email confermata il profilo si collega senza codice';
  -- Mario: email non confermata
  perform set_config('request.jwt.claims', json_build_object('sub',nc,'email','nonconf@t.it')::text, true);
  begin perform accetta_invito_cliente(neg, null, 'Mario Neri', null, 'Via Z', 'Lodi', null, null, null); r := r||E'\nERRORE 16) email non confermata';
  exception when others then r := r||E'\nOK 16) Con email non confermata il profilo non si collega'; end;
  reset role; select count(*) into n from coda_notifiche where chiave like 'invito:%' and destinatario = o;
  r := r||E'\n'||case when n=2 then 'OK' else 'ERRORE' end||' 17) Il titolare viene avvisato quando un invitato si registra ('||n||')';
  raise notice '%', r;
end $$;
