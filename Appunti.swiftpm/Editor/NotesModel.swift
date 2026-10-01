// Editor PDF: apre il file, gestisce le tele Pencil, salva come annotazioni ink
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

final class NotesModel: NSObject, ObservableObject, PDFPageOverlayViewProvider, UIGestureRecognizerDelegate, UIPencilInteractionDelegate, PKCanvasViewDelegate {
    @Published var document: PDFDocument?
    @Published var fileName: String = ""
    @Published var message: String = ""
    @Published var pencilMode: Bool = true {
        didSet { aggiornaInterazione() }
    }

    // MARK: Strumenti (barra dell'Editor)

    // Tutto si ricorda tra una sessione e l'altra (UserDefaults)
    private static let d = UserDefaults.standard

    @Published var strumenti: [Strumento] { didSet { salvaStrumenti(); applicaStrumento() } }
    @Published var selezionato: UUID? {
        didSet {
            if let s = selezionato { Self.d.set(s.uuidString, forKey: "ed.selezionato") }
            applicaStrumento()
        }
    }
    /// Pallini colore fissi a lato della barra (numero modificabile)
    @Published var pallini: [ColoreSalvato] { didSet { Self.salva(pallini, "ed.pallini") } }

    @Published var ditoDisegna: Bool {
        didSet {
            Self.d.set(ditoDisegna, forKey: "ed.ditoDisegna")
            for canvas in canvases.values { canvas.drawingPolicy = ditoDisegna ? .anyInput : .pencilOnly }
            aggiornaInterazione()
        }
    }
    @Published var dueDitaAnnulla: Bool { didSet { Self.d.set(dueDitaAnnulla, forKey: "ed.dueDita") } }
    /// Tenendo ferma la Pencil a fine tratto: retta o forma (rettangolo, quadrato, ellisse, cerchio)
    @Published var formeFerma: Bool {
        didSet {
            Self.d.set(formeFerma, forKey: "ed.formeFerma")
            aggiornaInterazione()
        }
    }
    @Published var doppioTocco: DoppioTocco { didSet { Self.d.set(doppioTocco.rawValue, forKey: "ed.doppioTocco") } }

    /// Strumento usato subito prima di quello attuale (per il doppio tocco sulla Pencil)
    private var precedente: UUID?

    var corrente: Strumento? {
        strumenti.first { $0.id == selezionato } ?? strumenti.first
    }

    override init() {
        let salvati: [Strumento]? = Self.leggi("ed.strumenti2")
        let lista = (salvati?.isEmpty == false) ? salvati! : Strumento.predefiniti
        strumenti = lista
        if let t = Self.d.string(forKey: "ed.selezionato"), let u = UUID(uuidString: t), lista.contains(where: { $0.id == u }) {
            selezionato = u
        } else {
            selezionato = lista.first?.id
        }
        pallini = Self.leggi("ed.pallini") ?? ColoreSalvato.pallini
        ditoDisegna = Self.d.bool(forKey: "ed.ditoDisegna")
        dueDitaAnnulla = Self.d.object(forKey: "ed.dueDita") == nil ? true : Self.d.bool(forKey: "ed.dueDita")
        doppioTocco = DoppioTocco(rawValue: Self.d.string(forKey: "ed.doppioTocco") ?? "") ?? .gomma
        formeFerma = Self.d.object(forKey: "ed.formeFerma") == nil ? true : Self.d.bool(forKey: "ed.formeFerma")
        super.init()
    }

    private static func salva<T: Encodable>(_ v: T, _ chiave: String) {
        if let dati = try? JSONEncoder().encode(v) { d.set(dati, forKey: chiave) }
    }

    private static func leggi<T: Decodable>(_ chiave: String) -> T? {
        guard let dati = d.data(forKey: chiave) else { return nil }
        return try? JSONDecoder().decode(T.self, from: dati)
    }

    private func salvaStrumenti() { Self.salva(strumenti, "ed.strumenti2") }

    // Selezione e modifica degli strumenti

    func seleziona(_ id: UUID?) {
        guard let id, id != selezionato else { return }
        precedente = selezionato
        selezionato = id
    }

    func modifica(_ id: UUID, _ cambio: (inout Strumento) -> Void) {
        guard let i = strumenti.firstIndex(where: { $0.id == id }) else { return }
        cambio(&strumenti[i])
    }

    func aggiungi(_ tipo: TipoStrumento) {
        let nuovo = Strumento.nuovo(tipo)
        strumenti.append(nuovo)
        seleziona(nuovo.id)
    }

    func rimuovi(at offsets: IndexSet) {
        strumenti.remove(atOffsets: offsets)
        if !strumenti.contains(where: { $0.id == selezionato }) { selezionato = strumenti.first?.id }
    }

    func sposta(from: IndexSet, to: Int) { strumenti.move(fromOffsets: from, toOffset: to) }

    /// Colore di un pallino: si applica allo strumento attivo (se ha un colore).
    func scegliColore(_ c: ColoreSalvato) {
        guard let id = corrente?.id, corrente?.tipo.haColore == true else { return }
        modifica(id) { $0.colore = c }
    }

    /// Cambia il colore del pallino i; se lo strumento attivo lo usava, lo segue.
    func cambiaPallino(_ i: Int, _ c: ColoreSalvato) {
        guard pallini.indices.contains(i) else { return }
        let vecchio = pallini[i]
        pallini[i] = c
        if let cur = corrente, cur.tipo.haColore, cur.colore.simile(a: vecchio) {
            modifica(cur.id) { $0.colore = c }
        }
    }

    func impostaNumeroPallini(_ n: Int) {
        let n = max(2, min(8, n))
        while pallini.count < n { pallini.append(.grigio) }
        if pallini.count > n { pallini.removeLast(pallini.count - n) }
    }

    weak var pdfView: PDFView?

    /// true se ci sono tratti non ancora salvati nel PDF
    private(set) var modificato = false
    private var caricando = false

    /// Salva solo se serve (cambio scheda, uscita dal documento).
    func salvaSeModificato() {
        if modificato { save() }
    }

    func segnaModificato() { modificato = true }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if !caricando { modificato = true }
    }

    /// Testi messi sulle pagine (disegnati da noi; nel PDF salvato sono annotazioni di testo)
    var testi: [PDFPage: [ElementoTesto]] = [:]
    private var fileURL: URL?
    private var hasSecurityScope = false
    var canvases: [PDFPage: PKCanvasView] = [:]
    private var contenitori: [PDFPage: PaginaTela] = [:]
    // Tratti modificabili letti dal PDF all'apertura, in attesa che la tela della pagina esista
    private var trattiSalvati: [PDFPage: PKDrawing] = [:]
    private static let nomeDati = "AptDati"        // annotazione nascosta con il disegno modificabile
    private static let nomeTratto = "AptTratto"    // annotazioni ink visibili (leggibili da altre app)
    private static let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")

    /// Le tele Pencil sono `risoluzione` volte più grandi della pagina e rimpicciolite di altrettanto
    /// (vedi `PaginaTela`): PencilKit le disegna così con più dettagli e i tratti restano nitidi con lo zoom.
    static let risoluzione: CGFloat = 3

    private var strumentoCorrente: PKTool {
        corrente?.pkTool(scala: Self.risoluzione) ?? PKInkingTool(.pen, color: .black, width: 3 * Self.risoluzione)
    }

    private func applicaStrumento() {
        let tool = strumentoCorrente
        for canvas in canvases.values { canvas.tool = tool }
        aggiornaInterazione()
    }

    /// Con il lazo attivo le tele non disegnano: la Pencil è seguita dal gesto del lazo.
    private func aggiornaInterazione() {
        let lazoAttivo = corrente?.tipo == .lazo
        for canvas in canvases.values { canvas.isUserInteractionEnabled = pencilMode && tela }
        let testoAttivo = corrente?.tipo == .testo
        controlloTesto?.tocco.isEnabled = testoAttivo
        if !testoAttivo { controlloTesto?.resetta() }

        // Forme con la Pencil ferma: solo con penne, evidenziatori e matite
        var disegna = false
        switch corrente?.tipo {
        case .penna?, .evidenziatore?, .matita?: disegna = true
        default: disegna = false
        }
        forme?.gesto.isEnabled = formeFerma && pencilMode && disegna

        guard let lazo else { return }
        lazo.gesto.isEnabled = pencilMode && lazoAttivo
        let tipi: [UITouch.TouchType] = ditoDisegna ? [.direct, .pencil] : [.pencil]
        lazo.gesto.allowedTouchTypes = tipi.map { NSNumber(value: $0.rawValue) }
        if !lazoAttivo { lazo.deseleziona() }
    }

    private(set) var lazo: LazoSelezione?
    private(set) var forme: FormePencil?
    private(set) var controlloTesto: TestoControllo?
    /// Testo in scrittura (finestra con la nostra tastiera)
    @Published var bozzaTesto: BozzaTesto?

    func confermaTesto(_ b: BozzaTesto, _ t: String) {
        controlloTesto?.conferma(b, testo: t)
        bozzaTesto = nil
    }

    /// Penna, evidenziatore, matita e gomma disegnano sulla tela; lazo e testo no.
    private var tela: Bool { corrente?.tipo != .lazo && corrente?.tipo != .testo }

    // MARK: Gesti: tocco con due dita e doppio tocco sulla Pencil

    func installaGesti(su v: PDFView) {
        let due = UITapGestureRecognizer(target: self, action: #selector(dueDitaTap))
        due.numberOfTouchesRequired = 2
        due.cancelsTouchesInView = false
        due.delegate = self
        v.addGestureRecognizer(due)
        let pi = UIPencilInteraction()
        pi.delegate = self
        v.addInteraction(pi)
        let l = LazoSelezione(model: self)
        lazo = l
        v.addGestureRecognizer(l.gesto)
        v.addInteraction(l.menu)
        let f = FormePencil(model: self)
        forme = f
        v.addGestureRecognizer(f.gesto)
        let tc = TestoControllo(model: self)
        controlloTesto = tc
        v.addGestureRecognizer(tc.tocco)
        v.addInteraction(tc.menu)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomCambiato), name: .PDFViewScaleChanged, object: v)
        aggiornaInterazione()
    }

    @objc private func dueDitaTap() {
        if dueDitaAnnulla { annulla() }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { doppioToccoPencil() }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { doppioToccoPencil() }

    private func doppioToccoPencil() {
        switch doppioTocco {
        case .niente:
            break
        case .precedente:
            seleziona(precedente)
        case .gomma:
            if corrente?.tipo == .gomma { seleziona(precedente) }
            else if let g = strumenti.first(where: { $0.tipo == .gomma }) { seleziona(g.id) }
        }
    }

    func annulla() { pdfView?.undoManager?.undo() }
    func ripeti() { pdfView?.undoManager?.redo() }

    // MARK: Apertura

    func open(url: URL) {
        closeCurrent()

        // Se il file sta dentro la cartella radice già autorizzata, la richiesta può
        // restituire false pur avendo accesso: si prosegue comunque e si prova a leggere.
        hasSecurityScope = url.startAccessingSecurityScopedResource()
        fileURL = url

        var coordError: NSError?
        var readError: Error?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            do { data = try Data(contentsOf: readURL) } catch { readError = error }
        }

        if let err = coordError ?? (readError as NSError?) {
            message = "Errore di lettura: \(err.localizedDescription)"
            closeCurrent()
            return
        }
        guard let data, let doc = PDFDocument(data: data) else {
            message = "Il file non è un PDF leggibile."
            closeCurrent()
            return
        }

        fileName = url.lastPathComponent
        caricaTratti(da: doc)
        document = doc
        message = ""
    }

    func close() {
        closeCurrent()
    }

    private func closeCurrent() {
        lazo?.deseleziona()
        if hasSecurityScope, let u = fileURL { u.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
        fileURL = nil
        canvases.removeAll()
        contenitori.removeAll()
        trattiSalvati.removeAll()
        testi.removeAll()
        document = nil
        fileName = ""
        modificato = false
    }

    // MARK: Overlay Pencil per ogni pagina

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let esistente = contenitori[page] { return esistente }

        let contenitore = PaginaTela(dimensione: page.bounds(for: .cropBox).size, k: Self.risoluzione)
        let canvas = contenitore.canvas
        canvas.delegate = self
        canvas.drawingPolicy = ditoDisegna ? .anyInput : .pencilOnly   // di base il dito scorre/zooma il PDF, la Pencil disegna
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false              // così i gesti del dito arrivano al PDF
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = strumentoCorrente
        canvas.isUserInteractionEnabled = pencilMode && tela
        contenitori[page] = contenitore
        canvases[page] = canvas
        return contenitore
    }

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = (overlayView as? PaginaTela)?.canvas else { return }
        DispatchQueue.main.async { [weak self] in self?.controlloTesto?.ridisegna(page) }
        guard let salvato = trattiSalvati[page] else { return }
        let larghezza = canvas.bounds.width
        guard larghezza > 0 else { return }
        let fattore = larghezza / page.bounds(for: .cropBox).width
        caricando = true
        canvas.drawing = salvato.transformed(using: CGAffineTransform(scaleX: fattore, y: fattore))
        caricando = false
        trattiSalvati[page] = nil
    }

    // Lo zoom cambia la nitidezza del testo (disegnato da noi): si ridisegna a zoom fermo
    private var attesaZoom: Timer?

    @objc private func zoomCambiato() {
        attesaZoom?.invalidate()
        attesaZoom = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.controlloTesto?.ridisegnaTutte()
        }
    }

    // MARK: Lettura dei tratti salvati nel PDF


    /// Toglie dal documento in memoria le annotazioni dell'app (tratti visibili e dati nascosti):
    /// i tratti tornano modificabili sulla tela e a ogni salvataggio vengono rigenerati.
    private func caricaTratti(da doc: PDFDocument) {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for a in page.annotations {
                if a.userName == Self.nomeDati {
                    if let testo = a.value(forAnnotationKey: Self.chiaveDati) as? String,
                       let dati = Data(base64Encoded: testo),
                       let disegno = try? PKDrawing(data: dati) {
                        trattiSalvati[page] = disegno
                    }
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomeTratto {
                    page.removeAnnotation(a)
                } else if a.userName == TestoControllo.nome {
                    testi[page, default: []].append(TestoControllo.elemento(da: a))
                    page.removeAnnotation(a)
                }
            }
        }
    }

    // MARK: Scarta

    func discardUnsaved() {
        guard let url = fileURL else { return }
        pdfView?.undoManager?.removeAllActions()
        open(url: url)              // riapre dal file: tornano solo i tratti già salvati
        message = "Tratti non salvati scartati."
    }

    // MARK: Salvataggio

    func save() {
        guard let document, let url = fileURL else {
            message = "Nessun PDF aperto."
            return
        }

        // Per ogni pagina: tratti visibili (ink) + disegno modificabile in un'annotazione nascosta
        var aggiunte: [(PDFPage, PDFAnnotation)] = []
        var tratti = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for e in testi[page] ?? [] {
                let a = TestoControllo.annotazione(da: e)
                page.addAnnotation(a)
                aggiunte.append((page, a))
            }
            let box = page.bounds(for: .cropBox)
            var disegno: PKDrawing?
            if let canvas = canvases[page], canvas.bounds.width > 0 {
                let f = box.width / canvas.bounds.width
                disegno = canvas.drawing.transformed(using: CGAffineTransform(scaleX: f, y: f))
            } else if let ancora = trattiSalvati[page] {
                disegno = ancora          // pagina mai mostrata: i tratti letti restano com'erano
            }
            guard let d = disegno, !d.strokes.isEmpty else { continue }
            let nuove = addAnnotations(from: d, canvasSize: box.size, to: page)
            aggiunte += nuove.map { (page, $0) }
            tratti += nuove.count

            let dati = PDFAnnotation(bounds: CGRect(x: box.minX, y: box.minY, width: 1, height: 1), forType: .square, withProperties: nil)
            dati.userName = Self.nomeDati
            dati.shouldDisplay = false
            dati.shouldPrint = false
            _ = dati.setValue(d.dataRepresentation().base64EncodedString(), forAnnotationKey: Self.chiaveDati)
            page.addAnnotation(dati)
            aggiunte.append((page, dati))
        }

        let data = document.dataRepresentation()
        // In memoria le annotazioni non servono: i tratti restano sulle tele
        for (page, a) in aggiunte { page.removeAnnotation(a) }
        guard let data else {
            message = "Impossibile generare il PDF."
            return
        }

        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do { try data.write(to: writeURL) } catch { writeError = error }
        }
        if let err = coordError ?? (writeError as NSError?) {
            message = "Errore di scrittura: \(err.localizedDescription)"
            return
        }
        modificato = false
        message = "Salvato in «\(fileName)»: \(tratti) tratti."
    }

    // MARK: Conversione tratti Pencil -> annotazioni PDF (ink)

    private func addAnnotations(from drawing: PKDrawing, canvasSize: CGSize, to page: PDFPage) -> [PDFAnnotation] {
        let pageBounds = page.bounds(for: .cropBox)
        let size = canvasSize.width > 0 ? canvasSize : pageBounds.size
        let scale = pageBounds.width / size.width
        var create: [PDFAnnotation] = []

        for stroke in drawing.strokes {
            let points = Array(stroke.path.interpolatedPoints(by: .distance(3)))
            guard points.count > 1 else { continue }

            let avgWidth = points.map { $0.size.width }.reduce(0, +) / CGFloat(points.count)
            let lineWidth = max(avgWidth * scale, 1)

            let path = UIBezierPath()
            for (i, p) in points.enumerated() {
                let loc = p.location.applying(stroke.transform)
                // Canvas: origine in alto a sinistra. PDF: origine in basso a sinistra.
                let pt = CGPoint(
                    x: pageBounds.minX + loc.x * scale,
                    y: pageBounds.maxY - loc.y * scale
                )
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }

            let bounds = path.bounds.insetBy(dx: -lineWidth, dy: -lineWidth)
            // Il percorso di un'annotazione ink è relativo all'origine dei suoi bounds
            path.apply(CGAffineTransform(translationX: -bounds.origin.x, y: -bounds.origin.y))

            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            // Evidenziatore: semitrasparente. Penna: colore pieno.
            // Il vecchio evidenziatore (marker) va reso più trasparente; quello nuovo (linea semitrasparente) ha già il suo valore
            let vecchioMarker = stroke.ink.inkType == .marker
            annotation.color = vecchioMarker ? stroke.ink.color.withAlphaComponent(0.4 * stroke.ink.color.cgColor.alpha) : stroke.ink.color
            let border = PDFBorder()
            border.lineWidth = lineWidth
            annotation.border = border
            annotation.add(path)

            annotation.userName = Self.nomeTratto
            page.addAnnotation(annotation)
            create.append(annotation)
        }
        return create
    }
}
