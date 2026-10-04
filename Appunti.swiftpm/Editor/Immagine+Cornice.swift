// Immagine: strati sotto la tela, cornice e maniglie
import SwiftUI
import PDFKit
import PencilKit

extension ImmagineControllo {
    // MARK: Disegno (strati sotto la tela dei tratti)

    /// Ricostruisce lo strato di sotto della pagina: tratti più vecchi e immagini, in ordine di creazione.
    func ridisegna(_ pagina: PDFPage) {
        guard let model, let tela = model.canvases[pagina], let contenitore = tela.superview as? PaginaTela else { return }
        contenitore.layer.sublayers?
            .filter { $0.name == Self.nomeLivello || $0.name == Self.nomeStrato }
            .forEach { $0.removeFromSuperlayer() }
        let box = pagina.bounds(for: .cropBox)
        let k = tela.fattoreRisoluzione
        var restanti = model.sotto[pagina] ?? []

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func aggiungi(_ l: CALayer) { contenitore.layer.insertSublayer(l, below: tela.layer) }

        for e in (model.immagini[pagina] ?? []).sorted(by: { $0.creazione < $1.creazione }) {
            let piu_vecchi = restanti.filter { $0.path.creationDate < e.creazione }
            restanti = restanti.filter { $0.path.creationDate >= e.creazione }
            if !piu_vecchi.isEmpty { aggiungi(Self.strato(piu_vecchi, dimensione: box.size, k: k)) }
            let l = CALayer()
            l.name = Self.nomeLivello
            l.contentsGravity = .resize
            livelli[e.id] = l
            applica(e, a: l, box: box)
            aggiungi(l)
        }
        if !restanti.isEmpty { aggiungi(Self.strato(restanti, dimensione: box.size, k: k)) }
        CATransaction.commit()
        mostraSelezione()
    }

    /// Strato con i tratti già disegnati (sola immagine, non modificabile finché non si torna alla gomma o al lazo)
    static func strato(_ tratti: [PKStroke], dimensione: CGSize, k: CGFloat) -> CALayer {
        let l = CALayer()
        l.name = nomeStrato
        l.frame = CGRect(origin: .zero, size: dimensione)
        let d = PKDrawing(strokes: tratti)
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: CGRect(x: 0, y: 0, width: dimensione.width * k, height: dimensione.height * k), scale: 1)
        }
        l.contents = img?.cgImage
        l.contentsGravity = .resize
        return l
    }

    func applica(_ e: ElementoImmagine, a l: CALayer, box: CGRect) {
        l.contents = e.ritagliata.cgImage
        l.bounds = CGRect(x: 0, y: 0, width: e.larghezza, height: e.altezza)
        l.position = CGPoint(x: e.centro.x - box.minX, y: box.maxY - e.centro.y)
        l.transform = CATransform3DMakeRotation(-e.angolo, 0, 0, 1)
    }

    /// Anteprima in tempo reale durante lo spostamento, il ridimensionamento, la rotazione e il ritaglio
    func anteprima(_ e: ElementoImmagine) {
        guard let s = scelta, let l = livelli[e.id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applica(e, a: l, box: s.pagina.bounds(for: .cropBox))
        CATransaction.commit()
        mostraSelezione(e)
    }

    // MARK: Cornice e maniglie della selezione

    func mostraSelezione(_ ovr: ElementoImmagine? = nil) {
        let pagine: [PDFPage] = model.map { Array($0.canvases.keys) } ?? []
        for pagina in pagine {
            guard let cont = model?.canvases[pagina]?.superview as? PaginaTela else { continue }
            cont.layer.sublayers?.filter { $0.name == Self.nomeSelezione }.forEach { $0.removeFromSuperlayer() }
        }
        guard let s = scelta, let e = ovr ?? elemento(s.pagina, s.id),
              let cont = model?.canvases[s.pagina]?.superview as? PaginaTela else { return }
        let box = s.pagina.bounds(for: .cropBox)
        let u = unita
        let colore = UIColor(AptTema.accento)
        func c(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - box.minX, y: box.maxY - p.y) }

        let radice = CALayer()
        radice.name = Self.nomeSelezione
        let cornice = CAShapeLayer()
        let path = UIBezierPath()
        let a = e.angoli.map(c)
        path.move(to: a[0]); a.dropFirst().forEach { path.addLine(to: $0) }; path.close()
        cornice.path = path.cgPath
        cornice.fillColor = nil
        cornice.strokeColor = colore.cgColor
        cornice.lineWidth = (ritagliando ? 2.5 : 1.5) * u
        cornice.lineDashPattern = ritagliando ? nil : [NSNumber(value: Double(6 * u)), NSNumber(value: Double(4 * u))]
        radice.addSublayer(cornice)

        if !ritagliando {
            let top = c(e.mondo(CGPoint(x: 0, y: e.altezza / 2)))
            let rot = c(e.mondo(CGPoint(x: 0, y: e.altezza / 2 + 38 * u)))
            let linea = CAShapeLayer()
            let lp = UIBezierPath(); lp.move(to: top); lp.addLine(to: rot)
            linea.path = lp.cgPath
            linea.strokeColor = colore.cgColor
            linea.lineWidth = 1.5 * u
            radice.addSublayer(linea)
        }
        for (_, p) in maniglie(e) {
            let m = CAShapeLayer()
            let q = c(p)
            let r = 9 * u
            m.path = UIBezierPath(ovalIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)).cgPath
            m.fillColor = UIColor(AptTema.carta).cgColor
            m.strokeColor = colore.cgColor
            m.lineWidth = 2 * u
            radice.addSublayer(m)
        }
        cont.layer.addSublayer(radice)
    }
}
