// Memoria: ogni pagina mostrata ha una tela Pencil grande (4× la pagina) che resta viva finché il PDF è aperto.
// In un PDF lungo, scorrendo, le tele si accumulano fino a quando iPadOS chiude l'app («crash senza motivo»).
// Qui le tele delle pagine lontane da quelle che si vedono vengono buttate: i tratti passano in `trattiSalvati`
// (in punti di pagina, come appena aperto il PDF) e la tela si rifà da sola quando la pagina torna in vista (`willDisplayOverlayView`).
// Immagini e testi non si toccano: stanno in `immagini` e `testi` e si ridisegnano come al solito.
import UIKit
import PDFKit
import PencilKit

extension NotesModel {
    /// Quante tele tenere vive insieme (oltre, si buttano le più lontane). In vista doppia le tele sono più piccole: se ne tengono di più.
    private var massimoTele: Int { risoluzioneMax >= NotesModel.risoluzione ? 14 : 20 }

    /// Chiamata a ogni pagina mostrata: se le tele sono troppe, si scende un po' sotto il massimo (così non succede a ogni pagina)
    func limitaTele() {
        guard canvases.count > massimoTele else { return }
        liberaTeleLontane(massimo: massimoTele - 4)
    }

    /// Butta le tele delle pagine che PDFKit non sta più mostrando, partendo dalle più lontane da quella corrente, finché ne restano `massimo`.
    /// Le pagine in vista non si toccano mai. La cronologia di annulla si azzera (le azioni puntavano a tele ormai sparite).
    func liberaTeleLontane(massimo: Int) {
        guard let doc = document, canvases.count > massimo else { return }
        let centro = paginaCorrente
        var candidate: [(pagina: PDFPage, distanza: Int)] = []
        for page in fuoriVista where canvases[page] != nil {
            let i = doc.index(for: page)
            if i == NSNotFound { continue }
            candidate.append((page, abs(i - centro)))
        }
        // Prima le pagine senza niente da annullare, poi le altre; a parità, le più lontane
        candidate.sort {
            let a = haCronologia($0.pagina), b = haCronologia($1.pagina)
            return a == b ? $0.distanza > $1.distanza : !a
        }
        var buttate = 0
        for c in candidate {
            if canvases.count <= massimo { break }
            if c.distanza <= 1 { continue }       // la pagina accanto a quella che si legge resta
            scartaTela(c.pagina)
            buttate += 1
        }
        if buttate > 0 { aggiornaUndo() }
    }

    private func scartaTela(_ page: PDFPage) {
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = page.bounds(for: .cropBox).width / canvas.bounds.width
            let disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
            trattiSalvati[page] = disegno.strokes.isEmpty ? nil : disegno
        }
        canvases[page] = nil
        contenitori[page] = nil
        azzeraStrati(page)
        scartaUndo(page)           // le sue azioni di annulla puntano alla tela appena buttata
    }
}
