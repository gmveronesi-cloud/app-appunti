// Penna screenshot: con la Pencil si traccia un riquadro o un contorno a mano libera sulla pagina;
// all'alzata la parte scelta (pagina, tratti, immagini e testi come si vedono) diventa un'immagine.
// Destinazione (impostazione dell'ingranaggio): vassoio (di base), appunti, nel foglio, foglio di condivisione (per Foto).
import SwiftUI
import PDFKit
import UIKit

enum DestinazioneCattura: String, CaseIterable, Identifiable {
    case vassoio, appunti, foglio, condividi

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .vassoio: return "Vassoio"
        case .appunti: return "Appunti"
        case .foglio: return "Nel foglio"
        case .condividi: return "Foto o condividi"
        }
    }
}

final class CatturaSchermo: NSObject, UIGestureRecognizerDelegate {
    weak var model: NotesModel?
    let gesto = LazoGesto()

    private var tracciato: [CGPoint] = []          // punti in coordinate della vista PDF
    private let linea = CAShapeLayer()

    init(model: NotesModel) {
        self.model = model
        super.init()
        gesto.delegate = self
        gesto.isEnabled = false
        gesto.cancelsTouchesInView = true
        gesto.alInizio = { [weak self] p in self?.inizia(p) }
        gesto.alMovimento = { [weak self] p in self?.muovi(p) }
        gesto.allaFine = { [weak self] _, annullato in self?.finisci(annullato: annullato) }

        let colore = UIColor(AptTema.accento)
        linea.strokeColor = colore.cgColor
        linea.fillColor = colore.withAlphaComponent(0.08).cgColor
        linea.lineWidth = 1.5
        linea.lineDashPattern = [6, 4]
        linea.lineJoin = .round
        linea.zPosition = 10_000
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

    private var vista: PDFView? { model?.pdfView }
    private var riquadro: Bool { model?.corrente?.catturaRiquadro ?? false }

    // MARK: Gesto

    private func inizia(_ p: CGPoint) {
        guard let vista else { return }
        tracciato = [p]
        if linea.superlayer !== vista.layer { vista.layer.addSublayer(linea) }
        aggiorna()
    }

    private func muovi(_ p: CGPoint) {
        tracciato.append(p)
        aggiorna()
    }

    private func finisci(annullato: Bool) {
        let punti = tracciato
        tracciato = []
        linea.isHidden = true
        linea.removeFromSuperlayer()
        linea.isHidden = false
        guard !annullato, let vista, let forma = forma(punti) else { return }
        let r = forma.bounds.intersection(vista.bounds)
        guard r.width > 12, r.height > 12 else { return }
        guard let img = immagine(vista, forma, r) else {
            model?.avviso("Cattura non riuscita.")
            return
        }
        consegna(img, r)
    }

    // MARK: Disegno del contorno

    private func forma(_ punti: [CGPoint]) -> UIBezierPath? {
        if riquadro, let a = punti.first, let b = punti.last {
            return UIBezierPath(rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
        }
        guard punti.count > 2 else { return nil }
        let p = UIBezierPath()
        p.move(to: punti[0])
        for q in punti.dropFirst() { p.addLine(to: q) }
        p.close()
        return p
    }

    private func aggiorna() {
        let path = UIBezierPath()
        if riquadro, let a = tracciato.first, let b = tracciato.last {
            path.append(UIBezierPath(rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))))
        } else if let primo = tracciato.first {
            path.move(to: primo)
            for q in tracciato.dropFirst() { path.addLine(to: q) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        linea.path = path.cgPath
        CATransaction.commit()
    }

    // MARK: Cattura

    /// Disegna la vista PDF così com'è (pagina, tratti, immagini, testi) e ritaglia la parte scelta.
    /// A mano libera fuori dal contorno resta trasparente.
    private func immagine(_ vista: PDFView, _ forma: UIBezierPath, _ r: CGRect) -> UIImage? {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = max(vista.traitCollection.displayScale, 2)
        formato.opaque = false
        let libera = !riquadro
        let img = UIGraphicsImageRenderer(size: r.size, format: formato).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: -r.origin.x, y: -r.origin.y)
            if libera {
                c.addPath(forma.cgPath)
                c.clip()
            }
            vista.drawHierarchy(in: vista.bounds, afterScreenUpdates: true)
        }
        return img.cgImage == nil ? nil : img
    }

    private func consegna(_ img: UIImage, _ r: CGRect) {
        guard let model, let vista else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch model.destinazioneCattura {
        case .vassoio:
            Vassoio.condiviso.aggiungi(immagine: img, larghezza: r.width)
        case .appunti:
            UIPasteboard.general.image = img
            model.avviso("Cattura copiata negli appunti.")
        case .foglio:
            let centro = CGPoint(x: r.midX, y: r.midY)
            guard let pagina = vista.page(for: centro, nearest: true), let dati = img.pngData() else {
                model.avviso("Impossibile mettere la cattura nel foglio.")
                return
            }
            let punto = vista.convert(centro, to: pagina)
            let larghezza = r.width / max(vista.scaleFactor, 0.01)
            model.inserisciCattura(dati, pagina: pagina, punto: punto, larghezza: larghezza)
        case .condividi:
            let vc = UIActivityViewController(activityItems: [img], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = vista
            vc.popoverPresentationController?.sourceRect = r
            var cima = vista.window?.rootViewController
            while let sopra = cima?.presentedViewController { cima = sopra }
            cima?.present(vc, animated: true)
        }
    }
}
