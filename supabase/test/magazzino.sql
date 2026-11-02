-- Magazzino dell'olio: titolare e manager sì, agricoltore ed estranei no.
do $$
declare
  o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); a uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  n int; r text := ''; g uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (o,'mo@t.it',now()),(m,'mm@t.it',now()),(a,'ma@t.it',now()),(x,'mx@t.it',now());
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub',o,'email','mo@t.it')::text, true);
  insert into magazzino_olio(annata,litri,descrizione) values (2025,30,'Latte in cantina') returning id into g;
  insert into collaboratori(email,ruolo,azienda) values ('mm@t.it','manager','U'),('ma@t.it','agricoltore','U');
  begin insert into magazzino_olio(annata,litri) values (2025,-5); r := r||E'\nERRORE 1) litri negativi accettati';
  exception when others then r := r||E'\nOK 1) Litri negativi rifiutati'; end;
  begin insert into magazzino_olio(annata,litri,tipo) values (2025,5,'furto'); r := r||E'\nERRORE 2) tipo non valido accettato';
  exception when others then r := r||E'\nOK 2) Tipo non valido rifiutato'; end;
  -- manager
  perform set_config('request.jwt.claims', json_build_object('sub',m,'email','mm@t.it')::text, true);
  perform accetta_inviti();
  select count(*) into n from magazzino_olio; r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 3) Il manager vede il magazzino del titolare ('||n||')';
  insert into magazzino_olio(user_id,tipo,annata,litri,descrizione) values (o,'scarico',2025,2,'Uso in famiglia');
  r := r||E'\nOK 4) Il manager registra un''uscita';
  update magazzino_olio set litri = 28 where id = g; get diagnostics n = row_count;
  r := r||E'\n'||case when n=1 then 'OK' else 'ERRORE' end||' 5) Il manager modifica un movimento';
  -- agricoltore
  perform set_config('request.jwt.claims', json_build_object('sub',a,'email','ma@t.it')::text, true);
  perform accetta_inviti();
  select count(*) into n from magazzino_olio; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 6) L''agricoltore non vede il magazzino ('||n||')';
  begin insert into magazzino_olio(user_id,annata,litri) values (o,2025,5); r := r||E'\nERRORE 7) agricoltore scrive nel magazzino';
  exception when others then r := r||E'\nOK 7) L''agricoltore non può scrivere nel magazzino'; end;
  update magazzino_olio set litri = 1 where id = g; get diagnostics n = row_count;
  r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 8) L''agricoltore non può modificare il magazzino';
  -- estraneo
  perform set_config('request.jwt.claims', json_build_object('sub',x,'email','mx@t.it')::text, true);
  select count(*) into n from magazzino_olio; r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 9) Un estraneo non vede il magazzino ('||n||')';
  begin insert into magazzino_olio(user_id,annata,litri) values (o,2025,5); r := r||E'\nERRORE 10) estraneo scrive nel magazzino altrui';
  exception when others then r := r||E'\nOK 10) Un estraneo non può scrivere nel magazzino altrui'; end;
  delete from magazzino_olio where id = g; get diagnostics n = row_count;
  r := r||E'\n'||case when n=0 then 'OK' else 'ERRORE' end||' 11) Un estraneo non può cancellare';
  raise notice '%', r;
end $$;
