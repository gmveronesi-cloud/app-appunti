// Lazo: trascinamento veloce. Mentre si sposta, ridimensiona o ruota, i tratti scelti escono dalla tela
// e diventano un'immagine che la GPU muove senza ridisegnare nulla (come fa il selettore di sistema).
// Il disegno vero, con i tratti nella nuova posizione, si scrive una sola volta a fine gesto.
import SwiftUI
import PencilKit

extension LazoSelezione {
    /// Massimo di pixel dell'immagine dei tratti scelti (oltre, scende un poco di risoluzione)
    private static let pixelMassimi: CGFloat = 12_000_000

    /// All'inizio del movimento: i tratti scelti diventano un'immagine sopra la tela; la tela resta con gli altri
    func preparaTrascinamento(_ tela: PKCanvasView) {
        guard stratoTratti == nil, !selezione.isEmpty, let base = disegnoPrima else { return }
        let tutti = base.strokes
        let scelti = selezione.filter { tutti.indices.contains($0) }.map { tutti[$0] }
        guard !scelti.isEmpty else { return }
        var r = CGRect.null
        for t in scelti { r = r.union(t.renderBounds) }
        r = r.insetBy(dx: -4, dy: -4).integral
        guard r.width > 0, r.height > 0 else { return }
        let scala = min(2, sqrt(Self.pixelMassimi / (r.width * r.height)))
        var immagine: UIImage?
        // Le tele sono sempre chiare: l'immagine va disegnata con lo stesso aspetto
        tela.traitCollection.performAsCurrent {
            immagine = PKDrawing(strokes: scelti).image(from: r, scale: scala)
        }
        guard let cg = immagine?.cgImage else { return }
        let resto = tutti.enumerated().filter { !selezione.contains($0.offset) }.map { $0.element }

        let strato = CALayer()
        strato.anchorPoint = .zero
        strato.bounds = CGRect(origin: .zero, size: r.size)
        strato.position = r.origin
        strato.contents = cg
        strato.contentsGravity = .resize
        strato.magnificationFilter = .linear
        strato.minificationFilter = .linear

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tela.drawing = PKDrawing(strokes: resto)
        if selezioneLayer.superlayer === tela.layer {
            tela.layer.insertSublayer(strato, below: selezioneLayer)
        } else {
            tela.layer.addSublayer(strato)
        }
        CATransaction.commit()
        stratoTratti = strato
        origineStrato = r.origin
    }

    /// `m` è la trasformazione nelle coordinate della tela
    func muoviTrascinamento(_ m: CGAffineTransform) {
        guard let s = stratoTratti else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        s.position = origineStrato.applying(m)
        s.setAffineTransform(CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: 0, ty: 0))
        CATransaction.commit()
    }

    /// Solo per lo spostamento: contorno e maniglie scivolano con una semplice traslazione, senza ricalcolare nulla
    func muoviContorno(_ t: CGAffineTransform) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selezioneLayer.setAffineTransform(t)
        for l in maniglie { l.setAffineTransform(t) }
        manigliaRuota.setAffineTransform(t)
        lineaRuota.setAffineTransform(t)
        CATransaction.commit()
    }

    func azzeraTrasformazioniContorno() {
        selezioneLayer.setAffineTransform(.identity)
        for l in maniglie { l.setAffineTransform(.identity) }
        manigliaRuota.setAffineTransform(.identity)
        lineaRuota.setAffineTransform(.identity)
    }

    /// Fine del gesto: il disegno vero, con i tratti scelti nella nuova posizione, scritto una volta sola
    func concludiTrascinamento(_ tela: PKCanvasView) {
        guard let strato = stratoTratti else { return }
        if let base = disegnoPrima {
            let m = mCorrente
            let scala = sqrt(abs(m.a * m.d - m.b * m.c))
            var tutti = base.strokes
            for i in selezione where tutti.indices.contains(i) {
                tutti[i] = Self.spostato(base.strokes[i], m, scala: scala)
            }
            tela.drawing = PKDrawing(strokes: tutti)
        }
        stratoTratti = nil
        // L'immagine resta un attimo, finché PencilKit ha disegnato i tratti: nessun lampo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { strato.removeFromSuperlayer() }
    }

    /// Gesto annullato o selezione interrotta: i tratti tornano dov'erano
    func annullaTrascinamento(_ tela: PKCanvasView?) {
        if let strato = stratoTratti {
            strato.removeFromSuperlayer()
            stratoTratti = nil
            if let tela, let prima = disegnoPrima { tela.drawing = prima }
        } else if let tela, let prima = disegnoPrima, fase != .disegno {
            tela.drawing = prima
        }
    }
}
