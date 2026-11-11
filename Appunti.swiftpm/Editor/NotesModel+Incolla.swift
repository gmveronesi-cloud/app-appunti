// Appunti interni dell'app (lazo, immagine, testo): un solo «Incolla» per tutti, che rimette TUTTO ciò che è stato copiato insieme
import SwiftUI
import PDFKit
import PencilKit

enum AppuntiInterni {
    static var pieno: Bool { LazoSelezione.haAppunti || !ImmagineControllo.appunti.isEmpty || !TestoControllo.appunti.isEmpty }

    /// Ogni nuova copia sostituisce la precedente: prima si svuota tutto, così non restano avanzi di una copia più vecchia
    static func svuota() {
        LazoSelezione.appunti = []
        LazoSelezione.appuntiImmagini = []
        LazoSelezione.appuntiTesti = []
        ImmagineControllo.appunti = []
        TestoControllo.appunti = []
    }
}

extension NotesModel {
    /// Incolla gli appunti interni attorno a un punto della pagina (coordinate pagina).
    /// Copiati col lazo: tratti, immagini e testi insieme, con le stesse posizioni reciproche. Altrimenti: tutte le immagini e tutti i testi copiati.
    func incollaInterno(pagina p: PDFPage, punto pp: CGPoint) {
        if LazoSelezione.haAppunti, let lazo, let tela = canvases[p] {
            lazo.canvas = tela
            lazo.puntoIncolla = lazo.versoTela(pp, p.bounds(for: .cropBox), tela.fattoreRisoluzione)
            lazo.incolla()
            return
        }
        // Pagina senza tela (o appunti senza tratti): immagini e testi si incollano comunque tutti
        if !ImmagineControllo.appunti.isEmpty { controlloImmagini?.incollaImmagini(ImmagineControllo.appunti, pagina: p, attorno: pp) }
        if !TestoControllo.appunti.isEmpty { controlloTesto?.incollaTesti(TestoControllo.appunti, pagina: p, attorno: pp) }
    }
}
