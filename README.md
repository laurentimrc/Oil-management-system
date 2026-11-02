# 🫒 Il mio Uliveto

Web app per gestire l'intero ciclo di un uliveto, **pianta per pianta**: lavori e trattamenti, raccolta, frantoio, costi e vendite. Pensata per il telefono e installabile sulla schermata Home.

**App:** https://laurentimrc.github.io/Oil-management-system/

## Funzioni

- **Senza rete**: lavori, raccolte, piante, appezzamenti, promemoria, conti e magazzino si salvano anche senza campo; restano in coda sul telefono (con l'indicatore "⏳ N da inviare") e partono da soli al ritorno della rete. Ogni riga nuova ha già il suo id, così un invio ripetuto non crea doppioni.
- **Oggi**: all'apertura carenze in corso, lavori in programma nella settimana e pulsanti per registrare lavoro e raccolta; sotto i numeri dell'annata.
- **Annata**: olive raccolte, olio prodotto, resa media e costo al litro, con confronto sull'anno precedente; consigli stagionali del mese; avvisi sui tempi di carenza dei trattamenti; classifica delle piante più produttive.
- **Piante**: anagrafica di ogni albero (codice, varietà, anno d'impianto, stato, appezzamento, note), creazione in blocco (es. A-1 … A-80), scheda con produzione per anno e storico lavori.
- **Appezzamenti** (in Piante → Appezzamenti): via e località con suggerimenti automatici (OpenStreetMap) oppure posizione incollata da Google Maps (coordinate, link o link breve `maps.app.goo.gl`), comune, provincia, foglio e particella catastale; posizione del lotto sulla mappa e link per raggiungerlo.
- **Meteo**: condizioni attuali e previsioni a 7 giorni per ogni appezzamento (Open-Meteo), con avvisi su gelo, pioggia abbondante, giorni adatti ai trattamenti e possibile dilavamento dei trattamenti recenti; meteo anche nella scheda di ogni pianta.
- **Promemoria e notifiche**: lavori da fare con data (anche come ripetizione automatica dopo N giorni); notifiche push sul telefono per meteo (gelo, pioggia forte, giorni adatti ai trattamenti), promemoria del giorno, nuovi clienti e ordini, lavori e raccolte registrati dai collaboratori; preferenze per categoria.
- **Mappa**: vista satellite o stradale, piante colorate per stato o per produzione, posizionamento con GPS o toccando la mappa.
- **Lavori**: potatura, concimazione, trattamenti, irrigazione, lavorazioni, sfalcio, con prodotto, dose, giorni di carenza, ore e costi; assegnabili a tutto l'uliveto, a un appezzamento o a singole piante.
- **Raccolta e frantoio**: kg di olive per pianta o appezzamento, moliture con litri/kg di olio e calcolo automatico della resa.
- **Vendita olio**: negozio con link e QR da condividere; i clienti si registrano e chiedono l'accesso, il gestore li autorizza; prenotazione per formati con controllo della disponibilità, prezzo deciso dal gestore su ogni ordine, consegna all'indirizzo del cliente, incasso registrato automaticamente nei Conti.
- **Vetrina e clienti**: titolare e manager personalizzano la vetrina (copertina, galleria, colore, storia, annata, foto e descrizione dei formati, WhatsApp, prezzi e disponibilità visibili o no), visibile anche a chi non è ancora autorizzato; bacheca di annunci con notifica ai clienti; aggiornamenti in tempo reale (Supabase Realtime) su ordini, richieste e annunci; **punti oliva**: 50 di benvenuto più 20 punti e 10 per litro a ogni ordine consegnato, cinque livelli da Germoglio a Ulivo secolare con premi decisi dal produttore. I punti si calcolano dagli ordini consegnati, quindi il cliente non può modificarli.
- **Magazzino dell'olio**: litri rimasti annata per annata (le moliture entrano da sole, l'olio degli anni precedenti e quello usato in casa si registrano a mano); titolare e manager scelgono quanti litri mettere in vendita, mai più di quelli in magazzino né meno di quelli già prenotati.
- **Conti**: spese ed entrate per categoria, saldo dell'annata; i costi di lavori e moliture sono inclusi in automatico.
- **Collaboratori**: il titolare invita via email un *manager* (vede e modifica tutto, tranne il team) o un *agricoltore* (vede l'uliveto, registra lavori e raccolte, aggiorna le piante; niente conti, vendite e costi). L'invito si attiva solo con email confermata; l'accesso si revoca in ogni momento.
- **QR code**: ogni pianta ha un QR univoco che apre direttamente la sua scheda; stampa delle etichette in fogli A4 da 12 (tutte o per appezzamento).
- **Cosa c'è di nuovo**: dopo ogni aggiornamento una finestra mostra, una sola volta e filtrate per ruolo, le funzioni nuove con un pulsante per provarle; lo storico completo è in Impostazioni → Novità. Le novità si aggiungono in cima all'array `NOVITA` (vedi `CLAUDE.md`).
- **Guida iniziale**: presentazione animata delle funzioni al primo accesso (scorrevole, saltabile), con schermate e testi adatti al ruolo (titolare, manager, agricoltore); richiamabile dalle impostazioni.
- **Account e backup**: registrazione con email, recupero password, esportazione completa dei dati in JSON.

## Architettura

- Frontend: un solo file `index.html` (HTML/CSS/JS senza build), [supabase-js](https://github.com/supabase/supabase-js) e [Leaflet](https://leafletjs.com/) da CDN.
- Backend: [Supabase](https://supabase.com) (PostgreSQL + Auth), regione `eu-central-1` (Francoforte).
- Sicurezza: Row Level Security su tutte le tabelle, ogni utente accede solo ai propri dati. La chiave nel codice è la chiave *publishable*, pensata per stare nel browser.
- Notifiche: Web Push (service worker `sw.js`), Edge Function [`supabase/functions/notifiche`](supabase/functions/notifiche/index.ts) e job `pg_cron` (coda ogni minuto, promemoria e meteo ogni mattina). Le chiavi VAPID sono generate dalla funzione e restano nel database.
- Link brevi di Google Maps: Edge Function [`supabase/functions/risolvi-link`](supabase/functions/risolvi-link/index.ts), che segue i reindirizzamenti solo verso host di Google.
- Hosting: GitHub Pages.

Lo schema del database è in [`supabase/schema.sql`](supabase/schema.sql) (gestione dell'uliveto) [`supabase/collaboratori.sql`](supabase/collaboratori.sql) (accesso condiviso per ruolo), [`supabase/notifiche.sql`](supabase/notifiche.sql) (promemoria e notifiche) [`supabase/vendite.sql`](supabase/vendite.sql) (vendita olio: i clienti scrivono solo tramite funzioni che verificano autorizzazione e disponibilità), [`supabase/magazzino.sql`](supabase/magazzino.sql) (magazzino dell'olio) e [`supabase/vetrina.sql`](supabase/vetrina.sql) (vetrina pubblica, bacheca, notifiche ai clienti, foto nello storage `vetrine`, tempo reale).

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
