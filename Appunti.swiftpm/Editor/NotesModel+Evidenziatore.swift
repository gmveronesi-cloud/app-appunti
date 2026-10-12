// Evidenziatore «sotto» il testo del PDF e sotto gli altri tratti
//
// Un evidenziatore semitrasparente messo sopra il testo lo tinge. Come un vero evidenziatore, il colore deve stare
// SOTTO le lettere: lo strato dell'evidenziatore si fonde con il foglio in modalità «multiply» (il bianco lascia passare
// il colore, il nero resta nero). Gli altri tratti (penne, matite) stanno in una tela o in uno strato SOPRA, normali.
// Divisione in strati: vedi `ripartisci`. Le immagini e i testi restano sotto l'evidenziatore.
import UIKit
import PDFKit
import PencilKit

extension NotesModel {
    static let fusioneSottoTesto = "multiplyBlendMode"

    /// Stessa regola del lazo: marker o linea semitrasparente
    static func eEvidenziatore(_ t: PKStroke) -> Bool {
        switch t.ink.inkType {
        case .marker: return true
        case .monoline: return t.ink.color.cgColor.alpha < 0.95
        default: return false
        }
    }

    /// La tela si fonde col foglio solo quando contiene soltanto evidenziatori (strumento evidenziatore attivo)
    func aggiornaFusione(_ page: PDFPage) {
        guard let canvas = canvases[page] else { return }
        let serve = corrente?.tipo == .evidenziatore && !unificato
        let attuale = canvas.layer.compositingFilter as? String
        if serve && attuale != Self.fusioneSottoTesto {
            canvas.layer.compositingFilter = Self.fusioneSottoTesto
        } else if !serve && attuale != nil {
            canvas.layer.compositingFilter = nil
        }
    }
}
