// Da dove arrivano le immagini dello strumento Immagine: foto, file immagine, PDF o documenti di testo
// (convertiti in immagini, una per pagina) e scansione di un foglio con la fotocamera.
import SwiftUI
import PDFKit
import VisionKit

enum OrigineImmagine { case foto, file, documento, scansione }

/// PDF (o testo, RTF, HTML) aperto per scegliere le pagine da mettere sulla pagina attuale
struct DocumentoScelto: Identifiable {
    let id = UUID()
    let documento: PDFDocument
    let nome: String
}

enum ConvertitoreDocumento {
    /// Apre un PDF; testo semplice, RTF e HTML vengono impaginati in un PDF A4 temporaneo.
    static func pdf(da url: URL) -> PDFDocument? {
        let accesso = url.startAccessingSecurityScopedResource()
        defer { if accesso { url.stopAccessingSecurityScopedResource() } }
        guard let dati = try? Data(contentsOf: url) else { return nil }
        switch url.pathExtension.lowercased() {
        case "pdf":
            return PDFDocument(data: dati)
        case "rtf":
            guard let a = try? NSAttributedString(data: dati, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                  documentAttributes: nil) else { return nil }
            return paginato(a)
        case "html", "htm":
            guard let a = try? NSAttributedString(data: dati, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                       .characterEncoding: String.Encoding.utf8.rawValue],
                                                  documentAttributes: nil) else { return nil }
            return paginato(a)
        default:
            let testo = String(data: dati, encoding: .utf8) ?? String(data: dati, encoding: .isoLatin1) ?? ""
            return paginato(NSAttributedString(string: testo, attributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black]))
        }
    }

    /// Testo su pagine A4 con margini
    static func paginato(_ testo: NSAttributedString) -> PDFDocument? {
        let pagina = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margine: CGFloat = 48
        let fs = CTFramesetterCreateWithAttributedString(testo)
        let dati = UIGraphicsPDFRenderer(bounds: pagina).pdfData { ctx in
            var inizio = 0
            repeat {
                ctx.beginPage()
                let c = ctx.cgContext
                c.saveGState()
                c.translateBy(x: 0, y: pagina.height)
                c.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: margine, y: margine, width: pagina.width - 2 * margine,
                                               height: pagina.height - 2 * margine), transform: nil)
                let frame = CTFramesetterCreateFrame(fs, CFRange(location: inizio, length: 0), path, nil)
                CTFrameDraw(frame, c)
                let visibile = CTFrameGetVisibleStringRange(frame)
                c.restoreGState()
                if visibile.length == 0 { break }
                inizio += visibile.length
            } while inizio < testo.length
        }
        return PDFDocument(data: dati)
    }

    /// Una pagina come immagine JPEG, su fondo bianco
    static func immagine(_ page: PDFPage, lato: CGFloat = 2000) -> Data? {
        let r = page.bounds(for: .cropBox)
        guard r.width > 0, r.height > 0 else { return nil }
        let s = lato / max(r.width, r.height)
        let misura = CGSize(width: r.width * s, height: r.height * s)
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let img = UIGraphicsImageRenderer(size: misura, format: formato).image { c in
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: misura))
            let g = c.cgContext
            g.translateBy(x: 0, y: misura.height)
            g.scaleBy(x: s, y: -s)
            g.translateBy(x: -r.minX, y: -r.minY)
            page.draw(with: .cropBox, to: g)
        }
        return img.jpegData(compressionQuality: 0.9)
    }
}

/// Scansione di un foglio con la fotocamera (strumento di sistema)
struct ScannerDocumento: UIViewControllerRepresentable {
    let alTermine: ([Data]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let v = VNDocumentCameraViewController()
        v.delegate = context.coordinator
        return v
    }

    func updateUIViewController(_ v: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinatore { Coordinatore(alTermine: alTermine) }

    final class Coordinatore: NSObject, VNDocumentCameraViewControllerDelegate {
        let alTermine: ([Data]) -> Void
        init(alTermine: @escaping ([Data]) -> Void) { self.alTermine = alTermine }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pagine = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) }
            alTermine(pagine)
        }

        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { alTermine([]) }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { alTermine([]) }
    }
}

/// Miniature delle pagine del documento: si toccano quelle da aggiungere
struct SceltaPagine: View {
    let scelto: DocumentoScelto
    let aggiungi: ([Int]) -> Void
    let annulla: () -> Void
    @State private var selezionate: Set<Int> = [0]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scelto.nome).font(AptTema.titoloMedio).foregroundColor(AptTema.testo).lineLimit(1)
                Spacer()
                Button("Annulla", action: annulla).buttonStyle(AptStileSecondario())
                Button("Aggiungi \(selezionate.count)") { aggiungi(selezionate.sorted()) }
                    .buttonStyle(AptStilePrimario())
                    .disabled(selezionate.isEmpty)
            }
            .padding(16)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    ForEach(0..<scelto.documento.pageCount, id: \.self) { i in
                        Button {
                            if selezionate.contains(i) { selezionate.remove(i) } else { selezionate.insert(i) }
                        } label: {
                            VStack(spacing: 4) {
                                miniatura(i)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(selezionate.contains(i) ? AptTema.accento : AptTema.linea,
                                                          lineWidth: selezionate.contains(i) ? 3 : 1)
                                    )
                                Text("\(i + 1)").font(AptTema.dettaglio)
                                    .foregroundColor(selezionate.contains(i) ? AptTema.accentoTesto : AptTema.testo2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func miniatura(_ i: Int) -> some View {
        let img = scelto.documento.page(at: i)?.thumbnail(of: CGSize(width: 220, height: 300), for: .cropBox)
        return Group {
            if let img { Image(uiImage: img).resizable().scaledToFit() } else { Color.gray.opacity(0.2) }
        }
        .frame(height: 140)
        .background(Color.white)
    }
}
