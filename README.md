# 🫒 Il mio Uliveto

Web app per gestire l'intero ciclo di un uliveto, **pianta per pianta**: lavori e trattamenti, raccolta, frantoio, costi e vendite. Pensata per il telefono e installabile sulla schermata Home.

**App:** https://laurentimrc.github.io/Oil-management-system/

## Funzioni

- **Annata**: olive raccolte, olio prodotto, resa media e costo al litro, con confronto sull'anno precedente; consigli stagionali del mese; avvisi sui tempi di carenza dei trattamenti; classifica delle piante più produttive.
- **Piante**: anagrafica di ogni albero (codice, varietà, anno d'impianto, stato, appezzamento, note), creazione in blocco (es. A-1 … A-80), scheda con produzione per anno e storico lavori.
- **Mappa**: vista satellite o stradale, piante colorate per stato o per produzione, posizionamento con GPS o toccando la mappa.
- **Lavori**: potatura, concimazione, trattamenti, irrigazione, lavorazioni, sfalcio, con prodotto, dose, giorni di carenza, ore e costi; assegnabili a tutto l'uliveto, a un appezzamento o a singole piante.
- **Raccolta e frantoio**: kg di olive per pianta o appezzamento, moliture con litri/kg di olio e calcolo automatico della resa.
- **Conti**: spese ed entrate per categoria, saldo dell'annata; i costi di lavori e moliture sono inclusi in automatico.
- **Account e backup**: registrazione con email, recupero password, esportazione completa dei dati in JSON.

## Architettura

- Frontend: un solo file `index.html` (HTML/CSS/JS senza build), [supabase-js](https://github.com/supabase/supabase-js) e [Leaflet](https://leafletjs.com/) da CDN.
- Backend: [Supabase](https://supabase.com) (PostgreSQL + Auth), regione `eu-central-1` (Francoforte).
- Sicurezza: Row Level Security su tutte le tabelle, ogni utente accede solo ai propri dati. La chiave nel codice è la chiave *publishable*, pensata per stare nel browser.
- Hosting: GitHub Pages.

Lo schema completo del database è in [`supabase/schema.sql`](supabase/schema.sql).

## Configurazione Supabase

In **Authentication → URL Configuration** impostare come *Site URL* e tra i *Redirect URLs*:

```
https://laurentimrc.github.io/Oil-management-system/
```

Per l'uso pubblico configurare un SMTP proprio in **Authentication → SMTP Settings**: il servizio email incluso in Supabase ha limiti molto bassi ed è pensato solo per i test.

## Sviluppo in locale

```bash
python3 -m http.server 8000
# poi apri http://localhost:8000
```
