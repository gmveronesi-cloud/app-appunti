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

## Decisioni Editor (30/09, prese da Cristina)
- Barra strumenti: fissa in alto O flottante, scelta nelle impostazioni (ingranaggio nella barra del titolo, salvata con @AppStorage).
- Strumenti: penna, evidenziatore, gomma, annulla/ripeti. (Sottolineato, barrato, nota testuale: rimandati.)
- Colore: selettore libero di iPadOS (ColorPicker). Spessore: slider. Un secondo tocco sullo strumento attivo apre il pannello.
- Gomma: a pezzetti di base; interruttore "tratto intero" nel pannello della gomma.
- Implementato 30/09 (da verificare sull'iPad, Pencil non testabile da qui): penna salvata a colore pieno, evidenziatore al 40%.
- Da fare: la barra flottante non ricorda la posizione dopo la chiusura; annulla/ripeti sempre attivi (non si spengono).

## Prossimi passi
1. Verificare sull'iPad le 2 correzioni della Libreria e la nuova barra strumenti.
2. Editor: sottolineato, barrato, nota testuale.
3. Poi roadmap nel file di stato del Progetto (rifinitura Libreria, quaderno, esportazione, ricerca testo).
