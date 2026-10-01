// Strumento Testo: si tocca la pagina, si scrive con la nostra tastiera e il testo resta nel PDF
// come annotazione di testo (visibile in ogni lettore). Toccando un testo già messo: Modifica, Sposta, Elimina.
//
// Nell'app il testo è disegnato da noi (livelli di testo vettoriali sopra la tela della pagina), perché il
// testo disegnato da PDFKit risultava sgranato. Al salvataggio ogni testo diventa un'annotazione `AptTesto`
// del PDF; all'apertura le annotazioni `AptTesto` tornano testi modificabili (come per i tratti).
import SwiftUI
import PDFKit

/// Un testo messo su una pagina
struct ElementoTesto: Identifiable, Equatable {
    let id = UUID()
    var testo: String
    var punto: CGPoint              // angolo in alto a sinistra, coordinate della pagina (PDF)
    var corpo: CGFloat              // dimensione del carattere, in punti della pagina
    var colore: UIColor

    static func == (a: ElementoTesto, b: ElementoTesto) -> Bool { a.id == b.id }

    static func font(_ corpo: CGFloat) -> UIFont {
        UIFont(name: "Helvetica", size: corpo) ?? UIFont.systemFont(ofSize: corpo)
    }

    var misura: CGSize {
        let m = (testo as NSString).boundingRect(
            with: CGSize(width: 600, height: 2000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: Self.font(corpo)],
            context: nil)
        return CGSize(width: ceil(m.width) + 10, height: ceil(m.height) + 6)
    }

    /// Rettangolo occupato, in coordinate della pagina (origine in basso a sinistra)
    var rettangolo: CGRect {
        let m = misura
        return CGRect(x: punto.x, y: punto.y - m.height, width: m.width, height: m.height)
    }
}

/// Testo in corso di scrittura (nuovo o da modificare)
struct BozzaTesto: Identifiable {
    let id = UUID()
    let pagina: PDFPage
    var punto: CGPoint
    var testo: String
    var corpo: CGFloat
    var colore: UIColor
    var esistente: ElementoTesto?
}

final class TestoControllo: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    weak var model: NotesModel?
    let tocco = UITapGestureRecognizer()
    private(set) var menu: UIEditMenuInteraction!

    static let nome = "AptTesto"
    private static let nomeLivello = "AptTestoLivello"
    private var scelto: (PDFPage, ElementoTesto)?
    private var daSpostare: (PDFPage, ElementoTesto)?

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
        scelto = nil
        daSpostare = nil
    }

    // MARK: Disegno del testo (livelli vettoriali sulla tela della pagina)

    func ridisegnaTutte() {
        guard let model else { return }
        for pagina in model.canvases.keys { ridisegna(pagina) }
    }

    func ridisegna(_ pagina: PDFPage) {
        guard let model, let tela = model.canvases[pagina] else { return }
        tela.layer.sublayers?.filter { $0.name == Self.nomeLivello }.forEach { $0.removeFromSuperlayer() }
        guard tela.bounds.width > 0 else { return }
        let box = pagina.bounds(for: .cropBox)
        let f = tela.bounds.width / box.width
        // Il livello sta nella tela (k volte la pagina, rimpicciolita) e poi PDFView lo ingrandisce con lo zoom
        let zoom = model.pdfView?.scaleFactor ?? 1
        let scala = tela.traitCollection.displayScale * max(1, zoom / tela.fattoreRisoluzione)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in model.testi[pagina] ?? [] {
            let r = e.rettangolo
            let l = CATextLayer()
            l.name = Self.nomeLivello
            l.string = e.testo
            l.font = CTFontCreateWithName("Helvetica" as CFString, e.corpo * f, nil)
            l.fontSize = e.corpo * f
            l.foregroundColor = e.colore.cgColor
            l.alignmentMode = .left
            l.isWrapped = false
            l.contentsScale = scala
            l.frame = CGRect(x: (r.minX - box.minX) * f, y: (box.maxY - r.maxY) * f,
                             width: r.width * f, height: r.height * f)
            tela.layer.addSublayer(l)
        }
        CATransaction.commit()
    }

    private func elemento(in pagina: PDFPage, at p: CGPoint) -> ElementoTesto? {
        model?.testi[pagina]?.last { $0.rettangolo.insetBy(dx: -6, dy: -6).contains(p) }
    }

    // MARK: Tocco sulla pagina

    @objc private func toccato(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let model, let vista = model.pdfView,
              let s = model.corrente, s.tipo == .testo else { return }
        let pv = g.location(in: vista)
        guard let pagina = vista.page(for: pv, nearest: false) else { return }
        let pp = vista.convert(pv, to: pagina)

        if let (p, e) = daSpostare {
            daSpostare = nil
            guard p === pagina else { return }
            var nuovo = e
            nuovo.punto = pp
            cambia(p, togli: e, metti: ElementoTesto(testo: nuovo.testo, punto: pp, corpo: nuovo.corpo, colore: nuovo.colore))
            return
        }

        if let e = elemento(in: pagina, at: pp) {
            scelto = (pagina, e)
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
            return
        }

        model.bozzaTesto = BozzaTesto(pagina: pagina, punto: pp, testo: "", corpo: CGFloat(s.spessore),
                                      colore: s.colore.ui, esistente: nil)
    }

    // MARK: Menu sul testo

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard scelto != nil else { return nil }
        let modifica = UIAction(title: "Modifica", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.modifica() }
        let sposta = UIAction(title: "Sposta", image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")) { [weak self] _ in
            self?.daSpostare = self?.scelto
        }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        return UIMenu(options: .displayInline, children: [modifica, sposta, elimina])
    }

    private func modifica() {
        guard let (p, e) = scelto, let model else { return }
        model.bozzaTesto = BozzaTesto(pagina: p, punto: e.punto, testo: e.testo, corpo: e.corpo,
                                      colore: e.colore, esistente: e)
    }

    private func elimina() {
        guard let (p, e) = scelto else { return }
        cambia(p, togli: e, metti: nil)
        scelto = nil
    }

    // MARK: Conferma dalla finestra di scrittura

    func conferma(_ b: BozzaTesto, testo: String) {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        if pulito.isEmpty {
            if let e = b.esistente { cambia(b.pagina, togli: e, metti: nil) }
            return
        }
        if let e = b.esistente, e.testo == pulito { return }
        let nuovo = ElementoTesto(testo: pulito, punto: b.punto, corpo: b.corpo, colore: b.colore)
        cambia(b.pagina, togli: b.esistente, metti: nuovo)
    }

    // MARK: Aggiunta/rimozione con annulla e ripeti

    private func cambia(_ p: PDFPage, togli: ElementoTesto?, metti: ElementoTesto?) {
        guard let model else { return }
        var lista = model.testi[p] ?? []
        if let t = togli { lista.removeAll { $0.id == t.id } }
        if let m = metti { lista.append(m) }
        model.testi[p] = lista
        ridisegna(p)
        model.segnaModificato()
        model.pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.cambia(p, togli: metti, metti: togli) }
    }

    // MARK: Da e verso il PDF

    /// Annotazione di testo da scrivere nel PDF al salvataggio
    static func annotazione(da e: ElementoTesto) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: e.rettangolo, forType: .freeText, withProperties: nil)
        a.font = ElementoTesto.font(e.corpo)
        a.fontColor = e.colore
        a.color = .clear
        a.alignment = .left
        a.contents = e.testo
        a.userName = nome
        let bordo = PDFBorder()
        bordo.lineWidth = 0
        a.border = bordo
        return a
    }

    /// Testo modificabile letto da un'annotazione dell'app
    static func elemento(da a: PDFAnnotation) -> ElementoTesto {
        ElementoTesto(testo: a.contents ?? "",
                      punto: CGPoint(x: a.bounds.minX, y: a.bounds.maxY),
                      corpo: a.font?.pointSize ?? 16,
                      colore: a.fontColor ?? .black)
    }
}
