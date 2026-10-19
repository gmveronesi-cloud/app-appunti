// Lazo: immagini scelte insieme ai tratti e selezione
import SwiftUI
import PDFKit
import PencilKit

extension LazoSelezione {
    // MARK: Immagini scelte insieme ai tratti

    var paginaTela: PDFPage? {
        guard let t = canvas else { return nil }
        return model?.pagina(di: t)
    }

    var haSelezione: Bool { !selezione.isEmpty || !immaginiSel.isEmpty || !testiSel.isEmpty }

    /// Immagini scelte, lette dal modello (sempre aggiornate)
    func immaginiScelte() -> [ElementoImmagine] {
        guard let p = paginaTela else { return [] }
        let lista = model?.immagini[p] ?? []
        return immaginiSel.compactMap { id in lista.first { $0.id == id } }
    }

    /// Testi scelti, letti dal modello (sempre aggiornati)
    func testiScelti() -> [ElementoTesto] {
        guard let p = paginaTela else { return [] }
        let lista = model?.testi[p] ?? []
        return testiSel.compactMap { id in lista.first { $0.id == id } }
    }

    /// Il testo trasformato come i tratti: si sposta; con il ridimensionamento cambia la larghezza del blocco
    /// (le lettere restano della stessa dimensione); la rotazione non lo ruota.
    func trasformato(_ e: ElementoTesto, _ m: CGAffineTransform, pagina: PDFPage, k: CGFloat) -> ElementoTesto {
        let box = pagina.bounds(for: .cropBox)
        var n = e
        n.punto = versoPagina(versoTela(e.punto, box, k).applying(m), box, k)
        let s = sqrt(abs(m.a * m.d - m.b * m.c))
        if abs(s - 1) > 0.001 { n.larghezza = max(ElementoTesto.minimo, e.misura.width * s) }
        return n
    }

    func versoTela(_ p: CGPoint, _ box: CGRect, _ k: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - box.minX) * k, y: (box.maxY - p.y) * k)
    }

    func versoPagina(_ p: CGPoint, _ box: CGRect, _ k: CGFloat) -> CGPoint {
        CGPoint(x: p.x / k + box.minX, y: box.maxY - p.y / k)
    }

    /// L'immagine trasformata come i tratti (`m` è nelle coordinate della tela: y verso il basso, rotazione oraria)
    func trasformata(_ e: ElementoImmagine, _ m: CGAffineTransform, pagina: PDFPage, k: CGFloat) -> ElementoImmagine {
        let box = pagina.bounds(for: .cropBox)
        var n = e
        n.centro = versoPagina(versoTela(e.centro, box, k).applying(m), box, k)
        n.larghezza = e.larghezza * sqrt(abs(m.a * m.d - m.b * m.c))
        n.angolo = e.angolo - atan2(m.b, m.a)
        return n
    }

    func anteprimaImmagini(_ m: CGAffineTransform, _ tela: PKCanvasView) {
        guard let pagina = paginaTela, let c = model?.controlloImmagini else { return }
        let k = tela.fattoreRisoluzione
        for e in immaginiPrima { c.anteprimaGruppo(trasformata(e, m, pagina: pagina, k: k), pagina: pagina) }
        if let t = model?.controlloTesto {
            for e in testiPrima { t.anteprima(trasformato(e, m, pagina: pagina, k: k), pagina: pagina) }
        }
    }

    /// Gesto annullato: le immagini tornano dov'erano
    func ripristinaImmagini() {
        guard !immaginiPrima.isEmpty || !testiPrima.isEmpty, let pagina = paginaTela else { return }
        model?.controlloImmagini?.ridisegna(pagina)
    }

    /// Fine di uno spostamento, ridimensionamento o rotazione: tratti e immagini in un solo passo di annulla
    func confermaModifica(_ tela: PKCanvasView, _ prima: PKDrawing) {
        if !selezione.isEmpty {
            registra(tela, da: prima, a: tela.drawing)
        } else if !immaginiPrima.isEmpty || !testiPrima.isEmpty {
            registraSoloImmagini()
        }
        if let pagina = paginaTela, let c = model?.controlloImmagini {
            let k = tela.fattoreRisoluzione
            for e in immaginiPrima { c.cambia(pagina, togli: e, metti: trasformata(e, mCorrente, pagina: pagina, k: k)) }
        }
        if let pagina = paginaTela, let t = model?.controlloTesto {
            let k = tela.fattoreRisoluzione
            for e in testiPrima { t.cambia(pagina, togli: e, metti: trasformato(e, mCorrente, pagina: pagina, k: k)) }
        }
        immaginiPrima = immaginiScelte()
        testiPrima = testiScelti()
        model?.segnaModificato()
    }

    /// Annulla e ripeti quando sono state toccate solo immagini (i tratti non c'entrano)
    func registraSoloImmagini() {
        model?.gestoreUndo(per: paginaTela).registerUndo(withTarget: self) { s in
            s.deseleziona()
            s.registraSoloImmagini()
        }
    }

    // MARK: Selezione

    func seleziona(in tela: PKCanvasView) {
        guard let s = model?.corrente, s.tipo == .lazo else { return }
        let riquadro = s.lazoRiquadro
        let k = tela.fattoreRisoluzione
        let forma: (CGPoint) -> Bool
        /// Vero se il punto è dentro il lazo o a meno di `tol` dal suo contorno
        let vicino: (CGPoint, CGFloat) -> Bool
        var areaLazo = CGRect.null
        if riquadro, let a = tracciato.first, let b = tracciato.last {
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            forma = { r.contains($0) }
            vicino = { p, tol in r.insetBy(dx: -tol, dy: -tol).contains(p) }
            areaLazo = r
        } else {
            guard tracciato.count > 2 else { return }
            let path = UIBezierPath()
            path.move(to: tracciato[0])
            for q in tracciato.dropFirst() { path.addLine(to: q) }
            path.close()
            forma = { path.contains($0) }
            let poligono = tracciato
            vicino = { p, tol in path.contains(p) || Self.distanza(p, daPoligono: poligono) <= tol }
            for q in tracciato { areaLazo = areaLazo.union(CGRect(origin: q, size: .zero)) }
        }

        // Due passate: prima il lazo preciso (con 2 pt di tolleranza: un cerchio un po' storto o che passa
        // sul bordo del tratto lo prende lo stesso); se non ha preso nulla, una passata più larga (10 pt).
        func scegli(tolleranza tol: CGFloat) -> [Int] {
            var trovati: [Int] = []
            let zona = areaLazo.insetBy(dx: -tol, dy: -tol)
            for (i, t) in tela.drawing.strokes.enumerated() {
                guard s.lazoFiltri.contains(tipoTratto(t)) else { continue }
                // Scarta subito i tratti lontani dal lazo
                guard t.renderBounds.intersects(zona) else { continue }
                // Basta un solo punto del tratto dentro il lazo per selezionarlo tutto
                let punti = t.path.interpolatedPoints(by: .distance(2)).map { $0.location.applying(t.transform) }
                if punti.contains(where: { vicino($0, tol) }) { trovati.append(i) }
            }
            return trovati
        }
        var scelti = scegli(tolleranza: 2 * k)
        if scelti.isEmpty { scelti = scegli(tolleranza: 10 * k) }

        // Immagini: basta che il lazo ne circondi circa un quinto (25 punti di prova sull'immagine)
        var imm: [UUID] = []
        if s.lazoImmagini, let pagina = model?.pagina(di: tela), let lista = model?.immagini[pagina], !lista.isEmpty {
            let box = pagina.bounds(for: .cropBox)
            let k = tela.fattoreRisoluzione
            for e in lista {
                var dentro = 0
                for ix in 0...4 {
                    for iy in 0...4 {
                        let l = CGPoint(x: (CGFloat(ix) / 4 - 0.5) * e.larghezza, y: (CGFloat(iy) / 4 - 0.5) * e.altezza)
                        if forma(versoTela(e.mondo(l), box, k)) { dentro += 1 }
                    }
                }
                if dentro >= 5 { imm.append(e.id) }
            }
            // Lazo tutto dentro un'immagine (e niente altro preso): sceglie l'immagine più in alto
            if imm.isEmpty && scelti.isEmpty, let primo = tracciato.first, let ultimo = tracciato.last {
                let punti = riquadro ? [primo, ultimo] : tracciato
                let dentroImmagine = lista.sorted { $0.creazione > $1.creazione }.first { e in
                    punti.allSatisfy { e.contiene(versoPagina($0, box, k)) }
                }
                if let e = dentroImmagine { imm = [e.id] }
            }
        }

        // Testi: basta che il lazo ne circondi circa un sesto (25 punti di prova sul blocco)
        var tst: [UUID] = []
        if s.lazoTesti, let pagina = model?.pagina(di: tela), let lista = model?.testi[pagina], !lista.isEmpty {
            let box = pagina.bounds(for: .cropBox)
            let k = tela.fattoreRisoluzione
            for e in lista {
                let r = e.rettangolo
                var dentro = 0
                for ix in 0...4 {
                    for iy in 0...4 {
                        let q = CGPoint(x: r.minX + CGFloat(ix) / 4 * r.width, y: r.minY + CGFloat(iy) / 4 * r.height)
                        if forma(versoTela(q, box, k)) { dentro += 1 }
                    }
                }
                if dentro >= 4 { tst.append(e.id) }
            }
        }

        guard !scelti.isEmpty || !imm.isEmpty || !tst.isEmpty else { return }

        // Una sola immagine e nient'altro: selezione completa dell'immagine (maniglie, rotazione, ritaglio)
        if scelti.isEmpty, tst.isEmpty, imm.count == 1, let pagina = model?.pagina(di: tela) {
            deseleziona()
            model?.controlloImmagini?.seleziona(pagina, id: imm[0])
            return
        }

        model?.controlloImmagini?.annullaSelezione()
        selezione = scelti
        immaginiSel = imm
        testiSel = tst
        mostraRiquadro(riquadroSelezione(in: tela))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()     // conferma tattile: il lazo ha preso qualcosa
    }

    /// Distanza minima di un punto dal contorno del poligono (chiuso)
    static func distanza(_ p: CGPoint, daPoligono v: [CGPoint]) -> CGFloat {
        guard var a = v.last else { return .greatestFiniteMagnitude }
        var minimo = CGFloat.greatestFiniteMagnitude
        for b in v {
            let dx = b.x - a.x, dy = b.y - a.y
            let l2 = dx * dx + dy * dy
            var t: CGFloat = l2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2 : 0
            t = max(0, min(1, t))
            minimo = min(minimo, hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
            a = b
        }
        return minimo
    }

    func angoli(di r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.minY)]
    }

    func tipoTratto(_ t: PKStroke) -> TipoStrumento {
        switch t.ink.inkType {
        case .marker: return .evidenziatore
        case .monoline where t.ink.color.cgColor.alpha < 0.95: return .evidenziatore
        case .pencil, .crayon: return .matita
        default: return .penna
        }
    }

    func riquadroSelezione(in tela: PKCanvasView) -> CGRect {
        let tratti = tela.drawing.strokes
        var r = CGRect.null
        for i in selezione where tratti.indices.contains(i) { r = r.union(tratti[i].renderBounds) }
        let k = tela.fattoreRisoluzione
        if !r.isNull { r = r.insetBy(dx: -6 * k, dy: -6 * k) }
        if let pagina = paginaTela {
            let box = pagina.bounds(for: .cropBox)
            for e in immaginiScelte() {
                for q in e.angoli.map({ versoTela($0, box, k) }) { r = r.union(CGRect(origin: q, size: .zero)) }
            }
            for e in testiScelti() {
                for q in angoli(di: e.rettangolo).map({ versoTela($0, box, k) }) { r = r.union(CGRect(origin: q, size: .zero)) }
            }
        }
        return r.isNull ? .zero : r
    }

    /// Copia del tratto con la nuova posizione scritta direttamente nei punti.
    static func spostato(_ t: PKStroke, _ m: CGAffineTransform, scala: CGFloat = 1, data: Date? = nil) -> PKStroke {
        let totale = t.transform.concatenating(m)
        var punti: [PKStrokePoint] = []
        for i in 0..<t.path.count {
            let p = t.path[i]
            punti.append(PKStrokePoint(location: p.location.applying(totale), timeOffset: p.timeOffset, size: CGSize(width: p.size.width * scala, height: p.size.height * scala),
                                       opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude))
        }
        let path = PKStrokePath(controlPoints: punti, creationDate: data ?? t.path.creationDate)
        return PKStroke(ink: t.ink, path: path, transform: .identity, mask: t.mask)
    }
}
