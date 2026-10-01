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

    static func aggiungiTesto(_ doc: PDFDocument?) {
        guard let page = doc?.page(at: 0) else { return }
        page.addAnnotation(TestoControllo.crea(testo: "Wsdfg annotazione", punto: CGPoint(x: 40, y: 700), corpo: 24, colore: .black))
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
                        ProvaNitidezza.aggiungiTesto(model.document)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if let p = model.document?.page(at: 0), let c = model.canvases[p] {
                                c.drawing = ProvaNitidezza.tratto()
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
