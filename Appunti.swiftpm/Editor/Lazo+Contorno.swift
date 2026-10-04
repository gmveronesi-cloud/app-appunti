// Lazo: disegno dei contorni
import SwiftUI
import PDFKit
import PencilKit

extension LazoSelezione {
    // MARK: Disegno dei contorni

    /// Spessori e tratteggio dei segni di selezione: stanno nella tela (k volte la pagina), quindi si moltiplicano per k.
    func aggiornaStile(_ k: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [lineaLayer, selezioneLayer] {
            l.lineWidth = 1.5 * k
            l.lineDashPattern = [NSNumber(value: Double(6 * k)), NSNumber(value: Double(4 * k))]
        }
        for m in maniglie { m.lineWidth = 2 * k }
        manigliaRuota.lineWidth = 2 * k
        lineaRuota.lineWidth = 1.5 * k
        CATransaction.commit()
    }

    func aggiornaLinea() {
        let path = UIBezierPath()
        if (model?.corrente?.lazoRiquadro ?? false), let a = tracciato.first, let b = tracciato.last {
            path.append(UIBezierPath(rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))))
        } else if let primo = tracciato.first {
            path.move(to: primo)
            for q in tracciato.dropFirst() { path.addLine(to: q) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineaLayer.path = path.cgPath
        CATransaction.commit()
    }

    /// Mostra il contorno tratteggiato attorno ai tratti scelti (non un riquadro).
    /// Senza `trasf` il contorno è ricalcolato dai tratti; durante spostamento, ridimensionamento
    /// e rotazione si usa quello già calcolato, trasformato come i tratti.
    func mostraRiquadro(_ r: CGRect, trasf: CGAffineTransform? = nil) {
        guard let tela = canvas else { return }
        let k = tela.fattoreRisoluzione
        aggiornaStile(k)
        if selezioneLayer.superlayer == nil { tela.layer.addSublayer(selezioneLayer) }
        if trasf == nil { contorno = calcolaContorno(in: tela) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if var m = trasf, let c = contorno {
            selezioneLayer.path = c.copy(using: &m)
        } else {
            selezioneLayer.path = contorno
        }
        let angoli = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                      CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        for (i, m) in maniglie.enumerated() {
            if modoRidimensiona {
                if m.superlayer == nil { tela.layer.addSublayer(m) }
                m.path = UIBezierPath(ovalIn: CGRect(x: angoli[i].x - 9 * k, y: angoli[i].y - 9 * k, width: 18 * k, height: 18 * k)).cgPath
            } else {
                m.removeFromSuperlayer()
            }
        }
        if modoRidimensiona {
            let rot = CGPoint(x: r.midX, y: r.minY - 40 * k)
            let l = UIBezierPath()
            l.move(to: CGPoint(x: r.midX, y: r.minY))
            l.addLine(to: rot)
            lineaRuota.path = l.cgPath
            manigliaRuota.path = UIBezierPath(ovalIn: CGRect(x: rot.x - 10 * k, y: rot.y - 10 * k, width: 20 * k, height: 20 * k)).cgPath
            if lineaRuota.superlayer == nil { tela.layer.addSublayer(lineaRuota) }
            if manigliaRuota.superlayer == nil { tela.layer.addSublayer(manigliaRuota) }
        } else {
            lineaRuota.removeFromSuperlayer()
            manigliaRuota.removeFromSuperlayer()
        }
        CATransaction.commit()
    }

    func calcolaContorno(in tela: PKCanvasView) -> CGPath {
        let tratti = tela.drawing.strokes
        let unire = selezione.count <= 40
        var risultato: CGPath?
        let tutti = CGMutablePath()
        for i in selezione where tratti.indices.contains(i) {
            let t = tratti[i]
            let k = tela.fattoreRisoluzione
            let pt = Array(t.path.interpolatedPoints(by: .distance(5 * k)))
            guard let primo = pt.first else { continue }
            let linea = CGMutablePath()
            linea.move(to: primo.location.applying(t.transform))
            for q in pt.dropFirst() { linea.addLine(to: q.location.applying(t.transform)) }
            if pt.count == 1 { linea.addLine(to: primo.location.applying(t.transform)) }
            let largo = pt.map { $0.size.width }.reduce(0, +) / CGFloat(pt.count)
            let bordo = linea.copy(strokingWithWidth: max(largo, 1) + 10 * k, lineCap: .round, lineJoin: .round, miterLimit: 10)
            if unire {
                let n = bordo.normalized(using: .winding)
                risultato = risultato.map { $0.union(n, using: .winding) } ?? n
            } else {
                tutti.addPath(bordo)
            }
        }
        // Le immagini scelte: il loro quadrilatero
        if let pagina = paginaTela {
            let box = pagina.bounds(for: .cropBox)
            let k = tela.fattoreRisoluzione
            for e in immaginiScelte() {
                let q = CGMutablePath()
                q.addLines(between: e.angoli.map { versoTela($0, box, k) })
                q.closeSubpath()
                if unire { risultato = risultato.map { $0.union(q, using: .winding) } ?? q } else { tutti.addPath(q) }
            }
        }
        // I testi scelti: il loro rettangolo
        if let pagina = paginaTela {
            let box = pagina.bounds(for: .cropBox)
            let k = tela.fattoreRisoluzione
            for e in testiScelti() {
                let q = CGMutablePath()
                q.addLines(between: angoli(di: e.rettangolo).map { versoTela($0, box, k) })
                q.closeSubpath()
                if unire { risultato = risultato.map { $0.union(q, using: .winding) } ?? q } else { tutti.addPath(q) }
            }
        }
        if unire { return risultato ?? CGMutablePath() }
        return tutti
    }

    func deseleziona() {
        lineaLayer.removeFromSuperlayer()
        selezioneLayer.removeFromSuperlayer()
        for m in maniglie { m.removeFromSuperlayer() }
        lineaRuota.removeFromSuperlayer()
        manigliaRuota.removeFromSuperlayer()
        contorno = nil
        modoRidimensiona = false
        selezione = []
        immaginiSel = []
        immaginiPrima = []
        testiSel = []
        testiPrima = []
        tracciato = []
        disegnoPrima = nil
        canvas = nil
        fase = .niente
    }
}
