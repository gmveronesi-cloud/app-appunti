# STATO DEL PROGETTO — App Appunti (da leggere all'inizio di ogni chat)

Aggiornato da Claude a ogni consegna. Tenere questo file CORTO (obiettivo: sotto 10 KB). I dettagli delle consegne
passate stanno in `docs/storico.md` (archivio: non rileggerlo, solo `grep` se serve il perché di una scelta).
Contesto generale e vincoli di design: istruzioni del Progetto e file `stato-e-metodo-app-appunti.md` nel Progetto.

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
- Cristina sull'iPad: scarica lo ZIP da github.com (Code → Download ZIP), lo decomprime in File, apre `Appunti.swiftpm`
  in Swift Playgrounds, preme Esegui e riferisce cosa vede. (Working Copy: l'app trovata era una copia in cinese, non quella di Anders Borum; da rivedere.)
- Ogni consegna: due righe su cosa è cambiato e cosa provare; nessuna spiegazione del codice.
- Cristina non è sviluppatrice: passi uno alla volta, italiano semplice, dire sempre cosa non si può verificare.

## Cosa non si può verificare da qui
Pencil, PencilKit, salvataggio su iCloud, selettore cartelle, fotocamera, notifiche, resa reale dell'interfaccia su iPadOS 27 (il runner ha SDK 26.5):
solo sull'iPad di Cristina. La compilazione controlla solo che il codice compili.

## Stato (04/10/2026)
- Tutto ciò che è stato consegnato è compilato (0 errori) e **verificato da Cristina sull'iPad** il 04/10 sera: Libreria, Editor, tratti, forme,
  testo, immagini, timer, penna screenshot, vassoio, lazo con immagini, aggiungi PDF, pannello «Modifica».
- Check-up del 04/10 sera: tolta la diagnostica `ProvaNitidezza`, sistemati i 3 avvisi di compilazione, STATO.md snellito, README aggiornato, i 4 file più grandi spezzati in file da 70-340 righe (solo spostamento di codice; per questo molti membri `private` sono ora interni), mockup HTML allineati al marrone terracotta.
- **Liquid Glass: NON voluto** (decisione di Cristina, 04/10/2026). Lo stile proprio (`AptTema`) resta quello definitivo: non usare `.glassEffect()`.

- **Salvataggio automatico/manuale** (in Impostazioni → «Salvataggio»; chiave `ed.salvaAuto`). Manuale = solo con «Salva»; con modifiche non salvate, uscendo/cambiando scheda compare «Salva / Non salvare / Annulla».
  Automatico (predefinito), **a due livelli** (06/10, da PROVARE su iPad; codice in `NotesModel+Recupero.swift` e `programmaSalvataggio` in `NotesModel.swift`):
  1. *Diario di recupero*: ogni 2 s di lavoro (throttle, non riparte a ogni tratto) si scrivono solo le pagine cambiate (`pagineSporche`) in `Application Support/Recupero/<hash percorso>/p<n>.rec` + `base.rec` (dimensione e data del PDF su disco). All'apertura, se il PDF è quello di base, le modifiche si rimettono (`ripristinaRecupero`). Non è su iCloud.
  2. *PDF*: scrittura completa (`save()`) dopo 20 s di pausa, al cambio/chiusura scheda, uscendo in Libreria, con l'app in secondo piano, ogni 10 min se si lavora di continuo, e subito (1 s) se cambia l'ordine/numero delle pagine (`strutturaCambiata`: il diario indicizza le pagine per posizione nel PDF su disco). Dopo il salvataggio il diario si cancella. Il PDF resta la fonte di verità; il diario è una rete di sicurezza.
  Limite noto: `save()` rigenera ancora le annotazioni di TUTTE le pagine (lento sui PDF grandi, ma ora raro); idea futura: cache per pagina. `canvases`/`contenitori` tengono tutte le pagine viste (memoria nei PDF lunghi): idea futura, rilasciare quelle lontane.

- Nessuna notifica dopo il salvataggio (rimossa su richiesta; restano solo gli errori).
- **Consegna del 05/10 (compilata, DA PROVARE su iPad)**: lazo che seleziona anche i testi (filtro «Testi» nel pannello del lazo; un tocco su un testo lo sceglie);
  testo a più righe (tasto «A capo» della nostra tastiera) con blocco a larghezza regolabile (maniglie ai lati, cambia solo le parole per riga) e livelli
  nella stessa pila di tratti e immagini (data di creazione; «Porta sopra/sotto» anche per i testi); incolla del lazo rimette tratti, immagini e testi insieme;
  «Aggiungi PDF» annullabile; pagine riordinabili (miniature: tenere premuto e trascinare, annullabile); barra flottante: posizione ricordata (per orientamento) e
  trascinamento corretto; Annulla/Ripeti attivi solo quando serve; la cronologia di annulla si azzera cambiando documento. Pulsante Salva visibile solo col salvataggio manuale.

- **Consegna del 06/10 (da compilare e PROVARE su iPad)**: barra alta con sola freccia «‹» a sinistra; tocco sul nome del PDF = menu (peso del file, Rinomina, Elimina; rinomina = chiude, sposta, riapre il file e aggiorna `store.schede`/ordini);
  zoom: minimo = 0,4× pagina a tutta larghezza (07/10, era 0,8), massimo 6 (`NotesModel.zoomMassimo`, `AptPDFView`), tele a risoluzione 4 (nitide fino a zoom 4; tra 4 e 6 il tratto si ammorbidisce un poco: se pesa in memoria tornare a 3).
  Poi: parte destra della barra alta, poi miniature (elementi da dire da Cristina).
- **Consegna del 06/10 (pomeriggio, da compilare e PROVARE su iPad)**:
  1. Tocco a due dita = annulla: ora è un riconoscitore nostro (`DueDitaTap` in `NotesModel+Gesti.swift`): scatta solo se le due dita si alzano entro 0,4 s, senza spostarsi (>10 pt) e senza terzo dito; pizzico/scorrimento/zoom non annullano più.
  2. Crash scrivendo su pagina creata da foto: causa = `PDFPage(image:)` dava pagine della misura in pixel (es. 3000×4000 pt) e la tela ×4 esauriva la memoria. Ora le nuove pagine da foto hanno lato lungo 842 pt (`addImages`), e per TUTTI i PDF il fattore di risoluzione della tela è adattivo (`NotesModel.fattore(per:)`: max 4096 pt per lato e ~12 Mpx; spessore penna per tela con `strumentoCorrente(scala:)`). I PDF-foto già esistenti ora si aprono con tela ridotta (tratti meno nitidi con zoom, ma niente crash).
  3. Griglia di pagine pizzicando oltre lo zoom minimo (`GrigliaPagine.swift`, `AptPDFView.oltreIlMinimo`, `model.griglia`): tocco = apre la pagina, tenere premuto e trascinare = riordina, allargare le dita o «×» = chiude. Soglia: zoom desiderato < 0,85 × minimo.

## Struttura del codice (`Appunti.swiftpm`, ~8000 righe)
Le classi grandi sono divise in estensioni `Nome+Parte.swift`: per cercare una funzione usare grep.
- `MyApp.swift` — ingresso. `Tema/Tema.swift` — `AptTema` e componenti grafici (`AptIcona`, `AptLinea`, `aptBarra`, `aptPannello`, stili pulsante).
- `Libreria/` — Libreria su cartelle reali di iCloud Drive: `AptStore` (stato) + `AptStore+Ordine` (ordinamento, barra laterale, selezione), `+Cartelle`, `+Importa` (nuovi documenti, importazioni, esportazione), `+Raccolte` (raccolte e drag & drop);
  `Modelli`, `FileSystem`, `Contenuto`, `Elementi`, `BarraLaterale`, `Fogli`, `Miniature`, `Utilita`, `LibreriaView`.
- `Editor/` — `NotesModel` (strumenti) + `+Gesti`, `+Documento` (apertura, tele, lettura tratti, aggiungi pagine), `+Salvataggio`; `EditorView`, `BarraStrumenti`, `Strumenti`, `ImpostazioniEditor`, `PDFKitView`, `PaginaTela`,
  `RicercaPDF`, `Lazo` + `+Selezione`, `+Contorno`, `+Menu`; `Forme`, `Testo`, `Immagine` + `+Cornice`, `+Gesto`, `+Menu`; `Sorgenti`, `Cattura`, `Vassoio`, `Orologio`.
- `Tastiera/TastieraApp.swift` — tastiera nostra (Swift Playgrounds non mostra la tastiera di sistema).
- `docs/` — `mockup-editor.html` (decisioni dell'Editor, fonte di design), `stile-grafico.md` e `.html` (regole grafiche), `storico.md` (archivio).
- `prove/` — 3 prove di fattibilità (tratti, immagine) già adottate nel codice; non compilate dal workflow. Tenute come riferimento.
- Stored properties delle classi divise restano nel file principale (le estensioni non possono averne): una nuova proprietà va nel file principale della classe.

## Scelte tecniche da ricordare (valgono per ogni modifica)
- **Salvataggio nel PDF**: ogni pagina riceve annotazioni visibili in ogni lettore (ink `AptTratto`, stamp per le immagini, freeText `AptTesto`) PIÙ un'annotazione
  nascosta con i dati modificabili (`/AptDati` = PKDrawing in base64; immagini con `/AptInfo`). All'apertura le annotazioni dell'app vengono tolte dal documento
  in memoria e tutto torna modificabile. Si salva con Salva, o da solo se ci sono modifiche, al cambio/chiusura scheda e uscendo in Libreria.
- **Risoluzione tele**: la tela PencilKit di ogni pagina è `NotesModel.risoluzione` = 3× la pagina, rimpicciolita con `transform` (`PaginaTela`): tratti nitidi fino a ~3× di zoom.
  Coordinate tela = 3 × punti pagina; spessori, soglie del lazo e delle forme sono moltiplicati. Se pesa in memoria: scendere a 2.
- **Evidenziatore**: `.monoline` semitrasparente (non `.marker`); i vecchi evidenziatori `.marker` restano marker.
- **Livelli**: ordine di creazione (data del tratto / `creazione` dell'immagine). Con gomma e lazo tutti i tratti si «uniscono» nella tela; il testo sta sempre sopra.
- **Testo**: livelli `CATextLayer` vettoriali nella pila della pagina (`ImmagineControllo.ridisegna` mette insieme strati di tratti, immagini e testi per data di creazione);
  con larghezza impostata il testo è GIUSTIFICATO e riempie tutto il blocco (ultima riga a sinistra); finestra di scrittura con selettore dimensione carattere 8–96 (`FinestraTesto`);
  annotazioni freeText solo al salvataggio, con chiave `/AptInfoTesto` (larghezza, creazione). `ElementoTesto.larghezza` nil = automatica. Tastiera nostra (modo `multiriga`).
- **Interfaccia**: nessun `TextField` né tastiera di sistema; nelle viste nuove solo `AptTema` e componenti di `Tema.swift`; niente scritte piccole che spiegano l'uso.
  I colori degli strumenti sono scelti da Cristina e non seguono il tema.
- **Impostazioni** (strumenti, pallini colore, barra, destinazione cattura) in UserDefaults.
- `Package.swift`: iOS 17.0 minimo, capability fotocamera dichiarata (serve alla scansione in Playgrounds). Non modificare a mano oltre il necessario.

## Decisioni Editor (30/09, prese da Cristina nel mockup `docs/mockup-editor.html`, che è la fonte)
- Catalogo strumenti: penne, evidenziatori, matite, lazo, gomma (tratto/pixel), penna screenshot, immagine/PDF, testo. Sottolineato, barrato, post-it e indice/segnalibri: NON ci sono.
- Barra strumenti fissa (alto/basso/sinistra) o flottante; ogni strumento ricorda il proprio colore; pallini colore a lato; pannello «Modifica» per aggiungere/togliere/riordinare.
- Gesti: due dita = annulla; Pencil ferma = retta/forma; doppio tocco Pencil configurabile.
- Barra in alto: libreria, miniature | titolo | cerca, condividi, ···; sotto, schede dei PDF aperti.

## Problemi aperti
- Tastiera di sistema assente in Swift Playgrounds (probabile limite di Playgrounds/iPadOS 27): da ricontrollare quando l'app girerà fuori da Playgrounds.
- Working Copy: da rivedere (trovata una copia non originale); per ora si scarica lo ZIP.
- Da verificare sull'iPad (consegna del 05/10): vedi sopra; in particolare riordino pagine (drag nelle miniature), maniglie del testo, posizione barra flottante.
- Limiti noti: aggiungi PDF solo in fondo al documento; le miniature non mostrano i tratti non ancora salvati; il testo non si ruota (nel lazo si sposta e cambia solo la larghezza).

## Prossimi passi
Quando Cristina scrive «iniziamo con il prossimo passo», partire dal primo punto non fatto, senza chiedere conferme.
1. Verifica di Cristina sull'iPad delle novità del 05/10 e correzioni.
2. Poi, da concordare: quaderno per note bianche, esportazione/condivisione (foglio stile mockup), tema scuro.
