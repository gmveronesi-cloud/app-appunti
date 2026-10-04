# STATO DEL PROGETTO — App Appunti (da leggere all'inizio di ogni chat)

Aggiornato da Claude a ogni consegna. Tenere questo file CORTO (obiettivo: sotto 10 KB). I dettagli delle consegne
passate stanno in `docs/storico.md` (archivio: non rileggerlo, solo `grep` se serve il perché di una scelta).
Contesto generale e vincoli di design: istruzioni del Progetto e file `stato-e-metodo-app-appunti.md` nel Progetto.

## Come si lavora (metodo in vigore)
- Repository `gmveronesi-cloud/app-appunti` (**pubblico**, verificato il 04/10/2026; i documenti dicevano «privato»: vedi Problemi aperti).
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
Pencil, PencilKit, salvataggio su iCloud, selettore cartelle, fotocamera, notifiche, resa Liquid Glass reale su iPadOS 27 (il runner ha SDK 26.5):
solo sull'iPad di Cristina. La compilazione controlla solo che il codice compili.

## Stato (04/10/2026)
- Tutto ciò che è stato consegnato è compilato (0 errori) e **verificato da Cristina sull'iPad** il 04/10 sera: Libreria, Editor, tratti, forme,
  testo, immagini, timer, penna screenshot, vassoio, lazo con immagini, aggiungi PDF, pannello «Modifica».
- Check-up del 04/10 sera: tolta la diagnostica `ProvaNitidezza`, sistemati i 3 avvisi di compilazione, STATO.md snellito, README aggiornato.
  Da compilare al prossimo push di codice.

## Struttura del codice (`Appunti.swiftpm`, ~8000 righe)
- `MyApp.swift` — ingresso. `Tema/Tema.swift` — `AptTema` e componenti grafici (`AptIcona`, `AptLinea`, `aptBarra`, `aptPannello`, stili pulsante).
- `Libreria/` — Libreria su cartelle reali di iCloud Drive: `AptStore` (stato e operazioni, 704 righe), `Modelli`, `FileSystem`, `Contenuto`, `Elementi`,
  `BarraLaterale`, `Fogli`, `Miniature`, `Utilita`, `LibreriaView`.
- `Editor/` — `NotesModel` (strumenti, gesti, salvataggio), `EditorView`, `BarraStrumenti`, `Strumenti`, `ImpostazioniEditor`, `PDFKitView`, `PaginaTela`,
  `RicercaPDF`, `Lazo`, `Forme`, `Testo`, `Immagine`, `Sorgenti`, `Cattura`, `Vassoio`, `Orologio`.
- `Tastiera/TastieraApp.swift` — tastiera nostra (Swift Playgrounds non mostra la tastiera di sistema).
- `docs/` — `mockup-editor.html` (decisioni dell'Editor, fonte di design), `stile-grafico.md` e `.html` (regole grafiche), `storico.md` (archivio).
- `prove/` — 3 prove di fattibilità (tratti, immagine) già adottate nel codice; non compilate dal workflow. Tenute come riferimento.

## Scelte tecniche da ricordare (valgono per ogni modifica)
- **Salvataggio nel PDF**: ogni pagina riceve annotazioni visibili in ogni lettore (ink `AptTratto`, stamp per le immagini, freeText `AptTesto`) PIÙ un'annotazione
  nascosta con i dati modificabili (`/AptDati` = PKDrawing in base64; immagini con `/AptInfo`). All'apertura le annotazioni dell'app vengono tolte dal documento
  in memoria e tutto torna modificabile. Si salva con Salva, o da solo se ci sono modifiche, al cambio/chiusura scheda e uscendo in Libreria.
- **Risoluzione tele**: la tela PencilKit di ogni pagina è `NotesModel.risoluzione` = 3× la pagina, rimpicciolita con `transform` (`PaginaTela`): tratti nitidi fino a ~3× di zoom.
  Coordinate tela = 3 × punti pagina; spessori, soglie del lazo e delle forme sono moltiplicati. Se pesa in memoria: scendere a 2.
- **Evidenziatore**: `.monoline` semitrasparente (non `.marker`); i vecchi evidenziatori `.marker` restano marker.
- **Livelli**: ordine di creazione (data del tratto / `creazione` dell'immagine). Con gomma e lazo tutti i tratti si «uniscono» nella tela; il testo sta sempre sopra.
- **Testo**: livelli `CATextLayer` vettoriali sulla tela di pagina, annotazioni freeText solo al salvataggio. Una riga, tastiera nostra.
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
- **Repository pubblico**: GitHub risulta `public` (API, 04/10/2026), mentre i documenti dicevano «privato». Il codice e il mockup sono leggibili da chiunque abbia il link;
  non contengono dati personali né chiavi. Se Cristina lo vuole privato: GitHub → Settings → Danger Zone → Change visibility (ma allora i runner macOS contano 10× e la quota
  gratuita si esaurisce: vedi storico del 02/10). Decisione di Cristina.
- Tastiera di sistema assente in Swift Playgrounds (probabile limite di Playgrounds/iPadOS 27): da ricontrollare quando l'app girerà fuori da Playgrounds.
- Working Copy: da rivedere (trovata una copia non originale); per ora si scarica lo ZIP.
- Correzioni piccole note: barra flottante non ricorda la posizione; annulla/ripeti sempre attivi; `docs/stile-grafico.html` e `docs/mockup-editor.html` mostrano ancora il vecchio rosso (l'accento reale è marrone terracotta, vedi `docs/stile-grafico.md`).
- Limiti noti: testo su una sola riga; incolla del lazo rimette solo i tratti; aggiungi PDF solo in fondo e non annullabile; testi senza livelli.

## Prossimi passi
Quando Cristina scrive «iniziamo con il prossimo passo», partire dal primo punto non fatto, senza chiedere conferme.
1. Salvataggio automatico/manuale come impostazione.
2. Lazo che selezioni anche i testi.
3. Poi, da concordare: quaderno per note bianche, esportazione/condivisione (foglio stile mockup), tema scuro.
4. Proposta emersa dal check-up (da approvare): spezzare i file più grandi (`Immagine.swift` 795 righe, `Lazo.swift` 761, `AptStore.swift` 704, `NotesModel.swift` 673) in file più piccoli
   senza cambiare il comportamento; farlo prima di aggiungere funzioni nuove a quei file, con compilazione di verifica.
