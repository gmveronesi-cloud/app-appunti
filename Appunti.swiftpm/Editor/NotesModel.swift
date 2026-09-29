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

    weak var pdfView: PDFView?

    private var fileURL: URL?
    private var hasSecurityScope = false
    private var canvases: [PDFPage: PKCanvasView] = [:]
    private var lastAdded: [(PDFPage, PDFAnnotation)] = []

    // Evidenziatore giallo fisso (colore non dinamico, per evitare inversioni in dark mode)
    private let highlighter = PKInkingTool(
        .marker,
        color: UIColor(red: 1.0, green: 0.92, blue: 0.0, alpha: 1.0),
        width: 20
    )

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
        document = doc
        message = "Aperto: \(doc.pageCount) pagine. Evidenzia con la Pencil, poi tocca Salva."
    }

    func close() {
        closeCurrent()
    }

    private func closeCurrent() {
        if hasSecurityScope, let u = fileURL { u.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
        fileURL = nil
        canvases.removeAll()
        lastAdded.removeAll()
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
        canvas.tool = highlighter
        canvas.isUserInteractionEnabled = pencilMode
        canvases[page] = canvas
        return canvas
    }

    // MARK: Scarta

    func discardUnsaved() {
        for canvas in canvases.values { canvas.drawing = PKDrawing() }
        message = "Tratti non salvati scartati."
    }

    // MARK: Salvataggio

    func save() {
        guard let document, let url = fileURL else {
            message = "Nessun PDF aperto."
            return
        }

        lastAdded.removeAll()
        var added = 0
        for (page, canvas) in canvases {
            added += addAnnotations(from: canvas.drawing, canvasSize: canvas.bounds.size, to: page)
        }

        guard added > 0 else {
            message = "Nessun tratto nuovo da salvare."
            return
        }
        guard let data = document.dataRepresentation() else {
            rollback()
            message = "Impossibile generare il PDF."
            return
        }

        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do { try data.write(to: writeURL) } catch { writeError = error }
        }

        if let err = coordError ?? (writeError as NSError?) {
            rollback()
            message = "Errore di scrittura: \(err.localizedDescription)"
            return
        }

        // Ok: i tratti ora sono annotazioni nel PDF, svuoto le tele
        for canvas in canvases.values { canvas.drawing = PKDrawing() }
        for page in Set(lastAdded.map { $0.0 }) { pdfView?.annotationsChanged(on: page) }
        lastAdded.removeAll()
        message = "Salvato in «\(fileName)»: \(added) tratti."
    }

    private func rollback() {
        for (page, annotation) in lastAdded { page.removeAnnotation(annotation) }
        for page in Set(lastAdded.map { $0.0 }) { pdfView?.annotationsChanged(on: page) }
        lastAdded.removeAll()
    }

    // MARK: Conversione tratti Pencil -> annotazioni PDF (ink)

    private func addAnnotations(from drawing: PKDrawing, canvasSize: CGSize, to page: PDFPage) -> Int {
        let pageBounds = page.bounds(for: .cropBox)
        let size = canvasSize.width > 0 ? canvasSize : pageBounds.size
        let scale = pageBounds.width / size.width
        var count = 0

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
            annotation.color = stroke.ink.color.withAlphaComponent(0.4)
            let border = PDFBorder()
            border.lineWidth = lineWidth
            annotation.border = border
            annotation.add(path)

            page.addAnnotation(annotation)
            lastAdded.append((page, annotation))
            count += 1
        }
        return count
    }
}
