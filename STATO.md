# STATO DEL PROGETTO — App Appunti (da leggere all'inizio di ogni chat)

Aggiornato da Claude a ogni consegna. Contesto generale e vincoli: istruzioni del Progetto
e file `stato-e-metodo-app-appunti.md` nel Progetto (restano validi).

## Come si lavora (metodo in vigore)
- Repository privato `gmveronesi-cloud/app-appunti`. Se non è collegato alla sessione:
  `list_repos` → `add_repo` (access push) → clone → `register_repo_root`. Lo fa Claude, non Cristina.
- Il progetto è `Appunti.swiftpm` (una vista per file). Claude modifica i file e fa push su `main`.
- A ogni push GitHub Actions (`.github/workflows/compila.yml`, macOS, Xcode 26.6) compila per
  simulatore iPad e scatta uno screenshot all'avvio.
- Esito: i log grezzi di GitHub NON sono raggiungibili (host bloccato dal proxy: non aggirare).
  Il workflow scrive `riassunto.txt`, `build.log`, `avvio.png` sul ramo `esiti` (`git fetch origin esiti`,
  poi checkout in una cartella temporanea, mai nella working tree). Stato del run: API
  `api.github.com/repos/gmveronesi-cloud/app-appunti/actions/runs?head_sha=<sha>` con `$GH_TOKEN`.
- Claude corregge gli errori di compilazione da solo prima di dire a Cristina di provare.
- Cristina sull'iPad: scarica lo ZIP da github.com (Code → Download ZIP), lo decomprime in File,
  apre `Appunti.swiftpm` in Swift Playgrounds, preme Esegui e riferisce cosa vede.
  (Working Copy: l'app trovata era una copia in cinese, non quella di Anders Borum; da rivedere.)
- Ogni consegna: due righe su cosa è cambiato e cosa provare; nessuna spiegazione del codice.
- Cristina non è sviluppatrice: passi uno alla volta, italiano semplice, dire sempre cosa non si può verificare.

## Cosa non si può verificare da qui
Pencil, PencilKit, salvataggio su iCloud, selettore cartelle, resa Liquid Glass reale su iPadOS 27
(il runner ha SDK 26.5): solo sull'iPad di Cristina.

## Struttura
- `Appunti.swiftpm/Libreria/` — Libreria (barra laterale, griglia/lista, ordinamento, selezione, fogli).
  `AptStore.swift` è grande (~690 righe): candidato a essere spezzato.
- `Appunti.swiftpm/Editor/` — `NotesModel` (strumenti + salvataggio tratti come annotazioni ink nel PDF),
  `PDFKitView`, `EditorView`, `BarraStrumenti` (barra fissa o flottante, pannello colore/spessore).
- Codice recuperato dalle chat del 28/09/2026 (Libreria.swift completo + Prototipo 1).

## Stato
- Setup completato: repo, workflow, compilazione OK (0 errori, 2 avvisi `onChange` deprecato), ZIP su iPad OK.
- Provata da Cristina sull'iPad il 30/09: l'app parte e funziona; ha individuato 3 problemi (da elencare nella prossima chat).

## Problemi aperti
- (risolto 30/09, da verificare sull'iPad) Non si potevano creare sottocartelle: il "+" della riga compariva solo al passaggio del mouse (su iPad non esiste). Ora il "+" è sempre visibile sulle cartelle e sulla raccolta attiva, e il menu "Nuovo" ha "Nuova cartella".
- (risolto 30/09, da verificare sull'iPad) Rinomina cartella/raccolta: la tastiera non compariva. Il campo UITextField inline si attivava (cursore visibile) ma la tastiera a schermo non compariva. Provato: rinomina in una finestrella (`.alert` con TextField) in `AptSideRow`; `AptNameField` non più usato. Verificato 30/09: la tastiera a schermo NON compare nemmeno nella finestrella di sistema (altre app OK, riavvii OK), ma con Scribble (scrittura Apple Pencil) la rinomina funziona. Probabile limite di Swift Playgrounds/iPadOS 27: da ricontrollare quando l'app girerà fuori da Playgrounds.
- (nuovo 30/09, da verificare sull'iPad) Tastiera a schermo assente in Swift Playgrounds: ora c'è una tastiera nostra (`Tastiera/TastieraApp.swift`: `AptTastiera`, `AptCampo`, `AptRinomina`). Usata nella rinomina (finestra `.sheet`, nome selezionato: il primo tasto lo sostituisce) e nella ricerca nel PDF (tastiera sotto il PDF, tasto per nasconderla). Niente TextField/tastiera di sistema in tutta l'app; tolto `AptNameField`. Limiti: si scrive e cancella solo in fondo al testo (niente cursore mobile, niente incolla/selezione); layout italiano con accenti à è é ì ò ù e apostrofo; pagina simboli. Se non piace o non funziona: si tolgono le funzioni con tastiera (rinomina → solo Scribble, ricerca).
- Cristina ha detto che i problemi sono solo 2 (non 3).
- (corretto 30/09, da verificare sull'iPad) Eliminare un documento congelava l'app: `trashItem` annidato dentro una coordinazione di file (deadlock su iCloud/File). Ora `AptFS.trash` usa solo `removeItem` e `AptStore.delete` lavora fuori dal thread principale. Niente più cestino locale: su iCloud Drive i file vanno in «Eliminati di recente».

## Decisioni Editor (30/09, prese da Cristina nel mockup `docs/mockup-editor.html`)
Il mockup interattivo (aprire il file in un browser) è la fonte: contiene tutte le scelte e un riepilogo copiabile.
Sintesi:
- Barra strumenti: fissa (alto/basso/sinistra) O flottante (trascinabile, si riduce a pulsante tondo, si può spingere fuori schermo con linguetta), scelta dal menu ···. Modifica: si aggiungono, tolgono e riordinano gli strumenti; icone fisse a lato.
- Catalogo strumenti: penne (più di una, ognuna con colore/spessore/stile), evidenziatori (più di uno; spessore e trasparenza; NESSUN effetto pastello, resta semplice), matite, lazo (mano libera o riquadro; filtri per penne/evidenziatori/matite/immagini/testi/post-it), gomma (tratto intero o solo pixel), penna screenshot (riquadro o mano libera), immagine/PDF (immagine, aggiungi PDF, converti PDF in immagine sopra la pagina), testo, post-it. Sottolineato e barrato: NON nel catalogo.
- Penna/matita: solo spessore (parte dal minimo possibile) e stile (normale, stilografica, monolinea; matita, pastello a cera). Il colore NON è nel pannello dello strumento.
- Colori: ogni strumento ricorda il proprio colore; pallini colore fissi a lato della barra, numero modificabile, tocco su pallino già selezionato = cambia colore con il selettore Apple.
- Comportamento: tocco rapido con due dita = annulla; tenere ferma la Pencil = linea dritta o forma (quadrato, rettangolo, cerchio/ovale); dito scorre o disegna; doppio tocco Pencil configurabile; salvataggio automatico o manuale.
- Cronometro/timer: pulsante prima di Modifica; riquadro mobile e ridimensionabile su tutte le schermate, secondi opzionali, spinto fuori schermo diventa linguetta.
- Barra in alto: libreria, miniature pagine | titolo | cerca nel testo, condividi/esporta, menu ···. Sotto, striscia sottile con una scheda per ogni PDF aperto (× a sinistra, + per i file recenti), tra la barra in alto e la barra strumenti. Indice e segnalibri: RIMOSSI.
- Salvataggio tratti: annotazioni ink visibili in ogni lettore PIÙ i tratti modificabili (PKDrawing) conservati dentro il PDF. Serve per lazo, gomma a pixel e stili. Verifica di fattibilità in `prove/ProvaTratti.swift` (esito su ramo `esiti`, `prova.txt`).
- Stato del codice al 30/09: già fatto in Swift solo penna, evidenziatore, gomma, annulla/ripeti, barra fissa/flottante (semplice). Tutto il resto è da fare.
- Piano di lavoro concordato: 1) documento e salvataggio tratti; 2) barra in alto e schede; 3) barra strumenti completa; 4) resto uno alla volta (lazo, forme, immagini/testo, timer, cattura, ricerca, condividi). Le icone della barra in alto restano inerti finché non si arriva al punto 2.
- Da verificare sull'iPad: tastiera nostra (testo e post-it useranno `AptTastiera`/`AptCampo`), notifiche del timer.

## Prossimi passi (ordine concordato il 30/09)
Quando Cristina scrive "iniziamo con il prossimo passo", partire dal primo punto NON fatto di questo elenco, senza chiedere conferme.
1. FATTO — Passo 1: tratti modificabili nel PDF + impostazioni strumenti ricordate (da verificare su iPad).
2. FATTO (30/09, compila senza errori; da verificare su iPad) — Passo 3: barra strumenti (vedi sezione Passo 3 sotto).
3. FATTO (30/09, compila senza errori; da verificare su iPad) — Passo 2: barra in alto + schede (vedi sezione Passo 2 sotto).
4. FATTO (30/09, compila senza errori; da verificare su iPad) — Ricerca testo (vedi sezione sotto).
5. PROSSIMO, uno alla volta: lazo, rette/forme (tenere ferma la Pencil), immagini/testo/post-it, timer/cronometro, penna screenshot, linguetta per la barra fuori schermo, salvataggio automatico/manuale come impostazione.
- Aperto: forma del tratto evidenziatore fuori dall'app diversa (chiedere screenshot a Cristina).
- Aperto: verificare sull'iPad le correzioni Libreria (sottocartelle, rinomina) e il Passo 1.
- Correzioni piccole note: barra flottante non ricorda la posizione; annulla/ripeti sempre attivi; avviso `onChange` deprecato in Contenuto.swift:60.

## Stile grafico (deciso 01/10/2026)
- Riferimento vincolante: `docs/stile-grafico.md` (regole) e `docs/stile-grafico.html` (esempi visivi, chiaro/scuro). Codice: `Appunti.swiftpm/Tema/Tema.swift` (`AptTema`).
- Requisiti di Cristina: moderno, rosso e colori caldi, pastello (mai acceso o fluorescente), minimal ma curato.
- Piano: base grafica subito (Tema + barra strumenti + Libreria), poi ogni strumento nuovo già nello stile, lucidatura alla fine.
- Note di Cristina (01/10): (1) colori di penne/evidenziatori/matite restano normali e scelti da lei, il tema vale solo per l'interfaccia; (2) tolte tutte le scritte piccole che spiegano come usare l'app (fatto nel codice; da ora non aggiungerne di nuove).
- Stato: Tema.swift creato (non ancora applicato alle viste). PROSSIMO: applicare il tema a Libreria e barra strumenti.

## Passo 1 (consegnato): tratti modificabili dentro il PDF
- Prova macOS #2 riuscita: annotazione nascosta di tipo Square con i dati in chiave personalizzata /AptDati: si rilegge identica, nessun Popup, rimozione/sostituzione senza copie residue.
- NotesModel: al salvataggio ogni pagina riceve (a) annotazioni ink visibili (userName AptTratto) e (b) un'annotazione nascosta AptDati con il PKDrawing in base64 (coordinate in punti pagina). All'apertura le annotazioni dell'app vengono tolte dal documento in memoria e il disegno torna sulle tele, quindi restano modificabili (gomma, ecc.).
- Da verificare su iPad: che i tratti tornino modificabili dopo chiusura/riapertura, posizione corretta dopo zoom, PDF aperto in un'altra app con tratti visibili.
- Barra superiore (miniature, cerca, condividi, schede): passo 2, per ora nulla di nuovo.

- Impostazioni strumenti (strumento, colori, spessori, gomma) ora ricordate tra le sessioni (UserDefaults).
- Aperto: forma del tratto evidenziatore fuori dall'app diversa da quella nell'app (il pennarello PencilKit ha punta piatta, le annotazioni PDF ink no). Serve screenshot per decidere la correzione.
- Barra strumenti/superiore come da mockup: passi 2 e 3, non ancora fatti.

## Passo 3 (consegnato 30/09): barra strumenti
- File: `Editor/Strumenti.swift` (modello: tipo, stile, colore, spessore per ogni strumento), `Editor/BarraStrumenti.swift` (barra, pannello strumento, modifica barra, barra flottante), `Editor/ImpostazioniEditor.swift` (ingranaggio), `NotesModel` (elenco strumenti e pallini salvati in UserDefaults, gesti).
- Strumenti disponibili: penna (normale/stilografica/monolinea), evidenziatore (spessore + trasparenza, default 0 = come prima), matita (matita/pastello a cera), gomma (tratto intero/solo pixel + dimensione). Se ne possono avere più di uno per tipo, ognuno con colore/spessore/stile propri. Un tocco attiva, secondo tocco apre le impostazioni.
- Pallini colore a lato (numero modificabile 2-8 da «Modifica»): tocco = colore allo strumento attivo; tocco su pallino già selezionato = selettore colori Apple.
- «Modifica» (icona cursori): riordina (trascina), togli (scorri), aggiungi dal catalogo; lazo, screenshot, immagine/PDF, testo, post-it compaiono come «in arrivo». Differenza dal mockup: la modifica è in un pannello, non direttamente sulla barra.
- Barra: fissa in alto/basso/sinistra, oppure flottante (orizzontale/verticale, maniglia, si riduce a pulsante tondo, posizione e stato ricordati, resta dentro lo schermo). Dimensione normale/grande, nomi sotto le icone, annulla/ripeti opzionali.
- Comportamento (ingranaggio): dito scorre/disegna, tocco con due dita = annulla, doppio tocco Pencil = gomma / strumento prima / niente.
- Da verificare su iPad: doppio tocco Pencil (richiede che sia attivo in Impostazioni → Apple Pencil), tocco con due dita (l'annulla usa ancora l'undo del PDF, mai provato: possibile che non annulli i tratti), trasparenza evidenziatore, dito che disegna (scorrere potrebbe non funzionare), stili penna/matita, barra verticale/sinistra.
- Non fatto: spingere la barra fuori schermo con linguetta, cronometro, salvataggio automatico/manuale, riconoscimento rette/forme.

## Passo 2 (consegnato 30/09): barra in alto e schede
- `Editor/EditorView.swift` riscritto: barra in alto (Libreria, miniature, titolo, lente disattivata, condividi, ingranaggio, Salva, menu ···), sotto la striscia schede (× a sinistra del nome, «+» con i 15 file più recenti per data di modifica non ancora aperti), poi barra strumenti e PDF. Niente più NavigationStack.
- Schede: `AptStore.schede` (documenti aperti, restano anche tornando in Libreria, si perdono alla chiusura dell'app). Un solo `NotesModel` per l'Editor: al cambio scheda si salva se ci sono modifiche e si apre l'altro PDF (la cronologia annulla e la posizione di scorrimento non si conservano tra schede). Chiudere l'ultima scheda torna in Libreria. `reload()` toglie le schede di file eliminati/spostati.
- Salvataggio: nuovo flag `modificato` (delegate PencilKit). Si salva da solo solo se ci sono modifiche: al cambio/chiusura scheda e uscendo in Libreria (prima uscire senza Salva perdeva i tratti). «Scarta tratti non salvati» è nel menu ···.
- Miniature: PDFThumbnailView in un pannello a sinistra del PDF (icona a sinistra in alto).
- Condividi: ShareLink sul file PDF. Ricerca nel testo: non ancora (passo successivo).
- Da verificare su iPad: cambio scheda con tratti non salvati (devono restare), miniature (tocco porta alla pagina), titolo centrato e non sovrapposto ai pulsanti in verticale, condividi, «+».

## Ricerca testo (consegnata 30/09)
- `Editor/RicercaPDF.swift` (modello + `BarraRicerca`); la lente nella barra in alto apre una striscia di ricerca sotto le schede.
- Cerca mentre si scrive (da 2 caratteri, attesa 0,3 s), senza distinguere maiuscole/accenti; risultati evidenziati in giallo, corrente selezionato, contatore «n di N», frecce su/giù (Invio = successivo). Cambiando scheda la ricerca si azzera. Solo testo digitato nel PDF (non la scrittura a mano).
- Dal 30/09 sera usa la tastiera nostra (vedi Problemi aperti). Da verificare su iPad: PDF scansionati senza testo non danno risultati; velocità su PDF molto lunghi (ricerca sincrona).
