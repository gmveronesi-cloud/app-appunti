// Editor: gesti con due dita e doppio tocco sulla Pencil
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

extension NotesModel {
    // MARK: Gesti: tocco con due dita e doppio tocco sulla Pencil

    func installaGesti(su v: PDFView) {
        let due = UITapGestureRecognizer(target: self, action: #selector(dueDitaTap))
        due.numberOfTouchesRequired = 2
        due.cancelsTouchesInView = false
        due.delegate = self
        v.addGestureRecognizer(due)
        let pi = UIPencilInteraction()
        pi.delegate = self
        v.addInteraction(pi)
        let l = LazoSelezione(model: self)
        lazo = l
        v.addGestureRecognizer(l.gesto)
        v.addInteraction(l.menu)
        let f = FormePencil(model: self)
        forme = f
        v.addGestureRecognizer(f.gesto)
        let cs = CatturaSchermo(model: self)
        cattura = cs
        v.addGestureRecognizer(cs.gesto)
        let tc = TestoControllo(model: self)
        controlloTesto = tc
        v.addGestureRecognizer(tc.tocco)
        v.addInteraction(tc.menu)
        v.addGestureRecognizer(tc.trascina)
        let ic = ImmagineControllo(model: self)
        controlloImmagini = ic
        v.addGestureRecognizer(ic.tocco)
        v.addGestureRecognizer(ic.trascina)
        // La Pencil con il lazo sposta l'immagine scelta invece di fare il lazo
        l.gesto.cede = { [weak ic] pv in ic?.afferra(pv) ?? false }
        v.addInteraction(ic.menu)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomCambiato), name: .PDFViewScaleChanged, object: v)
        aggiornaInterazione()
    }

    @objc func dueDitaTap() {
        if dueDitaAnnulla { annulla() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { doppioToccoPencil() }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { doppioToccoPencil() }

    func doppioToccoPencil() {
        switch doppioTocco {
        case .niente:
            break
        case .precedente:
            seleziona(precedente)
        case .gomma:
            if corrente?.tipo == .gomma { seleziona(precedente) }
            else if let g = strumenti.first(where: { $0.tipo == .gomma }) { seleziona(g.id) }
        }
    }

    func annulla() { pdfView?.undoManager?.undo() }
    func ripeti() { pdfView?.undoManager?.redo() }
}
