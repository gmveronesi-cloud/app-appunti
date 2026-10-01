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

final class LazoSelezione: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate, UIColorPickerViewControllerDelegate {
    weak var model: NotesModel?
    let gesto = LazoGesto()
    private(set) var menu: UIEditMenuInteraction!

    private enum Fase { case niente, disegno, sposta, ridimensiona }
    private var fase = Fase.niente

    private weak var canvas: PKCanvasView?
    private var tracciato: [CGPoint] = []          // punti in coordinate della tela
    private var partenza: CGPoint = .zero          // dove è iniziato il gesto (tela)
    private var selezione: [Int] = []              // indici dei tratti selezionati
    private var disegnoPrima: PKDrawing?           // disegno prima dello spostamento
    private var riquadroPrima: CGRect = .zero
    private var spostato = false

    /// Tratti copiati o tagliati (restano finché l'app è aperta)
    private static var appunti: [PKStroke] = []
    private var modoRidimensiona = false
    private var ancora: CGPoint = .zero            // angolo fermo durante il ridimensionamento
    private var angoloPrima: CGPoint = .zero       // angolo trascinato, posizione iniziale
    private var puntoIncolla: CGPoint = .zero
    private var coloreBase: PKDrawing?
    private var coloreCambiato = false
    private let maniglie: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }

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
        for m in maniglie {
            m.fillColor = UIColor(AptTema.carta).cgColor
            m.strokeColor = colore.cgColor
            m.lineWidth = 2
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

        // Maniglie di ridimensionamento
        if modoRidimensiona, canvas === tela, !selezione.isEmpty {
            let r = riquadroSelezione(in: tela)
            let angoli = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                          CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            if let i = angoli.indices.first(where: { hypot(angoli[$0].x - p.x, angoli[$0].y - p.y) < 30 }) {
                fase = .ridimensiona
                angoloPrima = angoli[i]
                ancora = angoli[3 - i]
                disegnoPrima = tela.drawing
                riquadroPrima = r
                spostato = false
                return
            }
        }

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
        case .ridimensiona:
            guard let base = disegnoPrima else { return }
            let d0 = hypot(angoloPrima.x - ancora.x, angoloPrima.y - ancora.y)
            guard d0 > 1 else { return }
            let vx = (angoloPrima.x - ancora.x) / d0
            let vy = (angoloPrima.y - ancora.y) / d0
            let proiezione = ((p.x - ancora.x) * vx + (p.y - ancora.y) * vy) / d0
            let k = max(0.1, min(10, proiezione))
            spostato = true
            let m = CGAffineTransform(translationX: -ancora.x, y: -ancora.y)
                .concatenating(CGAffineTransform(scaleX: k, y: k))
                .concatenating(CGAffineTransform(translationX: ancora.x, y: ancora.y))
            var tutti = base.strokes
            for i in selezione where tutti.indices.contains(i) {
                tutti[i] = Self.spostato(base.strokes[i], m, scala: k)
            }
            tela.drawing = PKDrawing(strokes: tutti)
            mostraRiquadro(riquadroPrima.applying(m))
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
            if piccolo {
                if !Self.appunti.isEmpty {
                    puntoIncolla = p
                    menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
                }
                return
            }
            seleziona(in: tela)
        case .ridimensiona:
            if annullato {
                if let prima = disegnoPrima { tela.drawing = prima }
                mostraRiquadro(riquadroPrima)
                return
            }
            if spostato, let prima = disegnoPrima {
                registra(tela, da: prima, a: tela.drawing)
                model?.segnaModificato()
                mostraRiquadro(riquadroSelezione(in: tela))
            }
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
                modoRidimensiona = false
                mostraRiquadro(riquadroSelezione(in: tela))
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
    static func spostato(_ t: PKStroke, _ m: CGAffineTransform, scala: CGFloat = 1) -> PKStroke {
        let totale = t.transform.concatenating(m)
        var punti: [PKStrokePoint] = []
        for i in 0..<t.path.count {
            let p = t.path[i]
            punti.append(PKStrokePoint(location: p.location.applying(totale), timeOffset: p.timeOffset, size: CGSize(width: p.size.width * scala, height: p.size.height * scala),
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
        let angoli = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                      CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        for (i, m) in maniglie.enumerated() {
            if modoRidimensiona {
                if m.superlayer == nil { tela.layer.addSublayer(m) }
                m.path = UIBezierPath(ovalIn: CGRect(x: angoli[i].x - 9, y: angoli[i].y - 9, width: 18, height: 18)).cgPath
            } else {
                m.removeFromSuperlayer()
            }
        }
        CATransaction.commit()
    }

    func deseleziona() {
        lineaLayer.removeFromSuperlayer()
        selezioneLayer.removeFromSuperlayer()
        for m in maniglie { m.removeFromSuperlayer() }
        modoRidimensiona = false
        selezione = []
        tracciato = []
        disegnoPrima = nil
        canvas = nil
        fase = .niente
    }

    // MARK: Menu (taglia, elimina, ridimensiona, copia, colore; incolla su un punto vuoto)

    private func mostraMenu() {
        guard let vista, let tela = canvas, !selezione.isEmpty else { return }
        let r = riquadroSelezione(in: tela)
        let punto = vista.convert(CGPoint(x: r.midX, y: r.minY), from: tela)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: punto))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if selezione.isEmpty {
            guard !Self.appunti.isEmpty else { return nil }
            return UIMenu(children: [UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incolla() }])
        }
        let taglia = UIAction(title: "Taglia", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.taglia() }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        let ridim = UIAction(title: "Ridimensiona", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak self] _ in self?.ridimensiona() }
        let copia = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copia() }
        let colore = UIAction(title: "Colore", image: UIImage(systemName: "paintpalette")) { [weak self] _ in self?.cambiaColore() }
        return UIMenu(options: .displayInline, children: [taglia, elimina, ridim, copia, colore])
    }

    private func trattiSelezionati() -> [PKStroke] {
        guard let tela = canvas else { return [] }
        let t = tela.drawing.strokes
        return selezione.compactMap { t.indices.contains($0) ? t[$0] : nil }
    }

    private func copia() {
        Self.appunti = trattiSelezionati()
    }

    private func taglia() {
        Self.appunti = trattiSelezionati()
        elimina()
    }

    private func ridimensiona() {
        guard let tela = canvas else { return }
        modoRidimensiona = true
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    private func incolla() {
        guard let tela = canvas, !Self.appunti.isEmpty else { return }
        var r = CGRect.null
        for t in Self.appunti { r = r.union(t.renderBounds) }
        let m = CGAffineTransform(translationX: puntoIncolla.x - r.midX, y: puntoIncolla.y - r.midY)
        let prima = tela.drawing
        var d = prima
        let primoNuovo = d.strokes.count
        d.strokes.append(contentsOf: Self.appunti.map { Self.spostato($0, m) })
        tela.drawing = d
        registra(tela, da: prima, a: d)
        model?.segnaModificato()
        selezione = Array(primoNuovo..<d.strokes.count)
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    // Colore: selettore di sistema, applicato in diretta ai tratti scelti
    private func cambiaColore() {
        guard let tela = canvas, let primo = trattiSelezionati().first else { return }
        coloreBase = tela.drawing
        coloreCambiato = false
        let picker = UIColorPickerViewController()
        picker.selectedColor = primo.ink.color
        picker.supportsAlpha = false
        picker.delegate = self
        var alto = vista?.window?.rootViewController
        while let p = alto?.presentedViewController { alto = p }
        alto?.present(picker, animated: true)
    }

    func colorPickerViewController(_ vc: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        guard let tela = canvas, let base = coloreBase else { return }
        var tutti = base.strokes
        for i in selezione where tutti.indices.contains(i) {
            let t = tutti[i]
            let alpha = t.ink.color.cgColor.alpha
            tutti[i] = PKStroke(ink: PKInk(t.ink.inkType, color: color.withAlphaComponent(alpha)), path: t.path, transform: t.transform, mask: t.mask)
        }
        tela.drawing = PKDrawing(strokes: tutti)
        coloreCambiato = true
        model?.segnaModificato()
    }

    func colorPickerViewControllerDidFinish(_ vc: UIColorPickerViewController) {
        guard let tela = canvas, let base = coloreBase, coloreCambiato else { return }
        registra(tela, da: base, a: tela.drawing)
        mostraRiquadro(riquadroSelezione(in: tela))
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
