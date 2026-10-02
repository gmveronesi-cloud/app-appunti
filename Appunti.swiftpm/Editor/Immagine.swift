// Strumento Immagine: si tocca la pagina, si sceglie una foto (o un file immagine) e si mette sulla pagina.
// Nell'app l'immagine è un livello sotto i tratti (così si può scrivere sopra). Al salvataggio diventa
// un'annotazione Stamp con l'immagine vera (visibile in ogni lettore PDF; verificato con `prove/ProvaImmagine`)
// e con i dati originali in una chiave nascosta, così all'apertura torna modificabile.
// Toccando un'immagine già messa: Sposta, Ingrandisci, Rimpicciolisci, Elimina.
import SwiftUI
import PDFKit

/// Un'immagine messa su una pagina
struct ElementoImmagine: Identifiable, Equatable {
    let id = UUID()
    var dati: Data                  // JPEG o PNG già ridimensionato (è ciò che viene salvato nel PDF)
    var immagine: UIImage
    var rett: CGRect                // coordinate della pagina (PDF, origine in basso a sinistra)

    static func == (a: ElementoImmagine, b: ElementoImmagine) -> Bool { a.id == b.id }

    /// Orienta correttamente, riduce (lato massimo 1400 px) e codifica. nil se i dati non sono un'immagine.
    static func prepara(_ dati: Data) -> (UIImage, Data)? {
        guard let src = UIImage(data: dati) else { return nil }
        let pw = src.size.width * src.scale, ph = src.size.height * src.scale
        guard pw > 0, ph > 0 else { return nil }
        let s = min(1, 1400 / max(pw, ph))
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

/// Annotazione Stamp che disegna l'immagine: PDFKit la salva nel file con il suo aspetto.
final class AnnotazioneImmagine: PDFAnnotation {
    var immagine: UIImage?

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = immagine?.cgImage else { return }
        context.draw(cg, in: bounds)
    }
}

final class ImmagineControllo: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    weak var model: NotesModel?
    let tocco = UITapGestureRecognizer()
    private(set) var menu: UIEditMenuInteraction!

    static let nome = "AptImmagine"
    static let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")
    private static let nomeLivello = "AptImmagineLivello"
    private var scelta: (PDFPage, ElementoImmagine)?
    private var daSpostare: (PDFPage, ElementoImmagine)?

    init(model: NotesModel) {
        self.model = model
        super.init()
        tocco.addTarget(self, action: #selector(toccato(_:)))
        tocco.delegate = self
        tocco.isEnabled = false
        tocco.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                   NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        menu = UIEditMenuInteraction(delegate: self)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// Si chiama quando cambia strumento: lo spostamento in sospeso si annulla.
    func resetta() {
        scelta = nil
        daSpostare = nil
    }

    // MARK: Disegno (livelli sotto la tela dei tratti)

    func ridisegna(_ pagina: PDFPage) {
        guard let model, let tela = model.canvases[pagina], let contenitore = tela.superview as? PaginaTela else { return }
        contenitore.layer.sublayers?.filter { $0.name == Self.nomeLivello }.forEach { $0.removeFromSuperlayer() }
        let box = pagina.bounds(for: .cropBox)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in model.immagini[pagina] ?? [] {
            let l = CALayer()
            l.name = Self.nomeLivello
            l.contents = e.immagine.cgImage
            l.contentsGravity = .resize
            l.frame = CGRect(x: e.rett.minX - box.minX, y: box.maxY - e.rett.maxY,
                             width: e.rett.width, height: e.rett.height)
            contenitore.layer.insertSublayer(l, below: tela.layer)
        }
        CATransaction.commit()
    }

    private func elemento(in pagina: PDFPage, at p: CGPoint) -> ElementoImmagine? {
        model?.immagini[pagina]?.last { $0.rett.insetBy(dx: -6, dy: -6).contains(p) }
    }

    // MARK: Tocco sulla pagina

    @objc private func toccato(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let model, let vista = model.pdfView,
              let s = model.corrente, s.tipo == .immagine else { return }
        let pv = g.location(in: vista)
        guard let pagina = vista.page(for: pv, nearest: false) else { return }
        let pp = vista.convert(pv, to: pagina)

        if let (p, e) = daSpostare {
            daSpostare = nil
            guard p === pagina else { return }
            var nuovo = e
            nuovo.rett = Self.dentro(CGRect(x: pp.x - e.rett.width / 2, y: pp.y - e.rett.height / 2,
                                            width: e.rett.width, height: e.rett.height), pagina)
            cambia(p, togli: e, metti: nuovo)
            return
        }

        if let e = elemento(in: pagina, at: pp) {
            scelta = (pagina, e)
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
            return
        }

        model.richiediImmagine(pagina: pagina, punto: pp)
    }

    /// Tiene il rettangolo dentro la pagina
    private static func dentro(_ r: CGRect, _ pagina: PDFPage) -> CGRect {
        let box = pagina.bounds(for: .cropBox)
        var n = r
        n.origin.x = min(max(n.origin.x, box.minX), max(box.minX, box.maxX - n.width))
        n.origin.y = min(max(n.origin.y, box.minY), max(box.minY, box.maxY - n.height))
        return n
    }

    // MARK: Inserimento (dopo la scelta del file)

    func inserisci(_ dati: Data, pagina: PDFPage, punto: CGPoint) -> Bool {
        guard let (img, d) = ElementoImmagine.prepara(dati) else { return false }
        let box = pagina.bounds(for: .cropBox)
        let w = min(260, box.width * 0.5)
        let h = w * img.size.height / max(img.size.width, 1)
        let r = Self.dentro(CGRect(x: punto.x - w / 2, y: punto.y - h / 2, width: w, height: h), pagina)
        cambia(pagina, togli: nil, metti: ElementoImmagine(dati: d, immagine: img, rett: r))
        return true
    }

    // MARK: Menu sull'immagine

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard scelta != nil else { return nil }
        let sposta = UIAction(title: "Sposta", image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")) { [weak self] _ in
            self?.daSpostare = self?.scelta
        }
        let piu = UIAction(title: "Ingrandisci", image: UIImage(systemName: "plus.magnifyingglass")) { [weak self] _ in self?.scala(1.25) }
        let meno = UIAction(title: "Rimpicciolisci", image: UIImage(systemName: "minus.magnifyingglass")) { [weak self] _ in self?.scala(0.8) }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        return UIMenu(options: .displayInline, children: [sposta, piu, meno, elimina])
    }

    private func scala(_ k: CGFloat) {
        guard let (p, e) = scelta else { return }
        let c = CGPoint(x: e.rett.midX, y: e.rett.midY)
        let w = max(30, e.rett.width * k), h = w * e.rett.height / max(e.rett.width, 1)
        var nuovo = e
        nuovo.rett = Self.dentro(CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), p)
        cambia(p, togli: e, metti: nuovo)
        scelta = (p, nuovo)
    }

    private func elimina() {
        guard let (p, e) = scelta else { return }
        cambia(p, togli: e, metti: nil)
        scelta = nil
    }

    // MARK: Aggiunta/rimozione con annulla e ripeti

    private func cambia(_ p: PDFPage, togli: ElementoImmagine?, metti: ElementoImmagine?) {
        guard let model else { return }
        var lista = model.immagini[p] ?? []
        if let t = togli { lista.removeAll { $0.id == t.id } }
        if let m = metti { lista.append(m) }
        model.immagini[p] = lista
        ridisegna(p)
        model.segnaModificato()
        model.pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.cambia(p, togli: metti, metti: togli) }
    }

    // MARK: Da e verso il PDF

    /// Annotazione da scrivere nel PDF al salvataggio (immagine visibile + dati originali nascosti nella stessa annotazione)
    static func annotazione(da e: ElementoImmagine) -> PDFAnnotation {
        let a = AnnotazioneImmagine(bounds: e.rett, forType: .stamp, withProperties: nil)
        a.immagine = e.immagine
        a.userName = nome
        _ = a.setValue(e.dati.base64EncodedString(), forAnnotationKey: chiaveDati)
        return a
    }

    /// Immagine modificabile letta da un'annotazione dell'app
    static func elemento(da a: PDFAnnotation) -> ElementoImmagine? {
        guard let testo = a.value(forAnnotationKey: chiaveDati) as? String,
              let dati = Data(base64Encoded: testo),
              let img = UIImage(data: dati) else { return nil }
        return ElementoImmagine(dati: dati, immagine: img, rett: a.bounds)
    }
}
