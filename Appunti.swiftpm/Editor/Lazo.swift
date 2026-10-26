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
    /// Se risponde true, durante il movimento si usa anche la posizione prevista dal sistema (meno ritardo nel trascinamento)
    var usaPredizione: (() -> Bool)?
    var tocco: UITouch?
    private var predettoInviato = false

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
        if usaPredizione?() == true, let previsto = event.predictedTouches(for: t)?.last {
            predettoInviato = true
            alMovimento?(previsto.location(in: view))
        } else {
            predettoInviato = false
            // Tutti i campioni intermedi della Pencil (240 Hz): il lazo disegnato in fretta resta fedele
            let campioni = event.coalescedTouches(for: t) ?? [t]
            for c in campioni { alMovimento?(c.location(in: view)) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tocco, touches.contains(t) else { return }
        state = .ended
        if predettoInviato { alMovimento?(t.location(in: view)) }     // la posizione finale è quella vera
        predettoInviato = false
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
    var menu: UIEditMenuInteraction!

    enum Fase { case niente, disegno, sposta, ridimensiona, ruota }
    var fase = Fase.niente

    weak var canvas: PKCanvasView?
    var tracciato: [CGPoint] = []          // punti in coordinate della tela
    var partenza: CGPoint = .zero          // dove è iniziato il gesto (tela)
    var selezione: [Int] = [] {            // indici dei tratti selezionati
        didSet {
            // La barra mostra i pallini dello strumento a cui appartiene il tratto scelto (evidenziatore → pallini evidenziatori)
            var tipo: TipoStrumento?
            if let primo = selezione.first, let t = canvas?.drawing.strokes, t.indices.contains(primo) { tipo = tipoTratto(t[primo]) }
            if model?.tipoSelezioneLazo != tipo { model?.tipoSelezioneLazo = tipo }
        }
    }
    var disegnoPrima: PKDrawing?           // disegno prima dello spostamento
    var riquadroPrima: CGRect = .zero
    var spostato = false
    var immaginiSel: [UUID] = []           // immagini scelte insieme ai tratti (stessa pagina della tela)
    var immaginiPrima: [ElementoImmagine] = []
    var testiSel: [UUID] = []              // testi scelti insieme ai tratti (stessa pagina della tela)
    var testiPrima: [ElementoTesto] = []
    var mCorrente = CGAffineTransform.identity
    var stratoTratti: CALayer?             // durante il trascinamento: i tratti scelti come immagine, mossa dalla GPU
    var origineStrato: CGPoint = .zero

    /// Tratti copiati o tagliati (restano finché l'app è aperta)
    static var appunti: [PKStroke] = []
    static var appuntiImmagini: [ElementoImmagine] = []
    static var appuntiTesti: [ElementoTesto] = []
    static var haAppunti: Bool { !appunti.isEmpty || !appuntiImmagini.isEmpty || !appuntiTesti.isEmpty }
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
        gesto.usaPredizione = { [weak self] in
            guard let f = self?.fase else { return false }
            return f == .sposta || f == .ridimensiona || f == .ruota
        }
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
                immaginiPrima = immaginiScelte(); testiPrima = testiScelti()
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
                immaginiPrima = immaginiScelte(); testiPrima = testiScelti()
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
                immaginiPrima = immaginiScelte(); testiPrima = testiScelti()
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
            let dx = p.x - partenza.x
            let dy = p.y - partenza.y
            if !spostato && hypot(dx, dy) < 4 * tela.fattoreRisoluzione { return }
            if !spostato { spostato = true; preparaTrascinamento(tela) }
            let t = CGAffineTransform(translationX: dx, y: dy)
            mCorrente = t
            muoviTrascinamento(t)
            anteprimaImmagini(t, tela)
            muoviContorno(t)
        case .ridimensiona:
            guard disegnoPrima != nil else { return }
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
            if stratoTratti == nil { preparaTrascinamento(tela) }
            mCorrente = m
            muoviTrascinamento(m)
            anteprimaImmagini(m, tela)
            mostraRiquadro(riquadroPrima.applying(m), trasf: m)
        case .ruota:
            guard disegnoPrima != nil else { return }
            let a = atan2(p.y - centroRotazione.y, p.x - centroRotazione.x) - angoloIniziale
            spostato = true
            let c = centroRotazione
            let m = CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(rotationAngle: a))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            if stratoTratti == nil { preparaTrascinamento(tela) }
            mCorrente = m
            muoviTrascinamento(m)
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
            // Tocco = il tracciato intero è minuscolo. Non si guarda la distanza tra primo e ultimo punto:
            // un cerchio ben chiuso finisce proprio dove è iniziato e verrebbe scambiato per un tocco.
            var minX = CGFloat.greatestFiniteMagnitude, minY = minX, maxX = -minX, maxY = -minX
            for q in tracciato { minX = min(minX, q.x); minY = min(minY, q.y); maxX = max(maxX, q.x); maxY = max(maxY, q.y) }
            let piccolo = tracciato.count < 2 || hypot(maxX - minX, maxY - minY) < 8 * tela.fattoreRisoluzione
            if piccolo {
                if model?.controlloImmagini?.tocca(pv) == true { return }     // tocco su un'immagine: la seleziona
                if let pagina = model?.pagina(di: tela), model?.corrente?.lazoTesti == true,
                   let t = model?.controlloTesto?.testoSotto(versoPagina(p, pagina.bounds(for: .cropBox), tela.fattoreRisoluzione), in: pagina) {
                    // tocco su un testo: lo sceglie
                    testiSel = [t.id]
                    mostraRiquadro(riquadroSelezione(in: tela))
                    return
                }
                if Self.haAppunti {
                    puntoIncolla = p
                    menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
                }
                return
            }
            seleziona(in: tela)
        case .ridimensiona, .ruota:
            if annullato {
                annullaTrascinamento(tela)
                ripristinaImmagini()
                mostraRiquadro(riquadroPrima)
                return
            }
            if spostato, let prima = disegnoPrima {
                concludiTrascinamento(tela)
                confermaModifica(tela, prima)
                mostraRiquadro(riquadroSelezione(in: tela))
            }
        case .sposta:
            if annullato {
                annullaTrascinamento(tela)
                ripristinaImmagini()
                mostraRiquadro(riquadroPrima)
                return
            }
            if spostato, let prima = disegnoPrima {
                concludiTrascinamento(tela)
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
