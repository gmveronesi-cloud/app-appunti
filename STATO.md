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
- Cristina ha detto che i problemi sono solo 2 (non 3).

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
- Da verificare sull'iPad: tastiera a schermo assente in Swift Playgrounds (testo e post-it dipendono da questo), notifiche del timer.

## Prossimi passi
1. Verificare sull'iPad le 2 correzioni della Libreria e la nuova barra strumenti.
2. Editor: sottolineato, barrato, nota testuale.
3. Poi roadmap nel file di stato del Progetto (rifinitura Libreria, quaderno, esportazione, ricerca testo).


## Passo 1 (consegnato): tratti modificabili dentro il PDF
- Prova macOS #2 riuscita: annotazione nascosta di tipo Square con i dati in chiave personalizzata /AptDati: si rilegge identica, nessun Popup, rimozione/sostituzione senza copie residue.
- NotesModel: al salvataggio ogni pagina riceve (a) annotazioni ink visibili (userName AptTratto) e (b) un'annotazione nascosta AptDati con il PKDrawing in base64 (coordinate in punti pagina). All'apertura le annotazioni dell'app vengono tolte dal documento in memoria e il disegno torna sulle tele, quindi restano modificabili (gomma, ecc.).
- Da verificare su iPad: che i tratti tornino modificabili dopo chiusura/riapertura, posizione corretta dopo zoom, PDF aperto in un'altra app con tratti visibili.
- Barra superiore (miniature, cerca, condividi, schede): passo 2, per ora nulla di nuovo.

- Impostazioni strumenti (strumento, colori, spessori, gomma) ora ricordate tra le sessioni (UserDefaults).
- Aperto: forma del tratto evidenziatore fuori dall'app diversa da quella nell'app (il pennarello PencilKit ha punta piatta, le annotazioni PDF ink no). Serve screenshot per decidere la correzione.
- Barra strumenti/superiore come da mockup: passi 2 e 3, non ancora fatti.
