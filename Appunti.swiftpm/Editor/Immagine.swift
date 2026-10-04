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
    var ritaglio: CGRect   // parte visibile, in pixel di `base`
    var ritagliata: UIImage
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
    var tocco: UITouch?

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
    var menu: UIEditMenuInteraction!

    static let nome = "AptImmagine"
    static let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")
    static let chiaveInfo = PDFAnnotationKey(rawValue: "/AptInfo")
    static let nomeLivello = "AptImmagineLivello"
    static let nomeStrato = "AptStrato"
    static let nomeSelezione = "AptSelezioneImmagine"

    /// Immagine copiata o tagliata (resta finché l'app è aperta)
    static var appunti: ElementoImmagine?

    var scelta: (pagina: PDFPage, id: UUID)?
    var ritagliando = false
    var livelli: [UUID: CALayer] = [:]

    enum Maniglia: Equatable {
        case angolo(Int, Int)       // ingrandisce (o ritaglia due lati)
        case bordo(Int, Int)        // ritaglia un lato
        case ruota
    }
    enum Fase { case niente, sposta, scala, ruota, ritaglia(Int, Int) }
    var fase = Fase.niente
    var inizio: CGPoint = .zero         // punto di pagina dove è iniziato il gesto
    var prima: ElementoImmagine?
    var inCorso: ElementoImmagine?
    var mosso = false
    var eraScelta = false
    var angoloIniziale: CGFloat = 0

    enum ModoMenu { case immagine, vuoto }
    var modoMenu = ModoMenu.immagine
    var puntoVuoto: (PDFPage, CGPoint)?

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
    func puoAgire(_ tipo: UITouch.TouchType) -> Bool {
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

    // MARK: Per il lazo

    /// Il lazo ha circondato una sola immagine: la sceglie (cornice, maniglie, rotazione e ritaglio come dopo un tocco)
    func seleziona(_ pagina: PDFPage, id: UUID) {
        scelta = (pagina, id)
        ritagliando = false
        mostraSelezione()
    }

    func annullaSelezione() {
        guard scelta != nil else { return }
        scelta = nil
        ritagliando = false
        mostraSelezione()
    }

    /// Anteprima in tempo reale di un'immagine del gruppo scelto dal lazo (spostamento, ridimensionamento, rotazione)
    func anteprimaGruppo(_ e: ElementoImmagine, pagina: PDFPage) {
        guard let l = livelli[e.id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applica(e, a: l, box: pagina.bounds(for: .cropBox))
        CATransaction.commit()
    }

    /// Copia o taglio dal lazo: l'ultima va negli appunti interni, tutte nel vassoio
    func copiaInAppunti(_ lista: [ElementoImmagine]) {
        guard let ultima = lista.last else { return }
        Self.appunti = ultima
        for e in lista { mettiNelVassoio(e) }
    }

    /// Si chiama quando si chiude il documento
    func resetta() {
        scelta = nil
        ritagliando = false
        fase = .niente
        mostraSelezione()
    }

    // MARK: Utilità

    var vista: PDFView? { model?.pdfView }
    var unita: CGFloat { 1 / max(vista?.scaleFactor ?? 1, 0.1) }     // punti di pagina per punto di schermo

    func elemento(_ p: PDFPage, _ id: UUID) -> ElementoImmagine? {
        model?.immagini[p]?.first { $0.id == id }
    }

    var elementoScelto: ElementoImmagine? {
        guard let s = scelta else { return nil }
        return elemento(s.pagina, s.id)
    }

    /// L'immagine più in alto sotto il punto
    func sotto(_ pp: CGPoint, in pagina: PDFPage) -> ElementoImmagine? {
        (model?.immagini[pagina] ?? []).sorted { $0.creazione > $1.creazione }.first { $0.contiene(pp, margine: 4 * unita) }
    }

    func maniglie(_ e: ElementoImmagine) -> [(Maniglia, CGPoint)] {
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

    func maniglia(_ e: ElementoImmagine, vicino a: CGPoint) -> Maniglia? {
        let raggio = 24 * unita
        return maniglie(e).first { hypot($0.1.x - a.x, $0.1.y - a.y) < raggio }?.0
    }

    func pagina(in pv: CGPoint) -> (PDFPage, CGPoint)? {
        guard let vista, let p = vista.page(for: pv, nearest: true) else { return nil }
        return (p, vista.convert(pv, to: p))
    }

}
