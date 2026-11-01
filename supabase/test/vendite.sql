do $$
declare
  g uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  neg uuid; f1 uuid; f2 uuid; o1 uuid; o2 uuid; n int; d numeric; r text := ''; s text;
begin
  insert into auth.users (id, email) values (g,'g@test.it'),(a,'a@test.it'),(b,'b@test.it'),(x,'x@test.it');
  perform set_config('request.jwt.claims', json_build_object('sub',g,'role','authenticated','email','g@test.it')::text, true);
  set local role authenticated;
  insert into appezzamenti(nome) values ('Privato del gestore');
  insert into negozi(slug, nome, litri_in_vendita) values ('test-olio-xyz','Olio Test',20) returning id into neg;
  insert into formati(negozio_id, nome, litri, prezzo) values (neg,'Latta 5 L',5,45) returning id into f1;
  insert into formati(negozio_id, nome, litri) values (neg,'Bottiglia 1 L',1) returning id into f2;

  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated','email','a@test.it')::text, true);
  perform richiedi_accesso(neg,'Anna','333','Via Roma 1','Monza','20900','mb',null);
  begin perform crea_ordine(neg,('[{"formato_id":"'||f1||'","quantita":1}]')::jsonb,'Via Roma 1','Monza',null,null,null,null,null); r := r||E'\nERRORE 1) A ordina prima di essere approvata';
  exception when others then r := r||E'\nOK 1) A non può ordinare prima di essere approvata'; end;
  select count(*) into n from formati; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 2) A non vede il listino prima dell''approvazione ('||n||')';

  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated','email','b@test.it')::text, true);
  perform richiedi_accesso(neg,'Bruno','334','Via Po 2','Milano',null,null,null);
  update clienti set stato='approvato' where user_id=b; get diagnostics n = row_count;
  r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 3) B non può auto-approvarsi ('||n||' righe)';

  perform set_config('request.jwt.claims', json_build_object('sub',g,'role','authenticated','email','g@test.it')::text, true);
  select count(*) into n from clienti; r := r||E'\n'||case when n=2 then 'OK' else 'ERRORE' end||' 4) Il gestore vede le 2 richieste ('||n||')';
  update clienti set stato='approvato' where user_id=a;

  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated','email','a@test.it')::text, true);
  select count(*) into n from formati; r := r||E'\n'||case when n=2 then 'OK' else 'ERRORE' end||' 5) A approvata vede il listino ('||n||' formati)';
  o1 := crea_ordine(neg,('[{"formato_id":"'||f1||'","quantita":2},{"formato_id":"'||f2||'","quantita":3}]')::jsonb,'Via Roma 1','Monza','20900','mb',null,null,'grazie');
  d := disponibilita(neg); r := r||E'\n'||case when d=7 then 'OK' else 'ERRORE' end||' 6) Ordine da 13 L su 20: restano '||d||' L';
  begin perform crea_ordine(neg,('[{"formato_id":"'||f1||'","quantita":2}]')::jsonb,'Via Roma 1','Monza',null,null,null,null,null); r := r||E'\nERRORE 7) A supera la disponibilità';
  exception when others then r := r||E'\nOK 7) A non può superare la disponibilità ('||sqlerrm||')'; end;
  update ordini set totale = 1 where id = o1; get diagnostics n = row_count; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 8) A non può cambiarsi il prezzo ('||n||')';
  update ordine_righe set prezzo_unitario = 0; get diagnostics n = row_count; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 9) A non può toccare i prezzi delle righe ('||n||')';
  begin insert into ordini(negozio_id,cliente_id,user_id,indirizzo,comune,stato) select neg, id, a, 'x','y','consegnato' from clienti where user_id=a; r := r||E'\nERRORE 10) A inserisce un ordine a mano';
  exception when others then r := r||E'\nOK 10) A non può inserire ordini a mano'; end;
  begin insert into formati(negozio_id,nome,litri) values (neg,'Fake',1); r := r||E'\nERRORE 10b) A aggiunge formati';
  exception when others then r := r||E'\nOK 10b) A non può modificare il listino'; end;
  select count(*) into n from appezzamenti; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 11) A non vede i dati dell''uliveto del gestore ('||n||')';
  select count(*) into n from clienti; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 12) A vede solo la propria scheda cliente ('||n||')';
  select provincia into s from ordini where id=o1; r := r||E'\n'||case when s='MB' then 'OK' else 'ERRORE' end||' 12b) Provincia normalizzata ('||s||')';
  o2 := crea_ordine(neg,('[{"formato_id":"'||f2||'","quantita":1}]')::jsonb,'Via Roma 1','Monza',null,null,null,null,null);
  perform annulla_ordine(o2); select stato into s from ordini where id=o2;
  r := r||E'\n'||case when s='annullato' then 'OK' else 'ERRORE' end||' 13) A annulla un ordine non ancora confermato ('||s||')';

  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated','email','b@test.it')::text, true);
  select count(*) into n from ordini; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 14) B non vede gli ordini di A ('||n||')';
  begin perform annulla_ordine(o1); r := r||E'\nERRORE 15) B annulla un ordine di A';
  exception when others then r := r||E'\nOK 15) B non può annullare ordini di altri'; end;
  begin perform crea_ordine(neg,('[{"formato_id":"'||f2||'","quantita":1}]')::jsonb,'Via Po 2','Milano',null,null,null,null,null); r := r||E'\nERRORE 15b) B (in attesa) ordina';
  exception when others then r := r||E'\nOK 15b) B in attesa non può ordinare'; end;

  perform set_config('request.jwt.claims', json_build_object('sub',x,'role','authenticated','email','x@test.it')::text, true);
  select count(*) into n from negozi; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 16) Un estraneo non legge i negozi ('||n||')';
  select count(*) into n from clienti; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 16b) Un estraneo non vede i clienti ('||n||')';
  begin d := disponibilita(neg); r := r||E'\nERRORE 17) Estraneo legge disponibilità';
  exception when others then r := r||E'\nOK 17) Un estraneo non legge la disponibilità'; end;

  perform set_config('request.jwt.claims', json_build_object('sub',g,'role','authenticated','email','g@test.it')::text, true);
  update ordine_righe set prezzo_unitario = 45 where ordine_id=o1 and nome like 'Latta%';
  update ordini set stato='confermato', totale=99 where id=o1; get diagnostics n = row_count;
  r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 18) Il gestore conferma l''ordine con il prezzo';
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated','email','a@test.it')::text, true);
  begin perform annulla_ordine(o1); r := r||E'\nERRORE 19) A annulla dopo la conferma';
  exception when others then r := r||E'\nOK 19) A non può annullare dopo la conferma'; end;
  select totale into d from ordini where id=o1; r := r||E'\n'||case when d=99 then 'OK' else 'ERRORE' end||' 20) A vede il totale confermato ('||d||' €)';

  reset role; set local role anon; perform set_config('request.jwt.claims', '', true);
  select count(*) into n from negozio_pubblico('test-olio-xyz'); r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 21) Chi apre il link senza account vede il nome del negozio';
  begin select count(*) into n from negozi; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 22) Anonimo non legge la tabella negozi ('||n||')';
  exception when others then r := r||E'\nOK 22) Anonimo non legge la tabella negozi'; end;
  begin perform richiedi_accesso(neg,'Z','1','v','c',null,null,null); r := r||E'\nERRORE 23) Anonimo chiede accesso';
  exception when others then r := r||E'\nOK 23) Senza account non si può chiedere accesso'; end;
  raise notice '%', r;
end $$;
