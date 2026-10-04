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
        // Annulla e Ripeti: i pulsanti seguono lo stato reale della cronologia
        let nomi: [Notification.Name] = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup,
                                         .NSUndoManagerCheckpoint, .NSUndoManagerDidOpenUndoGroup]
        for nome in nomi {
            let o = NotificationCenter.default.addObserver(forName: nome, object: nil, queue: .main) { [weak self] n in
                guard let self, let um = n.object as? UndoManager, um === self.pdfView?.undoManager else { return }
                DispatchQueue.main.async { self.aggiornaUndo() }
            }
            osservatoriUndo.append(o)
        }
        aggiornaInterazione()
    }

    func aggiornaUndo() {
        let um = pdfView?.undoManager
        let a = um?.canUndo ?? false
        let r = um?.canRedo ?? false
        if puoAnnullare != a { puoAnnullare = a }
        if puoRipetere != r { puoRipetere = r }
    }

    /// Azzera la cronologia di annulla e ripeti (cambio di documento o di divisione dei livelli)
    func pulisciCronologia() {
        pdfView?.undoManager?.removeAllActions()
        aggiornaUndo()
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

    func annulla() {
        guard let um = pdfView?.undoManager, um.canUndo else { return }
        um.undo()
        aggiornaUndo()
    }

    func ripeti() {
        guard let um = pdfView?.undoManager, um.canRedo else { return }
        um.redo()
        aggiornaUndo()
    }
}
