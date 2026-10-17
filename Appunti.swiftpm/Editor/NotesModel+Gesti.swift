// Editor: gesti con due dita e doppio tocco sulla Pencil
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

/// Tocco con due dita (dito, non Pencil): riconosciuto solo se entrambe le dita si alzano in meno di 0,4 s
/// senza essersi spostate di più di 10 punti e senza un terzo dito. Altrimenti (pizzico, scorrimento, zoom) fallisce.
final class DueDitaTap: UIGestureRecognizer {
    private var inizio: [UITouch: CGPoint] = [:]
    private var istante: TimeInterval = 0
    private var massimo = 0

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if inizio.isEmpty { istante = event.timestamp; massimo = 0 }
        for t in touches { inizio[t] = t.location(in: view) }
        massimo = max(massimo, inizio.count)
        if inizio.count > 2, state == .possible { state = .failed }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches {
            guard let p0 = inizio[t] else { continue }
            let p = t.location(in: view)
            if hypot(p.x - p0.x, p.y - p0.y) > 10 {
                if state == .possible { state = .failed }
                return
            }
        }
        if event.timestamp - istante > 0.4, state == .possible { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { inizio[t] = nil }
        guard inizio.isEmpty, state == .possible else { return }
        let valido: Bool = massimo == 2 && event.timestamp - istante < 0.4
        state = valido ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible { state = .failed }
    }

    override func reset() {
        inizio.removeAll()
        massimo = 0
    }
}

extension NotesModel {
    // MARK: Gesti: tocco con due dita e doppio tocco sulla Pencil

    func installaGesti(su v: PDFView) {
        // Tocco con due dita = annulla, ma solo se è un vero tocco: breve e senza spostamenti
        // (pizzico, scorrimento e zoom con due dita non lo fanno scattare)
        let due = DueDitaTap(target: self, action: #selector(dueDitaTap))
        due.cancelsTouchesInView = false
        due.delegate = self
        v.addGestureRecognizer(due)
        // Pizzicando oltre lo zoom minimo si apre la griglia delle pagine
        (v as? AptPDFView)?.oltreIlMinimo = { [weak self] in
            DispatchQueue.main.async { self?.griglia = true }
        }
        let oss = OsservaTocchi()
        oss.cancelsTouchesInView = false
        oss.quando = { [weak self] in self?.quandoToccato?() }
        v.addGestureRecognizer(oss)
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
        NotificationCenter.default.removeObserver(self, name: .PDFViewScaleChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomCambiato), name: .PDFViewScaleChanged, object: v)
        osservaUndo()
        aggiornaInterazione()
    }

    /// Un solo aggiornamento alla volta, rimandato al prossimo giro: tante notifiche di fila ne producono uno
    func programmaAggiornaUndo() {
        guard !aggiornamentoUndoProgrammato else { return }
        aggiornamentoUndoProgrammato = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.aggiornamentoUndoProgrammato = false
            self.aggiornaUndo()
        }
    }

    func aggiornaUndo() {
        let pagina = paginaUndo.flatMap { undoPagine[$0] }
        let a = undoGenerale.canUndo || (pagina?.canUndo ?? false)
        let r = undoGenerale.canRedo || (pagina?.canRedo ?? false)
        if puoAnnullare != a { puoAnnullare = a }
        if puoRipetere != r { puoRipetere = r }
    }

    /// Azzera tutte le cronologie di annulla e ripeti (cambio di documento, tele rifatte)
    func pulisciCronologia() {
        undoGenerale.removeAllActions()
        for u in undoPagine.values { u.removeAllActions() }
        aggiornaUndo()
    }

    /// Azzera solo la cronologia di una pagina (i suoi tratti sono stati divisi in strati in modo diverso)
    func pulisciCronologia(pagina: PDFPage) {
        undoPagine[pagina]?.removeAllActions()
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

    /// Annulla: prima l'ultima operazione sul documento (pagine aggiunte, tolte, spostate), poi la cronologia della pagina su cui si lavora.
    /// Finita la cronologia di quella pagina, annulla resta spento finché non si passa a un'altra pagina.
    func annulla() {
        if undoGenerale.canUndo {
            undoGenerale.undo()
        } else if let p = paginaUndo, let um = undoPagine[p], um.canUndo {
            paginaLavoro = p
            um.undo()
        } else {
            return
        }
        aggiornaUndo()
    }

    func ripeti() {
        if undoGenerale.canRedo {
            undoGenerale.redo()
        } else if let p = paginaUndo, let um = undoPagine[p], um.canRedo {
            paginaLavoro = p
            um.redo()
        } else {
            return
        }
        aggiornaUndo()
    }
}
