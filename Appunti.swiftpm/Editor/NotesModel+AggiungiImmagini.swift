// «Aggiungi pagina» → Immagini: ogni immagine scelta diventa una pagina del documento, dopo la pagina indicata.
import SwiftUI
import PDFKit
import PencilKit

extension NotesModel {
    /// Una pagina grande come l'immagine (A4 di larghezza, verticale o orizzontale a seconda dell'immagine)
    private static func paginaDaImmagine(_ dati: Data) -> PDFPage? {
        guard let img0 = UIImage(data: dati), img0.size.width > 1, img0.size.height > 1 else { return nil }
        let img = ElaboraImmagine.normalizza(img0)
        let larghezza: CGFloat = img.size.width > img.size.height ? 841.8 : 595.2
        let altezza = max((larghezza * img.size.height / img.size.width).rounded(), 100)
        let box = CGRect(x: 0, y: 0, width: larghezza, height: altezza)
        let r = UIGraphicsPDFRenderer(bounds: box)
        let pdf = r.pdfData { ctx in
            ctx.beginPage()
            UIColor.white.setFill()
            ctx.fill(box)
            img.draw(in: box)
        }
        guard let doc = PDFDocument(data: pdf), let p = doc.page(at: 0), let copia = p.copy() as? PDFPage else { return nil }
        copia.setBounds(box, for: .mediaBox)
        copia.setBounds(box, for: .cropBox)
        return copia
    }

    func aggiungiImmaginiComePagine(_ immagini: [Data]) {
        guard let document, document.pageCount > 0 else { message = "Nessun PDF aperto."; return }
        let dopo = min(max(inserisciDopo ?? (document.pageCount - 1), 0), document.pageCount - 1)
        inserisciDopo = nil
        let nuove = immagini.compactMap { Self.paginaDaImmagine($0) }
        guard !nuove.isEmpty else { message = "Non riesco a leggere le immagini scelte."; return }
        lazo?.deseleziona()
        controlloImmagini?.annullaSelezione()
        controlloTesto?.resetta()
        for (n, p) in nuove.enumerated() { document.insert(p, at: dopo + 1 + n) }
        let dati = nuove.map { DatiPagina(pagina: $0, tratti: nil, immagini: [], testi: []) }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        pdfView?.go(to: nuove[0])
        avviso(nuove.count == 1 ? "Aggiunta 1 pagina." : "Aggiunte \(nuove.count) pagine.")
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
    }
}
