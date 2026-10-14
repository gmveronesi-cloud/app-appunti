// Evidenziatori: la regola per riconoscerli.
// Dal 14/10 gli evidenziatori NON sono più disegnati dentro la pagina PDF (idea abbandonata): stanno nella tela come gli altri tratti
// e la gerarchia dei livelli è quella classica, vedi `NotesModel.ripartisci`.
import PencilKit

extension NotesModel {
    /// Stessa regola del lazo: marker o linea semitrasparente
    static func eEvidenziatore(_ t: PKStroke) -> Bool {
        switch t.ink.inkType {
        case .marker: return true
        case .monoline: return t.ink.color.cgColor.alpha < 0.95
        default: return false
        }
    }
}
