// Strumento Testo: si tocca la pagina, si scrive con la nostra tastiera e il testo resta nel PDF
// come annotazione di testo (visibile in ogni lettore). Toccando un testo già messo: si sceglie (cornice con due
// maniglie ai lati per cambiare la larghezza del blocco) e compare il menu: Modifica, Taglia, Copia, Elimina, livelli.
//
// Il testo può andare a capo (tasto «A capo» della nostra tastiera). La larghezza del blocco si cambia con le maniglie:
// cambia solo quante parole stanno in ogni riga, non la dimensione delle lettere.
//
// Nell'app il testo è disegnato da noi (livelli di testo vettoriali), perché il testo disegnato da PDFKit risultava
// sgranato. I livelli di testo stanno nella stessa pila delle immagini e dei tratti (vedi `ImmagineControllo.ridisegna`):
// ogni testo ha la data di creazione, come ogni tratto, e così rispetta l'ordine dei livelli.
// Al salvataggio ogni testo diventa un'annotazione `AptTesto` del PDF; all'apertura le annotazioni `AptTesto` tornano
// testi modificabili (come per i tratti).
import SwiftUI
import PDFKit

/// Un testo messo su una pagina
struct ElementoTesto: Identifiable, Equatable {
    var id = UUID()
    var testo: String
    var punto: CGPoint              // angolo in alto a sinistra, coordinate della pagina (PDF)
    var corpo: CGFloat              // dimensione del carattere, in punti della pagina
    var colore: UIColor
    var larghezza: CGFloat? = nil   // larghezza del blocco: nil = quella del testo più lungo (fino a `limiteAuto`)
    var creazione: Date = Date()
    static func == (a: ElementoTesto, b: ElementoTesto) -> Bool { a.id == b.id }

    static let margine: CGFloat = 10        // spazio a destra del testo dentro il blocco
    static let limiteAuto: CGFloat = 600
    static let minimo: CGFloat = 40         // larghezza minima del blocco

    static func font(_ corpo: CGFloat) -> UIFont {
        UIFont(name: "Helvetica", size: corpo) ?? UIFont.systemFont(ofSize: corpo)
    }

    var misura: CGSize {
        let disponibile = larghezza.map { max($0, Self.minimo) - 1 } ?? Self.limiteAuto
        let m = (testo as NSString).boundingRect(
            with: CGSize(width: disponibile, height: 6000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: Self.font(corpo)],
            context: nil)
        let w = larghezza.map { max($0, Self.minimo) } ?? (ceil(m.width) + Self.margine)
        return CGSize(width: w, height: ceil(m.height) + 6)
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
    var larghezza: CGFloat? = nil
    var esistente: ElementoTesto?
}

final class TestoControllo: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    weak var model: NotesModel?
    let tocco = UITapGestureRecognizer()
    let trascina = ImmagineGesto()
    private(set) var menu: UIEditMenuInteraction!

    static let nome = "AptTesto"
    static let chiaveInfo = PDFAnnotationKey(rawValue: "/AptInfoTesto")
    static let nomeLivello = "AptTestoLivello"
    static let nomeSelezione = "AptSelezioneTesto"

    /// Livelli di testo attualmente sulle pagine (per l'anteprima in tempo reale e la nitidezza)
    var livelli: [UUID: CALayer] = [:]
    private(set) var scelto: (PDFPage, ElementoTesto)?

    /// Testo copiato o tagliato (resta finché l'app è aperta)
    static var appunti: ElementoTesto?
    private enum ModoMenu { case testo, vuoto }
    private var modoMenu = ModoMenu.testo
    private var puntoVuoto: (PDFPage, CGPoint)?

    // Gesto con anteprima in tempo reale: sposta o cambia la larghezza
    private enum Fase { case niente, sposta, sinistra, destra }
    private var fase = Fase.niente
    private var base: (pagina: PDFPage, elemento: ElementoTesto, inizio: CGPoint)?
    private var inCorso: ElementoTesto?
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

    /// Si chiama quando cambia strumento o si chiude il documento
    func resetta() {
        let aveva = scelto != nil
        scelto = nil
        base = nil
        inCorso = nil
        fase = .niente
        if aveva { mostraSelezione() }
    }

    // MARK: Utilità

    private var vista: PDFView? { model?.pdfView }
    private var unita: CGFloat { 1 / max(vista?.scaleFactor ?? 1, 0.1) }     // punti di pagina per punto di schermo

    private func trovaPagina(_ pv: CGPoint, vicina: Bool) -> (PDFPage, CGPoint)? {
        guard let vista, let p = vista.page(for: pv, nearest: vicina) else { return nil }
        return (p, vista.convert(pv, to: p))
    }

    func elementoAttuale(_ p: PDFPage, _ id: UUID) -> ElementoTesto? {
        model?.testi[p]?.first { $0.id == id }
    }

    /// Il testo più in alto sotto il punto
    func elemento(in pagina: PDFPage, at p: CGPoint) -> ElementoTesto? {
        (model?.testi[pagina] ?? []).sorted { $0.creazione > $1.creazione }
            .first { $0.rettangolo.insetBy(dx: -6, dy: -6).contains(p) }
    }

    /// Per il lazo: un testo sotto il punto (coordinate della pagina)
    func testoSotto(_ p: CGPoint, in pagina: PDFPage) -> ElementoTesto? { elemento(in: pagina, at: p) }

    // MARK: Maniglie della larghezza

    private func maniglia(_ e: ElementoTesto, vicino a: CGPoint) -> Fase? {
        let r = e.rettangolo
        let raggio = 24 * unita
        if hypot(r.maxX - a.x, r.midY - a.y) < raggio { return .destra }
        if hypot(r.minX - a.x, r.midY - a.y) < raggio { return .sinistra }
        return nil
    }

    // MARK: Gesto: spostare o cambiare la larghezza

    private func colpisce(_ pv: CGPoint) -> Bool {
        guard let model, model.corrente?.tipo == .testo else { return false }
        if let (sp, se) = scelto, let (pagina, pp) = trovaPagina(pv, vicina: true), sp === pagina,
           let e = elementoAttuale(sp, se.id), maniglia(e, vicino: pp) != nil { return true }
        guard let (pagina, pp) = trovaPagina(pv, vicina: false) else { return false }
        return elemento(in: pagina, at: pp) != nil
    }

    private func inizia(_ pv: CGPoint) {
        mosso = false
        if let (sp, se) = scelto, let (pagina, pp) = trovaPagina(pv, vicina: true), sp === pagina,
           let e = elementoAttuale(sp, se.id), let lato = maniglia(e, vicino: pp) {
            base = (pagina, e, pp)
            inCorso = e
            fase = lato
            return
        }
        guard let (pagina, pp) = trovaPagina(pv, vicina: false), let e = elemento(in: pagina, at: pp) else { fase = .niente; return }
        base = (pagina, e, pp)
        inCorso = e
        fase = .sposta
    }

    private func muovi(_ pv: CGPoint) {
        guard let vista, let b = base, fase != .niente else { return }
        let pp = vista.convert(pv, to: b.pagina)
        let dx = pp.x - b.inizio.x, dy = pp.y - b.inizio.y
        if !mosso && hypot(dx, dy) < 5 * unita { return }
        mosso = true
        var n = b.elemento
        let larghezza0 = b.elemento.misura.width
        switch fase {
        case .sposta:
            n.punto = CGPoint(x: b.elemento.punto.x + dx, y: b.elemento.punto.y + dy)
        case .destra:
            n.larghezza = max(ElementoTesto.minimo, larghezza0 + dx)
        case .sinistra:
            let w = max(ElementoTesto.minimo, larghezza0 - dx)
            n.larghezza = w
            n.punto.x = b.elemento.punto.x + (larghezza0 - w)
        case .niente:
            return
        }
        inCorso = n
        anteprima(n, pagina: b.pagina)
    }

    private func finisci(_ pv: CGPoint, annullato: Bool) {
        defer { base = nil; inCorso = nil; mosso = false; fase = .niente }
        guard let b = base else { return }
        if mosso {
            if !annullato, let n = inCorso {
                cambia(b.pagina, togli: b.elemento, metti: n)
            } else {
                anteprima(b.elemento, pagina: b.pagina)
            }
        } else if !annullato {
            scelto = (b.pagina, b.elemento)
            mostraSelezione()
            modoMenu = .testo
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
        }
    }

    // MARK: Disegno del testo (livelli vettoriali nella pila della pagina)

    /// Cornice del livello nel contenitore della pagina (punti di pagina, y verso il basso)
    private func cornice(_ e: ElementoTesto, box: CGRect) -> CGRect {
        let r = e.rettangolo
        return CGRect(x: r.minX - box.minX, y: box.maxY - r.maxY, width: r.width, height: r.height)
    }

    /// Nitidezza: il livello è rimpicciolito/ingrandito dallo zoom del PDF
    var scalaContenuto: CGFloat {
        let zoom = vista?.scaleFactor ?? 1
        let schermo = vista?.traitCollection.displayScale ?? 2
        return min(schermo * max(1, zoom), 8)
    }

    /// Livello di testo per la pila della pagina (lo chiama `ImmagineControllo.ridisegna`)
    func creaLivello(_ e: ElementoTesto, box: CGRect) -> CALayer {
        let l = CATextLayer()
        l.name = Self.nomeLivello
        l.string = e.testo
        l.font = CTFontCreateWithName("Helvetica" as CFString, e.corpo, nil)
        l.fontSize = e.corpo
        l.foregroundColor = e.colore.cgColor
        l.alignmentMode = e.larghezza != nil ? .justified : .left     // con il blocco a larghezza fissa le righe occupano tutto lo spazio
        l.isWrapped = e.larghezza != nil
        l.truncationMode = .none
        l.contentsScale = scalaContenuto
        l.frame = cornice(e, box: box)
        livelli[e.id] = l
        return l
    }

    /// Ricostruisce la pila della pagina (tratti, immagini e testi)
    func ridisegna(_ pagina: PDFPage) {
        model?.controlloImmagini?.ridisegna(pagina)
    }

    /// Dopo lo zoom: i testi si ridisegnano con la nitidezza giusta
    func ridisegnaTutte() {
        let s = scalaContenuto
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in livelli.values where l.contentsScale != s { l.contentsScale = s }
        CATransaction.commit()
        mostraSelezione()
    }

    /// Anteprima in tempo reale (spostamento, larghezza): si aggiorna solo il livello del testo
    func anteprima(_ e: ElementoTesto, pagina: PDFPage) {
        guard let l = livelli[e.id] as? CATextLayer else { ridisegna(pagina); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.isWrapped = e.larghezza != nil
        l.alignmentMode = e.larghezza != nil ? .justified : .left
        l.frame = cornice(e, box: pagina.bounds(for: .cropBox))
        CATransaction.commit()
        mostraSelezione(e)
    }

    // MARK: Cornice e maniglie della selezione

    func mostraSelezione(_ ovr: ElementoTesto? = nil) {
        guard let model else { return }
        for (_, cont) in model.contenitori {
            cont.layer.sublayers?.filter { $0.name == Self.nomeSelezione }.forEach { $0.removeFromSuperlayer() }
        }
        guard let (pagina, e0) = scelto, model.corrente?.tipo == .testo,
              let cont = model.contenitori[pagina] else { return }
        let e = ovr ?? elementoAttuale(pagina, e0.id) ?? e0
        let box = pagina.bounds(for: .cropBox)
        let r = e.rettangolo
        let l = CGRect(x: r.minX - box.minX, y: box.maxY - r.maxY, width: r.width, height: r.height)
        let u = unita
        let colore = UIColor(AptTema.accento)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let radice = CALayer()
        radice.name = Self.nomeSelezione
        let c = CAShapeLayer()
        c.path = UIBezierPath(rect: l.insetBy(dx: -2 * u, dy: -2 * u)).cgPath
        c.fillColor = nil
        c.strokeColor = colore.cgColor
        c.lineWidth = 1.5 * u
        c.lineDashPattern = [NSNumber(value: Double(6 * u)), NSNumber(value: Double(4 * u))]
        radice.addSublayer(c)
        for x in [l.minX, l.maxX] {
            let m = CAShapeLayer()
            let raggio = 9 * u
            m.path = UIBezierPath(ovalIn: CGRect(x: x - raggio, y: l.midY - raggio, width: 2 * raggio, height: 2 * raggio)).cgPath
            m.fillColor = UIColor(AptTema.carta).cgColor
            m.strokeColor = colore.cgColor
            m.lineWidth = 2 * u
            radice.addSublayer(m)
        }
        cont.layer.addSublayer(radice)
        CATransaction.commit()
    }

    // MARK: Tocco sulla pagina

    @objc private func toccato(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let model, let vista = model.pdfView,
              let s = model.corrente, s.tipo == .testo else { return }
        let pv = g.location(in: vista)
        guard let pagina = vista.page(for: pv, nearest: false) else { return }
        let pp = vista.convert(pv, to: pagina)

        // Sui testi già messi (e sulle maniglie) lavora il gesto di trascinamento (anche per il menu)
        if elemento(in: pagina, at: pp) != nil { return }
        if let (sp, se) = scelto, sp === pagina, let e = elementoAttuale(sp, se.id), maniglia(e, vicino: pp) != nil { return }
        // Un tocco del dito su un'immagine la seleziona: non si crea un testo
        if ultimoTipo != .pencil, model.controlloImmagini?.haImmagine(in: pagina, at: pp) == true { return }

        // Tocco su un punto vuoto: niente più testo scelto
        if scelto != nil {
            scelto = nil
            mostraSelezione()
        }

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
        let su = UIAction(title: "Porta sopra", image: UIImage(systemName: "square.2.layers.3d.top.filled")) { [weak self] _ in self?.livello(su: true) }
        let giu = UIAction(title: "Porta sotto", image: UIImage(systemName: "square.2.layers.3d.bottom.filled")) { [weak self] _ in self?.livello(su: false) }
        return UIMenu(options: .displayInline, children: [elimina, modifica, taglia, copia, su, giu])
    }

    /// Copia o taglio dal lazo: l'ultimo testo va negli appunti interni
    func copiaInAppunti(_ lista: [ElementoTesto]) {
        if let ultimo = lista.last { Self.appunti = ultimo }
    }

    private func incolla() {
        guard var n = Self.appunti, let (p, pt) = puntoVuoto else { return }
        n.id = UUID()
        n.punto = pt
        n.creazione = Date()
        cambia(p, togli: nil, metti: n)
        scelto = (p, n)
        mostraSelezione()
    }

    private func modifica() {
        guard let (p, e) = scelto, let model else { return }
        model.bozzaTesto = BozzaTesto(pagina: p, punto: e.punto, testo: e.testo, corpo: e.corpo,
                                      colore: e.colore, larghezza: e.larghezza, esistente: e)
    }

    private func elimina() {
        guard let (p, e) = scelto else { return }
        scelto = nil
        cambia(p, togli: e, metti: nil)
    }

    // MARK: Livelli: un passo sopra o sotto

    /// Un livello = il gruppo di tratti adiacente o l'oggetto (immagine o testo) adiacente. Si cambia la data del testo
    /// perché stia subito dopo (sopra) o subito prima (sotto) di quel gruppo.
    private func livello(su: Bool) {
        guard let (p, e0) = scelto, let model, let e = elementoAttuale(p, e0.id) else { return }
        var voci: [(Date, Bool)] = model.tuttiITratti(p).map { ($0.path.creationDate, false) }
        voci += (model.immagini[p] ?? []).map { ($0.creazione, true) }
        voci += (model.testi[p] ?? []).filter { $0.id != e.id }.map { ($0.creazione, true) }
        voci.sort { $0.0 < $1.0 }
        let i = voci.firstIndex { $0.0 > e.creazione } ?? voci.count
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
        cambia(p, togli: e, metti: n)
    }

    // MARK: Conferma dalla finestra di scrittura

    func conferma(_ b: BozzaTesto, testo: String) {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        if pulito.isEmpty {
            if let e = b.esistente { cambia(b.pagina, togli: e, metti: nil) }
            return
        }
        if let e = b.esistente, e.testo == pulito, e.corpo == b.corpo { return }
        var nuovo = b.esistente ?? ElementoTesto(testo: pulito, punto: b.punto, corpo: b.corpo, colore: b.colore)
        nuovo.testo = pulito
        nuovo.corpo = b.corpo
        nuovo.larghezza = b.larghezza
        cambia(b.pagina, togli: b.esistente, metti: nuovo)
        if b.esistente != nil { scelto = (b.pagina, nuovo); mostraSelezione() }
    }

    // MARK: Aggiunta/rimozione con annulla e ripeti

    func cambia(_ p: PDFPage, togli: ElementoTesto?, metti: ElementoTesto?) {
        guard let model else { return }
        var lista = model.testi[p] ?? []
        if let t = togli { lista.removeAll { $0.id == t.id } }
        if let m = metti { lista.append(m) }
        model.testi[p] = lista
        if let s = scelto, s.0 === p {
            if let m = metti, m.id == s.1.id { scelto = (p, m) }
            else if !lista.contains(where: { $0.id == s.1.id }) { scelto = nil }
        }
        model.ripartisci(p, pulisciUndo: false)
        mostraSelezione()
        model.segnaModificato(p)
        model.pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.cambia(p, togli: metti, metti: togli) }
    }

    // MARK: Da e verso il PDF

    /// Annotazione di testo da scrivere nel PDF al salvataggio
    static func annotazione(da e: ElementoTesto) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: e.rettangolo, forType: .freeText, withProperties: nil)
        a.font = ElementoTesto.font(e.corpo)
        a.fontColor = e.colore
        a.color = .clear
        a.alignment = e.larghezza != nil ? .justified : .left
        a.contents = e.testo
        a.userName = nome
        let bordo = PDFBorder()
        bordo.lineWidth = 0
        a.border = bordo
        // larghezza del blocco (0 = automatica) e data di creazione, per riaprire il testo come era
        _ = a.setValue("\(Double(e.larghezza ?? 0)),\(e.creazione.timeIntervalSince1970)", forAnnotationKey: chiaveInfo)
        return a
    }

    private static var ordineLettura = 0

    /// Testo modificabile letto da un'annotazione dell'app
    static func elemento(da a: PDFAnnotation) -> ElementoTesto {
        var e = ElementoTesto(testo: a.contents ?? "",
                              punto: CGPoint(x: a.bounds.minX, y: a.bounds.maxY),
                              corpo: a.font?.pointSize ?? 16,
                              colore: a.fontColor ?? .black)
        if let info = a.value(forAnnotationKey: chiaveInfo) as? String {
            let v = info.split(separator: ",").compactMap { Double($0) }
            if v.count == 2 {
                if v[0] > 0 { e.larghezza = CGFloat(v[0]) }
                e.creazione = Date(timeIntervalSince1970: v[1])
                return e
            }
        }
        // salvato dalla versione precedente: sempre sopra, nell'ordine di lettura
        ordineLettura += 1
        e.creazione = Date().addingTimeInterval(Double(ordineLettura) * 0.001)
        return e
    }
}
