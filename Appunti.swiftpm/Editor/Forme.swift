// Rette e forme: tenendo ferma la Pencil alla fine di un tratto, il tratto diventa
// una retta, un rettangolo/quadrato o un'ellisse/cerchio (come in Note di Apple).
import SwiftUI
import PDFKit
import PencilKit

enum FormaRiconosciuta {
    case linea(CGPoint, CGPoint)
    case ellisse(CGRect)
    case rettangolo(CGRect)

    /// Contorno da mostrare in anteprima
    var percorso: UIBezierPath {
        switch self {
        case .linea(let a, let b):
            let p = UIBezierPath()
            p.move(to: a)
            p.addLine(to: b)
            return p
        case .ellisse(let r):
            return UIBezierPath(ovalIn: r)
        case .rettangolo(let r):
            return UIBezierPath(rect: r)
        }
    }

    /// Punti lungo il contorno, a passo regolare (per ricostruire il tratto)
    func punti(passo: CGFloat = 3) -> [CGPoint] {
        switch self {
        case .linea(let a, let b):
            return Self.segmento(a, b, passo: passo)
        case .rettangolo(let r):
            let c = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                     CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            var out: [CGPoint] = []
            for i in 0..<4 {
                let da = c[i]
                let a = c[(i + 1) % 4]
                // angolo ripetuto: tiene lo spigolo netto
                out += [da, da]
                out += Self.segmento(da, a, passo: passo).dropFirst().dropLast()
            }
            out += [c[0], c[0]]
            return out
        case .ellisse(let r):
            let rx = r.width / 2
            let ry = r.height / 2
            let h = pow((rx - ry) / (rx + ry), 2)
            let perimetro = CGFloat.pi * (rx + ry) * (1 + 3 * h / (10 + sqrt(4 - 3 * h)))
            let n = max(48, Int(perimetro / passo))
            return (0...n).map { i in
                let t = CGFloat(i) / CGFloat(n) * 2 * .pi
                return CGPoint(x: r.midX + rx * cos(t), y: r.midY + ry * sin(t))
            }
        }
    }

    private static func segmento(_ a: CGPoint, _ b: CGPoint, passo: CGFloat) -> [CGPoint] {
        let lunghezza = hypot(b.x - a.x, b.y - a.y)
        let n = max(2, Int(lunghezza / passo))
        return (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// Retta da a a b: se è quasi orizzontale o verticale si raddrizza.
    static func retta(da a: CGPoint, a b: CGPoint) -> FormaRiconosciuta {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lunghezza = hypot(dx, dy)
        guard lunghezza > 0 else { return .linea(a, b) }
        let soglia: CGFloat = 0.06            // circa 3,5 gradi
        if abs(dy) / lunghezza < soglia { return .linea(a, CGPoint(x: b.x, y: a.y)) }
        if abs(dx) / lunghezza < soglia { return .linea(a, CGPoint(x: a.x, y: b.y)) }
        return .linea(a, b)
    }
}

enum RiconoscitoreForme {
    /// Guarda il tratto fatto finora e dice se somiglia a una retta, a un rettangolo o a un'ellisse.
    static func riconosci(_ p: [CGPoint]) -> FormaRiconosciuta? {
        guard p.count >= 8, let a = p.first, let b = p.last else { return nil }
        var lunghezza: CGFloat = 0
        for i in 1..<p.count { lunghezza += hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y) }
        guard lunghezza > 30 else { return nil }
        let corda = hypot(b.x - a.x, b.y - a.y)

        // Retta: tutti i punti vicini alla linea tra primo e ultimo
        if corda > 25 {
            var scarto: CGFloat = 0
            for q in p {
                let croce = abs((b.x - a.x) * (a.y - q.y) - (a.x - q.x) * (b.y - a.y))
                scarto = max(scarto, croce / corda)
            }
            if scarto <= 0.07 * corda { return FormaRiconosciuta.retta(da: a, a: b) }
        }

        // Forma chiusa: inizio e fine vicini
        guard corda < 0.3 * lunghezza else { return nil }
        let xs = p.map { $0.x }
        let ys = p.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX
        let h = maxY - minY
        let lato = max(w, h)
        guard w > 20, h > 20, min(w, h) > 0.2 * lato else { return nil }

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let rx = w / 2
        let ry = h / 2

        var erroreEllisse: CGFloat = 0
        var erroreRett: CGFloat = 0
        for q in p {
            let r = sqrt(pow((q.x - cx) / rx, 2) + pow((q.y - cy) / ry, 2))
            erroreEllisse += abs(r - 1)
            let d = min(abs(q.x - minX), abs(q.x - maxX), abs(q.y - minY), abs(q.y - maxY))
            erroreRett += d
        }
        erroreEllisse /= CGFloat(p.count)
        erroreRett = erroreRett / CGFloat(p.count) / lato

        let puntiEllisse = erroreEllisse / 0.12
        let puntiRett = erroreRett / 0.05
        guard min(puntiEllisse, puntiRett) < 1 else { return nil }

        let quasiQuadrato = abs(w - h) < 0.12 * lato
        if puntiRett <= puntiEllisse {
            if quasiQuadrato {
                let s = (w + h) / 2
                return .rettangolo(CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
            }
            return .rettangolo(CGRect(x: minX, y: minY, width: w, height: h))
        } else {
            if quasiQuadrato {
                let s = (w + h) / 2
                return .ellisse(CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
            }
            return .ellisse(CGRect(x: minX, y: minY, width: w, height: h))
        }
    }
}

/// Segue la Pencil senza mai "prendere" il tocco: la tela continua a disegnare normalmente.
final class FormeGesto: UIGestureRecognizer {
    var alInizio: ((CGPoint) -> Void)?
    var alMovimento: ((CGPoint) -> Void)?
    var allaFine: ((Bool) -> Void)?
    private var tocco: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tocco == nil, let t = touches.first(where: { $0.type == .pencil }) else { return }
        tocco = t
        alInizio?(t.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        alMovimento?(t.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        tocco = nil
        allaFine?(false)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        tocco = nil
        allaFine?(true)
        state = .failed
    }

    override func reset() { tocco = nil }
}

final class FormePencil: NSObject, UIGestureRecognizerDelegate {
    weak var model: NotesModel?
    let gesto = FormeGesto(target: nil, action: nil)

    private weak var tela: PKCanvasView?
    private var punti: [CGPoint] = []          // tratto in coordinate della tela
    private var ultimoFermo: CGPoint = .zero   // da dove si misura se la Pencil è ferma
    private var timer: Timer?
    private var forma: FormaRiconosciuta?
    private var fermo = false
    private var tratti = 0                     // tratti sulla tela prima di questo
    private let anteprima = CAShapeLayer()

    private let attesa: TimeInterval = 0.6
    private let tolleranza: CGFloat = 4

    init(model: NotesModel) {
        self.model = model
        super.init()
        gesto.delegate = self
        gesto.isEnabled = false
        gesto.alInizio = { [weak self] p in self?.inizia(p) }
        gesto.alMovimento = { [weak self] p in self?.muovi(p) }
        gesto.allaFine = { [weak self] annullato in self?.finisci(annullato: annullato) }
        anteprima.fillColor = nil
        anteprima.lineCap = .round
        anteprima.lineJoin = .round
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    private var vista: PDFView? { model?.pdfView }

    private func inizia(_ pv: CGPoint) {
        timer?.invalidate()
        pulisci()
        guard let vista, let model, let pagina = vista.page(for: pv, nearest: false),
              let t = model.canvases[pagina] else { return }
        tela = t
        let p = t.convert(pv, from: vista)
        punti = [p]
        ultimoFermo = p
        tratti = t.drawing.strokes.count
        riavvia()
    }

    private func muovi(_ pv: CGPoint) {
        guard let vista, let t = tela else { return }
        let p = t.convert(pv, from: vista)
        punti.append(p)
        if fermo {
            // dopo il riconoscimento la retta segue la Pencil; le altre forme restano ferme
            if case .linea(let a, _) = forma {
                let f = FormaRiconosciuta.retta(da: a, a: p)
                forma = f
                mostra(f)
            }
            return
        }
        if hypot(p.x - ultimoFermo.x, p.y - ultimoFermo.y) > tolleranza {
            ultimoFermo = p
            riavvia()
        }
    }

    private func riavvia() {
        timer?.invalidate()
        let t = Timer(timeInterval: attesa, repeats: false) { [weak self] _ in self?.fermoRilevato() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fermoRilevato() {
        guard !fermo, tela != nil, let f = RiconoscitoreForme.riconosci(punti) else { return }
        fermo = true
        forma = f
        mostra(f)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Anteprima: la forma riconosciuta, nel colore dello strumento
    private func mostra(_ f: FormaRiconosciuta) {
        guard let t = tela else { return }
        let s = model?.corrente
        let base = s?.colore.ui ?? .black
        let evid = s?.tipo == .evidenziatore
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        anteprima.strokeColor = base.withAlphaComponent(evid ? 0.4 : 1).cgColor
        anteprima.lineWidth = max(1.5, CGFloat(s?.spessore ?? 2))
        anteprima.path = f.percorso.cgPath
        if anteprima.superlayer !== t.layer { t.layer.addSublayer(anteprima) }
        CATransaction.commit()
    }

    private func pulisci() {
        anteprima.removeFromSuperlayer()
        forma = nil
        fermo = false
        punti = []
    }

    private func finisci(annullato: Bool) {
        timer?.invalidate()
        guard !annullato, fermo, let f = forma, let t = tela else {
            pulisci()
            return
        }
        let prima = tratti
        fermo = false
        forma = nil
        punti = []
        // PencilKit aggiunge il tratto appena la Pencil si stacca: si aspetta un attimo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak t] in
            guard let self, let t else { return }
            self.sostituisci(con: f, su: t, tratti: prima)
            self.anteprima.removeFromSuperlayer()
        }
    }

    /// Al posto dell'ultimo tratto a mano libera mette la forma, con lo stesso inchiostro.
    private func sostituisci(con f: FormaRiconosciuta, su t: PKCanvasView, tratti prima: Int) {
        let disegnoPrima = t.drawing
        guard disegnoPrima.strokes.count > prima, let ultimo = disegnoPrima.strokes.last else { return }
        let originali = Array(ultimo.path)
        guard let primo = originali.first else { return }

        var larg: CGFloat = 0
        var alt: CGFloat = 0
        var forza: CGFloat = 0
        for q in originali {
            larg += q.size.width
            alt += q.size.height
            forza += q.force
        }
        let n = CGFloat(originali.count)
        let misura = CGSize(width: larg / n, height: alt / n)

        let controllo: [PKStrokePoint] = f.punti().enumerated().map { i, loc in
            PKStrokePoint(location: loc, timeOffset: TimeInterval(i) * 0.002, size: misura,
                          opacity: 1, force: forza / n, azimuth: primo.azimuth, altitude: primo.altitude)
        }
        let percorso = PKStrokePath(controlPoints: controllo, creationDate: Date())
        let nuovo = PKStroke(ink: ultimo.ink, path: percorso, transform: .identity, mask: ultimo.mask)

        var d = disegnoPrima
        d.strokes[d.strokes.count - 1] = nuovo
        t.drawing = d
        registra(t, da: disegnoPrima, a: d)
        model?.segnaModificato()
    }

    // MARK: Annulla e ripeti (riporta il tratto a mano libera, come l'aveva fatto lei)

    private func registra(_ t: PKCanvasView, da prima: PKDrawing, a dopo: PKDrawing) {
        let um = vista?.undoManager ?? t.undoManager
        um?.registerUndo(withTarget: self) { [weak t] s in
            guard let t else { return }
            t.drawing = prima
            s.registra(t, da: dopo, a: prima)
            s.model?.segnaModificato()
        }
    }
}
