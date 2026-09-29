// Vista PDF (UIKit dentro SwiftUI) collegata al modello dell'editor
import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var model: NotesModel

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .systemGray5
        v.pageOverlayViewProvider = model
        model.pdfView = v
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== model.document { v.document = model.document }
    }
}
