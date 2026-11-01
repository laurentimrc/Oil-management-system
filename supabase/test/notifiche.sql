do $$
declare
  o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); ag uuid := gen_random_uuid(); c uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  neg uuid; f1 uuid; ap uuid; pr uuid; n int; r text := ''; s text;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'o4@t.it',now()),(m,'m4@t.it',now()),(ag,'ag4@t.it',now()),(c,'c4@t.it',now()),(x,'x4@t.it',now());
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o4@t.it')::text, true);
  insert into appezzamenti(nome,lat,lng) values ('Alto',41.5,14.6) returning id into ap;
  insert into negozi(slug,nome) values ('neg-n4','Neg') returning id into neg;
  insert into formati(negozio_id,nome,litri) values (neg,'Latta 5 L',5) returning id into f1;
  insert into collaboratori(email,ruolo,nome) values ('m4@t.it','manager','Lucia'),('ag4@t.it','agricoltore','Giuseppe');
  insert into promemoria(user_id,data,tipo,titolo,appezzamento_id) values (o,current_date,'trattamento','Secondo trattamento rameico',ap) returning id into pr;
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m4@t.it')::text, true); perform accetta_inviti();
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'email','ag4@t.it')::text, true); perform accetta_inviti();

  -- agricoltore: promemoria e lavoro
  select count(*) into n from promemoria; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 1) L''agricoltore vede i promemoria ('||n||')';
  insert into promemoria(user_id,data,tipo,titolo) values (o,current_date+15,'trattamento','Ripetere rame'); r := r||E'\nOK 2) L''agricoltore crea un promemoria';
  update promemoria set fatto=true where id=pr; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 3) L''agricoltore segna un promemoria come fatto';
  update promemoria set fatto=false where id=pr;
  insert into interventi(user_id,tipo,descrizione) values (o,'potatura','Rimonda filare 3');
  insert into raccolte(user_id,kg_olive) values (o,42.5);
  begin select count(*) into n from coda_notifiche; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 4) Nessun utente può leggere la coda delle notifiche ('||n||' righe)';
  exception when others then r := r||E'\nOK 4) Nessun utente può leggere la coda delle notifiche'; end;
  begin perform accoda(o, array['manager'], 'vendite', 'falso', 'x', null, null, null); r := r||E'\nERRORE 5) un utente accoda notifiche';
  exception when others then r := r||E'\nOK 5) Nessun utente può inviare notifiche a nome di altri'; end;
  begin select count(*) into n from config_push; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 6) Nessun utente può leggere le chiavi private ('||n||' righe)';
  exception when others then r := r||E'\nOK 6) Nessun utente può leggere le chiavi private'; end;
  perform registra_push('https://push.example/ag','k','a','Android'); r := r||E'\nOK 7) Dispositivo registrato';
  insert into preferenze_notifiche(meteo) values (false); r := r||E'\nOK 8) Preferenze salvate';

  -- estraneo
  perform set_config('request.jwt.claims', json_build_object('sub',x,'email','x4@t.it')::text, true);
  select count(*) into n from promemoria; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 9) Un estraneo non vede i promemoria ('||n||')';
  select count(*) into n from push_iscrizioni; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 10) Un estraneo non vede i dispositivi altrui ('||n||')';
  select count(*) into n from preferenze_notifiche; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 11) …né le preferenze altrui ('||n||')';
  perform registra_push('https://push.example/ag','k2','a2','iPhone');
  -- stesso telefono passato a un altro account: ora appartiene a x
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'email','ag4@t.it')::text, true);
  select count(*) into n from push_iscrizioni; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 12) Un telefono riassegnato non riceve più le notifiche del vecchio account ('||n||')';

  -- cliente: richiesta e ordine
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o4@t.it')::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c4@t.it')::text, true);
  perform richiedi_accesso(neg,'Carla','1','Via A','Monza',null,null,null);
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m4@t.it')::text, true);
  update clienti set stato='approvato' where negozio_id=neg;
  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c4@t.it')::text, true);
  perform crea_ordine(neg,('[{"formato_id":"'||f1||'","quantita":3}]')::jsonb,'Via A','Monza',null,null,null,null,null);
  set constraints all immediate;

  reset role;  -- lato server (come la funzione di invio)
  perform prepara_promemoria();
  perform prepara_promemoria();  -- seconda esecuzione: nessun doppione
  select string_agg(format('%s→%s', case destinatario when o then 'titolare' when m then 'manager' when ag then 'agricoltore' else '?' end, titolo||': '||testo), E'\n     ' order by id) into s from coda_notifiche;
  r := r||E'\n--- Coda notifiche generata:\n     '||s;
  select count(*) into n from coda_notifiche where categoria='squadra' and destinatario<>o; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 13) Le attività della squadra arrivano solo al titolare';
  select count(*) into n from coda_notifiche where categoria='vendite' and destinatario=ag; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 14) Le vendite non arrivano all''agricoltore';
  select count(*) into n from coda_notifiche where categoria='promemoria'; r := r||E'\n'||case when n=3 then 'OK' else 'ERRORE' end||' 15) Il promemoria di oggi arriva una volta a tutta la squadra ('||n||')';
  select count(*) into n from coda_notifiche where destinatario=ag and categoria='squadra'; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 16) Chi registra un lavoro non riceve la propria notifica';
  select count(*) into n from luoghi_meteo(); r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 17) Luoghi per il meteo ('||n||')';
  raise notice '%', r;
end $$;
