-- Consensi, annunci solo con consenso, dati del venditore pubblici.
-- Chiusura dell'account e pulizia degli importati: Edge Function "account" (verificata a parte).
do $$
declare
  o uuid := gen_random_uuid(); c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  neg uuid; n int; r text := ''; j jsonb; b boolean;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'lg-o@t.it',now()),(c1,'lg-c1@t.it',now()),(c2,'lg-c2@t.it',now()),(x,'lg-x@t.it',now());
  set local role authenticated;
  -- titolare: negozio con dati del venditore
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','lg-o@t.it')::text, true);
  insert into negozi(slug,nome,dati_legali) values ('lg-olio','Olio LG','{"ragione_sociale":"Az. Agr. Rossi","piva":"01234567890","professionista":true}') returning id into neg;
  insert into consensi(tipo,versione) values ('termini','1.0');
  r := r||E'\nOK 1) Un utente registra la propria accettazione dei termini';
  begin insert into consensi(user_id,tipo,versione) values (c1,'termini','1.0'); r := r||E'\nERRORE 2) consenso a nome di altri';
  exception when others then r := r||E'\nOK 2) Non si può registrare un consenso a nome di un altro'; end;
  begin update consensi set versione = '9.9'; get diagnostics n = row_count; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 3) Lo storico dei consensi non si modifica ('||n||')';
  exception when others then r := r||E'\nOK 3) Lo storico dei consensi non si modifica'; end;
  -- due clienti autorizzati
  perform set_config('request.jwt.claims', json_build_object('sub',c1,'email','lg-c1@t.it')::text, true);
  perform richiedi_accesso(neg,'Cliente Uno','333','Via 1','Milano',null,null,null);
  perform set_config('request.jwt.claims', json_build_object('sub',c2,'email','lg-c2@t.it')::text, true);
  perform richiedi_accesso(neg,'Cliente Due','334','Via 2','Monza',null,null,null);
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','lg-o@t.it')::text, true);
  update clienti set stato='approvato' where negozio_id=neg;
  select count(*) into n from clienti where negozio_id=neg and annunci_ok; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 4) Consenso agli annunci spento di default';
  -- solo il cliente 1 accetta gli annunci
  perform set_config('request.jwt.claims', json_build_object('sub',c1,'email','lg-c1@t.it')::text, true);
  b := imposta_annunci(neg, true, '1.0');
  select count(*) into n from consensi where tipo='annunci' and valore; r := r||E'\n'||case when b and n=1 then 'OK' else 'ERRORE' end||' 5) Il cliente attiva gli annunci e resta traccia con versione e data';
  perform set_config('request.jwt.claims', json_build_object('sub',x,'email','lg-x@t.it')::text, true);
  begin perform imposta_annunci(neg, true, '1.0'); r := r||E'\nERRORE 6) estraneo';
  exception when others then r := r||E'\nOK 6) Chi non è cliente non può attivarli'; end;
  -- annuncio: notifica solo a chi ha acconsentito
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','lg-o@t.it')::text, true);
  insert into annunci(negozio_id,titolo) values (neg,'Olio nuovo');
  reset role; select count(*) into n from coda_notifiche where chiave like 'ann:%' and destinatario in (c1,c2);
  r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 7) L''annuncio arriva come notifica solo a chi ha acconsentito ('||n||' su 2)';
  set local role authenticated;
  select count(*) into n from consensi where negozio_id = neg; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 8) Il titolare vede i consensi dei suoi clienti ('||n||')';
  -- revoca
  perform set_config('request.jwt.claims', json_build_object('sub',c1,'email','lg-c1@t.it')::text, true);
  perform imposta_annunci(neg, false, '1.0');
  select count(*) into n from clienti where user_id=c1 and annunci_ok; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 9) La revoca spegne gli annunci';
  -- dati del venditore pubblici (anche senza account)
  reset role; set local role anon;
  j := vetrina_pubblica('lg-olio'); r := r||E'\n'||case when j->'venditore'->>'piva' = '01234567890' then 'OK' else 'ERRORE' end||' 10) I dati del venditore sono nella vetrina pubblica';
  reset role;
  raise notice '%', r;
end $$;
