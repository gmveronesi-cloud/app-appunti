// Strumento Testo: si tocca la pagina, si scrive con la nostra tastiera e il testo resta nel PDF
// come annotazione di testo (visibile in ogni lettore). Toccando un testo già messo: Modifica, Sposta, Elimina.
import SwiftUI
import PDFKit

/// Testo in corso di scrittura (nuovo o da modificare)
struct BozzaTesto: Identifiable {
    let id = UUID()
    let pagina: PDFPage
    var punto: CGPoint              // angolo in alto a sinistra, coordinate della pagina
    var testo: String
    var corpo: CGFloat
    var colore: UIColor
    var esistente: PDFAnnotation?
}

final class TestoControllo: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    weak var model: NotesModel?
    let tocco = UITapGestureRecognizer()
    private(set) var menu: UIEditMenuInteraction!

    static let nome = "AptTesto"
    private var scelto: (PDFPage, PDFAnnotation)?
    private var daSpostare: (PDFPage, PDFAnnotation)?

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

    // MARK: Tocco sulla pagina

    @objc private func toccato(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let model, let vista = model.pdfView,
              let s = model.corrente, s.tipo == .testo else { return }
        let pv = g.location(in: vista)
        guard let pagina = vista.page(for: pv, nearest: false) else { return }
        let pp = vista.convert(pv, to: pagina)

        if let (p, a) = daSpostare {
            daSpostare = nil
            guard p === pagina else { return }
            let nuovo = Self.crea(testo: a.contents ?? "", punto: pp,
                                  corpo: a.font?.pointSize ?? CGFloat(s.spessore),
                                  colore: a.fontColor ?? s.colore.ui)
            cambia(p, togli: a, metti: nuovo)
            return
        }

        if let a = pagina.annotation(at: pp), a.userName == Self.nome {
            scelto = (pagina, a)
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
        guard let (p, a) = scelto, let model else { return }
        model.bozzaTesto = BozzaTesto(pagina: p, punto: CGPoint(x: a.bounds.minX, y: a.bounds.maxY),
                                      testo: a.contents ?? "", corpo: a.font?.pointSize ?? 16,
                                      colore: a.fontColor ?? .black, esistente: a)
    }

    private func elimina() {
        guard let (p, a) = scelto else { return }
        cambia(p, togli: a, metti: nil)
        scelto = nil
    }

    // MARK: Conferma dalla finestra di scrittura

    func conferma(_ b: BozzaTesto, testo: String) {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        if pulito.isEmpty {
            if let e = b.esistente { cambia(b.pagina, togli: e, metti: nil) }
            return
        }
        if let e = b.esistente, e.contents == pulito { return }
        let nuovo = Self.crea(testo: pulito, punto: b.punto, corpo: b.corpo, colore: b.colore)
        cambia(b.pagina, togli: b.esistente, metti: nuovo)
    }

    // MARK: Aggiunta/rimozione con annulla e ripeti

    private func cambia(_ p: PDFPage, togli: PDFAnnotation?, metti: PDFAnnotation?) {
        if let t = togli { p.removeAnnotation(t) }
        if let m = metti { p.addAnnotation(m) }
        model?.pdfView?.annotationsChanged(on: p)
        model?.segnaModificato()
        let um = model?.pdfView?.undoManager
        um?.registerUndo(withTarget: self) { s in s.cambia(p, togli: metti, metti: togli) }
    }

    static func crea(testo: String, punto: CGPoint, corpo: CGFloat, colore: UIColor) -> PDFAnnotation {
        let font = UIFont.systemFont(ofSize: corpo)
        let misura = (testo as NSString).boundingRect(
            with: CGSize(width: 600, height: 2000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil)
        let w = ceil(misura.width) + 10
        let h = ceil(misura.height) + 6
        let a = PDFAnnotation(bounds: CGRect(x: punto.x, y: punto.y - h, width: w, height: h),
                              forType: .freeText, withProperties: nil)
        a.font = font
        a.fontColor = colore
        a.color = .clear
        a.alignment = .left
        a.contents = testo
        a.userName = nome
        let bordo = PDFBorder()
        bordo.lineWidth = 0
        a.border = bordo
        return a
    }
}
