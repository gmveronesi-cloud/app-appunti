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
    /// Se risponde true il tocco non è del lazo (per esempio sposta un'immagine già scelta)
    var cede: ((CGPoint) -> Bool)?
    var tocco: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tocco == nil, let t = touches.first else { return }
        if cede?(t.location(in: view)) == true { state = .failed; return }
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

    enum Fase { case niente, disegno, sposta, ridimensiona, ruota }
    var fase = Fase.niente

    weak var canvas: PKCanvasView?
    var tracciato: [CGPoint] = []          // punti in coordinate della tela
    var partenza: CGPoint = .zero          // dove è iniziato il gesto (tela)
    var selezione: [Int] = []              // indici dei tratti selezionati
    var disegnoPrima: PKDrawing?           // disegno prima dello spostamento
    var riquadroPrima: CGRect = .zero
    var spostato = false
    var immaginiSel: [UUID] = []           // immagini scelte insieme ai tratti (stessa pagina della tela)
    var immaginiPrima: [ElementoImmagine] = []
    var mCorrente = CGAffineTransform.identity

    /// Tratti copiati o tagliati (restano finché l'app è aperta)
    static var appunti: [PKStroke] = []
    var modoRidimensiona = false
    var ancora: CGPoint = .zero            // angolo fermo durante il ridimensionamento
    var angoloPrima: CGPoint = .zero       // angolo trascinato, posizione iniziale
    var puntoIncolla: CGPoint = .zero
    var coloreBase: PKDrawing?
    var coloreCambiato = false
    let maniglie: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }
    let manigliaRuota = CAShapeLayer()     // cerchio sopra la selezione per ruotare
    let lineaRuota = CAShapeLayer()
    var contorno: CGPath?                  // contorno tratteggiato attorno ai tratti scelti
    var centroRotazione: CGPoint = .zero
    var angoloIniziale: CGFloat = 0

    let lineaLayer = CAShapeLayer()        // tratteggio mentre si disegna
    let selezioneLayer = CAShapeLayer()    // riquadro attorno ai tratti scelti

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
        manigliaRuota.fillColor = UIColor(AptTema.carta).cgColor
        manigliaRuota.strokeColor = colore.cgColor
        manigliaRuota.lineWidth = 2
        lineaRuota.strokeColor = colore.cgColor
        lineaRuota.fillColor = nil
        lineaRuota.lineWidth = 1.5
        selezioneLayer.fillRule = .nonZero
        lineaLayer.fillColor = colore.withAlphaComponent(0.06).cgColor
        selezioneLayer.fillColor = colore.withAlphaComponent(0.10).cgColor
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

    // MARK: Gesto

    var vista: PDFView? { model?.pdfView }

    func inizia(_ pv: CGPoint) {
        guard let vista, let model else { fase = .niente; return }
        guard let pagina = vista.page(for: pv, nearest: true), let tela = model.canvases[pagina] else {
            deseleziona()
            fase = .niente
            return
        }
        let p = tela.convert(pv, from: vista)
        let k = tela.fattoreRisoluzione
        aggiornaStile(k)

        // Maniglie di ridimensionamento
        if modoRidimensiona, canvas === tela, haSelezione {
            let r = riquadroSelezione(in: tela)
            let angoli = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                          CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            let rot = CGPoint(x: r.midX, y: r.minY - 40 * k)
            if hypot(rot.x - p.x, rot.y - p.y) < 30 * k {
                fase = .ruota
                centroRotazione = CGPoint(x: r.midX, y: r.midY)
                angoloIniziale = atan2(p.y - centroRotazione.y, p.x - centroRotazione.x)
                disegnoPrima = tela.drawing
                immaginiPrima = immaginiScelte()
                mCorrente = .identity
                riquadroPrima = r
                spostato = false
                return
            }
            if let i = angoli.indices.first(where: { hypot(angoli[$0].x - p.x, angoli[$0].y - p.y) < 30 * k }) {
                fase = .ridimensiona
                angoloPrima = angoli[i]
                ancora = angoli[3 - i]
                disegnoPrima = tela.drawing
                immaginiPrima = immaginiScelte()
                mCorrente = .identity
                riquadroPrima = r
                spostato = false
                return
            }
        }

        // Dentro il riquadro di una selezione: si sposta
        if canvas === tela, haSelezione, selezioneLayer.superlayer != nil,
           riquadroSelezione(in: tela).insetBy(dx: -10 * k, dy: -10 * k).contains(p) {
            fase = .sposta
            partenza = p
            disegnoPrima = tela.drawing
                immaginiPrima = immaginiScelte()
                mCorrente = .identity
            riquadroPrima = riquadroSelezione(in: tela)
            spostato = false
            return
        }

        // Altrove: si ricomincia
        model.controlloImmagini?.annullaSelezione()
        deseleziona()
        canvas = tela
        fase = .disegno
        partenza = p
        tracciato = [p]
        tela.layer.addSublayer(lineaLayer)
        aggiornaLinea()
    }

    func muovi(_ pv: CGPoint) {
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
            if !spostato && hypot(dx, dy) < 4 * tela.fattoreRisoluzione { return }
            spostato = true
            let t = CGAffineTransform(translationX: dx, y: dy)
            let originali = disegnoPrima?.strokes ?? []
            var tutti = originali
            for i in selezione where tutti.indices.contains(i) {
                tutti[i] = Self.spostato(originali[i], t)
            }
            d = PKDrawing(strokes: tutti)
            tela.drawing = d
            mCorrente = t
            anteprimaImmagini(t, tela)
            mostraRiquadro(riquadroPrima.applying(t), trasf: t)
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
            mCorrente = m
            anteprimaImmagini(m, tela)
            mostraRiquadro(riquadroPrima.applying(m), trasf: m)
        case .ruota:
            guard let base = disegnoPrima else { return }
            let a = atan2(p.y - centroRotazione.y, p.x - centroRotazione.x) - angoloIniziale
            spostato = true
            let c = centroRotazione
            let m = CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(rotationAngle: a))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            var tutti = base.strokes
            for i in selezione where tutti.indices.contains(i) {
                tutti[i] = Self.spostato(base.strokes[i], m)
            }
            tela.drawing = PKDrawing(strokes: tutti)
            mCorrente = m
            anteprimaImmagini(m, tela)
            mostraRiquadro(riquadroPrima.applying(m), trasf: m)
        case .niente:
            break
        }
    }

    func finisci(_ pv: CGPoint, annullato: Bool) {
        defer { fase = .niente }
        guard let vista, let tela = canvas else { return }
        let p = tela.convert(pv, from: vista)

        switch fase {
        case .disegno:
            lineaLayer.removeFromSuperlayer()
            if annullato { return }
            let piccolo = hypot(p.x - partenza.x, p.y - partenza.y) < 8 * tela.fattoreRisoluzione
            if piccolo {
                if model?.controlloImmagini?.tocca(pv) == true { return }     // tocco su un'immagine: la seleziona
                if !Self.appunti.isEmpty {
                    puntoIncolla = p
                    menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
                }
                return
            }
            seleziona(in: tela)
        case .ridimensiona, .ruota:
            if annullato {
                if let prima = disegnoPrima { tela.drawing = prima }
                ripristinaImmagini()
                mostraRiquadro(riquadroPrima)
                return
            }
            if spostato, let prima = disegnoPrima {
                confermaModifica(tela, prima)
                mostraRiquadro(riquadroSelezione(in: tela))
            }
        case .sposta:
            if annullato {
                if let prima = disegnoPrima { tela.drawing = prima }
                ripristinaImmagini()
                mostraRiquadro(riquadroPrima)
                return
            }
            if spostato, let prima = disegnoPrima {
                confermaModifica(tela, prima)
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

}
