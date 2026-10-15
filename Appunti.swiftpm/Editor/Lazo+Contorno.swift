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
        azzeraTrasformazioniContorno()
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

    /// Fino a questo numero di tratti il contorno segue ogni tratto; con più tratti si mostra solo il contorno esterno dei gruppi
    static let trattiPerRaggruppare = 8

    func calcolaContorno(in tela: PKCanvasView) -> CGPath {
        let tratti = tela.drawing.strokes
        let raggruppa = selezione.count > Self.trattiPerRaggruppare
        let unire = !raggruppa
        var risultato: CGPath?
        let tutti = CGMutablePath()
        if raggruppa { tutti.addPath(contornoGruppi(tratti, k: tela.fattoreRisoluzione)) }
        for i in selezione where !raggruppa && tratti.indices.contains(i) {
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

    // MARK: Contorno esterno di tanti tratti

    /// Tanti tratti: un solo contorno esterno per ogni gruppo di tratti vicini (un guscio arrotondato), invece di un contorno per tratto.
    /// Veloce anche con centinaia di tratti: usa solo i punti di controllo e non unisce forme.
    private func contornoGruppi(_ tratti: [PKStroke], k: CGFloat) -> CGPath {
        let scelti = selezione.compactMap { tratti.indices.contains($0) ? tratti[$0] : nil }
        let percorso = CGMutablePath()
        guard !scelti.isEmpty else { return percorso }
        let n = scelti.count
        let margine: CGFloat = 8 * k          // distanza del contorno dai tratti
        let vicino: CGFloat = 36 * k          // tratti più vicini di così stanno nello stesso gruppo

        // Gruppi: tratti i cui riquadri (allargati) si toccano
        var padre = Array(0..<n)
        func radice(_ i: Int) -> Int {
            var x = i
            while padre[x] != x { padre[x] = padre[padre[x]]; x = padre[x] }
            return x
        }
        let riquadri = scelti.map { $0.renderBounds.insetBy(dx: -vicino / 2, dy: -vicino / 2) }
        if n > 1500 {
            for i in 1..<n { padre[i] = 0 }                    // troppi per confrontarli a coppie: un solo gruppo
        } else {
            for i in 0..<n {
                for j in (i + 1)..<max(n, i + 1) where riquadri[i].intersects(riquadri[j]) {
                    let a = radice(i), b = radice(j)
                    if a != b { padre[a] = b }
                }
            }
        }

        // Punti di ogni gruppo (al massimo ~40 per tratto) e spessore massimo
        var punti: [Int: [CGPoint]] = [:]
        var spessore: [Int: CGFloat] = [:]
        for (i, t) in scelti.enumerated() {
            let g = radice(i)
            let totale = t.path.count
            guard totale > 0 else { continue }
            let passo = max(1, totale / 40)
            var j = 0
            while j < totale {
                let p = t.path[j]
                punti[g, default: []].append(p.location.applying(t.transform))
                spessore[g] = max(spessore[g] ?? 0, p.size.width)
                j += passo
            }
            let ultimo = t.path[totale - 1]
            punti[g, default: []].append(ultimo.location.applying(t.transform))
        }

        for (g, pts) in punti {
            let raggio = margine + (spessore[g] ?? 0) / 2
            let guscio = Self.guscioArrotondato(pts, raggio: raggio)
            guard guscio.count >= 3 else { continue }
            percorso.addLines(between: guscio)
            percorso.closeSubpath()
        }
        return percorso
    }

    /// Involucro convesso dei punti, allargato di `raggio` con gli angoli arrotondati
    private static func guscioArrotondato(_ punti: [CGPoint], raggio: CGFloat) -> [CGPoint] {
        guard !punti.isEmpty else { return [] }
        var intorno: [CGPoint] = []
        intorno.reserveCapacity(min(punti.count, 400) * 12)
        for p in involucro(punti) {
            for s in 0..<12 {
                let a = CGFloat(s) * .pi / 6
                intorno.append(CGPoint(x: p.x + cos(a) * raggio, y: p.y + sin(a) * raggio))
            }
        }
        return involucro(intorno)
    }

    /// Involucro convesso (catena monotona di Andrew)
    private static func involucro(_ p: [CGPoint]) -> [CGPoint] {
        let punti = p.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard punti.count > 2 else { return punti }
        func giro(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var sotto: [CGPoint] = []
        for q in punti {
            while sotto.count >= 2 && giro(sotto[sotto.count - 2], sotto[sotto.count - 1], q) <= 0 { sotto.removeLast() }
            sotto.append(q)
        }
        var sopra: [CGPoint] = []
        for q in punti.reversed() {
            while sopra.count >= 2 && giro(sopra[sopra.count - 2], sopra[sopra.count - 1], q) <= 0 { sopra.removeLast() }
            sopra.append(q)
        }
        sotto.removeLast()
        sopra.removeLast()
        return sotto + sopra
    }

    func deseleziona() {
        if stratoTratti != nil { annullaTrascinamento(canvas) }       // selezione interrotta a metà: i tratti tornano al loro posto
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
