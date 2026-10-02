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
    let trascina = ImmagineGesto()
    private(set) var menu: UIEditMenuInteraction!

    static let nome = "AptTesto"
    private static let nomeLivello = "AptTestoLivello"
    private var scelto: (PDFPage, ElementoTesto)?

    /// Testo copiato o tagliato (resta finché l'app è aperta)
    private static var appunti: ElementoTesto?
    private enum ModoMenu { case testo, vuoto }
    private var modoMenu = ModoMenu.testo
    private var puntoVuoto: (PDFPage, CGPoint)?

    // Trascinamento con anteprima in tempo reale
    private var trascinato: (pagina: PDFPage, prima: ElementoTesto, inizio: CGPoint)?
    private var mosso = false

    init(model: NotesModel) {
        self.model = model
        super.init()
        tocco.addTarget(self, action: #selector(toccato(_:)))
        tocco.delegate = self
        tocco.isEnabled = false
        tocco.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                   NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        trascina.delegate = self
        trascina.isEnabled = false
        trascina.cancelsTouchesInView = true
        trascina.allowedTouchTypes = tocco.allowedTouchTypes
        trascina.colpisce = { [weak self] p, _ in self?.colpisce(p) ?? false }
        trascina.alInizio = { [weak self] p in self?.inizia(p) }
        trascina.alMovimento = { [weak self] p in self?.muovi(p) }
        trascina.allaFine = { [weak self] p, annullato in self?.finisci(p, annullato: annullato) }
        menu = UIEditMenuInteraction(delegate: self)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { g === tocco }

    private var ultimoTipo = UITouch.TouchType.direct

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if g === tocco { ultimoTipo = touch.type }
        return true
    }

    func attiva(_ si: Bool) {
        tocco.isEnabled = si
        trascina.isEnabled = si
        if !si { resetta() }
    }

    /// Si chiama quando cambia strumento
    func resetta() {
        scelto = nil
        trascinato = nil
    }

    // MARK: Trascinamento di un testo (si vede muovere mentre si trascina)

    private func colpisce(_ pv: CGPoint) -> Bool {
        guard let model, model.corrente?.tipo == .testo, let vista = model.pdfView,
              let pagina = vista.page(for: pv, nearest: false) else { return false }
        return elemento(in: pagina, at: vista.convert(pv, to: pagina)) != nil
    }

    private func inizia(_ pv: CGPoint) {
        guard let vista = model?.pdfView, let pagina = vista.page(for: pv, nearest: false) else { return }
        let pp = vista.convert(pv, to: pagina)
        guard let e = elemento(in: pagina, at: pp) else { return }
        trascinato = (pagina, e, pp)
        mosso = false
    }

    private func muovi(_ pv: CGPoint) {
        guard let model, let vista = model.pdfView, let t = trascinato else { return }
        let pp = vista.convert(pv, to: t.pagina)
        if !mosso && hypot(pp.x - t.inizio.x, pp.y - t.inizio.y) < 5 / max(vista.scaleFactor, 0.1) { return }
        mosso = true
        var n = t.prima
        n.punto = CGPoint(x: t.prima.punto.x + pp.x - t.inizio.x, y: t.prima.punto.y + pp.y - t.inizio.y)
        var lista = model.testi[t.pagina] ?? []
        if let i = lista.firstIndex(where: { $0.id == t.prima.id }) { lista[i] = n }
        model.testi[t.pagina] = lista
        ridisegna(t.pagina)
    }

    private func finisci(_ pv: CGPoint, annullato: Bool) {
        defer { trascinato = nil; mosso = false }
        guard let model, let vista = model.pdfView, let t = trascinato else { return }
        if mosso {
            // riporta la lista com'era e applica la modifica con annulla/ripeti
            let pp = vista.convert(pv, to: t.pagina)
            var lista = model.testi[t.pagina] ?? []
            let corrente = lista.first { $0.id == t.prima.id }
            if let i = lista.firstIndex(where: { $0.id == t.prima.id }) { lista[i] = t.prima }
            model.testi[t.pagina] = lista
            if !annullato, let n = corrente {
                _ = pp
                cambia(t.pagina, togli: t.prima, metti: n)
            } else {
                ridisegna(t.pagina)
            }
        } else if !annullato {
            scelto = (t.pagina, t.prima)
            modoMenu = .testo
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
        }
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
            let cornice = CGRect(x: (r.minX - box.minX) * f, y: (box.maxY - r.maxY) * f,
                                 width: r.width * f, height: r.height * f)
            let l = CATextLayer()
            l.name = Self.nomeLivello
            l.string = e.testo
            l.font = CTFontCreateWithName("Helvetica" as CFString, e.corpo * f, nil)
            l.fontSize = e.corpo * f
            l.foregroundColor = e.colore.cgColor
            l.alignmentMode = .left
            l.isWrapped = false
            l.contentsScale = scala
            l.frame = cornice
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

        // Sui testi già messi lavora il gesto di trascinamento (anche per il menu)
        if elemento(in: pagina, at: pp) != nil { return }
        // Un tocco del dito su un'immagine la seleziona: non si crea un testo
        if ultimoTipo != .pencil, model.controlloImmagini?.haImmagine(in: pagina, at: pp) == true { return }

        if Self.appunti != nil {
            puntoVuoto = (pagina, pp)
            modoMenu = .vuoto
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
            return
        }
        nuovoTesto(pagina, pp)
    }

    private func nuovoTesto(_ pagina: PDFPage, _ pp: CGPoint) {
        guard let model, let s = model.corrente else { return }
        model.bozzaTesto = BozzaTesto(pagina: pagina, punto: pp, testo: "", corpo: CGFloat(s.spessore),
                                      colore: s.colore.ui, esistente: nil)
    }

    // MARK: Menu sul testo

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if modoMenu == .vuoto {
            var voci: [UIMenuElement] = []
            if Self.appunti != nil {
                voci.append(UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incolla() })
            }
            voci.append(UIAction(title: "Nuovo testo", image: UIImage(systemName: "textformat")) { [weak self] _ in
                guard let (p, pt) = self?.puntoVuoto else { return }
                self?.nuovoTesto(p, pt)
            })
            return UIMenu(options: .displayInline, children: voci)
        }
        guard scelto != nil else { return nil }
        let modifica = UIAction(title: "Modifica", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.modifica() }
        let taglia = UIAction(title: "Taglia", image: UIImage(systemName: "scissors")) { [weak self] _ in
            Self.appunti = self?.scelto?.1
            self?.elimina()
        }
        let copia = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in Self.appunti = self?.scelto?.1 }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        return UIMenu(options: .displayInline, children: [modifica, taglia, copia, elimina])
    }

    private func incolla() {
        guard let o = Self.appunti, let (p, pt) = puntoVuoto else { return }
        cambia(p, togli: nil, metti: ElementoTesto(testo: o.testo, punto: pt, corpo: o.corpo, colore: o.colore))
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
