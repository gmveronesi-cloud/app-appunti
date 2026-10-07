# STORICO — App Appunti (archivio, NON da leggere a ogni chat)

Archivio dettagliato delle consegne fino al 04/10/2026, spostato qui da `STATO.md` il 04/10/2026 per tenere
`STATO.md` corto. Serve solo per ritrovare il perché di una scelta o i dettagli di una funzione (cercare con grep).
Le note «da verificare su iPad» di questo archivio sono tutte VERIFICATE da Cristina il 04/10 sera.

## Problemi risolti (30/09)
- (risolto 30/09, da verificare sull'iPad) Non si potevano creare sottocartelle: il "+" della riga compariva solo al passaggio del mouse (su iPad non esiste). Ora il "+" è sempre visibile sulle cartelle e sulla raccolta attiva, e il menu "Nuovo" ha "Nuova cartella".
- (risolto 30/09, da verificare sull'iPad) Rinomina cartella/raccolta: la tastiera non compariva. Il campo UITextField inline si attivava (cursore visibile) ma la tastiera a schermo non compariva. Provato: rinomina in una finestrella (`.alert` con TextField) in `AptSideRow`; `AptNameField` non più usato. Verificato 30/09: la tastiera a schermo NON compare nemmeno nella finestrella di sistema (altre app OK, riavvii OK), ma con Scribble (scrittura Apple Pencil) la rinomina funziona. Probabile limite di Swift Playgrounds/iPadOS 27: da ricontrollare quando l'app girerà fuori da Playgrounds.
- (nuovo 30/09, da verificare sull'iPad) Tastiera a schermo assente in Swift Playgrounds: ora c'è una tastiera nostra (`Tastiera/TastieraApp.swift`: `AptTastiera`, `AptCampo`, `AptRinomina`). Usata nella rinomina (finestra `.sheet`, nome selezionato: il primo tasto lo sostituisce) e nella ricerca nel PDF (tastiera sotto il PDF, tasto per nasconderla). Niente TextField/tastiera di sistema in tutta l'app; tolto `AptNameField`. Limiti: si scrive e cancella solo in fondo al testo (niente cursore mobile, niente incolla/selezione); layout italiano con accenti à è é ì ò ù e apostrofo; pagina simboli. Se non piace o non funziona: si tolgono le funzioni con tastiera (rinomina → solo Scribble, ricerca).
- Cristina ha detto che i problemi sono solo 2 (non 3).
- (corretto 30/09, da verificare sull'iPad) Eliminare un documento congelava l'app: `trashItem` annidato dentro una coordinazione di file (deadlock su iCloud/File). Ora `AptFS.trash` usa solo `removeItem` e `AptStore.delete` lavora fuori dal thread principale. Niente più cestino locale: su iCloud Drive i file vanno in «Eliminati di recente».


## Elenco dei passi completati (ordine concordato il 30/09)
1. FATTO — Passo 1: tratti modificabili nel PDF + impostazioni strumenti ricordate (da verificare su iPad).
2. FATTO (30/09, compila senza errori; da verificare su iPad) — Passo 3: barra strumenti (vedi sezione Passo 3 sotto).
3. FATTO (30/09, compila senza errori; da verificare su iPad) — Passo 2: barra in alto + schede (vedi sezione Passo 2 sotto).
4. FATTO (30/09, compila senza errori; da verificare su iPad) — Ricerca testo (vedi sezione sotto).
5. FATTO (01/10, compila senza errori; da verificare su iPad) — Lazo (vedi sezione sotto).
6. FATTO (01/10, da verificare compilazione e iPad) — Rette/forme con la Pencil ferma (vedi sezione sotto).
7. FATTO (01/10, compila senza errori; da verificare su iPad) — Testo (vedi sezione sotto).
8. FATTO (02/10, compila senza errori; da verificare su iPad) — Immagini, livelli, ritaglio, taglia/copia/incolla (vedi sezione sotto). Post-it rimosso.
9. FATTO (02/10 sera, compila senza errori; da verificare su iPad) — Timer/cronometro (vedi sezione sotto).
10. FATTO (02/10 sera, compila senza errori; da verificare su iPad) — Penna screenshot (vedi sezione sotto).
11. FATTO (02/10 sera, compila senza errori; da verificare su iPad) — Vassoio delle immagini in sospeso (vedi sezione sotto).
12. FATTO (04/10, compila senza errori; da verificare su iPad) — Lazo che seleziona anche le immagini (vedi sezione sotto).
13. FATTO (04/10 sera, compila senza errori; da verificare su iPad) — Aggiungi PDF al documento (vedi sezione sotto). «Converti PDF in immagine sopra la pagina» esisteva già («PDF o documento di testo»).
14. PROSSIMO, uno alla volta: salvataggio automatico/manuale come impostazione, lazo che selezioni anche i testi.
- Aperto: forma del tratto evidenziatore fuori dall'app diversa (chiedere screenshot a Cristina).
- Verifica iPad del 04/10 sera: Cristina ha provato TUTTO ciò che era «da verificare» (Editor, tratti, forme, testo, immagini, timer, penna screenshot, vassoio, lazo con immagini, aggiungi PDF, Libreria) e va tutto bene. Tutte le voci «da verificare su iPad» sopra sono quindi VERIFICATE. Unica correzione: pannello «Modifica» della barra (sotto).
- Correzioni piccole note: barra flottante non ricorda la posizione; annulla/ripeti sempre attivi; avviso `onChange` deprecato in Contenuto.swift:60.

## Stile grafico (deciso 01/10/2026)
- Riferimento vincolante: `docs/stile-grafico.md` (regole) e `docs/stile-grafico.html` (esempi visivi, chiaro/scuro). Codice: `Appunti.swiftpm/Tema/Tema.swift` (`AptTema`).
- Requisiti di Cristina: moderno, rosso e colori caldi, pastello (mai acceso o fluorescente), minimal ma curato.
- Piano: base grafica subito (Tema + barra strumenti + Libreria), poi ogni strumento nuovo già nello stile, lucidatura alla fine.
- Note di Cristina (01/10): (1) colori di penne/evidenziatori/matite restano normali e scelti da lei, il tema vale solo per l'interfaccia; (2) tolte tutte le scritte piccole che spiegano come usare l'app (fatto nel codice; da ora non aggiungerne di nuove).
- Stato (01/10, compila senza errori): tema APPLICATO a tutta l'app: Libreria (barra in alto nostra al posto di quella di sistema, barra laterale, griglia/lista, fogli), Editor (barra in alto, schede a pillola, barra strumenti a capsula fissa o flottante, ricerca, tastiera), pulsanti e selettori. Riferimento: `docs/stile-grafico.html`. Nelle viste nuove usare solo `AptTema` e i componenti di `Tema.swift` (`AptIcona`, `AptLinea`, `aptBarra`, `aptPannello`, `aptCapsulaBarra`, stili pulsante).
- Da verificare sull'iPad (il runner mostra solo la schermata iniziale): resa di Libreria ed Editor rispetto alla guida, sfondo e bordi di elenchi nei fogli (Sposta, Aggiungi cartelle), barra laterale di sistema su iPadOS 27, popover.

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

## Lazo (consegnato 01/10)
- File: `Editor/Lazo.swift` (`LazoGesto`, `LazoSelezione`), `TipoStrumento.lazo` in `Strumenti.swift` (campi `lazoRiquadro`, `lazoFiltri`; lettura tollerante dei dati vecchi), pannello in `BarraStrumenti.swift`, collegamento in `NotesModel` (`aggiornaInterazione`).
- Come funziona: lo strumento «Lazo» si aggiunge dalla barra (Modifica → Aggiungi). Con il lazo attivo le tele non disegnano e la Pencil (o il dito, se «dito disegna» è attivo) traccia un contorno tratteggiato a mano libera o un riquadro (impostazione nel pannello, secondo tocco sullo strumento). Basta un solo punto del tratto dentro il contorno per selezionarlo tutto (correzione 01/10). Lo spostamento riscrive i punti dei tratti (non più `transform`), così i tratti seguono il riquadro. Filtri: penne, evidenziatori, matite (immagini/testi/post-it si aggiungono quando esisteranno).
- Selezione: riquadro tratteggiato. Trascinare dentro = sposta (annullabile); tocco dentro = menu Duplica / Elimina; tocco o tratto fuori = nuova selezione. La selezione è su una sola pagina.
- Da verificare su iPad: che la Pencil con il lazo non faccia scorrere il PDF, posizione del riquadro dopo zoom, che annulla/ripeti riportino indietro spostamenti ed eliminazioni (usano l'undo del PDF, come tutto il resto: ancora non provato per i tratti normali), menu Duplica/Elimina.
- Non fatto: copia/incolla tra pagine, ridimensionare/ruotare la selezione, selezione su più pagine.

## Lazo: menu sulla selezione (consegnato 01/10, compila; da verificare su iPad)
- Tocco dentro la selezione → menu nell'ordine voluto da Cristina: Taglia, Elimina, Ridimensiona, Copia, Colore.
- Ridimensiona: compaiono 4 maniglie agli angoli; si trascina un angolo (proporzionale, angolo opposto fermo, spessore compreso). Si esce toccando dentro la selezione o fuori.
- Colore: selettore colori di sistema, applicato in diretta ai tratti scelti (trasparenza dell'evidenziatore mantenuta); annullabile.
- Incolla (aggiunto da Claude, serve a Taglia/Copia): tocco su un punto vuoto della pagina con il lazo attivo, se ci sono tratti copiati → menu «Incolla», centrato sul punto. Appunti interni all'app, validi finché resta aperta.
- Tolto il menu Duplica (sostituito da Copia + Incolla).
- Prossime funzioni del lazo: da decidere con Cristina.

## Lazo: contorno e rotazione (consegnato 01/10, compila; da verificare su iPad)
- La selezione non è più un riquadro: contorno tratteggiato che segue la forma dei tratti scelti (`calcolaContorno`, unione dei contorni; sopra 40 tratti niente unione, quindi possibili linee interne). Il riquadro invisibile resta per il tocco e le maniglie.
- Menu «Ridimensiona e ruota»: 4 maniglie agli angoli (scala) + cerchio sopra la selezione (ruota attorno al centro). Annullabile.

## Rette e forme con la Pencil ferma (consegnato 01/10, compila senza errori; da verificare su iPad)
- File: `Editor/Forme.swift` (`RiconoscitoreForme`, `FormaRiconosciuta`, `FormeGesto`, `FormePencil`), collegato in `NotesModel` (`formeFerma`, `installaGesti`, `aggiornaInterazione`) e interruttore in `ImpostazioniEditor` («Rette e forme con la Pencil ferma», attivo di base).
- Come funziona: con penna, evidenziatore o matita si traccia un segno e, senza sollevare la Pencil, si tiene ferma ~0,6 s. Compare in anteprima la forma riconosciuta (tocco leggero di feedback); alzando la Pencil il tratto a mano libera viene sostituito dalla forma, con lo stesso inchiostro/colore. Retta: l'estremo segue la Pencil anche dopo il riconoscimento, e si raddrizza se è quasi orizzontale/verticale (~3,5°). Forme chiuse: rettangolo, quadrato (lati quasi uguali), ellisse, cerchio. Se non somiglia a nulla resta il tratto a mano libera.
- Limiti: rettangoli ruotati/rombi e triangoli non riconosciuti (restano a mano libera); la forma ha lo spessore medio del tratto originale.
- Annulla: riporta il tratto a mano libera (un secondo annulla lo toglie).
- Da verificare su iPad: che la Pencil ferma faccia comparire l'anteprima, tempo di attesa (0,6 s) e tolleranza di tremore (4 pt), sostituzione al sollevamento, annulla.

## Colore del tema (01/10, richiesta di Cristina)
- Accento spostato dal rosa a un marrone terracotta pastello (`AptTema.accento` 0xAE6B4B chiaro / 0xDDA27F scuro, tenui e testi di conseguenza; sfondi e linee leggermente meno rosati). `pericolo` (Elimina) resta rosso. Aggiornato `docs/stile-grafico.md`; `docs/stile-grafico.html` e `docs/mockup-editor.html` mostrano ancora il vecchio rosso.

## Testo (consegnato 01/10, compila senza errori; da verificare su iPad)
- File: `Editor/Testo.swift` (`TestoControllo`, `BozzaTesto`), `TipoStrumento.testo` (icona textformat, colore e dimensione carattere 10-48 nello slider «Dimensione»), collegamento in `NotesModel` (`bozzaTesto`, `controlloTesto`, `confermaTesto`) e finestra in `EditorView` (`AptRinomina` con la nostra tastiera).
- Come funziona: aggiungere «Testo» dalla barra (Modifica → Aggiungi). Con il testo attivo si tocca un punto della pagina → finestra con tastiera nostra → «Salva» mette il testo con colore e dimensione dello strumento. Nel PDF è un'annotazione vera (freeText, nome `AptTesto`, visibile in ogni lettore), salvata col PDF. Toccando un testo già messo: Modifica / Sposta (poi tocco sul nuovo punto, stessa pagina) / Elimina. Tutto annullabile.
- Limiti: una sola riga (la tastiera nostra non ha «a capo»), niente cursore mobile; il testo non va a capo da solo; lo spostamento è a due tocchi (non trascinando).
- Da verificare su iPad: tocco sulla pagina con il testo attivo (anche con il dito), resa del testo nel PDF dopo salvataggio e in altri lettori, menu Modifica/Sposta/Elimina, annulla.

## Nitidezza (01/10 sera, da verificare su iPad)
- Cristina: testo e tratti «un po' sgranati». Causa probabile per i tratti: la tela PencilKit di ogni pagina viene ingrandita da PDFView con la pagina, ma resta disegnata alla risoluzione dello zoom 100%. Correzione in `NotesModel.rendiNitida`: dopo ogni zoom (attesa 0,25 s) e alla comparsa della pagina, `contentScaleFactor` della tela (e dei suoi livelli) = scala schermo × ingrandimento reale, massimo 6 e circa 16 milioni di pixel per pagina. In più `PDFView.interpolationQuality = .high`.
- Per il testo (annotazione freeText di PDFKit) non c'è una causa certa: se resta sgranato chiedere uno screenshot e il livello di zoom (se sgranato solo ingrandendo o anche a zoom normale).

## Nitidezza, seconda correzione (01/10 sera, compila; simulatore: testo e tratto nitidi; da verificare su iPad)
- Screenshot di Cristina: il testo (annotazione freeText disegnata da PDFKit) è una bitmap a bassa risoluzione, in Times invece che Helvetica, a ogni zoom; l'evidenziatore (`.marker` di PencilKit) ha i bordi sfumati; la penna nera è nitida.
- Testo: ora nell'app è disegnato da noi con livelli `CATextLayer` (vettoriali) sulla tela di ogni pagina (`TestoControllo.ridisegna`, ridisegnati a ogni zoom). I testi stanno in `NotesModel.testi` (`ElementoTesto`); al salvataggio diventano annotazioni `AptTesto` (freeText, Helvetica) e all'apertura tornano testi modificabili, come i tratti (le annotazioni `AptTesto` si tolgono dal documento in memoria). Nel PDF salvato il testo resta testo vero.
- Evidenziatore: non più `.marker` ma `.monoline` semitrasparente (alpha 0,45 × (1 − trasparenza)): spessore costante, bordi netti, punta tonda (uguale a come appare fuori dall'app: risolve anche il punto aperto sulla forma). Evidenziatori già disegnati con il vecchio marker restano marker. Il lazo riconosce come evidenziatore sia il marker sia la linea semitrasparente.
- Tenuta anche la correzione `rendiNitida` (scala della tela con lo zoom).
- Da verificare su iPad: testo nitido, posizione del testo dopo salvataggio/riapertura (stessa posizione e dimensione), evidenziatore netto e con lo stesso aspetto di prima come colore, che i vecchi evidenziatori si vedano ancora.
- Nota: `Editor/ProvaNitidezza.swift` (diagnostica aggiunta da un'altra sessione, si attiva solo con APT_PROVA nel simulatore di GitHub Actions) è stata adattata al testo vettoriale; le immagini `nitidezza-A.png` (Editor) e `nitidezza-B.png` (PDFView semplice) stanno sul ramo `esiti`. Nel simulatore il testo disegnato da noi e il tratto escono nitidi; il simulatore però non riproduce la resa dell'iPad, e l'evidenziatore nuovo non è coperto dalla prova.

## Nitidezza dei tratti, correzione vera (02/10, compila; simulatore: bordo netto; da verificare su iPad)
- Diagnostica nel simulatore (`ProvaNitidezza`, `diag-A.txt` su `esiti`): la tela PencilKit di ogni pagina misurava 595×842 punti mentre PDFView mostra la pagina a 1,71×: PencilKit disegna alla risoluzione della propria tela, quindi i tratti venivano ingranditi come una bitmap. L'impostazione di `contentScaleFactor`/`contentsScale` (anche su tutta la gerarchia, provata come modo G) NON cambia nulla: la correzione `rendiNitida` del 01/10 era inutile ed è stata tolta.
- Correzione: `Editor/PaginaTela.swift`. La vista di sovrapposizione di ogni pagina è un contenitore con dentro la tela PencilKit grande `NotesModel.risoluzione` = 3 volte la pagina e rimpicciolita con `transform` 1/3: PencilKit disegna con 3× i dettagli, a schermo lo spazio è lo stesso. Nitido fino a circa 3× di zoom (oltre torna morbido); costo: più memoria per pagina.
- Conseguenze nel codice (coordinate della tela = 3 × punti pagina; `tela.fattoreRisoluzione` = 3): spessori e gomma moltiplicati (`Strumento.pkTool(scala:)`); soglie e segni di selezione di Lazo (`aggiornaStile`, maniglie, contorno) e di Forme (tolleranza, lunghezze minime, spessore anteprima) moltiplicati; salvataggio/caricamento già usavano il rapporto tra tela e pagina, quindi i PDF esistenti si leggono uguali; Testo usa il rapporto e la scala del livello `displayScale × max(1, zoom/3)`.
- Da verificare su iPad: nitidezza a zoom normale e alto, scrittura fluida (la tela è 9× più grande in pixel), spessori della penna uguali a prima, lazo (maniglie, tocchi, rotazione), forme con Pencil ferma, gomma, tratti già salvati riletti nella stessa posizione e dimensione, memoria con PDF molto lunghi (se pesa: ridurre `risoluzione` a 2).

## Immagini, livelli e testo (02/10 mezzogiorno, compila senza errori; da verificare su iPad)
- Post-it: RIMOSSO del tutto (richiesta di Cristina). Un vecchio strumento Post-it salvato sull'iPad viene scartato in silenzio (`Tollerante<Strumento>`).
- Immagini: decisione presa: devono vedersi in altri lettori → annotazione Stamp con `draw` personalizzato (prova `prove/ProvaImmagine.swift`, esito `prova-immagine.txt`). Strumento «Immagine» (icona photo); file `Editor/Immagine.swift`.
  - Tocco su un punto vuoto → «Dalle Foto / Da File» (o, se c'è qualcosa copiato, menu Incolla / Nuova immagine). Tocco su un'immagine la seleziona: cornice tratteggiata, 4 maniglie agli angoli (ingrandisce in diretta, proporzionale), cerchio sopra (ruota, si ferma da solo agli angoli retti). Trascinare l'immagine la sposta con anteprima in tempo reale. Tocco su un'immagine già scelta → menu: Taglia, Copia, Ritaglia, Porta sopra, Porta sotto, Elimina. «Ingrandisci/Rimpicciolisci» tolti.
  - Ritaglio: dal menu → 8 maniglie (angoli e lati) che muovono i bordi del ritaglio, anche per riespandere; menu «Fine ritaglio / Ripristina». L'immagine intera resta salvata (`/AptDati`), il ritaglio e la posizione stanno in `/AptInfo` (centro, larghezza, angolo, data, ritaglio).
  - Il gesto di trascinamento parte solo se il tocco cade su un'immagine o su una maniglia: altrove il dito scorre il PDF.
- Livelli (richiesta di Cristina): ordine di creazione. Ogni tratto ha già una data (`PKStroke.path.creationDate`), ogni immagine ha `creazione`. Un tratto più vecchio dell'immagine più recente sta SOTTO le immagini, uno più nuovo SOPRA. Implementazione in `NotesModel.ripartisci`: i tratti vecchi vanno in `sotto[pagina]` e sono mostrati come strati-immagine (non modificabili) tra le immagini; la tela PencilKit contiene solo i tratti nuovi. Con GOMMA e LAZO si «uniscono» tutti i tratti nella tela (così funzionano su tutto) e tornano divisi cambiando strumento; ogni cambio di divisione azzera la cronologia di annulla (solo se la pagina ha immagini). Nel PDF le annotazioni (tratti e immagini) sono scritte in ordine di data, così anche gli altri lettori mostrano lo stesso ordine; il testo è sempre sopra.
  - «Porta sopra / Porta sotto» sull'immagine: un livello = il gruppo di tratti adiacente o l'immagine adiacente (si cambia la data dell'immagine). Anche nel menu del lazo (solo se la pagina ha immagini): sposta i tratti scelti subito sopra l'immagine più vicina sopra / subito sotto quella più vicina sotto; si vede tornando alla penna (con il lazo attivo i tratti sono tutti nella tela).
  - Incolla di tratti dal lazo: ora ricevono la data attuale (stanno sopra le immagini).
- Testo: trascinando un testo si vede muovere in tempo reale (non più «Sposta» a due tocchi); menu: Modifica, Taglia, Copia, Elimina; tocco su un punto vuoto con qualcosa copiato → Incolla / Nuovo testo.
- Da verificare su iPad: maniglie e rotazione (precisione del tocco, soprattutto con zoom alto), ritaglio, anteprime in diretta, livelli (scrivere sotto/sopra un'immagine, tornare a gomma/lazo e alla penna), annulla dopo aver messo un'immagine (la cronologia dei tratti precedenti si azzera), apertura di un PDF già salvato con immagini ruotate/ritagliate, visibilità in altri lettori, velocità con molte immagini.
- Non fatto: livelli per i testi (stanno sempre sopra), selezione di immagini col lazo, aggiungi PDF.

## Sorgenti immagine e selezione (02/10 pomeriggio) — NON ANCORA COMPILATO
- ATTENZIONE: il commit `7397ef4` non è stato compilato: GitHub Actions rifiuta di avviare il job («recent account payments have failed or your spending limit needs to be increased», vedi Impostazioni → Billing & plans dell'account GitHub). Finché non si sblocca non c'è verifica di compilazione: al primo esito utile leggere gli errori e correggerli.
- Pulsanti dell'icona Immagine (nel pannello dello strumento, secondo tocco sull'icona, e nella finestra che compare toccando un punto vuoto della pagina): Dalle Foto, Da File (immagine), PDF o documento di testo, Scansiona documento. File `Editor/Sorgenti.swift`.
  - PDF/testo: `ConvertitoreDocumento` apre PDF; .txt, .rtf, .html vengono impaginati in A4 (CoreText). Un solo foglio → entra subito; più pagine → finestra con le miniature (si toccano quelle da aggiungere). Ogni pagina diventa un'immagine JPEG (lato 2000 px, larghezza 80% della pagina), in cascata. Word (.docx) non supportato.
  - Scansione: `VNDocumentCameraViewController` (VisionKit) a schermo intero; ogni foglio scansionato diventa un'immagine. `Package.swift` ora dichiara la capability `.camera(purposeString:)` (serve in Swift Playgrounds; se Playgrounds la riscrive/rifiuta, controllare). Non disponibile nel simulatore.
  - Dal pannello l'immagine va al centro della pagina visibile (`NotesModel.avvia`).
- Selezione delle immagini (`ImmagineControllo.puoAgire`): con il DITO tocco su un'immagine = selezione con qualsiasi strumento (tranne quando «dito disegna» è attivo con penna/evidenziatore/matita/gomma); con la PENCIL solo con lazo e immagine. Una volta scelta, il dito la sposta/ridimensiona/ruota con qualsiasi strumento; con il lazo la Pencil sposta l'immagine scelta (il lazo cede, `LazoGesto.cede`) e un tocco breve su un'immagine la seleziona (`tocca`). Con lo strumento Testo un tocco del dito su un'immagine la seleziona (non crea testo; per scrivere sopra un'immagine usare la Pencil). Toccando fuori si deseleziona. La selezione resta cambiando strumento.
- Da verificare su iPad: tutto quanto sopra, in particolare conflitti tra gesti (dito che scorre vs tocco su immagine scelta, lazo vs immagine).

## Risparmio minuti GitHub Actions (02/10 sera)
- I runner macOS contano 10× sui repository privati e la quota gratuita è finita (vedi sezione precedente). Il workflow ora: non parte per modifiche a `*.md`, `docs/`, `prove/`; annulla le compilazioni vecchie dello stesso ramo; la schermata nel simulatore si scatta solo con «Run workflow» a mano o con `[schermata]` nel messaggio del commit; tolte le prove nitidezza e le prove macOS (i file in `prove/` restano). Compilazione sola ≈ 5 minuti invece di 9-10. Consiglio: raggruppare più modifiche per ogni push.

## Timer e cronometro (02/10 sera) — compila senza errori; da verificare su iPad
- File: `Editor/Orologio.swift` (`OrologioModello.condiviso`, `OrologioRiquadro`, `PannelloOrologio`). Pulsante orologio nella barra strumenti, prima di «Modifica» (si colora quando il conteggio è attivo); il riquadro è sovrapposto sia all'Editor sia alla Libreria, quindi resta visibile su tutte le schermate. Lo stato è in un oggetto condiviso (non nell'ambiente SwiftUI) per non dipendere dal passaggio nel `fullScreenCover`.
- Pannello (senza tastiera di sistema): Cronometro / Timer; timer con durate rapide 5-10-15-25-45′ e contatori Minuti e Secondi (passo 5); «Mostra i secondi»; Avvia. Con il conteggio attivo: Pausa/Riprendi, Mostra il riquadro (se è sulla linguetta), Chiudi.
- Riquadro: ora, pausa/riprendi, «s» (secondi sì/no: senza secondi mostra «n min» o «h min»), chiudi; barra di avanzamento per il timer. Si trascina (anche fuori schermo fino a ~85%: lascia una linguetta sul bordo, un tocco la riporta), si ingrandisce dalla maniglia in basso a destra (0,7×–2,6×, ricordato). A fine timer: riquadro evidenziato, pausa disattivata, vibrazione di conferma e notifica locale «Timer scaduto» (programmata all'avvio/ripresa, annullata con pausa/chiudi; il sistema la mostra solo se l'app non è in primo piano; il permesso si chiede alla prima partenza di un timer).
- Non ricordati tra le sessioni: il conteggio e la posizione (restano secondi sì/no e dimensione).
- Da verificare su iPad: trascinamento (il dito partito sui pulsanti non trascina), maniglia di ingrandimento, linguetta sui 4 bordi, tocco di ritorno, rotazione dell'iPad con il riquadro fuori posizione, notifica a timer finito con l'app in secondo piano (in Swift Playgrounds il permesso notifiche potrebbe non essere concesso), accuratezza dopo pausa lunga.

## Penna screenshot e timer più compatto (02/10 sera) — compila senza errori; da verificare su iPad
- Timer: la barra di avanzamento ora è una linea sul bordo basso del riquadro (non una riga in più): il riquadro del timer ha le stesse dimensioni di quello del cronometro.
- Penna screenshot: `Editor/Cattura.swift` (`CatturaSchermo`, `DestinazioneCattura`), `TipoStrumento.catturaSchermo` (icona camera.viewfinder, campo `catturaRiquadro`), collegamento in `NotesModel` (gesto, `destinazioneCattura`, `inserisciCattura`, `avviso`), `ImmagineControllo.inserisci(... larghezza:)`. Si aggiunge da Modifica → Aggiungi.
- Come funziona: con lo strumento attivo la Pencil traccia un riquadro o un contorno a mano libera (scelta nel pannello dello strumento). All'alzata la parte scelta (pagina, tratti, immagini e testi come appaiono) diventa un'immagine con `drawHierarchy` della vista PDF, alla risoluzione dello schermo; a mano libera fuori dal contorno è trasparente. Minimo 12 pt.
- Destinazione (ingranaggio → «Penna screenshot: dove va»): Appunti (negli appunti di sistema, di base), Nel foglio (immagine sulla pagina, alla stessa dimensione che aveva a schermo, stesso livello/selezione delle altre immagini), Foto o condividi (foglio di condivisione di sistema: «Salva immagine» la mette in Foto; scelto così perché salvare direttamente in Foto richiede un permesso da dichiarare in `Package.swift` e non voglio rischiare un blocco in Swift Playgrounds).
- Da verificare su iPad: che l'immagine contenga davvero PDF e tratti (la cattura di PDFKit con `drawHierarchy` non si prova nel simulatore), nitidezza, contorno tratteggiato mentre si traccia, le tre destinazioni, incolla in un'altra app, foglio di condivisione su iPad.

## Vassoio delle immagini in sospeso (02/10 sera) — compila senza errori; da verificare su iPad
- File: `Editor/Vassoio.swift` (`Vassoio.condiviso`, `VassoioView`). Anteprime in basso nell'Editor (sopra il foglio, nascoste quando c'è la tastiera della ricerca). Valgono per tutta l'app, non per il foglio: restano passando da un documento all'altro e dopo aver chiuso l'app (file in Application Support/Vassoio + `indice.json`; si perdono se si disinstalla l'app).
- Cosa ci finisce: gli screenshot della penna screenshot (nuova destinazione «Vassoio», ora quella di base; chi aveva già scelto un'altra destinazione la mantiene) e le immagini tagliate o copiate con lo strumento Immagine (ritaglio incluso, senza rotazione).
- Uso: tocco sull'anteprima = l'immagine va al centro di ciò che si vede del foglio attuale (e RESTA nel vassoio, così si può usare in altri documenti); X = elimina; pulsante in alto a sinistra = foglio di condivisione (file immagine); freccia a sinistra della striscia = riduce il vassoio a una pillola con il numero, un tocco la riapre. Le più recenti stanno a sinistra.
- Non incluso: tratti e testi tagliati/copiati con lazo e testo restano negli appunti interni come prima (non finiscono nel vassoio). Da decidere con Cristina se servono.
- Da verificare su iPad: che l'anteprima compaia subito dopo la cattura, tocco = inserimento nel punto giusto, condivisione, persistenza dopo riavvio, ingombro con la barra flottante in basso.

## Correzioni al vassoio e ai menu (02/10 sera) — compila senza errori; da verificare su iPad
- Vassoio: tolto il pannello di fondo; le anteprime stanno una accanto all'altra direttamente sopra il foglio, ognuna con la propria ombra (come in Appunti+). Con poche immagini la striscia è larga quanto serve (`ViewThatFits`), con tante scorre. Il tocco sul foglio tra un'anteprima e l'altra passa al foglio.
- «Elimina» è la PRIMA voce di tutti i menu di selezione: immagine (Elimina, Taglia, Copia, Ritaglia, Porta sopra, Porta sotto), lazo (Elimina, Taglia, Ridimensiona e ruota, Copia, Colore, …), testo (Elimina, Modifica, Taglia, Copia).
- Grandezza originale: il vassoio ricorda la larghezza a schermo (punti) dell'immagine al momento dello scatto o della copia; reinserendola ha la stessa grandezza a schermo allo zoom di adesso (`inserisciDaVassoio(_:larghezzaSchermo:)`). Vale anche per le immagini copiate/tagliate. Il vecchio vassoio di prova (senza larghezza) usa la grandezza standard.
- La destinazione della cattura ora parte da «Vassoio» per tutti (chiave salvata `ed.cattura2`: la scelta fatta prima non conta più).

## Lazo: selezione delle immagini (04/10) — compila senza errori; da verificare su iPad
- File toccati: `Lazo.swift` (gruppo di immagini accanto ai tratti), `Immagine.swift` (`seleziona`, `annullaSelezione`, `anteprimaGruppo`, `copiaInAppunti`), `Strumenti.swift` (campo `lazoImmagini`, di base acceso, anche per i lazo già salvati), `BarraStrumenti.swift` (interruttore «Immagini» nel pannello del lazo, sotto Penne/Evidenziatori/Matite).
- Regole: un'immagine viene presa se il lazo (a mano libera o riquadro) ne circonda circa un quinto (25 punti di prova); oppure se il lazo sta tutto dentro un'immagine e non prende nient'altro (sceglie quella più in alto).
- Una sola immagine e nessun tratto: diventa la selezione completa dell'immagine (cornice, maniglie, rotazione, ritaglio, menu con Porta sopra/sotto), come dopo un tocco.
- Più immagini, oppure immagini insieme a tratti: selezione di gruppo del lazo (contorno tratteggiato che include le immagini). Trascinare dentro = sposta tutto; «Ridimensiona e ruota» agisce su tratti e immagini insieme; menu: Elimina, Taglia, Ridimensiona e ruota, Copia (+ Colore se ci sono tratti; Porta sopra/sotto solo per soli tratti). Un solo passo di annulla per tratti e immagini. Taglia/Copia: tratti negli appunti del lazo, immagini nel vassoio (e l'ultima negli appunti delle immagini).
- Limiti: l'incolla del lazo rimette solo i tratti (le immagini si incollano con lo strumento Immagine o dal vassoio); niente ritaglio per gruppi.
- Da verificare su iPad: circondare un'immagine (singola) → cornice e maniglie; due immagini o immagine + scritta → contorno unico e spostamento insieme; ridimensiona/ruota di gruppo (angolo e posizione delle immagini rispetto ai tratti); annulla dopo lo spostamento di gruppo; tocco con il dito su un'immagine dopo una selezione di gruppo.

## Aggiungi PDF al documento (04/10 sera) — compila senza errori; da verificare su iPad
- Voce «Aggiungi PDF al documento» accanto alle altre sorgenti dell'icona Immagine (pannello dello strumento e finestra che compare toccando un punto vuoto della pagina). Accetta PDF, .txt, .rtf, .html (gli ultimi tre impaginati in A4 come per le immagini).
- Un solo foglio: viene aggiunto subito. Più fogli: finestra con le miniature, tutte le pagine scelte di base (si tocca per toglierle), «Aggiungi N».
- Le pagine vanno IN FONDO al documento aperto (copie: il file scelto non cambia); la vista scorre alla prima pagina nuova. Il documento risulta modificato: si salva con Salva o all'uscita/cambio scheda. Se il PDF aggiunto contiene tratti, immagini o testi fatti con questa app, tornano modificabili (stessa lettura dell'apertura, `caricaTratti(da:dalla:)`).
- Codice: `NotesModel.aggiungiPagine(da:indici:)`, `OrigineImmagine.aggiungiPDF`, `DocumentoScelto.aggiungeAlDocumento` (Sorgenti.swift), collegamento in `EditorView`.
- Non fatto: scegliere dove inserire (ora sempre in fondo), annullare l'aggiunta (si usa «Scarta tratti non salvati» dal menu ···, che riapre il file), eliminare/riordinare pagine.
- Da verificare su iPad: file scelto da iCloud, miniature e contatore pagine dopo l'aggiunta, salvataggio e riapertura con le pagine nuove, PDF aggiunto che contiene già tratti dell'app.

## Pannello «Modifica» della barra (04/10 sera) — compila senza errori; da verificare su iPad
- Richieste di Cristina: (1) strumenti nella barra e strumenti da aggiungere devono avere lo stesso spazio; (2) righe e caratteri della stessa dimensione (prima la parte alta si sovrapponeva alla bassa); (3) «Aggiungi PDF — in arrivo» non ha più senso (la funzione c'è, dentro l'icona Immagine).
- Ora: due elenchi con titoli uguali («Nella barra», «Da aggiungere»), ciascuno metà dello spazio, righe alte 46 pt, stesso carattere; tolta la voce «in arrivo»; il contatore dei pallini resta fisso in fondo. Pannello 360×680.


## Parte del documento del Progetto «stato-e-metodo» rimossa il 04/10/2026 perché superata
- Vecchio metodo (mockup → blocco unico Swift → copia/incolla in Swift Playgrounds): sostituito dal metodo con repository + GitHub Actions (vedi STATO.md).
- Alternativa non scelta (Strada B): cartella iCloud scritta dall'app desktop di Claude sul MacBook Air (compatibilità con macOS Ventura da verificare, Mac acceso e app aperta). Utilizzabile in seguito se serve.
- Prototipi 1 e 2 «da riportare in multi-file»: fatto, ora sono nel repository.
- Roadmap dopo l'editor (superata): Libreria rifinita, Quaderno per note bianche, esportazione/condivisione (foglio stile mockup), tema scuro, ricerca testo nel PDF. Ricerca testo e Libreria sono fatte; restano quaderno, esportazione e tema scuro (vedi «Prossimi passi» in STATO.md).



## Consegne del 05 e 06/10/2026 (dettagli; da provare su iPad al 07/10)

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
