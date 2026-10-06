// Vista PDF (UIKit dentro SwiftUI) collegata al modello dell'editor
import SwiftUI
import PDFKit

/// PDFView con limiti di zoom propri: non si può rimpicciolire la pagina oltre una soglia,
/// e l'ingrandimento massimo è fissato (vedi `NotesModel.zoomMassimo`).
final class AptPDFView: PDFView, UIGestureRecognizerDelegate {
    /// Zoom minimo, in rapporto alla pagina a tutta larghezza (1 = pagina larga come la vista)
    static let minimoRelativo: CGFloat = 0.8
    /// Chiamata quando si pizzica ancora oltre lo zoom minimo (apre la griglia delle pagine)
    var oltreIlMinimo: (() -> Void)?
    private var zoomIniziale: CGFloat = 1
    private var scattato = false
    private var pizzico: UIPinchGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard pizzico == nil else { return }
        let p = UIPinchGestureRecognizer(target: self, action: #selector(pizzicato(_:)))
        p.cancelsTouchesInView = false
        p.delegate = self
        addGestureRecognizer(p)
        pizzico = p
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func pizzicato(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            zoomIniziale = scaleFactor
            scattato = false
        case .changed:
            // Zoom che si avrebbe senza il limite: se scende ben sotto il minimo, si apre la griglia
            guard !scattato, minScaleFactor > 0 else { return }
            if zoomIniziale * g.scale < minScaleFactor * 0.85 {
                scattato = true
                oltreIlMinimo?()
            }
        default:
            break
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        aggiornaLimiti()
    }

    func aggiornaLimiti() {
        let adatto = scaleFactorForSizeToFit
        guard adatto > 0 else { return }
        let minimo = adatto * Self.minimoRelativo
        if abs(minScaleFactor - minimo) > 0.001 { minScaleFactor = minimo }
        if abs(maxScaleFactor - NotesModel.zoomMassimo) > 0.001 { maxScaleFactor = NotesModel.zoomMassimo }
    }
}

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var model: NotesModel

    func makeUIView(context: Context) -> PDFView {
        let v = AptPDFView()
        v.autoScales = true
        v.interpolationQuality = .high
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(AptTema.scrivania)
        v.pageOverlayViewProvider = model
        model.pdfView = v
        model.installaGesti(su: v)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== model.document { v.document = model.document }
    }
}
