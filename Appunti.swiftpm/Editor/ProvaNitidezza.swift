// SOLO DIAGNOSTICA (si attiva solo con la variabile APT_PROVA nel simulatore di GitHub Actions):
// apre un PDF generato con testo vettoriale, un testo annotato e un tratto, per fotografare la nitidezza.
import SwiftUI
import PDFKit
import PencilKit

enum ProvaNitidezza {
    static var modo: String? { ProcessInfo.processInfo.environment["APT_PROVA"] }

    /// PDF di prova: una riga di testo vettoriale a 24 pt
    static func creaPDF() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prova.pdf")
        let r = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try? r.writePDF(to: url) { ctx in
            ctx.beginPage()
            ("Testo nel PDF originale" as NSString).draw(at: CGPoint(x: 40, y: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        return url
    }

    static func elementoProva() -> ElementoTesto {
        ElementoTesto(testo: "Wsdfg annotazione", punto: CGPoint(x: 40, y: 700), corpo: 24, colore: UIColor.black)
    }

    /// Testo come annotazione di PDFKit (il modo vecchio, usato dalla vista B di confronto)
    static func aggiungiTesto(_ doc: PDFDocument?) {
        guard let page = doc?.page(at: 0) else { return }
        page.addAnnotation(TestoControllo.annotazione(da: elementoProva()))
    }

    /// Esperimento G: scala di disegno su tutta la gerarchia (viste e livelli, anche Metal)
    static func scalaTutto(_ v: UIView, _ s: CGFloat) {
        v.contentScaleFactor = s
        scalaLivello(v.layer, s)
        for sub in v.subviews { scalaTutto(sub, s) }
    }

    static func scalaLivello(_ l: CALayer, _ s: CGFloat) {
        l.contentsScale = s
        if let m = l as? CAMetalLayer { m.drawableSize = CGSize(width: m.bounds.width * s, height: m.bounds.height * s) }
        for sub in l.sublayers ?? [] { scalaLivello(sub, s) }
    }

    static func descrivi(_ c: PKCanvasView, _ v: PDFView, _ m: CGFloat) -> String {
        var righe: [String] = []
        righe.append("pdfView.scaleFactor=\(v.scaleFactor) screenScale=\(c.traitCollection.displayScale)")
        righe.append("canvas.bounds=\(c.bounds) frame=\(c.frame) transform=\(c.transform)")
        righe.append("canvas su schermo: \(c.convert(c.bounds, to: v)) -> ingrandimento misurato \(m)")
        righe.append("canvas.contentScaleFactor=\(c.contentScaleFactor) zoomScale=\(c.zoomScale)")
        func vista(_ x: UIView, _ d: Int) {
            let pad = String(repeating: "  ", count: d)
            righe.append("\(pad)V \(type(of: x)) bounds=\(x.bounds.size) csf=\(x.contentScaleFactor) layer=\(type(of: x.layer)) cs=\(x.layer.contentsScale)")
            func liv(_ l: CALayer, _ dd: Int) {
                for sl in l.sublayers ?? [] {
                    righe.append("\(pad)  L \(type(of: sl)) bounds=\(sl.bounds.size) cs=\(sl.contentsScale)")
                    if dd < 2 { liv(sl, dd + 1) }
                }
            }
            liv(x.layer, 0)
            if d < 4 { for sub in x.subviews { vista(sub, d + 1) } }
        }
        vista(c, 0)
        return righe.joined(separator: "\n")
    }

    static func scrivi(_ modo: String, _ testo: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/diag-\(modo).txt")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? testo.write(to: url, atomically: true, encoding: .utf8)
    }

    static func tratto() -> PKDrawing {
        var punti: [PKStrokePoint] = []
        for i in 0...120 {
            let t = CGFloat(i) / 120
            punti.append(PKStrokePoint(location: CGPoint(x: 40 + 400 * t, y: 220 + 60 * sin(t * 9)),
                                       timeOffset: TimeInterval(i) * 0.01, size: CGSize(width: 3, height: 3),
                                       opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
        }
        let s = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: punti, creationDate: Date()))
        return PKDrawing(strokes: [s])
    }
}

/// A = come l'Editor (con le tele Pencil sopra le pagine), B = PDFView semplice, senza tele
struct ProvaNitidezzaView: View {
    let modo: String
    @StateObject private var model = NotesModel()
    private let url = ProvaNitidezza.creaPDF()

    var body: some View {
        Group {
            if modo == "B" {
                PDFSemplice(url: url)
            } else {
                PDFKitView(model: model)
                    .onAppear {
                        model.open(url: url)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if let p = model.document?.page(at: 0), let c = model.canvases[p] {
                                c.drawing = ProvaNitidezza.tratto()
                                // come nell'Editor: testo disegnato da noi sopra la tela
                                model.testi[p] = [ProvaNitidezza.elementoProva()]
                                model.controlloTesto?.ridisegna(p)
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            guard let p = model.document?.page(at: 0), let c = model.canvases[p], let v = model.pdfView else { return }
                            let sullo = c.convert(c.bounds, to: v).width
                            let m = max(1, sullo / c.bounds.width)
                            if modo == "G" { ProvaNitidezza.scalaTutto(c, c.traitCollection.displayScale * m) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                ProvaNitidezza.scrivi(modo, ProvaNitidezza.descrivi(c, v, m))
                            }
                        }
                    }
            }
        }
        .ignoresSafeArea()
    }
}

private struct PDFSemplice: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.document = PDFDocument(url: url)
        ProvaNitidezza.aggiungiTesto(v.document)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}
