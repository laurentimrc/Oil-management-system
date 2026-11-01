# Il mio Uliveto — note per chi sviluppa

- L'app è un solo file: `index.html` (niente build). Database e permessi in `supabase/*.sql`, funzioni server in `supabase/functions/`.
- **Ogni nuova funzione visibile agli utenti va annunciata** nella finestra "Cosa c'è di nuovo": aggiungi in cima all'array `NOVITA` in `index.html` un oggetto con `n` = numero più alto + 1, data, titolo e voci (`ic`, `t`, `d`, facoltativi `perm`, `cta`, `vai`). Gli utenti la vedono una volta al prossimo accesso.
- Se la funzione cambia cosa possono fare i ruoli, aggiorna anche `guidaSchermate()` (guida iniziale) e i controlli in `supabase/test/`.
- I permessi si controllano nel database (RLS), non solo nell'interfaccia: ogni nuova tabella deve avere RLS e regole per titolare, manager, agricoltore.
- Testi dell'interfaccia in italiano, frasi semplici.
