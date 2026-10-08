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
- **Da PROVARE su iPad (consegne 05–06/10, dettagli in `docs/storico.md`)**: lazo anche sui testi; testo a più righe con larghezza regolabile e livelli;
  «Aggiungi PDF» annullabile; riordino pagine dalle miniature; barra flottante che ricorda la posizione; tocco a due dita = annulla (`DueDitaTap`);
  fix crash sulle pagine da foto (lato lungo 842 pt, tele adattive `NotesModel.fattore(per:)`); griglia di pagine pizzicando oltre lo zoom minimo;
  zoom 0,4×–6×; menu sul nome del PDF (peso, Rinomina, Elimina).
- **Consegna del 07/10 (compilata, 0 errori, DA PROVARE su iPad)** — barra alta e pagine, su richiesta di Cristina (screenshot dell'app «Appunti +»):
  1. **Barra alta su UNA riga** (prima erano due, ~106 pt, ora ~44 pt): `‹`, miniature | schede dei PDF (la scheda attiva ha il nome con il menu peso/Rinomina/Elimina) | `+` |
     cerca, condividi, **estendi pagina**, **vista doppia**, impostazioni, (Salva se manuale), `···`. Margini verticali della capsula strumenti ridotti (8→4).
  2. **Estendi pagina** (`MenuEstendi`, `NotesModel+Pagina.swift`): lati Nessuno/Sinistra/Destra/Sinistra e Destra + Piccolo/Medio/Grande (0,3/0,5/0,8 della larghezza pagina, per lato).
     Allarga mediaBox e cropBox di TUTTE le pagine; i tratti si spostano di conseguenza; la misura originale è salvata nel PDF in un'annotazione nascosta `AptEstensione` (`/AptOrig`), così si può tornare a «Nessun riempimento».
  3. **Vista doppia** (`VistaDoppia.swift`, `EditorView`): secondo `NotesModel` (`secondario`) accanto al principale; segnaposto «Seleziona documento»; divisore da trascinare (25–75%);
     «×» chiude, «⇄» scambia i lati. La barra strumenti agisce sul riquadro attivo (bordo marrone; si cambia toccando: `OsservaTocchi`); strumenti/colori allineati tra i due (`allineaStrumenti`).
     Un documento non può stare in due riquadri (aprirlo come scheda chiude il secondo). Chiudendo il secondo si salva sempre.
  4. **Finestra `···`** (`PannelloPagina`): Pagine singola/doppia · Aggiungi pagina (pagina bianca dopo quella corrente, annullabile; pagine da un PDF) · Modello e colore pagina (GRIGIO: serve il quaderno) ·
     Direzione di scorrimento (orizzontale/verticale + continuo/singolo) · Vai a pagina (ruota). «Scarta tratti non salvati» è passato in Impostazioni → «Scarta i tratti non salvati».
  Non fatto: pagine distinte / «papiro» continuo (solo per i quaderni, che non esistono ancora).

## Struttura del codice (`Appunti.swiftpm`, ~8500 righe)
Le classi grandi sono divise in estensioni `Nome+Parte.swift`: per cercare una funzione usare grep.
- `MyApp.swift` — ingresso. `Tema/Tema.swift` — `AptTema` e componenti grafici (`AptIcona`, `AptLinea`, `aptBarra`, `aptPannello`, stili pulsante).
- `Libreria/` — Libreria su cartelle reali di iCloud Drive: `AptStore` (stato) + `AptStore+Ordine` (ordinamento, barra laterale, selezione), `+Cartelle`, `+Importa` (nuovi documenti, importazioni, esportazione), `+Raccolte` (raccolte e drag & drop);
  `Modelli`, `FileSystem`, `Contenuto`, `Elementi`, `BarraLaterale`, `Fogli`, `Miniature`, `Utilita`, `LibreriaView`.
- `Editor/` — `NotesModel` (strumenti) + `+Gesti`, `+Documento` (apertura, tele, lettura tratti, aggiungi pagine), `+Salvataggio`; `EditorView`, `BarraStrumenti`, `Strumenti`, `ImpostazioniEditor`, `PDFKitView`, `PaginaTela`,
  `RicercaPDF`, `Lazo` + `+Selezione`, `+Contorno`, `+Menu`; `Forme`, `Testo`, `Immagine` + `+Cornice`, `+Gesto`, `+Menu`; `Sorgenti`, `Cattura`, `Vassoio`, `Orologio`;
  `NotesModel+Pagina` (vista, estensione, vai a pagina, pagina bianca), `PannelloPagina` (menu estendi e finestra `···`), `VistaDoppia` (pezzi della schermata divisa).
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

## Piccole modifiche del 07/10 (seconda consegna)
- Barra strumenti un po' più bassa, barra alta un po' più alta con icone destra 40/21; schede documento larghe tutte 176; margini laterali ridotti (4 / 6 pt).
- **Larghezza comune delle pagine** (`NotesModel+Standard.swift`, 07/10 terza consegna, sostituisce il vecchio «tutte A4»): all'apertura le pagine con larghezza diversa dalla più comune del documento vengono riscalate a quella larghezza **tenendo la propria proporzione** (una pagina orizzontale resta orizzontale, solo più bassa): nessun bordo bianco aggiunto. Si salva nel file solo al primo salvataggio. Non toccate: pagine con annotazioni di altri programmi (tranne link; possono restare di larghezza diversa) e documenti già allargati con «Estendi pagina». «Aggiungi PDF» usa `larghezzaPagina` del documento; Foto→PDF: larghezza 595 (842 se la maggioranza è orizzontale), altezza dalla proporzione di ogni foto.
- **Vista doppia, lentezza: RISOLTA (07/10 sera, causa trovata con una prova automatica nel simulatore)**. Causa: `aggiornaUndo()` leggeva `canUndo/canRedo`, che fanno scattare la notifica `NSUndoManagerCheckpoint`, a cui era iscritto lo stesso aggiornamento → ciclo infinito (con due riquadri, che condividono lo stesso UndoManager, raddoppiava a ogni giro: 0 schermate/s, 3,5 GB). Ora niente `Checkpoint` e un solo aggiornamento alla volta (`programmaAggiornaUndo`). Prova prima/dopo: schermate/s con due documenti da 0 a 37–60, memoria da 3,5 GB a ~0,4 GB. Restano (innocue) le correzioni intermedie: divisore che ridimensiona solo al rilascio, `allineaStrumenti` leggero (`inAllineamento`), niente `clipShape` sul PDF, secondo documento aperto 0,4 s dopo l'elenco. `impostaRisoluzione`/`risoluzioneMax` (tele 2×) restano nel codice ma NON sono usati.
- **Prova di prestazioni nel simulatore** (`Editor/ProvaPrestazioni.swift`, solo con la variabile `APT_PROVA`, mai sull'iPad): messaggio del commit con `[prova]` (o «Run workflow») → il workflow apre due PDF di 40 pagine, attiva la vista doppia, misura CPU/schermate al secondo/pause/memoria e conta eventi (`ProvaContatori`), poi campiona il processo con `sample`. Esito sul ramo `esiti`: `prova.txt`, `campione_B.txt`, `campione_D.txt`, `prova.png`. Utile ogni volta che l'app «è lenta»: riproduce da qui ciò che altrimenti si vede solo sull'iPad.

- **08/10 (DA PROVARE su iPad)**: vista doppia, clic più sicuri: pulsanti «×» e «⇄» più grandi (58×52 pt), sopra a tutto (`zIndex`); divisore più largo (28 pt, maniglia 6×64) con gesto prioritario.

## Problemi aperti
- Da verificare (07/10): scorrimento «Singolo» usa `usePageViewController` — se le tele Pencil non compaiono in quella modalità, tornare a «Continuo» e correggere; estensione su pagine ruotate non gestita;
  in vista doppia annulla/ripeti usano la cronologia di sistema, condivisa tra i due riquadri (l'ultima azione, di qualunque riquadro).
- Tastiera di sistema assente in Swift Playgrounds (probabile limite di Playgrounds/iPadOS 27): da ricontrollare quando l'app girerà fuori da Playgrounds.
- Working Copy: da rivedere (trovata una copia non originale); per ora si scarica lo ZIP.
- Da verificare sull'iPad (consegna del 05/10): vedi sopra; in particolare riordino pagine (drag nelle miniature), maniglie del testo, posizione barra flottante.
- Limiti noti: aggiungi PDF solo in fondo al documento; le miniature non mostrano i tratti non ancora salvati; il testo non si ruota (nel lazo si sposta e cambia solo la larghezza).

## Prossimi passi
Quando Cristina scrive «iniziamo con il prossimo passo», partire dal primo punto non fatto, senza chiedere conferme.
1. Verifica di Cristina: novità 05–07/10 verificate (08/10); resta da riprovare il clic su «×», «⇄» e divisore.
2. Miniature (elementi da dire da Cristina).
3. Poi, da concordare: quaderno per note bianche (con «Modello e colore pagina» e pagine distinte/«papiro»), esportazione/condivisione (foglio stile mockup), tema scuro.
