do $$
declare
  o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); ag uuid := gen_random_uuid(); c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
  neg uuid; f1 uuid; o1 uuid; n int; r text := ''; j jsonb; s text;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'o5@t.it',now()),(m,'m5@t.it',now()),(ag,'ag5@t.it',now()),(c,'c5@t.it',now()),(c2,'c6@t.it',now());
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o5@t.it')::text, true);
  insert into negozi(slug,nome,litri_in_vendita,vetrina) values ('neg-v5','Olio di Marco',100,'{"titolo":"Il nostro olio","colore":"oliva"}') returning id into neg;
  insert into formati(negozio_id,nome,litri,prezzo,descrizione) values (neg,'Latta 5 L',5,55,'Ideale per la famiglia') returning id into f1;
  insert into collaboratori(email,ruolo) values ('m5@t.it','manager'),('ag5@t.it','agricoltore');
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m5@t.it')::text, true); perform accetta_inviti();
  update negozi set vetrina = vetrina || '{"storia":"Dal 1950"}', copertina_url='https://x/c.jpg' where id=neg; get diagnostics n=row_count;
  r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 1) Il manager personalizza la vetrina';
  update formati set foto_url='https://x/f.jpg' where id=f1; get diagnostics n=row_count; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 2) Il manager mette la foto a un formato';
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'email','ag5@t.it')::text, true); perform accetta_inviti();
  update negozi set vetrina='{}' where id=neg; get diagnostics n=row_count; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 3) L''agricoltore non può cambiare la vetrina';

  -- visitatore anonimo
  reset role; set local role anon; perform set_config('request.jwt.claims', '', true);
  j := vetrina_pubblica('neg-v5');
  r := r||E'\n'||case when j->'vetrina'->>'storia'='Dal 1950' and j->>'copertina' is not null then 'OK' else 'ERRORE' end||' 4) Chi apre il link vede la vetrina senza account';
  r := r||E'\n'||case when (j->'formati'->0->>'prezzo') is null then 'OK' else 'ERRORE' end||' 5) …ma non i prezzi (nascosti per scelta predefinita)';
  r := r||E'\n'||case when j::text not like '%@%' then 'OK' else 'ERRORE' end||' 6) …e nessun dato personale (email/clienti)';
  r := r||E'\n'||case when (j->>'disponibili')::numeric=100 then 'OK' else 'ERRORE' end||' 7) Disponibilità mostrata ('||(j->>'disponibili')||' L)';
  reset role; set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o5@t.it')::text, true);
  update negozi set vetrina = vetrina || '{"prezzi_pubblici":true,"mostra_disponibilita":false}' where id=neg;
  reset role; set local role anon; perform set_config('request.jwt.claims', '', true);
  j := vetrina_pubblica('neg-v5');
  r := r||E'\n'||case when (j->'formati'->0->>'prezzo')::numeric=55 and j->>'disponibili' is null then 'OK' else 'ERRORE' end||' 8) Prezzi pubblici e disponibilità nascosta quando il gestore lo sceglie';
  reset role; set local role authenticated;

  -- clienti
  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c5@t.it')::text, true);
  perform richiedi_accesso(neg,'Anna','1','Via A','Monza',null,null,null);
  perform set_config('request.jwt.claims', json_build_object('sub',c2,'email','c6@t.it')::text, true);
  perform richiedi_accesso(neg,'Bruno','2','Via B','Milano',null,null,null);
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o5@t.it')::text, true);
  insert into annunci(negozio_id,titolo,testo) values (neg,'Bozza prima dell''approvazione','x');
  update clienti set stato='approvato' where user_id=c;
  -- dal 2026-11 gli annunci arrivano come notifica solo a chi li ha attivati (legale.sql)
  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c5@t.it')::text, true);
  perform imposta_annunci(neg, true, '1.0');
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','o5@t.it')::text, true);
  insert into annunci(negozio_id,emoji,titolo,testo) values (neg,'🫒','Olio nuovo pronto!','Raccolta 2026 disponibile da sabato.');
  perform set_config('request.jwt.claims', json_build_object('sub',c,'email','c5@t.it')::text, true);
  select count(*) into n from annunci; r := r||E'\n'||case when n=2 then 'OK' else 'ERRORE' end||' 9) Il cliente autorizzato legge la bacheca ('||n||')';
  begin insert into annunci(negozio_id,titolo) values (neg,'Falso'); r := r||E'\nERRORE 10) cliente pubblica annunci';
  exception when others then r := r||E'\nOK 10) Il cliente non può pubblicare annunci'; end;
  o1 := crea_ordine(neg,('[{"formato_id":"'||f1||'","quantita":2}]')::jsonb,'Via A','Monza',null,null,null,null,null);
  perform set_config('request.jwt.claims', json_build_object('sub',c2,'email','c6@t.it')::text, true);
  select count(*) into n from annunci; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 11) Chi non è autorizzato non legge la bacheca ('||n||')';
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'email','ag5@t.it')::text, true);
  select count(*) into n from annunci; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 12) L''agricoltore non vede la bacheca ('||n||')';
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','m5@t.it')::text, true);
  update ordini set stato='confermato', totale=110 where id=o1;
  update ordini set stato='in_consegna' where id=o1;
  update ordini set stato='consegnato' where id=o1;
  update ordini set nota_gestore='grazie' where id=o1;   -- nessun cambio di stato: nessuna notifica
  reset role;
  select string_agg(titolo||' — '||coalesce(testo,''), E'\n     ' order by id) into s from coda_notifiche where destinatario=c;
  r := r||E'\n--- Notifiche ricevute dal cliente:\n     '||s;
  select count(*) into n from coda_notifiche where destinatario=c; r := r||E'\n'||case when n=5 then 'OK' else 'ERRORE' end||' 13) Il cliente riceve 5 notifiche: autorizzazione, annuncio, conferma, consegna in corso, consegnato ('||n||')';
  select count(*) into n from coda_notifiche where destinatario=c2; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 14) Chi non è autorizzato non riceve annunci ('||n||')';
  raise notice '%', r;
end $$;
