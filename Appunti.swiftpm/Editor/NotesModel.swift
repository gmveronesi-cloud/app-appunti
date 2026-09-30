// Editor PDF: apre il file, gestisce le tele Pencil, salva come annotazioni ink
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

final class NotesModel: NSObject, ObservableObject, PDFPageOverlayViewProvider {
    @Published var document: PDFDocument?
    @Published var fileName: String = ""
    @Published var message: String = ""
    @Published var pencilMode: Bool = true {
        didSet {
            for canvas in canvases.values { canvas.isUserInteractionEnabled = pencilMode }
        }
    }

    // MARK: Strumenti (barra dell'Editor)

    enum Strumento: String { case penna, evidenziatore, gomma }

    // Le impostazioni degli strumenti si ricordano tra una sessione e l'altra (UserDefaults)
    private static let d = UserDefaults.standard

    @Published var strumento: Strumento = .evidenziatore { didSet { Self.d.set(strumento.rawValue, forKey: "ed.strumento"); applicaStrumento() } }
    @Published var colorePenna: Color = Color(red: 0.1, green: 0.1, blue: 0.12) { didSet { Self.salvaColore(colorePenna, "ed.colorePenna"); applicaStrumento() } }
    @Published var coloreEvidenziatore: Color = Color(red: 1.0, green: 0.92, blue: 0.0) { didSet { Self.salvaColore(coloreEvidenziatore, "ed.coloreEvid"); applicaStrumento() } }
    @Published var spessorePenna: Double = 3 { didSet { Self.d.set(spessorePenna, forKey: "ed.spessorePenna"); applicaStrumento() } }
    @Published var spessoreEvidenziatore: Double = 20 { didSet { Self.d.set(spessoreEvidenziatore, forKey: "ed.spessoreEvid"); applicaStrumento() } }
    @Published var gommaTrattoIntero: Bool = false { didSet { Self.d.set(gommaTrattoIntero, forKey: "ed.gommaIntera"); applicaStrumento() } }

    override init() {
        super.init()
        // nell'init i didSet non scattano: si caricano i valori salvati
        if let r = Self.d.string(forKey: "ed.strumento"), let v = Strumento(rawValue: r) { strumento = v }
        if let c = Self.leggiColore("ed.colorePenna") { colorePenna = c }
        if let c = Self.leggiColore("ed.coloreEvid") { coloreEvidenziatore = c }
        if Self.d.object(forKey: "ed.spessorePenna") != nil { spessorePenna = Self.d.double(forKey: "ed.spessorePenna") }
        if Self.d.object(forKey: "ed.spessoreEvid") != nil { spessoreEvidenziatore = Self.d.double(forKey: "ed.spessoreEvid") }
        if Self.d.object(forKey: "ed.gommaIntera") != nil { gommaTrattoIntero = Self.d.bool(forKey: "ed.gommaIntera") }
    }

    private static func salvaColore(_ c: Color, _ chiave: String) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        d.set([Double(r), Double(g), Double(b), Double(a)], forKey: chiave)
    }

    private static func leggiColore(_ chiave: String) -> Color? {
        guard let v = d.array(forKey: chiave) as? [Double], v.count == 4 else { return nil }
        return Color(.sRGB, red: v[0], green: v[1], blue: v[2], opacity: v[3])
    }

    weak var pdfView: PDFView?

    private var fileURL: URL?
    private var hasSecurityScope = false
    private var canvases: [PDFPage: PKCanvasView] = [:]
    // Tratti modificabili letti dal PDF all'apertura, in attesa che la tela della pagina esista
    private var trattiSalvati: [PDFPage: PKDrawing] = [:]
    private static let nomeDati = "AptDati"        // annotazione nascosta con il disegno modificabile
    private static let nomeTratto = "AptTratto"    // annotazioni ink visibili (leggibili da altre app)
    private static let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")

    private var strumentoCorrente: PKTool {
        switch strumento {
        case .penna:
            return PKInkingTool(.pen, color: UIColor(colorePenna), width: CGFloat(spessorePenna))
        case .evidenziatore:
            return PKInkingTool(.marker, color: UIColor(coloreEvidenziatore), width: CGFloat(spessoreEvidenziatore))
        case .gomma:
            return PKEraserTool(gommaTrattoIntero ? .vector : .bitmap)
        }
    }

    private func applicaStrumento() {
        let tool = strumentoCorrente
        for canvas in canvases.values { canvas.tool = tool }
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
        message = "Aperto: \(doc.pageCount) pagine. Scrivi con la Pencil, poi tocca Salva."
    }

    func close() {
        closeCurrent()
    }

    private func closeCurrent() {
        if hasSecurityScope, let u = fileURL { u.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
        fileURL = nil
        canvases.removeAll()
        trattiSalvati.removeAll()
        document = nil
        fileName = ""
    }

    // MARK: Overlay Pencil per ogni pagina

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let existing = canvases[page] { return existing }

        let canvas = PKCanvasView(frame: .zero)
        canvas.drawingPolicy = .pencilOnly          // il dito scorre/zooma il PDF, la Pencil disegna
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false              // così i gesti del dito arrivano al PDF
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = strumentoCorrente
        canvas.isUserInteractionEnabled = pencilMode
        canvases[page] = canvas
        return canvas
    }

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PKCanvasView, let salvato = trattiSalvati[page] else { return }
        let larghezza = canvas.bounds.width
        guard larghezza > 0 else { return }
        let fattore = larghezza / page.bounds(for: .cropBox).width
        canvas.drawing = salvato.transformed(using: CGAffineTransform(scaleX: fattore, y: fattore))
        trattiSalvati[page] = nil
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
            let evidenziatore = stroke.ink.inkType == .marker
            annotation.color = stroke.ink.color.withAlphaComponent(evidenziatore ? 0.4 : 1.0)
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
