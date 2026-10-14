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

## Stato (08/10/2026)
- Tutto ciò che è stato consegnato è compilato (0 errori) e **verificato da Cristina sull'iPad** il 04/10 sera: Libreria, Editor, tratti, forme,
  testo, immagini, timer, penna screenshot, vassoio, lazo con immagini, aggiungi PDF, pannello «Modifica».
- Check-up del 04/10 sera: tolta la diagnostica `ProvaNitidezza`, sistemati i 3 avvisi di compilazione, STATO.md snellito, README aggiornato, i 4 file più grandi spezzati in file da 70-340 righe (solo spostamento di codice; per questo molti membri `private` sono ora interni), mockup HTML allineati al marrone terracotta.
- **Liquid Glass: NON voluto** (decisione di Cristina, 04/10/2026). Lo stile proprio (`AptTema`) resta quello definitivo: non usare `.glassEffect()`.

- **Salvataggio** (Impostazioni → «Salvataggio», `ed.salvaAuto`): manuale = solo «Salva»; automatico (predefinito) a due livelli: diario di recupero ogni 2 s (`NotesModel+Recupero.swift`) + PDF completo dopo 20 s di pausa, al cambio scheda, uscendo, in secondo piano, ogni 10 min, e subito se cambia la struttura delle pagine. Dettagli in `docs/storico.md`.
- **Verificato da Cristina fino all'08/10**: barra alta su una riga, estendi pagina, vista doppia (il clic su «×», «⇄» e divisore da riprovare), menu a tre pallini e selezione nella griglia delle pagine. Dettagli in `docs/storico.md`.
- **Pagine di sola scrittura**: pagina in `modelli[page]`, sfondo vettoriale disegnato nel PDF (`ModelloPagina.swift`), salvato in annotazione nascosta `AptModello` (codice `RRGGBB|tipo|passo|idImmagine`; i vecchi nomi di colore si leggono ancora). «Conta come prima pagina»: `AptPrima`. Le note vecchie NON sono di sola scrittura.

- **08/10 — QUADERNI (compilato, 0 errori, DA PROVARE su iPad)**, su indicazioni di Cristina (screenshot di altre app, non da copiare):
  1. **Pagina «Modelli»** (`PaginaModelli.swift`, a tutto schermo): Verticale/Orizzontale/**Gigante** (A4, A4 per il lungo, lavagna 2400×1800 pt) + **5 colori a memoria** (tocco lungo = selettore di sistema; `ModelliArchivio`) ·
     **Recenti** (ultimi 7) · **Modelli del sistema** Bianco/Quadretti/Righe/Puntini, ciascuno con cursore di grandezza/distanza (ricordato) · **Modelli creati da me**: PDF da File (1ª pagina) o foto da Album; se la proporzione non è quella del foglio, schermata di ritaglio col riquadro fisso e foto da spostare/ingrandire (`RitagliaModello.swift`); salvati in Application Support/Modelli (tenere premuto = Elimina).
  2. **Nuovo quaderno** (Libreria → Nuovo → Crea; sostituisce «Nuova nota di appunti»): apre la pagina Modelli, un tocco crea il PDF con 1 pagina e lo apre. Il PDF porta l'annotazione nascosta `AptQuaderno` sulla prima pagina (modello predefinito + «pagine unite»), riscritta a ogni salvataggio.
  3. **Nuova pagina scorrendo oltre l'ultima** (`SuperaFine`, `NotesModel+Quaderno.swift`): tirando oltre la fine per più di 70 pt compare «Rilascia per aggiungere una pagina»; al rilascio nasce una pagina col modello del quaderno (nei PDF normali: quello dell'ultima pagina se è un foglio bianco, altrimenti l'ultimo usato). Annullabile. Non attivo con scorrimento «Singolo».
  4. **Modello e colore pagina** (tre puntini e miniature): pagina Modelli in modalità «Cambia Modello», con «Applica» e interruttore **Applica a tutte le pagine** (del quaderno / tutti i fogli bianchi), un solo annulla.
  5. **Pagina bianca nei PDF**: «Aggiungi pagina → Pagina bianca…» e menu miniatura «Inserisci pagina bianca dopo» aprono la pagina Modelli. Interruttore «Pagine unite» (senza spazio fra i fogli) nella finestra `···`, solo nei quaderni.
  Limiti: il **Gigante non è infinito** (un PDF arriva a ~24 fogli A4 per lato): è una lavagna grande e la tela Pencil scende di risoluzione (area massima ~12 milioni di punti, `NotesModel.fattore`); idea futura: allargarsi da sola vicino ai bordi. Annullare «Applica a tutte» non riporta il modello predefinito del quaderno. Un modello personale applicato a una pagina di altra misura riempie il foglio tagliando ciò che sporge. Non fatto: pagine distinte con spazi diversi per formato.

- **08/10 (pomeriggio) — Tema e pagine automatiche (compilato, DA PROVARE su iPad)**:
  1. **Tema** Come l'iPad (predefinito) / Chiaro / Scuro: `AspettoApp` in `Tema.swift`, scelta in Impostazioni (ingranaggio dell'Editor → «Aspetto») e con l'icona a mezzo cerchio nella barra della Libreria. Salvato in UserDefaults (`aspettoApp`), applicato a tutte le finestre. I fogli restano chiari (`overrideUserInterfaceStyle = .light` sulle tele) e i colori degli strumenti non seguono il tema.
  2. **Pagine automatiche = modello e formato del quaderno**: `Quaderno.formato` (nuovo, salvato in `AptQuaderno` come terzo campo `modello#unite#formato`; i quaderni vecchi usano il formato della prima pagina). La pagina nata scorrendo oltre l'ultima ha modello del quaderno + formato del quaderno (prima prendeva la misura dell'ultima pagina). «Applica a tutte» cambia ancora il modello del quaderno per le pagine future, non il formato.
  3. **Pagina bianca a mano** (3 puntini → Aggiungi pagina → Pagina di appunti): la pagina Modelli mostra il selettore Verticale/Orizzontale/Gigante, già posizionato sul formato del quaderno (o della pagina vicina), così si può aggiungere una pagina con orientamento diverso. Nei PDF normali, se il formato non cambia la pagina resta della misura esatta delle vicine.

- **08/10 (sera) — Tema scuro e colore dell'app (compilato, DA PROVARE)**: nel tema scuro le icone degli strumenti con colore molto scuro (nero) si schiariscono (`ColoreSalvato.perInterfaccia`; il colore vero del tratto non cambia) e i pallini scuri hanno bordo più visibile. Pulsante tavolozza in Libreria (accanto a «sidebar») = finestra colori di sistema che cambia l'accento dell'app (`AccentoApp`/`PulsanteColoreApp` in `Tema.swift`, UserDefaults `accentoApp`; tenute le tinte derivate chiaro/scuro; «Colore originale» ripristina). Si applica alla chiusura del popover; l'interfaccia si ridisegna (`.id` in `MyApp`).
- **08/10 (pomeriggio) — Pulsante «Cambia cartella dell'app»** nella barra alta della Libreria (icona cartella con ingranaggio, dopo la tavolozza): riapre il selettore di sistema e usa `setRoot` (bookmark in UserDefaults). Esisteva già, piccolo, in fondo alla barra laterale. Compilato, da provare.
- **09/10 — IPA rigenerato** dal commit edf3fee (1,7 MB, 0 errori; include Quaderni, Libreria rifatta, tema): `https://github.com/gmveronesi-cloud/app-appunti/raw/ipa/Appunti.ipa`. Installazione con SideStore da fare da parte di Cristina.
- **12/10 — Evidenziatore a strati e file dalle altre app (compilato: vedi esito; DA PROVARE su iPad; sostituisce la consegna del 09/10)**:
  1. **Colori**: con l'evidenziatore attivo la barra mostra i SUOI pallini pastello (`palliniEvid`, `NotesModel.palliniAttivi`), modificabili; stesso numero dei pallini delle penne. Tavolozza pastello nuova (chiave `ed.palliniEvidPastello` azzera quella vecchia una volta).
  2. **Tratto**: nuovo stile «Pastello» = `PKInkingTool(.marker)` (bordi morbidi come Appunti+), predefinito; «Linea netta» = il vecchio monoline 45% (`StileStrumento.marcatore/.lineaNetta`; i vecchi evidenziatori con stile `.normale` diventano `.marcatore` alla lettura). Lo slider «Trasparenza» regola l'alpha.
  3. **Evidenziatore nella pagina PDF: ABBANDONATO (14/10)**. Codice rimosso (`AnnotazioneEvidenziatore`, strato `evid`, prova automatica, `aggiornaFusione`). Livelli (`NotesModel.ripartisci`): gomma/lazo = tutto nella tela; penne e matite = tratti normali nella tela, evidenziatori nello strato `sopra` (immagine sopra la tela: l'evidenziatore sta SOPRA agli altri tratti); evidenziatore attivo = i suoi tratti nella tela e tutti gli altri nello strato `sotto` (immagine sotto la tela). Cambiando strumento la cronologia di annulla si azzera se ci sono tratti da spostare. Gli evidenziatori sono sotto a immagini e testi solo se più vecchi di essi (come tutti i tratti).
  4. **File dalle altre app**: `Info.plist` (PDF e immagini) + `.onOpenURL` + `AptStore+Esterno.swift`: finestra (UIHostingController presentato sopra QUALSIASI schermata, anche l'Editor: la prima versione era sotto l'Editor e non si vedeva) → «Salva nella cartella…» (elenco cartelle, preselezionata quella aperta) → «Apri ora» (`apriDocumento`: nuova scheda se l'Editor è aperto, `richiestaApri`) / «Rimani dove sei». Foto → PDF. Funziona solo con l'app installata (SideStore).

- **12/10 (sera) — Indicatore di pagina e lazo senza lag (compilato, 0 errori; DA PROVARE su iPad)**:
  1. **Indicatore «5 di 60»** (`IndicatorePagina` in `PannelloPagina.swift`, overlay in `riquadro` di `EditorView`): pillola piccola e semitrasparente sul bordo destro del PDF (anche in vista doppia, una per riquadro); si aggiorna con `.PDFViewPageChanged`. Un tocco apre un popover con la stessa finestra «Vai a pagina» dei tre puntini (estratta in `VaiAPaginaView`, usata da entrambi). Non compare se il documento ha 1 pagina. (14/10) Ora in alto a destra e trasportabile: tenendolo premuto 0,3 s si «aggancia» (ingrandito, bordo marrone, ombra, tocco aptico) e si trascina; posizione ricordata in UserDefaults `ed.indicatorePagina` (spostamento dall'angolo, uguale per entrambi i riquadri).
  2. **Lazo: trascinamento veloce** (`Lazo+Trascinamento.swift`): prima a ogni movimento si ricreavano tutti i tratti scelti e si riassegnava `tela.drawing` (con `canvasViewDrawingDidChange` che a ogni passo ricalcolava evidenziatore e fusione). Ora al primo movimento i tratti scelti diventano un'immagine (`stratoTratti`, CALayer) spostata/scalata/ruotata dalla GPU; `tela.drawing` si scrive 2 volte in tutto (inizio e fine). Contorno e maniglie scorrono con `setAffineTransform` (solo spostamento). In più `LazoGesto` usa i tocchi previsti (`predictedTouches`) per sposta/ridimensiona/ruota, e la posizione vera all'ultimo passo. Se il lazo è interrotto a metà, `deseleziona` rimette i tratti al loro posto. Limiti: durante il gesto l'evidenziatore è mostrato come immagine normale (senza multiply) e, con ridimensionamento forte, un po' sfocato; a fine gesto torna tutto nitido.

- **14/10 — Tratto identico nell'esportazione/salvataggio (compilato: vedi esito; DA PROVARE su iPad)**: causa: `creaAnnotazioni` faceva annotazioni «ink» con spessore = media di `size.width` dei punti, ma la tela è k× la pagina e `PKDrawing.transformed` non scala i `size` dei punti → tratti molto più grossi nel PDF esportato/salvato. Ora i tratti diventano immagini trasparenti disegnate da PencilKit (`AnnotazioneTratti`, stamp, `userName` = `AptTratto`, tolta in apertura come prima), 3 px/pt nel salvataggio e 4 px/pt nell'esportazione, un'immagine per ogni intervallo tra immagini/testi (`confini`) così i livelli restano; gli evidenziatori in immagini a parte con `setBlendMode(.multiply)` (come nell'app). Compromesso: i tratti nel PDF non sono più vettoriali né selezionabili in altri lettori (nell'app restano modificabili: i dati veri stanno in `AptDati`).

- **14/10 — Evidenziatore: la Pencil scorreva la pagina (corretto, DA PROVARE)**: `aggiornaFusione` nascondeva la tela con `layer.opacity = 0`, ma `UIView.alpha` è la stessa cosa e UIKit non fa il hit-test sotto 0,01: la Pencil non arrivava alla tela e spostava il PDF. Ora 0,02. L'indicatore di pagina è un overlay `.topTrailing` grande quanto la pillola (niente contenitore a tutto schermo).

- **14/10 (dopo) — Evidenziatore nella pagina DISATTIVATO**: con il colore nella pagina la tela si attenuava mentre si scriveva e gli altri tratti sembravano sparire. `NotesModel.evidInPagina` parte ora da `false` (= ripiego già esistente: evidenziatori nella tela, sopra il testo, come prima del 12/10). Il codice dell'evidenziatore nella pagina resta, spento: per riattivarlo basta rimettere `nil` (ma prima va risolto l'effetto sugli altri tratti). L'esportazione resta con evidenziatori fusi (multiply).

- **14/10 — Indicatore di pagina solo mentre si scorre (DA PROVARE)**: `RilevaScorrimento` (`PannelloPagina.swift`) osserva `contentOffset` dello scroll del PDFView; l'indicatore compare dopo mezza pagina di scorrimento (soglia = metà altezza/larghezza della pagina a schermo) e sparisce 1,3 s dopo che ci si ferma; resta visibile con popover aperto o durante il trascinamento. Compare brevemente anche a ogni cambio pagina (salto «Vai a pagina», modalità Singolo). Pillola più grande (testo 15). L'evidenziatore è tornato nella tela .

- **14/10 (sera) — Vista doppia: il file a lato è un file a tutti gli effetti (compilato: vedi esito; DA PROVARE su iPad)**:
  1. **Segue il riquadro selezionato** (`modelloAttivo`: bordo marrone = dove si lavora): miniature/pagine a sinistra (`MiniaturePagine`, ora con `.id` del riquadro e notifica di pagina filtrata), titolo con peso/Rinomina/Elimina, ricerca (`RicercaPDF.sposta`: toglie le evidenziazioni dal vecchio riquadro e cerca di nuovo nell'altro), conferma «modifiche non salvate» (`conConferma(per:)`), rinomina ed elimina (`rinomina`/`eliminaAttivo` agiscono su `docAttivo`; eliminando il file a lato si chiude il riquadro).
  2. **Schede**: il file a lato entra tra le schede (`apriSecondario`); è evidenziata la scheda del riquadro attivo, l'altro file visibile ha un filo di bordo. Tocco su scheda già visibile = passa a quel riquadro; su un'altra scheda = si apre nel riquadro principale. «×» sulla scheda del file a lato chiude il riquadro destro.
  3. **Memoria** (`MemoriaLaterale.swift`, UserDefaults `ed.laterale.doc` / `ed.laterale.pagina`): si ricorda quale file era a lato e a che pagina (aggiornata a ogni cambio pagina; anche dopo «×», uscita o chiusura dell'app). Riaccendendo la vista doppia il file torna da solo alla pagina ricordata (se esiste ancora e non è quello principale); scegliendo a mano lo stesso file riparte dalla stessa pagina. La rinomina riapre alla stessa pagina (anche per il principale). Non riapre la vista doppia da sola entrando nell'Editor.

- **08/10 — Pacchetto per SideStore**: workflow `.github/workflows/pacchetto.yml` (a mano o quando cambia il file) costruisce `Appunti.ipa` NON firmato (Release, iOS 17+, bundle `it.cristina.appunti`) e lo pubblica sul ramo `ipa` (`https://github.com/gmveronesi-cloud/app-appunti/raw/ipa/Appunti.ipa`). Costruito con successo (1,6 MB). Da fare: Cristina lo installa con SideStore (ID Apple gratuito dedicato; consigli di sicurezza già dati). Per ogni aggiornamento del codice: rilanciare «Pacchetto iPad» e reinstallare sopra.

- **08/10 (sera) — LIBRERIA RIFATTA (compilato: da verificare, DA PROVARE su iPad)**:
  1. **Cartelle e rinomina**: una sola finestra del nome a livello di Libreria (`store.renaming`, `AptRenameTarget`, `AptRenameSheet` in `Fogli.swift`), non più un foglio per ogni riga della barra laterale (se la riga non c'era — barra nascosta o cartella padre chiusa — la cartella restava «Nuova cartella»). Nuova cartella/raccolta si creano solo alla conferma del nome. Nome già esistente = avviso (prima veniva cambiato di nascosto in «nome 2»). Rinomina anche documenti (`renameDoc`). `remap` aggiorna anche cartella aperta e schede.
  2. **Menu a tocco lungo** su cartelle, documenti e raccolte nella griglia/lista: Rinomina, Nuova sottocartella, Sposta in…, Aggiungi a raccolta, Elimina.
  3. **Grafica**: intestazione con percorso a briciole, riepilogo («N cartelle · M documenti»), sezioni «Cartelle» e «Documenti», riquadri cartella tinti, bordo di selezione, lista in scheda. Barra laterale: intestazione con nome libreria e totali, frecce per aprire/chiudere i livelli (toccare la riga apre la pagina), riga attiva evidenziata anche per le cartelle, blocco **«Recenti»** (5 documenti con miniatura) fisso in basso. Tolto dalla barra laterale il pulsante «cartella dell'app» (c'è già in alto).

- **08/10 (sera) — LIBRERIA: barra laterale e schede (commit abcf74f, compilato: 0 errori, 0 avvisi nuovi; DA PROVARE su iPad)**:
  1. **Barra laterale**: «Recenti» ora è una scheda che riempie lo spazio libero in basso (tanti documenti quanti ne entrano, da 3 a 10, misurati su altezza di raccolte+cartelle; miniatura 34×44, pagine e data); **piede fisso** con «Quaderno» (apre la pagina Modelli: `store.showModelli`, spostato dal `@State` di `AptMainView`) e «Importa» (selettore PDF verso la cartella aperta).
  2. **Area principale**: colonne più larghe (documenti 150, cartelle 176), badge «N pag» sulla miniatura, data sotto il nome, riquadro cartella/raccolta con tondo per l'icona e numero di documenti, lista con freccia sulle cartelle, schermata iniziale con icona in riquadro tinto.
  Nota CI (08/10 sera): le macchine macOS arm64 di GitHub erano in coda per capacità (job «not acquired», 3 tentativi). Il workflow `Compila` ha ora l'ingresso `runner` (Run workflow): con `macos-15-intel` compila su Intel (Xcode 26.3) senza coda. Via API: `POST .../actions/workflows/compila.yml/dispatches` con `-H "Content-Type: application/json"` e `{"ref":"main","inputs":{"runner":"macos-15-intel"}}`. Con `runner` valorizzato, schermata e prova prestazioni non partono.

## Struttura del codice (`Appunti.swiftpm`, ~8500 righe)
Le classi grandi sono divise in estensioni `Nome+Parte.swift`: per cercare una funzione usare grep.
- `MyApp.swift` — ingresso. `Tema/Tema.swift` — `AptTema` e componenti grafici (`AptIcona`, `AptLinea`, `aptBarra`, `aptPannello`, stili pulsante).
- `Libreria/` — Libreria su cartelle reali di iCloud Drive: `AptStore` (stato) + `AptStore+Ordine` (ordinamento, barra laterale, selezione), `+Cartelle`, `+Importa` (nuovi documenti, importazioni, esportazione), `+Raccolte` (raccolte e drag & drop);
  `Modelli`, `FileSystem`, `Contenuto`, `Elementi`, `BarraLaterale`, `Fogli`, `Miniature`, `Utilita`, `LibreriaView`.
- `Editor/` — `NotesModel` (strumenti) + `+Gesti`, `+Documento` (apertura, tele, lettura tratti, aggiungi pagine), `+Salvataggio`; `EditorView`, `BarraStrumenti`, `Strumenti`, `ImpostazioniEditor`, `PDFKitView`, `PaginaTela`,
  `RicercaPDF`, `Lazo` + `+Selezione`, `+Contorno`, `+Menu`; `Forme`, `Testo`, `Immagine` + `+Cornice`, `+Gesto`, `+Menu`; `Sorgenti`, `Cattura`, `Vassoio`, `Orologio`;
  `NotesModel+Pagina` (vista, estensione, vai a pagina), `PannelloPagina` (menu estendi e finestra `···`), `VistaDoppia` (pezzi della schermata divisa),
  `NotesModel+Quaderno` (quaderno, nuova pagina, scorrimento oltre la fine, presentazione pagina Modelli), `PaginaModelli`, `ModelliArchivio`, `RitagliaModello`.
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
- **Evidenziatore**: stile «Pastello» = `.marker` (predefinito dal 12/10) o «Linea netta» = `.monoline` semitrasparente; livelli: vedi «12/10» punto 3.
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
- Da verificare (07/10): scorrimento «Singolo» usa `usePageViewController` — se le tele Pencil non compaiono in quella modalità, tornare a «Continuo» e correggere; estensione su pagine ruotate non gestita;
  in vista doppia annulla/ripeti usano la cronologia di sistema, condivisa tra i due riquadri (l'ultima azione, di qualunque riquadro).
- Tastiera di sistema assente in Swift Playgrounds (probabile limite di Playgrounds/iPadOS 27): da ricontrollare quando l'app girerà fuori da Playgrounds.
- Working Copy: da rivedere (trovata una copia non originale); per ora si scarica lo ZIP.
- Da verificare sull'iPad (consegna del 05/10): vedi sopra; in particolare riordino pagine (drag nelle miniature), maniglie del testo, posizione barra flottante.
- Limiti noti: aggiungi PDF solo in fondo al documento; le miniature non mostrano i tratti non ancora salvati; il testo non si ruota (nel lazo si sposta e cambia solo la larghezza).

## Prossimi passi
Quando Cristina scrive «iniziamo con il prossimo passo», partire dal primo punto non fatto, senza chiedere conferme.
1. Verifica di Cristina (consegna 08/10): quaderni (pagina Modelli, colori, ritaglio, «Applica a tutte»); NUOVA PAGINA TIRANDO OLTRE L'ULTIMA (ora gesto col dito su PDFView, soglia 60 pt, parte da max 80 pt dalla fine; era KVO e non andava); «Aggiungi pagina» (3 puntini e menu miniatura) = Pagina di appunti / File (PDF) / Immagini, dopo la pagina corrente (`inserisciDopo`); condividi = finestra `Esporta.swift` (rulli Da/A, con/senza annotazioni, «Tutte/Pagine X–Y» e «Solo questa pagina») poi foglio di condivisione di iPadOS (include Salva su File).
2. Gigante: farlo allargare da solo vicino ai bordi (fino al limite del PDF) con tele a risoluzione adeguata, come una lavagna Freeform.
3. Verifica del colore dell'app e del tema scuro schermata per schermata (Libreria, Editor, Modelli, finestre) e della nuova pagina con formato del quaderno / orientamento diverso a mano.
4. Da concordare: eventuale esportazione dalla Libreria con lo stesso intervallo pagine.
