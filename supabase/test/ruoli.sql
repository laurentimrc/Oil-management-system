do $$
declare
  o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); a uuid := gen_random_uuid(); x uuid := gen_random_uuid(); u uuid := gen_random_uuid();
  ap uuid; p1 uuid; n int; r text := ''; s text; neg uuid;
  procedure_dummy int;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'owner@t.it',now()),(m,'manager@t.it',now()),(a,'agri@t.it',now()),(x,'estraneo@t.it',now()),(u,'nonconf@t.it',null);
  set local role authenticated;
  -- TITOLARE: dati e inviti
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','owner@t.it')::text, true);
  insert into appezzamenti(nome) values ('Uliveto alto') returning id into ap;
  insert into piante(codice, appezzamento_id) values ('A-1', ap) returning id into p1;
  insert into movimenti(tipo,categoria,importo) values ('spesa','concimi',50);
  insert into moliture(kg_olive,litri_olio,costo) values (100,15,20);
  insert into negozi(slug,nome) values ('neg-test','Neg') returning id into neg;
  insert into collaboratori(email,ruolo,azienda) values ('manager@t.it','manager','Uliveto di O'),('agri@t.it','agricoltore','Uliveto di O'),('nonconf@t.it','agricoltore','Uliveto di O');
  begin insert into collaboratori(email,ruolo,user_id,stato) values ('estraneo@t.it','manager',x,'attivo'); r := r||E'\nERRORE 1) titolare collega a mano un utente';
  exception when others then r := r||E'\nOK 1) Il titolare non può collegare a mano un account (solo invito)'; end;

  -- ESTRANEO prima di tutto
  perform set_config('request.jwt.claims', json_build_object('sub',x,'email','estraneo@t.it')::text, true);
  select count(*) into n from piante; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 2) Un estraneo non vede le piante ('||n||')';
  n := accetta_inviti(); r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 3) Un estraneo non può accettare inviti altrui ('||n||')';

  -- EMAIL NON CONFERMATA
  perform set_config('request.jwt.claims', json_build_object('sub',u,'email','nonconf@t.it')::text, true);
  n := accetta_inviti(); select count(*) into procedure_dummy from piante;
  r := r||E'\n'||case when n=0 and procedure_dummy=0 then 'OK' else 'ERRORE' end||' 4) Con email non confermata l''invito non si attiva ('||n||')';

  -- MANAGER
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','manager@t.it')::text, true);
  select count(*) into n from piante; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 5) Prima di accettare il manager non vede nulla ('||n||')';
  n := accetta_inviti(); r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 6) Il manager accetta l''invito ('||n||')';
  select ruolo_su(o) into s; r := r||E'\n'||case when s='manager' then 'OK' else 'ERRORE' end||' 7) Ruolo riconosciuto: '||s;
  select count(*) into n from movimenti; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 8) Il manager vede i conti ('||n||')';
  insert into piante(user_id,codice,appezzamento_id) values (o,'A-2',ap); r := r||E'\nOK 9) Il manager aggiunge piante';
  insert into movimenti(user_id,tipo,categoria,importo) values (o,'entrata','vendita olio',10); r := r||E'\nOK 10) Il manager registra movimenti';
  update negozi set nome='Neg 2' where id=neg; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 11) Il manager gestisce il negozio ('||n||')';
  select count(*) into n from collaboratori where owner_id=o; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 12) Il manager vede solo il proprio invito, non il team ('||n||')';
  update collaboratori set ruolo='manager' where owner_id=o and email='agri@t.it'; get diagnostics n=row_count;
  r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 13) Il manager non può cambiare i ruoli del team ('||n||')';
  begin insert into collaboratori(owner_id,email,ruolo) values (o,'altro@t.it','manager'); r := r||E'\nERRORE 14) manager invita a nome del titolare';
  exception when others then r := r||E'\nOK 14) Il manager non può invitare altre persone'; end;

  -- AGRICOLTORE
  perform set_config('request.jwt.claims', json_build_object('sub',a,'email','agri@t.it')::text, true);
  perform accetta_inviti();
  select count(*) into n from piante; r := r||E'\n'||case when n=2 then 'OK' else 'ERRORE' end||' 15) L''agricoltore vede le piante ('||n||')';
  select count(*) into n from movimenti; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 16) L''agricoltore NON vede i conti ('||n||')';
  select count(*) into n from negozi; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 17) L''agricoltore NON vede il negozio ('||n||')';
  insert into interventi(user_id,tipo,descrizione) values (o,'potatura','Potatura A-1'); r := r||E'\nOK 18) L''agricoltore registra un lavoro';
  insert into raccolte(user_id,pianta_id,kg_olive) values (o,p1,25); r := r||E'\nOK 19) L''agricoltore registra una raccolta';
  update piante set stato='malata', note='macchie sulle foglie' where id=p1; get diagnostics n=row_count;
  r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 20) L''agricoltore aggiorna lo stato di una pianta ('||n||')';
  begin insert into piante(user_id,codice) values (o,'Z-1'); r := r||E'\nERRORE 21) agricoltore crea piante';
  exception when others then r := r||E'\nOK 21) L''agricoltore non può creare piante'; end;
  delete from piante where id=p1; get diagnostics n=row_count; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 22) L''agricoltore non può cancellare piante ('||n||')';
  delete from appezzamenti; get diagnostics n=row_count; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 23) L''agricoltore non può cancellare appezzamenti ('||n||')';
  begin insert into movimenti(user_id,tipo,categoria,importo) values (o,'spesa','altro',1); r := r||E'\nERRORE 24) agricoltore scrive nei conti';
  exception when others then r := r||E'\nOK 24) L''agricoltore non può scrivere nei conti'; end;
  begin insert into moliture(user_id,kg_olive) values (o,10); r := r||E'\nERRORE 25) agricoltore registra moliture';
  exception when others then r := r||E'\nOK 25) L''agricoltore non può registrare moliture'; end;
  begin insert into interventi(user_id,tipo) values (x,'potatura'); r := r||E'\nERRORE 26) scrive nei dati di un estraneo';
  exception when others then r := r||E'\nOK 26) Nessuno può scrivere nei dati di un uliveto a cui non ha accesso'; end;

  -- TITOLARE revoca l'agricoltore
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','owner@t.it')::text, true);
  select count(*) into n from collaboratori where stato='attivo'; r := r||E'\n'||case when n=2 then 'OK' else 'ERRORE' end||' 27) Il titolare vede i 2 collaboratori attivi ('||n||')';
  begin update collaboratori set user_id = x where email='agri@t.it'; r := r||E'\nERRORE 28) titolare sostituisce l''utente collegato';
  exception when others then r := r||E'\nOK 28) Il titolare non può sostituire l''account collegato a un invito'; end;
  update collaboratori set stato='revocato' where email='agri@t.it';
  perform set_config('request.jwt.claims', json_build_object('sub',a,'email','agri@t.it')::text, true);
  select count(*) into n from piante; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 29) Dopo la revoca l''agricoltore non vede più nulla ('||n||')';
  n := accetta_inviti(); r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 30) Il revocato non può riattivarsi da solo ('||n||')';
  -- clienti del negozio restano isolati
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','manager@t.it')::text, true);
  select count(*) into n from collaboratori; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 31) Il manager vede solo il suo accesso ('||n||')';
  raise notice '%', r;
end $$;
