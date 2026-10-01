// Lazo: la Pencil seleziona i tratti (a mano libera o con un riquadro), poi si spostano,
// si duplicano o si eliminano. Lavora sulla tela Pencil della pagina sotto la penna.
import SwiftUI
import PDFKit
import PencilKit

/// Segue un solo tocco (di solito la Pencil) e lo riferisce alla vista PDF.
final class LazoGesto: UIGestureRecognizer {
    var alInizio: ((CGPoint) -> Void)?
    var alMovimento: ((CGPoint) -> Void)?
    var allaFine: ((CGPoint, Bool) -> Void)?
    private var tocco: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tocco == nil, let t = touches.first else { return }
        tocco = t
        state = .began
        alInizio?(t.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        state = .changed
        alMovimento?(t.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        state = .ended
        allaFine?(t.location(in: view), false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        state = .cancelled
        allaFine?(t.location(in: view), true)
    }

    override func reset() { tocco = nil }
}

final class LazoSelezione: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    weak var model: NotesModel?
    let gesto = LazoGesto()
    private(set) var menu: UIEditMenuInteraction!

    private enum Fase { case niente, disegno, sposta }
    private var fase = Fase.niente

    private weak var canvas: PKCanvasView?
    private var tracciato: [CGPoint] = []          // punti in coordinate della tela
    private var partenza: CGPoint = .zero          // dove è iniziato il gesto (tela)
    private var selezione: [Int] = []              // indici dei tratti selezionati
    private var disegnoPrima: PKDrawing?           // disegno prima dello spostamento
    private var riquadroPrima: CGRect = .zero
    private var spostato = false

    private let lineaLayer = CAShapeLayer()        // tratteggio mentre si disegna
    private let selezioneLayer = CAShapeLayer()    // riquadro attorno ai tratti scelti

    init(model: NotesModel) {
        self.model = model
        super.init()
        gesto.delegate = self
        gesto.isEnabled = false
        gesto.cancelsTouchesInView = true
        gesto.alInizio = { [weak self] p in self?.inizia(p) }
        gesto.alMovimento = { [weak self] p in self?.muovi(p) }
        gesto.allaFine = { [weak self] p, annullato in self?.finisci(p, annullato: annullato) }
        menu = UIEditMenuInteraction(delegate: self)

        let colore = UIColor(AptTema.accento)
        for l in [lineaLayer, selezioneLayer] {
            l.strokeColor = colore.cgColor
            l.lineWidth = 1.5
            l.lineDashPattern = [6, 4]
            l.lineJoin = .round
        }
        lineaLayer.fillColor = colore.withAlphaComponent(0.06).cgColor
        selezioneLayer.fillColor = colore.withAlphaComponent(0.10).cgColor
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

    // MARK: Gesto

    private var vista: PDFView? { model?.pdfView }

    private func inizia(_ pv: CGPoint) {
        guard let vista, let model else { fase = .niente; return }
        guard let pagina = vista.page(for: pv, nearest: true), let tela = model.canvases[pagina] else {
            deseleziona()
            fase = .niente
            return
        }
        let p = tela.convert(pv, from: vista)

        // Dentro il riquadro di una selezione: si sposta
        if canvas === tela, !selezione.isEmpty, selezioneLayer.superlayer != nil,
           riquadroSelezione(in: tela).insetBy(dx: -10, dy: -10).contains(p) {
            fase = .sposta
            partenza = p
            disegnoPrima = tela.drawing
            riquadroPrima = riquadroSelezione(in: tela)
            spostato = false
            return
        }

        // Altrove: si ricomincia
        deseleziona()
        canvas = tela
        fase = .disegno
        partenza = p
        tracciato = [p]
        tela.layer.addSublayer(lineaLayer)
        aggiornaLinea()
    }

    private func muovi(_ pv: CGPoint) {
        guard let vista, let tela = canvas else { return }
        let p = tela.convert(pv, from: vista)
        switch fase {
        case .disegno:
            tracciato.append(p)
            aggiornaLinea()
        case .sposta:
            guard var d = disegnoPrima else { return }
            let dx = p.x - partenza.x
            let dy = p.y - partenza.y
            if !spostato && hypot(dx, dy) < 4 { return }
            spostato = true
            let t = CGAffineTransform(translationX: dx, y: dy)
            let originali = disegnoPrima?.strokes ?? []
            var tutti = originali
            for i in selezione where tutti.indices.contains(i) {
                tutti[i] = Self.spostato(originali[i], t)
            }
            d = PKDrawing(strokes: tutti)
            tela.drawing = d
            mostraRiquadro(riquadroPrima.applying(t))
        case .niente:
            break
        }
    }

    private func finisci(_ pv: CGPoint, annullato: Bool) {
        defer { fase = .niente }
        guard let vista, let tela = canvas else { return }
        let p = tela.convert(pv, from: vista)

        switch fase {
        case .disegno:
            lineaLayer.removeFromSuperlayer()
            if annullato { return }
            let piccolo = hypot(p.x - partenza.x, p.y - partenza.y) < 8
            if piccolo { return }
            seleziona(in: tela)
        case .sposta:
            if annullato {
                if let prima = disegnoPrima { tela.drawing = prima }
                mostraRiquadro(riquadroPrima)
                return
            }
            if spostato, let prima = disegnoPrima {
                registra(tela, da: prima, a: tela.drawing)
                model?.segnaModificato()
                mostraRiquadro(riquadroSelezione(in: tela))
            } else {
                // Tocco dentro la selezione: menu
                mostraMenu()
            }
        case .niente:
            break
        }
    }

    // MARK: Selezione

    private func seleziona(in tela: PKCanvasView) {
        guard let s = model?.corrente, s.tipo == .lazo else { return }
        let riquadro = s.lazoRiquadro
        let forma: (CGPoint) -> Bool
        if riquadro, let a = tracciato.first, let b = tracciato.last {
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            forma = { r.contains($0) }
        } else {
            guard tracciato.count > 2 else { return }
            let path = UIBezierPath()
            path.move(to: tracciato[0])
            for q in tracciato.dropFirst() { path.addLine(to: q) }
            path.close()
            forma = { path.contains($0) }
        }

        var scelti: [Int] = []
        for (i, t) in tela.drawing.strokes.enumerated() {
            guard s.lazoFiltri.contains(tipoTratto(t)) else { continue }
            // Basta un solo punto del tratto dentro il lazo per selezionarlo tutto
            let punti = t.path.interpolatedPoints(by: .distance(2)).map { $0.location.applying(t.transform) }
            if punti.contains(where: forma) { scelti.append(i) }
        }

        guard !scelti.isEmpty else { return }
        selezione = scelti
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    private func tipoTratto(_ t: PKStroke) -> TipoStrumento {
        switch t.ink.inkType {
        case .marker: return .evidenziatore
        case .pencil, .crayon: return .matita
        default: return .penna
        }
    }

    private func riquadroSelezione(in tela: PKCanvasView) -> CGRect {
        let tratti = tela.drawing.strokes
        var r = CGRect.null
        for i in selezione where tratti.indices.contains(i) { r = r.union(tratti[i].renderBounds) }
        return r.isNull ? .zero : r.insetBy(dx: -6, dy: -6)
    }

    /// Copia del tratto con la nuova posizione scritta direttamente nei punti.
    static func spostato(_ t: PKStroke, _ m: CGAffineTransform) -> PKStroke {
        let totale = t.transform.concatenating(m)
        var punti: [PKStrokePoint] = []
        for i in 0..<t.path.count {
            let p = t.path[i]
            punti.append(PKStrokePoint(location: p.location.applying(totale), timeOffset: p.timeOffset, size: p.size,
                                       opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude))
        }
        let path = PKStrokePath(controlPoints: punti, creationDate: t.path.creationDate)
        return PKStroke(ink: t.ink, path: path, transform: .identity, mask: t.mask)
    }

    // MARK: Disegno dei contorni

    private func aggiornaLinea() {
        let path = UIBezierPath()
        if (model?.corrente?.lazoRiquadro ?? false), let a = tracciato.first, let b = tracciato.last {
            path.append(UIBezierPath(rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))))
        } else if let primo = tracciato.first {
            path.move(to: primo)
            for q in tracciato.dropFirst() { path.addLine(to: q) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineaLayer.path = path.cgPath
        CATransaction.commit()
    }

    private func mostraRiquadro(_ r: CGRect) {
        guard let tela = canvas else { return }
        if selezioneLayer.superlayer == nil { tela.layer.addSublayer(selezioneLayer) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selezioneLayer.path = UIBezierPath(roundedRect: r, cornerRadius: 8).cgPath
        CATransaction.commit()
    }

    func deseleziona() {
        lineaLayer.removeFromSuperlayer()
        selezioneLayer.removeFromSuperlayer()
        selezione = []
        tracciato = []
        disegnoPrima = nil
        canvas = nil
        fase = .niente
    }

    // MARK: Menu (elimina, duplica)

    private func mostraMenu() {
        guard let vista, let tela = canvas, !selezione.isEmpty else { return }
        let r = riquadroSelezione(in: tela)
        let punto = vista.convert(CGPoint(x: r.midX, y: r.minY), from: tela)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: punto))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let duplica = UIAction(title: "Duplica", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplica() }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        return UIMenu(children: [duplica, elimina])
    }

    private func elimina() {
        guard let tela = canvas, !selezione.isEmpty else { return }
        let prima = tela.drawing
        var d = prima
        let fuori = Set(selezione)
        d.strokes = prima.strokes.enumerated().filter { !fuori.contains($0.offset) }.map { $0.element }
        tela.drawing = d
        registra(tela, da: prima, a: d)
        model?.segnaModificato()
        deseleziona()
    }

    private func duplica() {
        guard let tela = canvas, !selezione.isEmpty else { return }
        let prima = tela.drawing
        var d = prima
        let sposta = CGAffineTransform(translationX: 24, y: 24)
        let nuovi = selezione.compactMap { prima.strokes.indices.contains($0) ? prima.strokes[$0] : nil }.map { Self.spostato($0, sposta) }
        let primoNuovo = d.strokes.count
        d.strokes.append(contentsOf: nuovi)
        tela.drawing = d
        registra(tela, da: prima, a: d)
        model?.segnaModificato()
        selezione = Array(primoNuovo..<d.strokes.count)
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    // MARK: Annulla e ripeti

    private func registra(_ tela: PKCanvasView, da prima: PKDrawing, a dopo: PKDrawing) {
        let um = vista?.undoManager ?? tela.undoManager
        um?.registerUndo(withTarget: self) { [weak tela] s in
            guard let tela else { return }
            tela.drawing = prima
            s.deseleziona()
            s.registra(tela, da: dopo, a: prima)
            s.model?.segnaModificato()
        }
    }
}
