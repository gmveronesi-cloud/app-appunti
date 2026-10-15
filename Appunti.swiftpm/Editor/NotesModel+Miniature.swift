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
        let box = page.bounds(for: .cropBox)
        guard box.width > 1, box.height > 1 else { return page.thumbnail(of: CGSize(width: larghezza, height: larghezza), for: .cropBox) }
        let misura = CGSize(width: larghezza, height: max((larghezza * box.height / box.width).rounded(), 1))
        let base = page.thumbnail(of: misura, for: .cropBox)
        guard let disegno = disegnoInPunti(page), !disegno.strokes.isEmpty else { return base }
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
