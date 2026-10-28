// Immagine: strati sotto la tela, cornice e maniglie
import SwiftUI
import PDFKit
import PencilKit

extension ImmagineControllo {
    // MARK: Disegno (strati sotto la tela dei tratti)

    /// Ricostruisce lo strato di sotto della pagina: tratti più vecchi, immagini e testi, in ordine di creazione.
    func ridisegna(_ pagina: PDFPage) {
        guard let model, let tela = model.canvases[pagina], let contenitore = tela.superview as? PaginaTela else { return }
        contenitore.layer.sublayers?
            .filter { $0.name == Self.nomeLivello || $0.name == Self.nomeStrato || $0.name == TestoControllo.nomeLivello || $0.name == Self.nomeClip }
            .forEach { $0.removeFromSuperlayer() }
        let box = pagina.bounds(for: .cropBox)
        let k = tela.fattoreRisoluzione
        var restanti = model.sotto[pagina] ?? []

        enum Oggetto { case immagine(ElementoImmagine), testo(ElementoTesto) }
        var oggetti: [(Date, Oggetto)] = (model.immagini[pagina] ?? []).map { ($0.creazione, Oggetto.immagine($0)) }
        oggetti += (model.testi[pagina] ?? []).map { ($0.creazione, Oggetto.testo($0)) }
        oggetti.sort { $0.0 < $1.0 }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Tutto ciò che sta sotto la tela va in un livello che taglia sul bordo del foglio: se si toglie spazio ai lati,
        // le immagini e i testi che finiscono fuori dalla pagina spariscono (restano nel file e riappaiono se lo spazio torna)
        let clip = CALayer()
        clip.name = Self.nomeClip
        clip.frame = CGRect(origin: .zero, size: box.size)
        clip.masksToBounds = true
        contenitore.layer.insertSublayer(clip, below: tela.layer)
        func aggiungi(_ l: CALayer) { clip.addSublayer(l) }
        func aggiungiTratti(_ tratti: [PKStroke]) {
            if !tratti.isEmpty { aggiungi(Self.strato(tratti, dimensione: box.size, k: k)) }
        }

        for (data, o) in oggetti {
            let piu_vecchi = restanti.filter { $0.path.creationDate < data }
            restanti = restanti.filter { $0.path.creationDate >= data }
            aggiungiTratti(piu_vecchi)
            switch o {
            case .immagine(let e):
                let l = CALayer()
                l.name = Self.nomeLivello
                l.contentsGravity = .resize
                livelli[e.id] = l
                applica(e, a: l, box: box)
                aggiungi(l)
            case .testo(let t):
                if let l = model.controlloTesto?.creaLivello(t, box: box) { aggiungi(l) }
            }
        }
        aggiungiTratti(restanti)
        // Evidenziatori sopra la tela (quando si scrive con penne e matite)
        let sopra = model.sopra[pagina] ?? []
        if !sopra.isEmpty {
            contenitore.layer.insertSublayer(Self.strato(sopra, dimensione: box.size, k: k), above: tela.layer)
        }
        CATransaction.commit()
        mostraSelezione()
        model.controlloTesto?.mostraSelezione()
    }

    /// Strato con i tratti già disegnati (sola immagine, non modificabile finché non si torna alla gomma o al lazo).
    /// L'immagine copre solo l'ingombro dei tratti (non tutta la pagina) e ha al massimo ~4 milioni di pixel: prima ogni strato era
    /// grande quanto la tela (decine di MB), e con pagine larghe e molte pagine in vista la memoria finiva (chiusure improvvise).
    static func strato(_ tratti: [PKStroke], dimensione: CGSize, k: CGFloat) -> CALayer {
        let l = CALayer()
        l.name = nomeStrato
        l.frame = CGRect(origin: .zero, size: dimensione)
        var r = CGRect.null
        for t in tratti { r = r.union(t.renderBounds) }
        r = r.insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: dimensione.width * k, height: dimensione.height * k)).integral
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return l }
        let scala = min(1, (4_000_000 / (r.width * r.height)).squareRoot())
        let d = PKDrawing(strokes: tratti)
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: r, scale: scala)
        }
        l.frame = CGRect(x: r.minX / k, y: r.minY / k, width: r.width / k, height: r.height / k)
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
