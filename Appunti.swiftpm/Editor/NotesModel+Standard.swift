// Editor: formato standard delle pagine (tutte come un foglio A4, tutte verticali o tutte orizzontali).
import SwiftUI
import PDFKit

extension NotesModel {
    /// Foglio standard: A4 verticale o orizzontale (stessa area, quindi mai più grande l'uno dell'altro)
    static func foglioStandard(orizzontale: Bool) -> CGSize {
        orizzontale ? CGSize(width: 842, height: 595) : CGSize(width: 595, height: 842)
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

    /// Ridisegna una pagina su un foglio standard (contenuto adattato e centrato, senza deformarlo)
    static func paginaStandard(da p: PDFPage, foglio: CGSize) -> PDFPage? {
        guard siPuoRifare(p), let ref = p.pageRef else { return nil }
        let vista = misuraVista(p)
        if abs(vista.width - foglio.width) < 1, abs(vista.height - foglio.height) < 1 { return nil }
        let area = CGRect(origin: .zero, size: foglio)
        let dati = UIGraphicsPDFRenderer(bounds: area).pdfData { ctx in
            ctx.beginPage()
            let g = ctx.cgContext
            g.setFillColor(UIColor.white.cgColor)
            g.fill(area)
            g.translateBy(x: 0, y: foglio.height)
            g.scaleBy(x: 1, y: -1)
            g.concatenate(ref.getDrawingTransform(.cropBox, rect: area, rotate: 0, preserveAspectRatio: true))
            g.drawPDFPage(ref)
        }
        return PDFDocument(data: dati)?.page(at: 0)
    }

    /// Porta tutte le pagine allo stesso formato (verticale o orizzontale, come la maggioranza). Restituisce quante ne ha cambiate.
    @discardableResult
    func uniformaPagine(in doc: PDFDocument) -> Int {
        let n = doc.pageCount
        guard n > 0 else { return 0 }
        // un documento già allargato con «Estendi pagina» non si tocca
        for i in 0..<n {
            if let p = doc.page(at: i), p.annotations.contains(where: { $0.userName == Self.nomeEstensione }) { return 0 }
        }
        var orizzontali = 0
        for i in 0..<n {
            if let p = doc.page(at: i) {
                let m = Self.misuraVista(p)
                if m.width > m.height { orizzontali += 1 }
            }
        }
        foglio = Self.foglioStandard(orizzontale: orizzontali * 2 > n)
        var cambiate = 0
        for i in 0..<n {
            guard let p = doc.page(at: i), let nuova = Self.paginaStandard(da: p, foglio: foglio) else { continue }
            doc.removePage(at: i)
            doc.insert(nuova, at: i)
            cambiate += 1
        }
        return cambiate
    }
}
