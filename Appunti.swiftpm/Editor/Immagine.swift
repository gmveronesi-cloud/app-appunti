// Strumento Immagine: si tocca la pagina, si sceglie una foto (o un file immagine) e si mette sulla pagina.
//
// Selezione come per i tratti del lazo: 4 maniglie agli angoli (ingrandisce in diretta), cerchio sopra (ruota),
// trascinando l'immagine si sposta, con anteprima in tempo reale. Tocco su un'immagine già scelta: menu con
// Taglia, Copia, Ritaglia, Elimina, Porta sopra, Porta sotto. Tocco su un punto vuoto: nuova immagine (o Incolla).
//
// Livelli: ogni immagine ha la data di creazione, come ogni tratto. Un tratto disegnato prima dell'immagine sta
// SOTTO, uno disegnato dopo sta SOPRA (vedi `NotesModel.ripartisci`). Nel PDF le annotazioni sono scritte in
// quell'ordine, quindi anche gli altri lettori mostrano lo stesso ordine.
//
// Nel PDF l'immagine è un'annotazione Stamp con l'immagine vera (visibile in ogni lettore; verificato con
// `prove/ProvaImmagine`), più i dati originali e la posizione in chiavi nascoste, per riaprirla modificabile.
import SwiftUI
import PDFKit
import PencilKit

/// Un'immagine messa su una pagina
struct ElementoImmagine: Identifiable, Equatable {
    var id = UUID()
    var dati: Data                  // JPEG o PNG già ridimensionato: è l'immagine intera, senza ritaglio
    var base: UIImage               // l'immagine intera
    private(set) var ritaglio: CGRect   // parte visibile, in pixel di `base`
    private(set) var ritagliata: UIImage
    var centro: CGPoint             // coordinate della pagina (PDF, origine in basso a sinistra)
    var larghezza: CGFloat          // della parte visibile, in punti della pagina
    var angolo: CGFloat = 0         // radianti, antiorario (come nel PDF)
    var creazione: Date

    static func == (a: ElementoImmagine, b: ElementoImmagine) -> Bool { a.id == b.id }

    init(dati: Data, base: UIImage, ritaglio: CGRect? = nil, centro: CGPoint, larghezza: CGFloat, angolo: CGFloat = 0, creazione: Date) {
        self.dati = dati
        self.base = base
        let intera = CGRect(origin: .zero, size: base.size)
        let r = (ritaglio ?? intera).intersection(intera)
        self.ritaglio = r.isNull || r.width < 1 || r.height < 1 ? intera : r
        self.ritagliata = base
        self.centro = centro
        self.larghezza = larghezza
        self.angolo = angolo
        self.creazione = creazione
        impostaRitaglio(self.ritaglio)
    }

    mutating func impostaRitaglio(_ r: CGRect) {
        ritaglio = r
        let intera = CGRect(origin: .zero, size: base.size)
        if r == intera {
            ritagliata = base
        } else if let c = base.cgImage?.cropping(to: r.integral.intersection(intera)) {
            ritagliata = UIImage(cgImage: c)
        }
    }

    /// Punti di pagina per ogni pixel dell'immagine
    var scala: CGFloat { larghezza / max(ritaglio.width, 1) }
    var altezza: CGFloat { ritaglio.height * scala }

    // Coordinate: «locale» ha l'origine nel centro dell'immagine e gli assi ruotati con lei (y verso l'alto)
    func locale(_ p: CGPoint) -> CGPoint {
        let dx = p.x - centro.x, dy = p.y - centro.y
        let c = cos(angolo), s = sin(angolo)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    func mondo(_ l: CGPoint) -> CGPoint {
        let c = cos(angolo), s = sin(angolo)
        return CGPoint(x: centro.x + l.x * c - l.y * s, y: centro.y + l.x * s + l.y * c)
    }

    func contiene(_ p: CGPoint, margine: CGFloat = 0) -> Bool {
        let l = locale(p)
        return abs(l.x) <= larghezza / 2 + margine && abs(l.y) <= altezza / 2 + margine
    }

    var angoli: [CGPoint] {
        [mondo(CGPoint(x: -larghezza / 2, y: altezza / 2)), mondo(CGPoint(x: larghezza / 2, y: altezza / 2)),
         mondo(CGPoint(x: larghezza / 2, y: -altezza / 2)), mondo(CGPoint(x: -larghezza / 2, y: -altezza / 2))]
    }

    /// Rettangolo con i lati paralleli alla pagina che contiene l'immagine ruotata
    var riquadro: CGRect {
        let a = angoli
        let xs = a.map { $0.x }, ys = a.map { $0.y }
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    /// Orienta correttamente, riduce (lato massimo 1400 px) e codifica. nil se i dati non sono un'immagine.
    static func prepara(_ dati: Data, massimo: CGFloat = 1400) -> (UIImage, Data)? {
        guard let src = UIImage(data: dati) else { return nil }
        let pw = src.size.width * src.scale, ph = src.size.height * src.scale
        guard pw > 0, ph > 0 else { return nil }
        let s = min(1, massimo / max(pw, ph))
        let nuova = CGSize(width: max(1, (pw * s).rounded()), height: max(1, (ph * s).rounded()))
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = false
        let ridotta = UIGraphicsImageRenderer(size: nuova, format: formato).image { _ in
            src.draw(in: CGRect(origin: .zero, size: nuova))
        }
        let a = src.cgImage?.alphaInfo
        let haAlfa = !(a == nil || a == CGImageAlphaInfo.none || a == .noneSkipFirst || a == .noneSkipLast)
        guard let d = haAlfa ? ridotta.pngData() : ridotta.jpegData(compressionQuality: 0.85),
              let finale = UIImage(data: d) else { return nil }
        return (finale, d)
    }
}

/// Annotazione Stamp che disegna l'immagine (ruotata): PDFKit la salva nel file con il suo aspetto.
final class AnnotazioneImmagine: PDFAnnotation {
    var immagine: UIImage?
    var centro: CGPoint = .zero
    var larghezza: CGFloat = 0
    var altezza: CGFloat = 0
    var angolo: CGFloat = 0

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = immagine?.cgImage else { return }
        context.saveGState()
        context.translateBy(x: centro.x, y: centro.y)
        context.rotate(by: angolo)
        context.draw(cg, in: CGRect(x: -larghezza / 2, y: -altezza / 2, width: larghezza, height: altezza))
        context.restoreGState()
    }
}

/// Segue un solo tocco, ma parte solo se il tocco cade dove serve (`colpisce`): altrove il dito scorre il PDF.
final class ImmagineGesto: UIGestureRecognizer {
    var colpisce: ((CGPoint, UITouch.TouchType) -> Bool)?
    var alInizio: ((CGPoint) -> Void)?
    var alMovimento: ((CGPoint) -> Void)?
    var allaFine: ((CGPoint, Bool) -> Void)?
    private var tocco: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tocco == nil, let t = touches.first else { return }
        let p = t.location(in: view)
        guard colpisce?(p, t.type) == true else { state = .failed; return }
        tocco = t
        state = .began
        alInizio?(p)
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

final class ImmagineControllo: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    weak var model: NotesModel?
    let tocco = UITapGestureRecognizer()
    let trascina = ImmagineGesto()
    private(set) var menu: UIEditMenuInteraction!

    static let nome = "AptImmagine"
    static let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")
    static let chiaveInfo = PDFAnnotationKey(rawValue: "/AptInfo")
    private static let nomeLivello = "AptImmagineLivello"
    private static let nomeStrato = "AptStrato"
    private static let nomeSelezione = "AptSelezioneImmagine"

    /// Immagine copiata o tagliata (resta finché l'app è aperta)
    private static var appunti: ElementoImmagine?

    private var scelta: (pagina: PDFPage, id: UUID)?
    private var ritagliando = false
    private var livelli: [UUID: CALayer] = [:]

    private enum Maniglia: Equatable {
        case angolo(Int, Int)       // ingrandisce (o ritaglia due lati)
        case bordo(Int, Int)        // ritaglia un lato
        case ruota
    }
    private enum Fase { case niente, sposta, scala, ruota, ritaglia(Int, Int) }
    private var fase = Fase.niente
    private var inizio: CGPoint = .zero         // punto di pagina dove è iniziato il gesto
    private var prima: ElementoImmagine?
    private var inCorso: ElementoImmagine?
    private var mosso = false
    private var eraScelta = false
    private var angoloIniziale: CGFloat = 0

    private enum ModoMenu { case immagine, vuoto }
    private var modoMenu = ModoMenu.immagine
    private var puntoVuoto: (PDFPage, CGPoint)?

    init(model: NotesModel) {
        self.model = model
        super.init()
        tocco.addTarget(self, action: #selector(toccato(_:)))
        tocco.delegate = self
        tocco.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                   NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        trascina.delegate = self
        trascina.cancelsTouchesInView = true
        trascina.allowedTouchTypes = tocco.allowedTouchTypes
        trascina.colpisce = { [weak self] p, t in self?.colpisce(p, t) ?? false }
        trascina.alInizio = { [weak self] p in self?.inizia(p) }
        trascina.alMovimento = { [weak self] p in self?.muovi(p) }
        trascina.allaFine = { [weak self] p, annullato in self?.finisci(p, annullato: annullato) }
        menu = UIEditMenuInteraction(delegate: self)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g === tocco
    }

    /// Il tocco semplice (selezione) lo ricevono solo i tipi di tocco ammessi per lo strumento in uso
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard g === tocco else { return true }
        return puoAgire(touch.type)
    }

    /// Selezione e spostamento delle immagini: con il dito con qualsiasi strumento (tranne quando il dito disegna),
    /// con la Pencil solo con lazo e immagine (con le penne la Pencil scrive).
    private func puoAgire(_ tipo: UITouch.TouchType) -> Bool {
        guard let model else { return false }
        let t = model.corrente?.tipo
        if tipo == .pencil { return t == .lazo || t == .immagine }
        if model.ditoDisegna, t == .penna || t == .evidenziatore || t == .matita || t == .gomma { return false }
        return true
    }

    /// Per il lazo: il tocco cade su una maniglia o sull'immagine già scelta (la Pencil la sposta invece di fare il lazo)
    func afferra(_ pv: CGPoint) -> Bool {
        guard puoAgire(.pencil), let (pg, pp) = pagina(in: pv), let s = scelta, s.pagina === pg,
              let e = elemento(pg, s.id) else { return false }
        return maniglia(e, vicino: pp) != nil || e.contiene(pp, margine: 4 * unita)
    }

    /// Per il lazo: un tocco breve su un'immagine la seleziona. true se c'era un'immagine.
    func tocca(_ pv: CGPoint) -> Bool {
        guard puoAgire(.pencil), let (pg, pp) = pagina(in: pv), let e = sotto(pp, in: pg) else { return false }
        scelta = (pg, e.id)
        ritagliando = false
        mostraSelezione()
        return true
    }

    func haImmagine(in pagina: PDFPage, at p: CGPoint) -> Bool { sotto(p, in: pagina) != nil }

    /// Si chiama quando si chiude il documento
    func resetta() {
        scelta = nil
        ritagliando = false
        fase = .niente
        mostraSelezione()
    }

    // MARK: Utilità

    private var vista: PDFView? { model?.pdfView }
    private var unita: CGFloat { 1 / max(vista?.scaleFactor ?? 1, 0.1) }     // punti di pagina per punto di schermo

    private func elemento(_ p: PDFPage, _ id: UUID) -> ElementoImmagine? {
        model?.immagini[p]?.first { $0.id == id }
    }

    private var elementoScelto: ElementoImmagine? {
        guard let s = scelta else { return nil }
        return elemento(s.pagina, s.id)
    }

    /// L'immagine più in alto sotto il punto
    private func sotto(_ pp: CGPoint, in pagina: PDFPage) -> ElementoImmagine? {
        (model?.immagini[pagina] ?? []).sorted { $0.creazione > $1.creazione }.first { $0.contiene(pp, margine: 4 * unita) }
    }

    private func maniglie(_ e: ElementoImmagine) -> [(Maniglia, CGPoint)] {
        let w = e.larghezza / 2, h = e.altezza / 2
        var l: [(Maniglia, CGPoint)] = []
        for (dx, dy) in [(-1, 1), (1, 1), (1, -1), (-1, -1)] {
            let p = e.mondo(CGPoint(x: CGFloat(dx) * w, y: CGFloat(dy) * h))
            l.append((ritagliando ? .bordo(dx, dy) : .angolo(dx, dy), p))
        }
        if ritagliando {
            for (dx, dy) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                l.append((.bordo(dx, dy), e.mondo(CGPoint(x: CGFloat(dx) * w, y: CGFloat(dy) * h))))
            }
        } else {
            l.append((.ruota, e.mondo(CGPoint(x: 0, y: h + 38 * unita))))
        }
        return l
    }

    private func maniglia(_ e: ElementoImmagine, vicino a: CGPoint) -> Maniglia? {
        let raggio = 24 * unita
        return maniglie(e).first { hypot($0.1.x - a.x, $0.1.y - a.y) < raggio }?.0
    }

    private func pagina(in pv: CGPoint) -> (PDFPage, CGPoint)? {
        guard let vista, let p = vista.page(for: pv, nearest: true) else { return nil }
        return (p, vista.convert(pv, to: p))
    }

    // MARK: Disegno (strati sotto la tela dei tratti)

    /// Ricostruisce lo strato di sotto della pagina: tratti più vecchi e immagini, in ordine di creazione.
    func ridisegna(_ pagina: PDFPage) {
        guard let model, let tela = model.canvases[pagina], let contenitore = tela.superview as? PaginaTela else { return }
        contenitore.layer.sublayers?
            .filter { $0.name == Self.nomeLivello || $0.name == Self.nomeStrato }
            .forEach { $0.removeFromSuperlayer() }
        let box = pagina.bounds(for: .cropBox)
        let k = tela.fattoreRisoluzione
        var restanti = model.sotto[pagina] ?? []

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func aggiungi(_ l: CALayer) { contenitore.layer.insertSublayer(l, below: tela.layer) }

        for e in (model.immagini[pagina] ?? []).sorted(by: { $0.creazione < $1.creazione }) {
            let piu_vecchi = restanti.filter { $0.path.creationDate < e.creazione }
            restanti = restanti.filter { $0.path.creationDate >= e.creazione }
            if !piu_vecchi.isEmpty { aggiungi(Self.strato(piu_vecchi, dimensione: box.size, k: k)) }
            let l = CALayer()
            l.name = Self.nomeLivello
            l.contentsGravity = .resize
            livelli[e.id] = l
            applica(e, a: l, box: box)
            aggiungi(l)
        }
        if !restanti.isEmpty { aggiungi(Self.strato(restanti, dimensione: box.size, k: k)) }
        CATransaction.commit()
        mostraSelezione()
    }

    /// Strato con i tratti già disegnati (sola immagine, non modificabile finché non si torna alla gomma o al lazo)
    private static func strato(_ tratti: [PKStroke], dimensione: CGSize, k: CGFloat) -> CALayer {
        let l = CALayer()
        l.name = nomeStrato
        l.frame = CGRect(origin: .zero, size: dimensione)
        let d = PKDrawing(strokes: tratti)
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: CGRect(x: 0, y: 0, width: dimensione.width * k, height: dimensione.height * k), scale: 1)
        }
        l.contents = img?.cgImage
        l.contentsGravity = .resize
        return l
    }

    private func applica(_ e: ElementoImmagine, a l: CALayer, box: CGRect) {
        l.contents = e.ritagliata.cgImage
        l.bounds = CGRect(x: 0, y: 0, width: e.larghezza, height: e.altezza)
        l.position = CGPoint(x: e.centro.x - box.minX, y: box.maxY - e.centro.y)
        l.transform = CATransform3DMakeRotation(-e.angolo, 0, 0, 1)
    }

    /// Anteprima in tempo reale durante lo spostamento, il ridimensionamento, la rotazione e il ritaglio
    private func anteprima(_ e: ElementoImmagine) {
        guard let s = scelta, let l = livelli[e.id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applica(e, a: l, box: s.pagina.bounds(for: .cropBox))
        CATransaction.commit()
        mostraSelezione(e)
    }

    // MARK: Cornice e maniglie della selezione

    func mostraSelezione(_ ovr: ElementoImmagine? = nil) {
        let pagine: [PDFPage] = model.map { Array($0.canvases.keys) } ?? []
        for pagina in pagine {
            guard let cont = model?.canvases[pagina]?.superview as? PaginaTela else { continue }
            cont.layer.sublayers?.filter { $0.name == Self.nomeSelezione }.forEach { $0.removeFromSuperlayer() }
        }
        guard let s = scelta, let e = ovr ?? elemento(s.pagina, s.id),
              let cont = model?.canvases[s.pagina]?.superview as? PaginaTela else { return }
        let box = s.pagina.bounds(for: .cropBox)
        let u = unita
        let colore = UIColor(AptTema.accento)
        func c(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - box.minX, y: box.maxY - p.y) }

        let radice = CALayer()
        radice.name = Self.nomeSelezione
        let cornice = CAShapeLayer()
        let path = UIBezierPath()
        let a = e.angoli.map(c)
        path.move(to: a[0]); a.dropFirst().forEach { path.addLine(to: $0) }; path.close()
        cornice.path = path.cgPath
        cornice.fillColor = nil
        cornice.strokeColor = colore.cgColor
        cornice.lineWidth = (ritagliando ? 2.5 : 1.5) * u
        cornice.lineDashPattern = ritagliando ? nil : [NSNumber(value: Double(6 * u)), NSNumber(value: Double(4 * u))]
        radice.addSublayer(cornice)

        if !ritagliando {
            let top = c(e.mondo(CGPoint(x: 0, y: e.altezza / 2)))
            let rot = c(e.mondo(CGPoint(x: 0, y: e.altezza / 2 + 38 * u)))
            let linea = CAShapeLayer()
            let lp = UIBezierPath(); lp.move(to: top); lp.addLine(to: rot)
            linea.path = lp.cgPath
            linea.strokeColor = colore.cgColor
            linea.lineWidth = 1.5 * u
            radice.addSublayer(linea)
        }
        for (_, p) in maniglie(e) {
            let m = CAShapeLayer()
            let q = c(p)
            let r = 9 * u
            m.path = UIBezierPath(ovalIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)).cgPath
            m.fillColor = UIColor(AptTema.carta).cgColor
            m.strokeColor = colore.cgColor
            m.lineWidth = 2 * u
            radice.addSublayer(m)
        }
        cont.layer.addSublayer(radice)
    }

    // MARK: Gesto di trascinamento

    private func colpisce(_ pv: CGPoint, _ tipo: UITouch.TouchType) -> Bool {
        guard let model, puoAgire(tipo), let (pg, pp) = pagina(in: pv) else { return false }
        // maniglie e immagine già scelta: sempre
        if let s = scelta, s.pagina === pg, let e = elemento(pg, s.id),
           maniglia(e, vicino: pp) != nil || e.contiene(pp, margine: 4 * unita) { return true }
        // un'immagine non ancora scelta si afferra al volo solo con lo strumento Immagine
        return model.corrente?.tipo == .immagine && sotto(pp, in: pg) != nil
    }

    private func inizia(_ pv: CGPoint) {
        guard let (pg, pp) = pagina(in: pv) else { fase = .niente; return }
        inizio = pp
        mosso = false
        if let s = scelta, s.pagina === pg, let e = elemento(pg, s.id), let m = maniglia(e, vicino: pp) {
            prima = e
            inCorso = e
            eraScelta = true
            switch m {
            case .angolo: fase = .scala
            case .bordo(let dx, let dy): fase = .ritaglia(dx, dy)
            case .ruota:
                fase = .ruota
                angoloIniziale = atan2(pp.y - e.centro.y, pp.x - e.centro.x) - e.angolo
            }
            return
        }
        guard let e = sotto(pp, in: pg) else { fase = .niente; return }
        eraScelta = scelta?.id == e.id
        if !eraScelta { ritagliando = false }
        scelta = (pg, e.id)
        prima = e
        inCorso = e
        fase = .sposta
        mostraSelezione()
    }

    private func muovi(_ pv: CGPoint) {
        guard let (_, pp) = pagina(in: pv), let base = prima, let s = scelta else { return }
        let u = unita
        var e = base
        switch fase {
        case .niente:
            return
        case .sposta:
            if !mosso && hypot(pp.x - inizio.x, pp.y - inizio.y) < 5 * u { return }
            e.centro = CGPoint(x: base.centro.x + pp.x - inizio.x, y: base.centro.y + pp.y - inizio.y)
        case .scala:
            let d0 = max(hypot(inizio.x - base.centro.x, inizio.y - base.centro.y), 1)
            let d1 = hypot(pp.x - base.centro.x, pp.y - base.centro.y)
            let box = s.pagina.bounds(for: .cropBox)
            e.larghezza = min(max(base.larghezza * d1 / d0, 24), box.width * 3)
        case .ruota:
            var a = atan2(pp.y - base.centro.y, pp.x - base.centro.x) - angoloIniziale
            // si ferma da solo vicino agli angoli retti
            let passo = CGFloat.pi / 2
            let resto = a - (a / passo).rounded() * passo
            if abs(resto) < 0.04 { a -= resto }
            e.angolo = a
        case .ritaglia(let dx, let dy):
            e = Self.ritagliato(base, dx: dx, dy: dy, tocco: pp)
        }
        mosso = true
        inCorso = e
        anteprima(e)
    }

    private func finisci(_ pv: CGPoint, annullato: Bool) {
        defer { fase = .niente; prima = nil; inCorso = nil }
        guard let s = scelta, let vecchio = prima else { return }
        if annullato {
            anteprima(vecchio)
            return
        }
        if mosso, let nuovo = inCorso {
            cambia(s.pagina, togli: vecchio, metti: nuovo)
        } else if case .sposta = fase, eraScelta {
            // Tocco su un'immagine già scelta: menu
            modoMenu = .immagine
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
        }
    }

    /// Ritaglio: il lato (o i lati) toccato segue il dito; il resto dell'immagine resta dov'è.
    static func ritagliato(_ e: ElementoImmagine, dx: Int, dy: Int, tocco p: CGPoint) -> ElementoImmagine {
        let l = e.locale(p)
        let s = e.scala, w = e.larghezza, h = e.altezza
        let R = e.ritaglio
        let minimo: CGFloat = 20
        var minX = R.minX, maxX = R.maxX, minY = R.minY, maxY = R.maxY
        let px = R.minX + (l.x + w / 2) / s
        let py = R.minY + (h / 2 - l.y) / s
        if dx < 0 { minX = min(max(px, 0), R.maxX - minimo) }
        if dx > 0 { maxX = max(min(px, e.base.size.width), R.minX + minimo) }
        if dy > 0 { minY = min(max(py, 0), R.maxY - minimo) }
        if dy < 0 { maxY = max(min(py, e.base.size.height), R.minY + minimo) }
        let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let nw = r.width * s, nh = r.height * s
        let vecchio = CGPoint(x: (r.minX - R.minX) * s - w / 2, y: h / 2 - (r.minY - R.minY) * s)
        let nuovo = CGPoint(x: -nw / 2, y: nh / 2)
        var n = e
        n.impostaRitaglio(r)
        n.larghezza = nw
        n.centro = e.mondo(CGPoint(x: vecchio.x - nuovo.x, y: vecchio.y - nuovo.y))
        return n
    }

    // MARK: Tocco su un punto vuoto della pagina

    @objc private func toccato(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let model else { return }
        let pv = g.location(in: g.view)
        guard let (pg, pp) = pagina(in: pv) else { return }
        let strumento = model.corrente?.tipo
        // Maniglie e immagine già scelta: lavora il gesto di trascinamento
        if let s = scelta, s.pagina === pg, let e = elemento(pg, s.id),
           maniglia(e, vicino: pp) != nil || e.contiene(pp, margine: 4 * unita) { return }
        if let e = sotto(pp, in: pg) {
            if strumento == .immagine { return }           // lo afferra il gesto di trascinamento
            scelta = (pg, e.id)
            ritagliando = false
            mostraSelezione()
            return
        }
        if scelta != nil {
            scelta = nil
            ritagliando = false
            mostraSelezione()
            return
        }
        guard strumento == .immagine else { return }
        puntoVuoto = (pg, pp)
        if Self.appunti != nil {
            modoMenu = .vuoto
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
        } else {
            model.richiediImmagine(pagina: pg, punto: pp)
        }
    }

    // MARK: Inserimento (dopo la scelta del file)

    /// `documento`: pagina di un documento o scansione, messa grande (80% della pagina) e con più dettaglio
    func inserisci(_ dati: Data, pagina: PDFPage, punto: CGPoint, documento: Bool = false, larghezza: CGFloat? = nil) -> Bool {
        guard let (img, d) = ElementoImmagine.prepara(dati, massimo: documento ? 2000 : 1400) else { return false }
        let box = pagina.bounds(for: .cropBox)
        let w = larghezza.map { min(max($0, 20), box.width) } ?? (documento ? box.width * 0.8 : min(260, box.width * 0.5))
        let h = w * img.size.height / max(img.size.width, 1)
        let c = Self.dentro(punto, mezzaLarghezza: w / 2, mezzaAltezza: h / 2, pagina)
        let e = ElementoImmagine(dati: d, base: img, centro: c, larghezza: w, creazione: Date())
        scelta = (pagina, e.id)
        ritagliando = false
        cambia(pagina, togli: nil, metti: e)
        return true
    }

    private static func dentro(_ c: CGPoint, mezzaLarghezza: CGFloat, mezzaAltezza: CGFloat, _ pagina: PDFPage) -> CGPoint {
        let box = pagina.bounds(for: .cropBox)
        return CGPoint(x: min(max(c.x, box.minX + mezzaLarghezza), max(box.minX + mezzaLarghezza, box.maxX - mezzaLarghezza)),
                       y: min(max(c.y, box.minY + mezzaAltezza), max(box.minY + mezzaAltezza, box.maxY - mezzaAltezza)))
    }

    // MARK: Menu

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        switch modoMenu {
        case .vuoto:
            var voci: [UIMenuElement] = []
            if Self.appunti != nil {
                voci.append(UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incolla() })
            }
            voci.append(UIAction(title: "Nuova immagine", image: UIImage(systemName: "photo.badge.plus")) { [weak self] _ in
                guard let (p, pt) = self?.puntoVuoto else { return }
                self?.model?.richiediImmagine(pagina: p, punto: pt)
            })
            return UIMenu(options: .displayInline, children: voci)
        case .immagine:
            guard elementoScelto != nil else { return nil }
            if ritagliando {
                let fine = UIAction(title: "Fine ritaglio", image: UIImage(systemName: "checkmark")) { [weak self] _ in
                    self?.ritagliando = false
                    self?.mostraSelezione()
                }
                let ripristina = UIAction(title: "Ripristina", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in self?.ripristinaRitaglio() }
                return UIMenu(options: .displayInline, children: [fine, ripristina])
            }
            let taglia = UIAction(title: "Taglia", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.taglia() }
            let copia = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copia() }
            let ritaglia = UIAction(title: "Ritaglia", image: UIImage(systemName: "crop")) { [weak self] _ in
                self?.ritagliando = true
                self?.mostraSelezione()
            }
            let su = UIAction(title: "Porta sopra", image: UIImage(systemName: "square.2.layers.3d.top.filled")) { [weak self] _ in self?.livello(su: true) }
            let giu = UIAction(title: "Porta sotto", image: UIImage(systemName: "square.2.layers.3d.bottom.filled")) { [weak self] _ in self?.livello(su: false) }
            let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
            return UIMenu(options: .displayInline, children: [taglia, copia, ritaglia, su, giu, elimina])
        }
    }

    private func copia() {
        Self.appunti = elementoScelto
        mettiNelVassoio()
    }

    /// Copia e taglia mandano nel vassoio anche l'immagine così com'è vista (con il ritaglio, senza rotazione)
    private func mettiNelVassoio() {
        if let e = elementoScelto { Vassoio.condiviso.aggiungi(immagine: e.ritagliata) }
    }

    private func taglia() {
        Self.appunti = elementoScelto
        mettiNelVassoio()
        elimina()
    }

    private func incolla() {
        guard let originale = Self.appunti, let (p, pt) = puntoVuoto else { return }
        var e = originale
        e.id = UUID()
        e.creazione = Date()
        e.centro = Self.dentro(pt, mezzaLarghezza: e.larghezza / 2, mezzaAltezza: e.altezza / 2, p)
        scelta = (p, e.id)
        ritagliando = false
        cambia(p, togli: nil, metti: e)
    }

    private func elimina() {
        guard let s = scelta, let e = elementoScelto else { return }
        scelta = nil
        ritagliando = false
        cambia(s.pagina, togli: e, metti: nil)
    }

    private func ripristinaRitaglio() {
        guard let s = scelta, let e = elementoScelto else { return }
        var n = e
        let scalaAttuale = e.scala
        let intera = CGRect(origin: .zero, size: e.base.size)
        // il contenuto già visibile resta fermo: si riaggiungono i bordi
        let vecchio = CGPoint(x: (intera.minX - e.ritaglio.minX) * scalaAttuale - e.larghezza / 2,
                              y: e.altezza / 2 - (intera.minY - e.ritaglio.minY) * scalaAttuale)
        n.impostaRitaglio(intera)
        n.larghezza = intera.width * scalaAttuale
        let nuovo = CGPoint(x: -n.larghezza / 2, y: n.altezza / 2)
        n.centro = e.mondo(CGPoint(x: vecchio.x - nuovo.x, y: vecchio.y - nuovo.y))
        cambia(s.pagina, togli: e, metti: n)
    }

    // MARK: Livelli: un passo sopra o sotto

    /// Un livello = il gruppo di tratti adiacente o l'immagine adiacente. Si cambia la data dell'immagine
    /// perché stia subito dopo (sopra) o subito prima (sotto) di quel gruppo.
    private func livello(su: Bool) {
        guard let s = scelta, let e = elementoScelto, let model else { return }
        var voci: [(Date, Bool)] = model.tuttiITratti(s.pagina).map { ($0.path.creationDate, false) }
        voci += (model.immagini[s.pagina] ?? []).filter { $0.id != e.id }.map { ($0.creazione, true) }
        voci.sort { $0.0 < $1.0 }
        let i = voci.firstIndex { $0.0 > e.creazione } ?? voci.count        // posizione dell'immagine tra le altre voci
        var nuova: Date?
        if su {
            if i < voci.count {
                var j = i
                if !voci[i].1 { while j + 1 < voci.count && !voci[j + 1].1 { j += 1 } }
                nuova = voci[j].0.addingTimeInterval(0.001)
            }
        } else if i > 0 {
            var j = i - 1
            if !voci[j].1 { while j > 0 && !voci[j - 1].1 { j -= 1 } }
            nuova = voci[j].0.addingTimeInterval(-0.001)
        }
        guard let d = nuova else { return }
        var n = e
        n.creazione = d
        cambia(s.pagina, togli: e, metti: n)
    }

    // MARK: Aggiunta/rimozione con annulla e ripeti

    func cambia(_ p: PDFPage, togli: ElementoImmagine?, metti: ElementoImmagine?) {
        guard let model else { return }
        var lista = model.immagini[p] ?? []
        if let t = togli { lista.removeAll { $0.id == t.id } }
        if let m = metti { lista.append(m) }
        model.immagini[p] = lista
        if let s = scelta, s.pagina === p, !lista.contains(where: { $0.id == s.id }) {
            scelta = nil
            ritagliando = false
        }
        model.ripartisci(p, pulisciUndo: false)
        model.segnaModificato()
        model.pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.cambia(p, togli: metti, metti: togli) }
    }

    // MARK: Da e verso il PDF

    /// Annotazione da scrivere nel PDF al salvataggio (immagine visibile + dati originali nascosti nella stessa annotazione)
    static func annotazione(da e: ElementoImmagine) -> PDFAnnotation {
        let a = AnnotazioneImmagine(bounds: e.riquadro, forType: .stamp, withProperties: nil)
        a.immagine = e.ritagliata
        a.centro = e.centro
        a.larghezza = e.larghezza
        a.altezza = e.altezza
        a.angolo = e.angolo
        a.userName = nome
        _ = a.setValue(e.dati.base64EncodedString(), forAnnotationKey: chiaveDati)
        let r = e.ritaglio
        let info = [e.centro.x, e.centro.y, e.larghezza, e.angolo, e.creazione.timeIntervalSince1970, r.minX, r.minY, r.width, r.height]
            .map { String(Double($0)) }.joined(separator: ",")
        _ = a.setValue(info, forAnnotationKey: chiaveInfo)
        return a
    }

    /// Immagine modificabile letta da un'annotazione dell'app
    static func elemento(da a: PDFAnnotation) -> ElementoImmagine? {
        guard let testo = a.value(forAnnotationKey: chiaveDati) as? String,
              let dati = Data(base64Encoded: testo),
              let img = UIImage(data: dati) else { return nil }
        if let info = a.value(forAnnotationKey: chiaveInfo) as? String {
            let v = info.split(separator: ",").compactMap { Double($0) }
            if v.count == 9 {
                return ElementoImmagine(dati: dati, base: img, ritaglio: CGRect(x: v[5], y: v[6], width: v[7], height: v[8]),
                                        centro: CGPoint(x: v[0], y: v[1]), larghezza: CGFloat(v[2]), angolo: CGFloat(v[3]),
                                        creazione: Date(timeIntervalSince1970: v[4]))
            }
        }
        // salvata dalla versione precedente: senza rotazione né ritaglio
        return ElementoImmagine(dati: dati, base: img, centro: CGPoint(x: a.bounds.midX, y: a.bounds.midY),
                                larghezza: a.bounds.width, creazione: Date())
    }
}
