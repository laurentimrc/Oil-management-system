# Controlli di sicurezza

Script che simulano utenti diversi (titolare, manager, agricoltore, clienti, estranei, anonimi)
e verificano le regole di accesso. Ogni riga dell'esito inizia con `OK` o `ERRORE`.

Vanno eseguiti su un database **di prova** (PostgreSQL 15+) dopo aver applicato, in ordine,
`00_impalcatura_auth.sql`, `schema.sql`, `vendite.sql` e `collaboratori.sql`. Il primo file riproduce
lo schema `auth` di Supabase (tabella `auth.users`, funzioni `auth.uid()` e `auth.jwt()`,
ruoli `anon` e `authenticated`).

- `vendite.sql` — clienti, approvazione, ordini, disponibilità (27 controlli)
- `ruoli.sql` — collaboratori: inviti, manager, agricoltore, revoca (31 controlli)
- `manager_vendite.sql` — il manager gestisce il negozio del titolare (14 controlli)

Non eseguirli sul database di produzione: inseriscono utenti di prova.
