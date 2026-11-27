# Formato «a segnalini» — progetto tecnico (proposta del 27/11/2026, Binario A punto 1)

Stato: PROPOSTA mostrata a Cristina, in attesa di approvazione. Nessun codice scritto.
Base: prove del 26–27/11 (`prove/segnalino/`, esiti in STATO.md → PUNTO DI RIPRESA).

## 1. Cosa c'è nella pagina
In fondo al contenuto della pagina (quindi sopra la grafica originale, sotto le annotazioni di Anteprima) un unico blocco:

```
q
BT /AptF 1 Tf 3 Tr 1 0 0 1 2 2 Tm (APT-INIZIO v2 p<pagina> e<elementi> n<operazioni> h<impronta> k<pezzi>) Tj ET
BT ... (APT-D 1/k <base64>) Tj ET        ← dati, spezzati in pezzi da ≤ 30 000 caratteri
...
<disegno: elementi in ordine di livello>
BT ... (APT-FINE h<impronta>) Tj ET
Q
```
- Testo invisibile `3 Tr`, corpo 1, font standard Helvetica WinAnsi (nessun font incorporato). Il base64 non contiene `(`, `)`, `\`.
- `p` = numero di pagina al momento del salvataggio (solo informativo, non si controlla: la pagina può essere spostata da altri programmi).
- `e` = numero di elementi nei dati; `n` = numero di operazioni di disegno nel blocco (`f`, `S`, `Do`, blocchi di testo visibile).
- `h` = primi 16 caratteri esadecimali dello SHA-256 dei dati NON compressi. Ripetuta in FINE per riconoscere blocchi incrociati.
- Nomi delle risorse nostre con prefisso `Apt` (`/AptF`, `/AptIm…`, `/AptGs…`): Anteprima li rinomina, quindi il lettore NON si basa sui nomi.

## 2. Contenuto di `D:` (binario, zlib, base64)
Intestazione: versione formato, larghezza/altezza pagina, unità (centesimi di punto pagina), numero elementi.
Elementi in ordine di livello (= ordine di creazione, come nell'app):
- **Tratto** — strumento (penna, stilografica, evidenziatore, matita, …), colore RGBA, larghezza base, regolazioni stilografica (punta, piattezza),
  `randomSeed`, trasformazione, eventuale maschera della gomma (poligoni), creazione; punti con TUTTI i campi di `PKStrokePoint`
  (posizione, `timeOffset`, `size`, `opacity`, `force`, `azimuth`, `altitude`), quantizzati e scritti come differenze (varint).
  Formato nostro, NON `PKDrawing.dataRepresentation()`: non dipende dal formato interno Apple e servirà anche al motore del Binario B.
  Stima: 6–8 byte per punto prima di zlib.
- **Foto** — id, impronta SHA-256 (16 hex) dei byte JPEG/PNG, ritaglio (px), maschera a mano libera (poligoni), centro, larghezza, angolo, creazione.
  I byte dell'immagine NON stanno in `D:`: sono l'XObject della pagina (le prove: JPEG identico byte per byte dopo Anteprima).
  Il lettore trova l'XObject giusto confrontando l'impronta (non il nome).
- **Testo** — testo (UTF-8), punto, corpo, colore, larghezza (o automatica), creazione.

## 3. Come si disegna (versione universale, uguale in ogni lettore)
- Tratti: CONTORNO vettoriale ricavato dal disegno di PencilKit (metodo di `ProvaLinee.swift`, «contorni»: ~60 KB/pagina, 0,2 s).
  Raggruppati come nell'app: fra due «confini» (foto/testi) prima gli evidenziatori, poi gli inchiostri. Gli evidenziatori dello stesso colore
  nello stesso gruppo diventano UNA forma (unione) con trasparenza `ca` → negli incroci non si scuriscono. Inchiostri con texture: contorno pieno (texture persa, accettato da Cristina).
- Foto: `q <cm con posizione/rotazione> <clip del ritaglio e della maschera: re/percorso W n> /AptImN Do Q`. JPEG come `DCTDecode` senza ricompressione;
  PNG con trasparenza: `FlateDecode` + `SMask`. Stessa foto su più pagine = un solo oggetto.
- Testi: testo VERO visibile in Helvetica (ricercabile in Anteprima/Acrobat). Caratteri fuori da WinAnsi (emoji, alfabeti non latini): quel testo si disegna
  come contorni (visibile ma non ricercabile). Giustificazione: spaziatura `Tw`/posizione per riga calcolata dall'app.

## 4. Scrittura (salvataggio)
- Aggiornamento INCREMENTALE (meccanica di `PDFAggiunta`): per ogni pagina cambiata si aggiungono in coda un nuovo flusso con il blocco,
  le risorse nuove e un nuovo oggetto pagina con `/Contents [<flussi originali…> <flusso blocco>]` e `/Resources` = originali + nostre.
  Il blocco sta in un flusso SEPARATO: alla riapertura si toglie senza toccare i byte originali.
- Foto già presenti nel file (stessa impronta) si riusano, mai duplicate.
- Se servono cambi di struttura (pagine aggiunte/spostate) PDFKit scrive prima il documento pulito, poi si aggiungono i blocchi.
- VERIFICA prima di considerare riuscito: si rilegge il file con il nostro lettore, per ogni pagina si ritrova il blocco, si decodifica `D:`, si confronta
  l'impronta e il numero di elementi; PDFKit deve aprire il file con lo stesso numero di pagine. Se qualcosa non torna: si taglia la coda e il file torna
  esattamente com'era (`PDFAggiunta.tronca/ripristina`).

## 5. Lettura (apertura)
1. Per ogni pagina si leggono i flussi di `/Contents` e si interpretano gli OPERATORI (mai confronto di byte: Anteprima riformatta).
2. Si cerca `APT-INIZIO` … `APT-FINE`. Casi:
   - **Flusso separato nostro intatto** (ultimo salvataggio fatto dall'app): si toglie quel flusso dall'elenco.
   - **Flusso fuso** (Anteprima riscrive tutta la pagina in un flusso): si taglia da `q` prima di INIZIO a `Q` dopo FINE e si scrive un flusso nuovo
     con il resto.
3. Controlli: un solo INIZIO e un solo FINE per pagina, nell'ordine; impronta di `D:` giusta in INIZIO e FINE; elementi = `e`; operazioni di disegno = `n`.
   - Tutto giusto → elementi ricostruiti modificabili.
   - Dati giusti ma disegno diverso (`n` non torna) → elementi ricostruiti, avviso «il disegno era stato modificato fuori dall'app».
   - Dati illeggibili o impronta sbagliata → NON si toglie niente, la pagina resta com'è (si vede tutto, non modificabile) e avviso.
4. La pulizia si fa su una COPIA DI LAVORO (copia APFS istantanea, senza occupare spazio, nella cartella temporanea dell'app) con l'aggiornamento
   aggiunto in coda; PDFKit apre la copia. Il file vero non si tocca finché non si salva. Funziona anche con PDF da centinaia di MB (niente copia in RAM).
5. Le risorse rimaste orfane (foto non più usate) spariscono alla prima compattazione (`PDFCompatta`).

## 6. File vecchi (formato attuale ad annotazioni)
- Si leggono come oggi (`/AptDati`, `/AptInfo`, `/AptInfoTesto`).
- Al primo salvataggio passano al nuovo formato: annotazioni dell'app tolte, blocco scritto, verifica come al punto 4.
  Essendo un aggiornamento incrementale, la versione precedente resta dentro il file (recuperabile tagliando la coda) fino alla prima compattazione.
- All'inizio (Binario A punto 2) il nuovo formato si attiva SOLO sui documenti di prova (interruttore in Impostazioni o nome del file).

## 7. Altre funzioni
- «PDF senza annotazioni» (esportazione): copia del file con i blocchi tolti (punto 5) e, a scelta, senza le annotazioni di Anteprima.
- Ricerca nell'app: il blocco è tolto in memoria, quindi «APT» e i testi nostri non compaiono due volte; i testi dell'app si cercano come oggi.

## 8. Da verificare con un PDF di prova (prima o durante il punto 2)
Pezzi multipli «APT-D i/k» con molti dati (es. 150 KB); blocco in flusso separato dentro `/Contents` a elenco; testo visibile Helvetica; PNG con `SMask`;
clip a poligono; unione evidenziatori con `ca`. Poi Acrobat e reimport in GoodNotes se Cristina li usa.
