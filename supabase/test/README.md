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
- `notifiche.sql` — promemoria, preferenze, dispositivi e coda delle notifiche (17 controlli; applicare prima anche `notifiche.sql` senza le righe `create extension`)
- `vetrina.sql` — vetrina pubblica senza dati personali, prezzi solo se consentiti, bacheca per titolare/manager/clienti autorizzati (non agricoltore), notifiche ai clienti (14 controlli; applicare prima anche `vetrina.sql` fino alla sezione «Solo su Supabase»)
- `magazzino.sql` — magazzino dell'olio: titolare e manager sì, agricoltore ed estranei no (11 controlli; applicare prima `magazzino.sql`)

Non eseguirli sul database di produzione: inseriscono utenti di prova.
- `clienti_importati.sql` — import di vecchi clienti e inviti: solo titolare e manager importano, nessuna notifica a vuoto, il profilo si collega solo con il codice d'invito o l'email confermata (17 controlli; applicare prima `clienti_importati.sql`)
- `legale.sql` — registro dei consensi (solo propri, non modificabile), annunci come notifica solo a chi li ha attivati, dati del venditore nella vetrina pubblica (10 controlli; applicare prima `legale.sql`). Chiusura dell'account e pulizia degli importati sono nella Edge Function `account`.
