// Miniature della griglia delle pagine: la pagina con sopra i suoi tratti (bassa qualità: serve a vedere quali pagine hanno scritto).
import UIKit
import PDFKit
import PencilKit

extension NotesModel {
    /// I tratti della pagina in punti di pagina (dall'angolo in alto a sinistra), sia se la tela c'è sia se è stata buttata o mai mostrata
    func disegnoInPunti(_ page: PDFPage) -> PKDrawing? {
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = page.bounds(for: .cropBox).width / canvas.bounds.width
            return PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
        }
        return trattiSalvati[page]
    }

    /// Miniatura della pagina con i suoi tratti. Immagine piccola (scala 1): pesa poco in memoria.
    func miniatura(_ page: PDFPage, larghezza: CGFloat) -> UIImage {
        Self.disegnaMiniatura(page: page, box: page.bounds(for: .cropBox), disegno: disegnoInPunti(page), larghezza: larghezza)
    }

    /// Le miniature si fanno una alla volta, fuori dal thread principale: aprendo la griglia di un PDF lungo, farle tutte sul principale bloccava l'app
    static let codaMiniature = DispatchQueue(label: "appunti.miniature", qos: .userInitiated)

    /// Come `miniatura`, ma il disegno avviene in sottofondo; `fine` parte sul thread principale
    func miniaturaInSottofondo(_ page: PDFPage, larghezza: CGFloat, fine: @escaping (UIImage) -> Void) {
        let box = page.bounds(for: .cropBox)
        let disegno = disegnoInPunti(page)          // i tratti sono un valore: si copiano qui, il resto lavora per conto suo
        Self.codaMiniature.async {
            var immagine: UIImage?
            autoreleasepool {
                immagine = Self.disegnaMiniatura(page: page, box: box, disegno: disegno, larghezza: larghezza)
            }
            if let immagine { DispatchQueue.main.async { fine(immagine) } }
        }
    }

    static func disegnaMiniatura(page: PDFPage, box: CGRect, disegno: PKDrawing?, larghezza: CGFloat) -> UIImage {
        guard box.width > 1, box.height > 1 else { return page.thumbnail(of: CGSize(width: larghezza, height: larghezza), for: .cropBox) }
        let misura = CGSize(width: larghezza, height: max((larghezza * box.height / box.width).rounded(), 1))
        let base = page.thumbnail(of: misura, for: .cropBox)
        guard let disegno, !disegno.strokes.isEmpty else { return base }
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let rettangolo = CGRect(origin: .zero, size: misura)
        return UIGraphicsImageRenderer(size: misura, format: formato).image { _ in
            base.draw(in: rettangolo)
            var tratti: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                tratti = disegno.image(from: CGRect(origin: .zero, size: box.size), scale: larghezza / box.width)
            }
            tratti?.draw(in: rettangolo)
        }
    }

    /// Porta alla pagina scelta nella griglia. Se la vista è allo zoom minimo (da cui si apre la griglia) tutte le pagine sono già «in vista»
    /// e `go(to:)` non farebbe niente: prima si torna alla pagina a tutta larghezza, poi si va in cima alla pagina.
    func vaiAPaginaDallaGriglia(_ page: PDFPage) {
        guard let v = pdfView else { return }
        let adatto = v.scaleFactorForSizeToFit
        if adatto > 0, v.scaleFactor < adatto * 0.9 {
            v.scaleFactor = adatto
        }
        let box = page.bounds(for: .cropBox)
        let destinazione = PDFDestination(page: page, at: CGPoint(x: box.minX, y: box.maxY))
        v.layoutDocumentView()
        v.go(to: destinazione)
        // Dopo il ricalcolo della vista (la griglia sta chiudendosi) si ripete, così il punto è quello giusto
        DispatchQueue.main.async { [weak v] in v?.go(to: destinazione) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak v] in v?.go(to: destinazione) }
    }
}

/// Miniature già fatte, per non rifarle scorrendo la griglia avanti e indietro. NSCache le butta da sola se la memoria scarseggia.
final class CacheMiniature {
    private let cache: NSCache<NSNumber, UIImage> = {
        let c = NSCache<NSNumber, UIImage>()
        c.countLimit = 60
        return c
    }()

    private func chiave(_ p: PDFPage) -> NSNumber { NSNumber(value: ObjectIdentifier(p).hashValue) }
    func immagine(_ p: PDFPage) -> UIImage? { cache.object(forKey: chiave(p)) }
    func salva(_ i: UIImage, _ p: PDFPage) { cache.setObject(i, forKey: chiave(p)) }
}
