# STATO DEL PROGETTO — App Appunti (da leggere all'inizio di ogni chat)

Aggiornato da Claude a ogni consegna. Tenere questo file CORTO (obiettivo: sotto 10 KB). I dettagli delle consegne
passate stanno in `docs/storico.md` (archivio: non rileggerlo, solo `grep` se serve il perché di una scelta).
Contesto generale e vincoli di design: istruzioni del Progetto e file `stato-e-metodo-app-appunti.md` nel Progetto.

## PUNTO DI RIPRESA (27/11/2026) — leggere subito dopo l'intestazione
Ultimo commit di codice: 5a03c15 (IPA consegnato; compila 0 errori). Dal 26/11 nessuna modifica di codice: solo prove su PDF generati da Claude in Python
(script in `prove/segnalino/`) e salvati da Cristina con Anteprima/Markup di File (iPadOS 27.2.1).

**DECISIONE (27/11): FILE UNICO CON STRATO «A SEGNALINI»** (sostituisce l'idea dei «due file»). Modello GoodNotes più un passo in più:
- Nel PDF i nostri elementi (tratti, foto, poi testi) sono DISEGNATI NELLA PAGINA come contenuto vero (linee/forme vettoriali, immagini): versione universale,
  nitida, identica ovunque, non modificabile da Anteprima o altri. Non annotazioni.
- Il blocco è racchiuso fra due testi invisibili (`3 Tr`, corpo 1): «APT-INIZIO v2 n<conteggio> p<pagina> D:<dati>» … «APT-FINE». In `D:` i dati per
  ricostruire tutto modificabile (zlib + base64).
- Riaprendo il PDF l'app trova i segnalini, controlla i conti, toglie il blocco dalla pagina e ricostruisce gli elementi modificabili (o almeno eliminabili).
  Se i conti non tornano: non tocca nulla, mostra tutto com'è e avvisa.
- I segni fatti in Anteprima restano annotazioni sue (`/Stamp` con `AAPL:AKExtras`, autore «Mobile User»): l'app li mostra e non li tocca.

**Esiti delle prove (Anteprima salva → Claude analizza il file):**
1. Etichette PDF (contenuto marcato `BDC/EMC`, Optional Content/livelli): ELIMINATE da Anteprima (riscrive tutta la pagina con Quartz). Le linee restano identiche.
2. Segnalini a testo invisibile (`3 Tr` e anche testo con `ca 0`): SOPRAVVIVONO, nell'ordine giusto; la grafica originale resta fuori dal blocco.
3. Stilografica come forma piena + dati nel segnalino (3,6 K caratteri): dati identici byte per byte. Foto JPEG 1600×1200 intera e ritagliata (clip):
   JPEG identico byte per byte (non ricompresso), ritaglio conservato con la parte nascosta, immagine salvata una sola volta.
4. Secondo salvataggio consecutivo: tutto ancora integro. Anteprima riscrive di nuovo il blocco cambiando SOLO la formattazione (a capo, `/Cs1 cs` ripetuti
   tolti) → il lettore deve interpretare gli OPERATORI, mai confrontare i byte del blocco.
5. Peso: cresce solo per lo strato di Anteprima (i suoi segni sono immagini + dati Apple: 241 KB → 649 KB → 1,17 MB); il nostro strato non cresce.
   Tratti come linee: ~60 KB contro 3,8 MB delle immagini attuali, 0,2 s.
Non verificato: Acrobat e altri programmi, reimport in GoodNotes, pagine molto piene (lunghezza massima del testo invisibile: valutare spezzarlo in più
segnalini «APT-D 1/n»), testi digitati dell'app nel blocco, PDF originali complessi (scansioni, moduli). Effetto collaterale: «APT» si trova cercando nel testo.

**Decisioni di Cristina sul resto (valide):** penne ed evidenziatori identici all'app (texture di matite/pennelli non importano; pressione non usata:
Pencil economica); evidenziatore disegnato PRIMA dell'inchiostro (il nero sotto il giallo resta nero) e negli incroci si scurisce pochissimo; opzione in
app «PDF senza annotazioni» (= togliere il blocco); se un file manca o è stato riscritto da fuori l'app avvisa e non si rompe; mai sovrascrivere in silenzio.

**Due binari di lavoro (deciso il 27/11):**
- **A — app principale:** sistema a segnalini, prima SOLO su documenti di prova. Vedi «Prossimi passi».
- **B — app «Tester» separata** per un motore grafico nostro (stessa formula per schermo e PDF → identità 100%, ricostruzione perfetta).
  Minima: pagina bianca, penna, stilografica, evidenziatore, colore, spessore, annulla, cancella tutto; «Esporta resoconto» (punti grezzi della Pencil,
  PDF generato, tempi) e «Importa impostazioni» (parametri del motore in un file mandato da Claude, senza nuovo IPA); confronto PencilKit/motore affiancati.
  Proposta di Claude non ancora scelta: via di mezzo = PencilKit per scrivere (latenza, palmo), motore nostro per il tratto finito/PDF/riapertura.
  Limite SideStore: 3 app attive (SideStore + Appunti + Tester).

**Altro in sospeso:** mostrare il commit installato in Impostazioni e nel rapporto (offerto, non approvato); verifiche iPad sulle consegne del 19/11;
foto a 8 bit (consegnata, NON verificata: serve una foto nuova in un documento nuovo).

## Come si lavora (metodo in vigore)
- Repository `gmveronesi-cloud/app-appunti`, **pubblico** (scelta di Cristina, confermata il 04/10/2026: vantaggio, minuti di compilazione gratuiti; nessun dato personale né chiave nel repository, da non inserirne mai).
  Se non è collegato alla sessione: `list_repos` → `add_repo` (access push) → clone → `register_repo_root`. Lo fa Claude, non Cristina.
- Il progetto è `Appunti.swiftpm` (una vista per file). Claude modifica i file e fa push su `main`.
- A ogni push che tocca codice, GitHub Actions (`.github/workflows/compila.yml`, macOS, Xcode più recente: 26.6) compila per
  simulatore iPad. Non parte per modifiche a `*.md`, `docs/`, `prove/`. La schermata nel simulatore si scatta solo con
  «Run workflow» a mano o con `[schermata]` nel messaggio del commit. Raggruppare più modifiche per ogni push.
- Esito: i log grezzi di GitHub NON sono raggiungibili (host bloccato dal proxy: non aggirare). Il workflow scrive
  `riassunto.txt`, `build.log` (ed eventualmente `avvio.png`) sul ramo `esiti`:
  `git fetch origin +esiti:refs/remotes/origin/esiti` (con il `+`: il ramo viene riscritto ogni volta), poi `git show origin/esiti:riassunto.txt`
  (mai checkout nella working tree). La prima riga riporta il commit compilato: controllare che sia quello appena inviato.
  Stato del run: API `api.github.com/repos/gmveronesi-cloud/app-appunti/actions/runs?head_sha=<sha>` con `$GH_TOKEN`.
- Claude corregge gli errori di compilazione da solo prima di dire a Cristina di provare.
- Cristina prova SOLO con l'IPA (`Appunti.ipa`) installato con SideStore (Apple ID gratuito: rinnovo ogni 7 giorni, massimo 3 app attive).
  Swift Playgrounds NON si usa più (deciso il 27/11/2026). Il progetto resta in formato `Appunti.swiftpm`.
- Ogni consegna: due righe su cosa è cambiato e cosa provare; nessuna spiegazione del codice.
- Cristina non è sviluppatrice: passi uno alla volta, italiano semplice, dire sempre cosa non si può verificare.
- **REGOLA DI CHIUSURA (18/11/2026, deciso da Cristina)**: come ULTIMO passaggio di ogni richiesta Claude chiede soltanto «genero ipa?». Se Cristina risponde «ok»,
  Claude genera il file `Appunti.ipa` e lo consegna IN CHAT come allegato (`SendUserFile`), NON come link che rimanda a Safari. Metodo: lanciare il workflow
  «Pacchetto iPad» (`pacchetto.yml`, se serve con `runner=macos-15-intel`) sul commit appena compilato senza errori, attendere la fine, poi scaricare il ramo `ipa`
  con git (`git fetch origin +ipa:refs/remotes/origin/ipa`, poi `git show origin/ipa:Appunti.ipa > /home/claude/Appunti.ipa`; l'host raw di GitHub può essere bloccato dal proxy: non aggirare)
  e inviare il file. Dire il commit di provenienza e il peso. Senza «ok» non si genera nessun IPA. Se il file non si può consegnare, dirlo chiaramente (non ripiegare in silenzio sul link).
- **REGOLE SUI FILE DELL'UTENTE (18/11/2026, valgono per ogni modifica)**:
  1. **Nessuna modifica irreversibile sui file di Cristina** (PDF, quaderni, immagini, modelli): ogni scrittura deve poter essere annullata o recuperata. Quindi: mai sovrascrivere senza verifica
     (come già fanno `PDFCompatta`/`PDFAggiunta`: controllo strutturale e ritorno al file com'era se qualcosa non torna), scrittura atomica, dati originali conservati (`AptDati`, foto originali nascoste),
     operazioni sul documento annullabili, e nessun cancellamento definitivo senza conferma esplicita. In dubbio: conservare l'originale e chiedere.
  2. **Peso minimo e file ottimizzati**: ogni nuova funzione deve far pesare il meno possibile i file (niente dati duplicati o scarti in coda, immagini e tratti nel formato più compatto SENZA perdere qualità
     visibile né modificabilità: compressione senza perdita, PNG/JPEG ottimizzati, riuso degli oggetti) e ottimizzarli (compattazione, `alleggerisciImmagini`). Prima di consegnare, controllare l'effetto sul peso di un file
     (menu del titolo → «Peso») e dirlo a Cristina insieme a cosa provare.


## Cosa non si può verificare da qui
Pencil, PencilKit, salvataggio su iCloud, selettore cartelle, fotocamera, notifiche, resa reale dell'interfaccia su iPadOS 27 (il runner ha SDK 26.5):
solo sull'iPad di Cristina. La compilazione controlla solo che il codice compili.

## Struttura del codice (`Appunti.swiftpm`, ~8500 righe)
Le classi grandi sono divise in estensioni `Nome+Parte.swift`: per cercare una funzione usare grep.
- `MyApp.swift` — ingresso. `Tema/Tema.swift` — `AptTema` e componenti grafici (`AptIcona`, `AptLinea`, `aptBarra`, `aptPannello`, stili pulsante).
- `Libreria/` — Libreria su cartelle reali di iCloud Drive: `AptStore` (stato) + `AptStore+Ordine` (ordinamento, barra laterale, selezione), `+Cartelle`, `+Importa` (nuovi documenti, importazioni, esportazione), `+Raccolte` (raccolte e drag & drop);
  `Modelli`, `FileSystem`, `Contenuto`, `Elementi`, `BarraLaterale`, `Fogli`, `Miniature`, `Utilita`, `LibreriaView`.
- `Editor/` — `NotesModel` (strumenti) + `+Gesti`, `+Documento` (apertura, tele, lettura tratti, aggiungi pagine), `+Salvataggio`; `EditorView`, `BarraStrumenti`, `Strumenti`, `ImpostazioniEditor`, `PDFKitView`, `PaginaTela`,
  `RicercaPDF`, `Lazo` + `+Selezione`, `+Contorno`, `+Menu`; `Forme`, `Testo`, `Immagine` + `+Cornice`, `+Gesto`, `+Menu`; `Sorgenti`, `Cattura`, `Vassoio`, `Orologio`;
  `NotesModel+Pagina` (vista, estensione, vai a pagina), `PannelloPagina` (menu estendi e finestra `···`), `VistaDoppia` (pezzi della schermata divisa),
  `NotesModel+Quaderno` (quaderno, nuova pagina, scorrimento oltre la fine, presentazione pagina Modelli), `PaginaModelli`, `ModelliArchivio`, `RitagliaModello`.
- `Tastiera/TastieraApp.swift` — tastiera nostra (nata perché Swift Playgrounds non mostrava la tastiera di sistema; da riverificare nell'IPA).
- `docs/` — `formato-segnalini.md` (progetto del nuovo salvataggio), `mockup-editor.html` (decisioni dell'Editor, fonte di design), `stile-grafico.md` e `.html` (regole grafiche), `storico.md` (archivio).
- `prove/segnalino/` — script Python delle prove del 26–27/11 (PDF a segnalini, controllo dopo Anteprima). `prove/` — prove di fattibilità Swift (tratti, immagine) già adottate nel codice; non compilate dal workflow. Tenute come riferimento.
- Stored properties delle classi divise restano nel file principale (le estensioni non possono averne): una nuova proprietà va nel file principale della classe.

## Scelte tecniche da ricordare (valgono per ogni modifica)
- **Salvataggio nel PDF (formato ATTUALE, da sostituire col formato a segnalini: vedi PUNTO DI RIPRESA)**: ogni pagina riceve annotazioni visibili in ogni lettore (ink `AptTratto`, stamp per le immagini, freeText `AptTesto`) PIÙ un'annotazione
  nascosta con i dati modificabili (`/AptDati` = PKDrawing in base64; immagini con `/AptInfo`). All'apertura le annotazioni dell'app vengono tolte dal documento
  in memoria e tutto torna modificabile. Si salva con Salva, o da solo se ci sono modifiche, al cambio/chiusura scheda e uscendo in Libreria.
- **Risoluzione tele**: la tela PencilKit di ogni pagina è `NotesModel.risoluzione` = 3× la pagina, rimpicciolita con `transform` (`PaginaTela`): tratti nitidi fino a ~3× di zoom.
  Coordinate tela = 3 × punti pagina; spessori, soglie del lazo e delle forme sono moltiplicati. Se pesa in memoria: scendere a 2.
- **Evidenziatore**: stile «Pastello» = `.marker` (predefinito dal 12/10) o «Linea netta» = `.monoline` semitrasparente; livelli: vedi «12/10» punto 3.
- **Livelli**: ordine di creazione (data del tratto / `creazione` dell'immagine). Con gomma e lazo tutti i tratti si «uniscono» nella tela; il testo sta sempre sopra.
- **Testo**: livelli `CATextLayer` vettoriali nella pila della pagina (`ImmagineControllo.ridisegna` mette insieme strati di tratti, immagini e testi per data di creazione);
  con larghezza impostata il testo è GIUSTIFICATO e riempie tutto il blocco (ultima riga a sinistra); finestra di scrittura con selettore dimensione carattere 8–96 (`FinestraTesto`);
  annotazioni freeText solo al salvataggio, con chiave `/AptInfoTesto` (larghezza, creazione). `ElementoTesto.larghezza` nil = automatica. Tastiera nostra (modo `multiriga`).
- **Interfaccia**: nessun `TextField` né tastiera di sistema; nelle viste nuove solo `AptTema` e componenti di `Tema.swift`; niente scritte piccole che spiegano l'uso.
  I colori degli strumenti sono scelti da Cristina e non seguono il tema.
- **Impostazioni** (strumenti, pallini colore, barra, destinazione cattura) in UserDefaults.
- `Package.swift`: iOS 17.0 minimo, capability fotocamera dichiarata (serve alla scansione). Non modificare a mano oltre il necessario.


## Decisioni Editor
Fonte: `docs/mockup-editor.html`. Elenco completo delle decisioni (30/09 e successive) in `docs/storico.md`, sezione «Decisioni Editor (spostate da STATO.md il 27/11)».

## Problemi aperti
- Da verificare (07/10): scorrimento «Singolo» usa `usePageViewController` — se le tele Pencil non compaiono in quella modalità, tornare a «Continuo» e correggere; estensione su pagine ruotate non gestita;
  in vista doppia annulla/ripeti usano la cronologia di sistema, condivisa tra i due riquadri (l'ultima azione, di qualunque riquadro).
- Tastiera di sistema: era assente in Swift Playgrounds; da riverificare nell'IPA (se c'è, valutare se tenere la tastiera nostra).
- Da verificare sull'iPad (consegna del 05/10): vedi sopra; in particolare riordino pagine (drag nelle miniature), maniglie del testo, posizione barra flottante.
- Limiti noti: aggiungi PDF solo in fondo al documento; le miniature non mostrano i tratti non ancora salvati; il testo non si ruota (nel lazo si sposta e cambia solo la larghezza).


## Prossimi passi
Quando Cristina scrive «iniziamo con il prossimo passo», partire dal primo punto non fatto, senza chiedere conferme.
1. **Binario A — progetto tecnico del formato a segnalini** — FATTO il 27/11: `docs/formato-segnalini.md`, APPROVATO da Cristina il 27/11
   (anche: evidenziatori uniti senza scurirsi negli incroci nel PDF; testi come testo vero Helvetica). Prossimo: «Prova 4» (§8), poi punto 2. Traccia originale: contenuto di `D:` (elementi in ordine di
   livello: tratti con strumento/colore/spessore/punti e spessori per punto; foto con id, riquadro, ritaglio, rotazione, riferimento all'immagine nel PDF;
   testi), controllo (conteggio + impronta dei dati), posizione del blocco (in fondo al contenuto della pagina, quindi sopra), come togliere il blocco
   all'apertura (PDFKit non modifica il contenuto delle pagine: serve scrittura nostra del `/Contents`, vedi `PDFLettore`/`PDFAggiunta`), compatibilità con
   i file vecchi (si leggono come oggi, passano al nuovo formato al primo salvataggio con verifica prima di sostituire).
2. **Binario A — scrittura e lettura** nell'app, attivabili solo sui documenti di prova; ciclo app → Anteprima → app più volte; poi peso e tempi.
3. **Binario B — app Tester** (cartella separata nel repository, IPA separato, bundle id diverso), quando Cristina vuole.
4. Vecchi passi ancora validi (verifiche): quaderni, nuova pagina tirando oltre l'ultima, «Aggiungi pagina», finestra Esporta; Gigante che si allarga ai
   bordi; tema scuro schermata per schermata; esportazione dalla Libreria con intervallo pagine (da concordare).
