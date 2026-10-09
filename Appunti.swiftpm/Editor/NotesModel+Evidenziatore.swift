// Evidenziatore «sotto» il testo del PDF
//
// L'evidenziatore è un tratto semitrasparente. Sovrapposto al testo lo tingeva (il nero diventava marrone/oliva).
// Come un vero evidenziatore, il colore deve stare SOTTO le lettere: la tela della pagina si fonde con il foglio
// in modalità «multiply» (il bianco lascia passare il colore, il nero resta nero).
// Succede solo sulle pagine che hanno evidenziatore (o quando l'evidenziatore è lo strumento attivo): le altre
// pagine restano come prima. Penne e matite sulla stessa pagina si fondono allo stesso modo: sul foglio bianco
// non cambia nulla, su testo nero o immagini scure il loro colore si mescola un po' con quello sotto.
import UIKit
import PDFKit
import PencilKit

extension NotesModel {
    static let fusioneSottoTesto = "multiplyBlendMode"

    /// Stessa regola del lazo: marker vecchio o linea semitrasparente
    static func eEvidenziatore(_ t: PKStroke) -> Bool {
        switch t.ink.inkType {
        case .marker: return true
        case .monoline: return t.ink.color.cgColor.alpha < 0.95
        default: return false
        }
    }

    func aggiornaFusione(_ page: PDFPage) {
        guard let canvas = canvases[page] else { return }
        let serve = corrente?.tipo == .evidenziatore || canvas.drawing.strokes.contains(where: Self.eEvidenziatore)
        let attuale = canvas.layer.compositingFilter as? String
        if serve && attuale != Self.fusioneSottoTesto {
            canvas.layer.compositingFilter = Self.fusioneSottoTesto
        } else if !serve && attuale != nil {
            canvas.layer.compositingFilter = nil
        }
    }
}
