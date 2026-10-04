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
    private var tocco: UITouch?

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

    private enum Fase { case niente, disegno, sposta, ridimensiona, ruota }
    private var fase = Fase.niente

    private weak var canvas: PKCanvasView?
    private var tracciato: [CGPoint] = []          // punti in coordinate della tela
    private var partenza: CGPoint = .zero          // dove è iniziato il gesto (tela)
    private var selezione: [Int] = []              // indici dei tratti selezionati
    private var disegnoPrima: PKDrawing?           // disegno prima dello spostamento
    private var riquadroPrima: CGRect = .zero
    private var spostato = false
    private var immaginiSel: [UUID] = []           // immagini scelte insieme ai tratti (stessa pagina della tela)
    private var immaginiPrima: [ElementoImmagine] = []
    private var mCorrente = CGAffineTransform.identity

    /// Tratti copiati o tagliati (restano finché l'app è aperta)
    private static var appunti: [PKStroke] = []
    private var modoRidimensiona = false
    private var ancora: CGPoint = .zero            // angolo fermo durante il ridimensionamento
    private var angoloPrima: CGPoint = .zero       // angolo trascinato, posizione iniziale
    private var puntoIncolla: CGPoint = .zero
    private var coloreBase: PKDrawing?
    private var coloreCambiato = false
    private let maniglie: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }
    private let manigliaRuota = CAShapeLayer()     // cerchio sopra la selezione per ruotare
    private let lineaRuota = CAShapeLayer()
    private var contorno: CGPath?                  // contorno tratteggiato attorno ai tratti scelti
    private var centroRotazione: CGPoint = .zero
    private var angoloIniziale: CGFloat = 0

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

    private var vista: PDFView? { model?.pdfView }

    private func inizia(_ pv: CGPoint) {
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

    private func finisci(_ pv: CGPoint, annullato: Bool) {
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

    // MARK: Immagini scelte insieme ai tratti

    private var paginaTela: PDFPage? {
        guard let t = canvas else { return nil }
        return model?.pagina(di: t)
    }

    private var haSelezione: Bool { !selezione.isEmpty || !immaginiSel.isEmpty }

    /// Immagini scelte, lette dal modello (sempre aggiornate)
    private func immaginiScelte() -> [ElementoImmagine] {
        guard let p = paginaTela else { return [] }
        let lista = model?.immagini[p] ?? []
        return immaginiSel.compactMap { id in lista.first { $0.id == id } }
    }

    private func versoTela(_ p: CGPoint, _ box: CGRect, _ k: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - box.minX) * k, y: (box.maxY - p.y) * k)
    }

    private func versoPagina(_ p: CGPoint, _ box: CGRect, _ k: CGFloat) -> CGPoint {
        CGPoint(x: p.x / k + box.minX, y: box.maxY - p.y / k)
    }

    /// L'immagine trasformata come i tratti (`m` è nelle coordinate della tela: y verso il basso, rotazione oraria)
    private func trasformata(_ e: ElementoImmagine, _ m: CGAffineTransform, pagina: PDFPage, k: CGFloat) -> ElementoImmagine {
        let box = pagina.bounds(for: .cropBox)
        var n = e
        n.centro = versoPagina(versoTela(e.centro, box, k).applying(m), box, k)
        n.larghezza = e.larghezza * sqrt(abs(m.a * m.d - m.b * m.c))
        n.angolo = e.angolo - atan2(m.b, m.a)
        return n
    }

    private func anteprimaImmagini(_ m: CGAffineTransform, _ tela: PKCanvasView) {
        guard let pagina = paginaTela, let c = model?.controlloImmagini else { return }
        let k = tela.fattoreRisoluzione
        for e in immaginiPrima { c.anteprimaGruppo(trasformata(e, m, pagina: pagina, k: k), pagina: pagina) }
    }

    /// Gesto annullato: le immagini tornano dov'erano
    private func ripristinaImmagini() {
        guard !immaginiPrima.isEmpty, let pagina = paginaTela else { return }
        model?.controlloImmagini?.ridisegna(pagina)
    }

    /// Fine di uno spostamento, ridimensionamento o rotazione: tratti e immagini in un solo passo di annulla
    private func confermaModifica(_ tela: PKCanvasView, _ prima: PKDrawing) {
        if !selezione.isEmpty {
            registra(tela, da: prima, a: tela.drawing)
        } else if !immaginiPrima.isEmpty {
            registraSoloImmagini()
        }
        if let pagina = paginaTela, let c = model?.controlloImmagini {
            let k = tela.fattoreRisoluzione
            for e in immaginiPrima { c.cambia(pagina, togli: e, metti: trasformata(e, mCorrente, pagina: pagina, k: k)) }
        }
        immaginiPrima = immaginiScelte()
        model?.segnaModificato()
    }

    /// Annulla e ripeti quando sono state toccate solo immagini (i tratti non c'entrano)
    private func registraSoloImmagini() {
        vista?.undoManager?.registerUndo(withTarget: self) { s in
            s.deseleziona()
            s.registraSoloImmagini()
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

        // Immagini: basta che il lazo ne circondi circa un quinto (25 punti di prova sull'immagine)
        var imm: [UUID] = []
        if s.lazoImmagini, let pagina = model?.pagina(di: tela), let lista = model?.immagini[pagina], !lista.isEmpty {
            let box = pagina.bounds(for: .cropBox)
            let k = tela.fattoreRisoluzione
            for e in lista {
                var dentro = 0
                for ix in 0...4 {
                    for iy in 0...4 {
                        let l = CGPoint(x: (CGFloat(ix) / 4 - 0.5) * e.larghezza, y: (CGFloat(iy) / 4 - 0.5) * e.altezza)
                        if forma(versoTela(e.mondo(l), box, k)) { dentro += 1 }
                    }
                }
                if dentro >= 5 { imm.append(e.id) }
            }
            // Lazo tutto dentro un'immagine (e niente altro preso): sceglie l'immagine più in alto
            if imm.isEmpty && scelti.isEmpty, let primo = tracciato.first, let ultimo = tracciato.last {
                let punti = riquadro ? [primo, ultimo] : tracciato
                let dentroImmagine = lista.sorted { $0.creazione > $1.creazione }.first { e in
                    punti.allSatisfy { e.contiene(versoPagina($0, box, k)) }
                }
                if let e = dentroImmagine { imm = [e.id] }
            }
        }

        guard !scelti.isEmpty || !imm.isEmpty else { return }

        // Una sola immagine e nient'altro: selezione completa dell'immagine (maniglie, rotazione, ritaglio)
        if scelti.isEmpty, imm.count == 1, let pagina = model?.pagina(di: tela) {
            deseleziona()
            model?.controlloImmagini?.seleziona(pagina, id: imm[0])
            return
        }

        model?.controlloImmagini?.annullaSelezione()
        selezione = scelti
        immaginiSel = imm
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    private func tipoTratto(_ t: PKStroke) -> TipoStrumento {
        switch t.ink.inkType {
        case .marker: return .evidenziatore
        case .monoline where t.ink.color.cgColor.alpha < 0.95: return .evidenziatore
        case .pencil, .crayon: return .matita
        default: return .penna
        }
    }

    private func riquadroSelezione(in tela: PKCanvasView) -> CGRect {
        let tratti = tela.drawing.strokes
        var r = CGRect.null
        for i in selezione where tratti.indices.contains(i) { r = r.union(tratti[i].renderBounds) }
        let k = tela.fattoreRisoluzione
        if !r.isNull { r = r.insetBy(dx: -6 * k, dy: -6 * k) }
        if let pagina = paginaTela {
            let box = pagina.bounds(for: .cropBox)
            for e in immaginiScelte() {
                for q in e.angoli.map({ versoTela($0, box, k) }) { r = r.union(CGRect(origin: q, size: .zero)) }
            }
        }
        return r.isNull ? .zero : r
    }

    /// Copia del tratto con la nuova posizione scritta direttamente nei punti.
    static func spostato(_ t: PKStroke, _ m: CGAffineTransform, scala: CGFloat = 1, data: Date? = nil) -> PKStroke {
        let totale = t.transform.concatenating(m)
        var punti: [PKStrokePoint] = []
        for i in 0..<t.path.count {
            let p = t.path[i]
            punti.append(PKStrokePoint(location: p.location.applying(totale), timeOffset: p.timeOffset, size: CGSize(width: p.size.width * scala, height: p.size.height * scala),
                                       opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude))
        }
        let path = PKStrokePath(controlPoints: punti, creationDate: data ?? t.path.creationDate)
        return PKStroke(ink: t.ink, path: path, transform: .identity, mask: t.mask)
    }

    // MARK: Disegno dei contorni

    /// Spessori e tratteggio dei segni di selezione: stanno nella tela (k volte la pagina), quindi si moltiplicano per k.
    private func aggiornaStile(_ k: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [lineaLayer, selezioneLayer] {
            l.lineWidth = 1.5 * k
            l.lineDashPattern = [NSNumber(value: Double(6 * k)), NSNumber(value: Double(4 * k))]
        }
        for m in maniglie { m.lineWidth = 2 * k }
        manigliaRuota.lineWidth = 2 * k
        lineaRuota.lineWidth = 1.5 * k
        CATransaction.commit()
    }

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

    /// Mostra il contorno tratteggiato attorno ai tratti scelti (non un riquadro).
    /// Senza `trasf` il contorno è ricalcolato dai tratti; durante spostamento, ridimensionamento
    /// e rotazione si usa quello già calcolato, trasformato come i tratti.
    private func mostraRiquadro(_ r: CGRect, trasf: CGAffineTransform? = nil) {
        guard let tela = canvas else { return }
        let k = tela.fattoreRisoluzione
        aggiornaStile(k)
        if selezioneLayer.superlayer == nil { tela.layer.addSublayer(selezioneLayer) }
        if trasf == nil { contorno = calcolaContorno(in: tela) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if var m = trasf, let c = contorno {
            selezioneLayer.path = c.copy(using: &m)
        } else {
            selezioneLayer.path = contorno
        }
        let angoli = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                      CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        for (i, m) in maniglie.enumerated() {
            if modoRidimensiona {
                if m.superlayer == nil { tela.layer.addSublayer(m) }
                m.path = UIBezierPath(ovalIn: CGRect(x: angoli[i].x - 9 * k, y: angoli[i].y - 9 * k, width: 18 * k, height: 18 * k)).cgPath
            } else {
                m.removeFromSuperlayer()
            }
        }
        if modoRidimensiona {
            let rot = CGPoint(x: r.midX, y: r.minY - 40 * k)
            let l = UIBezierPath()
            l.move(to: CGPoint(x: r.midX, y: r.minY))
            l.addLine(to: rot)
            lineaRuota.path = l.cgPath
            manigliaRuota.path = UIBezierPath(ovalIn: CGRect(x: rot.x - 10 * k, y: rot.y - 10 * k, width: 20 * k, height: 20 * k)).cgPath
            if lineaRuota.superlayer == nil { tela.layer.addSublayer(lineaRuota) }
            if manigliaRuota.superlayer == nil { tela.layer.addSublayer(manigliaRuota) }
        } else {
            lineaRuota.removeFromSuperlayer()
            manigliaRuota.removeFromSuperlayer()
        }
        CATransaction.commit()
    }

    private func calcolaContorno(in tela: PKCanvasView) -> CGPath {
        let tratti = tela.drawing.strokes
        let unire = selezione.count <= 40
        var risultato: CGPath?
        let tutti = CGMutablePath()
        for i in selezione where tratti.indices.contains(i) {
            let t = tratti[i]
            let k = tela.fattoreRisoluzione
            let pt = Array(t.path.interpolatedPoints(by: .distance(5 * k)))
            guard let primo = pt.first else { continue }
            let linea = CGMutablePath()
            linea.move(to: primo.location.applying(t.transform))
            for q in pt.dropFirst() { linea.addLine(to: q.location.applying(t.transform)) }
            if pt.count == 1 { linea.addLine(to: primo.location.applying(t.transform)) }
            let largo = pt.map { $0.size.width }.reduce(0, +) / CGFloat(pt.count)
            let bordo = linea.copy(strokingWithWidth: max(largo, 1) + 10 * k, lineCap: .round, lineJoin: .round, miterLimit: 10)
            if unire {
                let n = bordo.normalized(using: .winding)
                risultato = risultato.map { $0.union(n, using: .winding) } ?? n
            } else {
                tutti.addPath(bordo)
            }
        }
        // Le immagini scelte: il loro quadrilatero
        if let pagina = paginaTela {
            let box = pagina.bounds(for: .cropBox)
            let k = tela.fattoreRisoluzione
            for e in immaginiScelte() {
                let q = CGMutablePath()
                q.addLines(between: e.angoli.map { versoTela($0, box, k) })
                q.closeSubpath()
                if unire { risultato = risultato.map { $0.union(q, using: .winding) } ?? q } else { tutti.addPath(q) }
            }
        }
        if unire { return risultato ?? CGMutablePath() }
        return tutti
    }

    func deseleziona() {
        lineaLayer.removeFromSuperlayer()
        selezioneLayer.removeFromSuperlayer()
        for m in maniglie { m.removeFromSuperlayer() }
        lineaRuota.removeFromSuperlayer()
        manigliaRuota.removeFromSuperlayer()
        contorno = nil
        modoRidimensiona = false
        selezione = []
        immaginiSel = []
        immaginiPrima = []
        tracciato = []
        disegnoPrima = nil
        canvas = nil
        fase = .niente
    }

    // MARK: Menu (taglia, elimina, ridimensiona, copia, colore; incolla su un punto vuoto)

    private func mostraMenu() {
        guard let vista, let tela = canvas, haSelezione else { return }
        let r = riquadroSelezione(in: tela)
        let punto = vista.convert(CGPoint(x: r.midX, y: r.minY), from: tela)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: punto))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if !haSelezione {
            guard !Self.appunti.isEmpty else { return nil }
            return UIMenu(children: [UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incolla() }])
        }
        let taglia = UIAction(title: "Taglia", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.taglia() }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        let ridim = UIAction(title: "Ridimensiona e ruota", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak self] _ in self?.ridimensiona() }
        let copia = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copia() }
        let colore = UIAction(title: "Colore", image: UIImage(systemName: "paintpalette")) { [weak self] _ in self?.cambiaColore() }
        var voci: [UIMenuElement] = [elimina, taglia, ridim, copia]
        if !selezione.isEmpty { voci.append(colore) }
        if !selezione.isEmpty, immaginiSel.isEmpty, let tela = canvas, let p = model?.pagina(di: tela), !(model?.immagini[p]?.isEmpty ?? true) {
            voci.append(UIAction(title: "Porta sopra", image: UIImage(systemName: "square.2.layers.3d.top.filled")) { [weak self] _ in self?.livello(su: true) })
            voci.append(UIAction(title: "Porta sotto", image: UIImage(systemName: "square.2.layers.3d.bottom.filled")) { [weak self] _ in self?.livello(su: false) })
        }
        return UIMenu(options: .displayInline, children: voci)
    }

    /// Un livello sopra o sotto l'immagine più vicina: si cambia la data di creazione dei tratti scelti.
    private func livello(su: Bool) {
        guard let tela = canvas, let model, let pagina = model.pagina(di: tela), !selezione.isEmpty else { return }
        let immagini = (model.immagini[pagina] ?? []).map { $0.creazione }.sorted()
        let prima = tela.drawing
        let date = selezione.compactMap { prima.strokes.indices.contains($0) ? prima.strokes[$0].path.creationDate : nil }
        guard let minimo = date.min(), let massimo = date.max() else { return }
        let base: Date
        if su {
            guard let t = immagini.first(where: { $0 > massimo }) else { return }
            base = t.addingTimeInterval(0.001)
        } else {
            guard let t = immagini.last(where: { $0 < minimo }) else { return }
            base = t.addingTimeInterval(-0.001 - Double(selezione.count) * 0.00001)
        }
        var tutti = prima.strokes
        for (n, i) in selezione.sorted().enumerated() where tutti.indices.contains(i) {
            tutti[i] = Self.spostato(prima.strokes[i], .identity, data: base.addingTimeInterval(Double(n) * 0.00001))
        }
        let dopo = PKDrawing(strokes: tutti)
        tela.drawing = dopo
        registra(tela, da: prima, a: dopo)
        model.segnaModificato()
        model.message = "Livello cambiato: lo vedi tornando alla penna."
    }

    private func trattiSelezionati() -> [PKStroke] {
        guard let tela = canvas else { return [] }
        let t = tela.drawing.strokes
        return selezione.compactMap { t.indices.contains($0) ? t[$0] : nil }
    }

    private func copia() {
        Self.appunti = trattiSelezionati()
        model?.controlloImmagini?.copiaInAppunti(immaginiScelte())
    }

    private func taglia() {
        copia()
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
        let adesso = Date()
        d.strokes.append(contentsOf: Self.appunti.enumerated().map { Self.spostato($1, m, data: adesso.addingTimeInterval(Double($0) * 0.00001)) })
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
        guard let tela = canvas, haSelezione else { return }
        let imm = immaginiScelte()
        let pagina = paginaTela
        if !selezione.isEmpty {
            let prima = tela.drawing
            var d = prima
            let fuori = Set(selezione)
            d.strokes = prima.strokes.enumerated().filter { !fuori.contains($0.offset) }.map { $0.element }
            tela.drawing = d
            registra(tela, da: prima, a: d)
        } else {
            registraSoloImmagini()
        }
        if let pagina, let c = model?.controlloImmagini {
            for e in imm { c.cambia(pagina, togli: e, metti: nil) }
        }
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
