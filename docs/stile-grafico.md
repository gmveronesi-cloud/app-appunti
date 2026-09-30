# Stile grafico — App Appunti (riferimento vincolante)

Approvato da Cristina il 01/10/2026 come base. Esempi visivi: `docs/stile-grafico.html` (aprire in un browser; ha tema chiaro e scuro).
Codice: `Appunti.swiftpm/Tema/Tema.swift` (`AptTema`, stili pulsante, `aptScheda`).

## Requisiti di Cristina
Look moderno · tema sempre su rosso o colori caldi · colori pastello, mai accesi o fluorescenti · aspetto minimal ma curato.

## Regole per Claude
1. In ogni vista nuova o ritoccata si usano solo i valori di `AptTema` (colori, raggi, spazi, caratteri). Mai colori di sistema (`.blue`, `Color.accentColor`, `.red`), mai numeri a mano.
2. Un solo accento: rosso pastello (`AptTema.accento`). Attivo/selezionato = `accentoTenue` con testo `accentoScuro`.
3. Neutrali sempre caldi: niente nero puro, bianco puro, grigi freddi. Il foglio del PDF resta bianco.
4. Niente gradienti, ombre dure, bordi spessi. Bordo sottile 1 pt colore `linea`. Ombra morbida solo su barra strumenti, elementi flottanti e finestre.
5. Raggi: 10 (elementi piccoli), 14 (barre, schede), 20 (finestre), pillola per pulsanti e barra strumenti.
6. Pulsanti: `AptStilePrimario` (azione principale, una per schermata), `AptStileSecondario`, `AptStileContorno` (Annulla; `pericolo: true` per Elimina).
7. Icone: simboli di sistema, peso leggero, colore `testo2`; lo strumento attivo ha sfondo `accentoTenue`.
8. Caratteri: San Francisco di sistema, scala 28 / 20 / 17 / 15 / 13.
9. Chiaro e scuro: ogni colore passa da `AptTema`, che ha già entrambe le versioni.
10. Colori dei tratti: `AptTema.inchiostri` (8 pallini) e `AptTema.evidenziatori` (3). Niente colori accesi nei valori predefiniti.
11. Ogni schermata nuova: confrontarla con l'esempio corrispondente in `stile-grafico.html`; se manca l'esempio, aggiungerlo lì prima.

## Piano di applicazione
- Ora: `Tema.swift` (fatto) + applicazione a barra strumenti e Libreria.
- Dopo: ogni strumento nuovo nasce già con lo stile.
- Alla fine: lucidatura (animazioni, dettagli, anteprime).
