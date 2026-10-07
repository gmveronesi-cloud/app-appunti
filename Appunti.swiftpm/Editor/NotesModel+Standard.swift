// Editor: pagine tutte della stessa larghezza. Ogni pagina tiene la propria altezza (e quindi il proprio formato):
// una pagina orizzontale tra pagine verticali resta orizzontale, solo rimpicciolita fino alla larghezza comune.
// Niente bordi bianchi aggiunti per far diventare le pagine tutte A4.
import SwiftUI
import PDFKit

extension NotesModel {
    /// Larghezza di partenza per i documenti nuovi (foto): quella di un A4 verticale o orizzontale
    static func larghezzaStandard(orizzontale: Bool) -> CGFloat {
        orizzontale ? 842 : 595
    }

    /// Misura della pagina come si vede (con la rotazione)
    static func misuraVista(_ p: PDFPage) -> CGSize {
        let s = p.bounds(for: .cropBox).size
        return (p.rotation % 180 == 90) ? CGSize(width: s.height, height: s.width) : s
    }

    /// Le pagine con annotazioni di altri programmi (a parte i link) non si toccano: ridisegnarle le perderebbe
    private static func siPuoRifare(_ p: PDFPage) -> Bool {
        for a in p.annotations {
            if let n = a.userName, [nomeDati, nomeTratto, nomeEstensione, ImmagineControllo.nome, TestoControllo.nome].contains(n) { return false }
            if a.type != "Link" { return false }
        }
        return p.pageRef != nil
    }

    /// Ridisegna una pagina alla larghezza indicata (stessa proporzione: contenuto intero, nessuno spazio bianco aggiunto).
    /// Restituisce nil se la pagina è già larga così o non si può rifare.
    static func paginaStandard(da p: PDFPage, larghezza: CGFloat) -> PDFPage? {
        guard larghezza > 0, siPuoRifare(p), let ref = p.pageRef else { return nil }
        let vista = misuraVista(p)
        guard vista.width > 0, vista.height > 0, abs(vista.width - larghezza) >= 1 else { return nil }
        let altezza = vista.height * larghezza / vista.width
        let area = CGRect(origin: .zero, size: CGSize(width: larghezza, height: altezza))
        let dati = UIGraphicsPDFRenderer(bounds: area).pdfData { ctx in
            ctx.beginPage()
            let g = ctx.cgContext
            g.setFillColor(UIColor.white.cgColor)
            g.fill(area)
            g.translateBy(x: 0, y: altezza)
            g.scaleBy(x: 1, y: -1)
            g.concatenate(ref.getDrawingTransform(.cropBox, rect: area, rotate: 0, preserveAspectRatio: true))
            g.drawPDFPage(ref)
        }
        return PDFDocument(data: dati)?.page(at: 0)
    }

    /// Porta tutte le pagine alla stessa larghezza: quella più comune nel documento. Restituisce quante ne ha cambiate.
    @discardableResult
    func uniformaPagine(in doc: PDFDocument) -> Int {
        let n = doc.pageCount
        guard n > 0 else { return 0 }
        // un documento già allargato con «Estendi pagina» non si tocca
        for i in 0..<n {
            if let p = doc.page(at: i), p.annotations.contains(where: { $0.userName == Self.nomeEstensione }) { return 0 }
        }
        // larghezza più comune (a parità vince quella che compare prima)
        var conteggi: [Int: Int] = [:]
        var esempio: [Int: CGFloat] = [:]
        var ordine: [Int] = []
        for i in 0..<n {
            guard let p = doc.page(at: i) else { continue }
            let w = Self.misuraVista(p).width
            guard w > 0 else { continue }
            let chiave = Int(w.rounded())
            if conteggi[chiave] == nil { esempio[chiave] = w; ordine.append(chiave) }
            conteggi[chiave, default: 0] += 1
        }
        var scelta: Int?
        var massimo = 0
        for c in ordine {
            let quante = conteggi[c] ?? 0
            if quante > massimo { massimo = quante; scelta = c }
        }
        guard let scelta, let larghezza = esempio[scelta] else { return 0 }
        larghezzaPagina = larghezza
        var cambiate = 0
        for i in 0..<n {
            guard let p = doc.page(at: i), let nuova = Self.paginaStandard(da: p, larghezza: larghezza) else { continue }
            doc.removePage(at: i)
            doc.insert(nuova, at: i)
            cambiate += 1
        }
        return cambiate
    }
}
