// Immagine: trascinamento, tocco su punto vuoto, inserimento
import SwiftUI
import PDFKit
import PencilKit

extension ImmagineControllo {
    // MARK: Gesto di trascinamento

    func colpisce(_ pv: CGPoint, _ tipo: UITouch.TouchType) -> Bool {
        // con «Ritaglia» aperto la Pencil lavora sull'immagine scelta anche se lo strumento è una penna
        guard let model, puoAgire(tipo) || (tipo == .pencil && ritagliando), let (pg, pp) = pagina(in: pv) else { return false }
        // maniglie e immagine già scelta: sempre
        if let s = scelta, s.pagina === pg, let e = elemento(pg, s.id),
           maniglia(e, vicino: pp) != nil || e.contiene(pp, margine: 4 * unita) { return true }
        // un'immagine non ancora scelta: con lo strumento Immagine si afferra al volo; col dito anche con qualsiasi altro strumento
        // (lì c'è comunque la pressione lunga di 0,4 s, vedi `attesa`); la Pencil con gli altri strumenti scrive
        return (model.corrente?.tipo == .immagine || tipo != .pencil) && sotto(pp, in: pg) != nil
    }

    /// Il punto cade su una maniglia o sull'immagine già scelta: il dito lavora subito, senza attesa
    func giaScelta(_ pv: CGPoint) -> Bool {
        guard let (pg, pp) = pagina(in: pv), let s = scelta, s.pagina === pg, let e = elemento(pg, s.id) else { return false }
        return maniglia(e, vicino: pp) != nil || e.contiene(pp, margine: 4 * unita)
    }

    func inizia(_ pv: CGPoint) {
        guard let (pg, pp) = pagina(in: pv) else { fase = .niente; return }
        inizio = pp
        mosso = false
        if let s = scelta, s.pagina === pg, let e = elemento(pg, s.id), let m = maniglia(e, vicino: pp) {
            prima = e
            inCorso = e
            eraScelta = true
            switch m {
            case .angolo: fase = .scala
            case .bordo(let dx, let dy): fase = .ritaglia(dx, dy)
            case .ruota:
                fase = .ruota
                angoloIniziale = atan2(pp.y - e.centro.y, pp.x - e.centro.x) - e.angolo
            }
            return
        }
        // Modalità «Ritaglia»: un tratto della sola PENCIL (non il dito) dentro l'immagine scelta disegna il contorno a mano libera (un tocco semplice apre il menu)
        if ritagliando, trascina.tocco?.type == .pencil, let s = scelta, s.pagina === pg, let e = elemento(pg, s.id), e.contiene(pp, margine: 4 * unita) {
            prima = e
            inCorso = e
            eraScelta = true
            fase = .contorno
            tracciatoContorno = [pp]
            return
        }
        guard let e = sotto(pp, in: pg) else { fase = .niente; return }
        eraScelta = scelta?.id == e.id
        if !eraScelta { ritagliando = false }
        scelta = (pg, e.id)
        prima = e
        inCorso = e
        fase = .sposta
        mostraSelezione()
    }

    func muovi(_ pv: CGPoint) {
        guard let (_, pp) = pagina(in: pv), let base = prima, let s = scelta else { return }
        let u = unita
        var e = base
        switch fase {
        case .niente:
            return
        case .contorno:
            // si resta sempre sulla pagina dell'immagine, anche se il dito esce dal foglio
            guard let q = vista?.convert(pv, to: s.pagina) else { return }
            tracciatoContorno.append(q)
            if !mosso && hypot(q.x - inizio.x, q.y - inizio.y) >= 5 * u { mosso = true }
            mostraContorno(s.pagina)
            return
        case .sposta:
            if !mosso && hypot(pp.x - inizio.x, pp.y - inizio.y) < 5 * u { return }
            e.centro = CGPoint(x: base.centro.x + pp.x - inizio.x, y: base.centro.y + pp.y - inizio.y)
        case .scala:
            let d0 = max(hypot(inizio.x - base.centro.x, inizio.y - base.centro.y), 1)
            let d1 = hypot(pp.x - base.centro.x, pp.y - base.centro.y)
            let box = s.pagina.bounds(for: .cropBox)
            e.larghezza = min(max(base.larghezza * d1 / d0, 24), box.width * 3)
        case .ruota:
            var a = atan2(pp.y - base.centro.y, pp.x - base.centro.x) - angoloIniziale
            // si ferma da solo vicino agli angoli retti
            let passo = CGFloat.pi / 2
            let resto = a - (a / passo).rounded() * passo
            if abs(resto) < 0.04 { a -= resto }
            e.angolo = a
        case .ritaglia(let dx, let dy):
            e = Self.ritagliato(base, dx: dx, dy: dy, tocco: pp)
        }
        mosso = true
        inCorso = e
        anteprima(e)
    }

    func finisci(_ pv: CGPoint, annullato: Bool) {
        defer { fase = .niente; prima = nil; inCorso = nil }
        guard let s = scelta, let vecchio = prima else { return }
        if case .contorno = fase {
            let punti = tracciatoContorno
            tracciatoContorno = []
            cancellaContorno()
            if annullato { return }
            if let nuovo = Self.conContorno(vecchio, punti: punti) {
                // si resta nella modalità «Ritaglia»: un altro contorno restringe ancora, «Ripristina» toglie tutto
                cambia(s.pagina, togli: vecchio, metti: nuovo)
            } else if !mosso {
                modoMenu = .immagine
                menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
            }
            return
        }
        if annullato {
            anteprima(vecchio)
            return
        }
        if mosso, let nuovo = inCorso {
            cambia(s.pagina, togli: vecchio, metti: nuovo)
        } else if case .sposta = fase, eraScelta {
            // Tocco su un'immagine già scelta: menu
            modoMenu = .immagine
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
        }
    }

    /// Ritaglio: il lato (o i lati) toccato segue il dito; il resto dell'immagine resta dov'è.
    static func ritagliato(_ e: ElementoImmagine, dx: Int, dy: Int, tocco p: CGPoint) -> ElementoImmagine {
        let l = e.locale(p)
        let s = e.scala, w = e.larghezza, h = e.altezza
        let R = e.ritaglio
        let minimo: CGFloat = 20
        var minX = R.minX, maxX = R.maxX, minY = R.minY, maxY = R.maxY
        let px = R.minX + (l.x + w / 2) / s
        let py = R.minY + (h / 2 - l.y) / s
        if dx < 0 { minX = min(max(px, 0), R.maxX - minimo) }
        if dx > 0 { maxX = max(min(px, e.base.size.width), R.minX + minimo) }
        if dy > 0 { minY = min(max(py, 0), R.maxY - minimo) }
        if dy < 0 { maxY = max(min(py, e.base.size.height), R.minY + minimo) }
        let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let nw = r.width * s, nh = r.height * s
        let vecchio = CGPoint(x: (r.minX - R.minX) * s - w / 2, y: h / 2 - (r.minY - R.minY) * s)
        let nuovo = CGPoint(x: -nw / 2, y: nh / 2)
        var n = e
        n.impostaRitaglio(r)
        n.larghezza = nw
        n.centro = e.mondo(CGPoint(x: vecchio.x - nuovo.x, y: vecchio.y - nuovo.y))
        return n
    }

    /// Ritaglio a mano libera: il contorno (punti di pagina, chiuso da sé) diventa una maschera dell'immagine.
    /// La parte visibile diventa il riquadro più piccolo che contiene il contorno e il contenuto resta fermo al suo posto.
    /// nil se il contorno è troppo piccolo o fuori dall'immagine.
    static func conContorno(_ e: ElementoImmagine, punti: [CGPoint]) -> ElementoImmagine? {
        guard punti.count > 2 else { return nil }
        let R = e.ritaglio
        let s = e.scala, w = e.larghezza, h = e.altezza
        var pixel: [CGPoint] = []
        for p in punti {
            let l = e.locale(p)
            let x = R.minX + (l.x + w / 2) / s
            let y = R.minY + (h / 2 - l.y) / s
            pixel.append(CGPoint(x: x, y: y))
        }
        let contorno = ElementoImmagine.semplifica(pixel, tolleranza: 0.6)
        guard contorno.count > 2 else { return nil }
        var minX = contorno[0].x, maxX = contorno[0].x, minY = contorno[0].y, maxY = contorno[0].y
        for q in contorno {
            minX = min(minX, q.x)
            maxX = max(maxX, q.x)
            minY = min(minY, q.y)
            maxY = max(maxY, q.y)
        }
        let ingombro = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(R)
        guard !ingombro.isNull, ingombro.width >= 8, ingombro.height >= 8 else { return nil }
        let r = ingombro
        let nw = r.width * s, nh = r.height * s
        let vecchio = CGPoint(x: (r.minX - R.minX) * s - w / 2, y: h / 2 - (r.minY - R.minY) * s)
        let nuovo = CGPoint(x: -nw / 2, y: nh / 2)
        var n = e
        n.maschera.append(contorno)
        n.impostaRitaglio(r)
        n.larghezza = nw
        n.centro = e.mondo(CGPoint(x: vecchio.x - nuovo.x, y: vecchio.y - nuovo.y))
        return n
    }

    /// Linea tratteggiata del contorno mentre lo si disegna
    func mostraContorno(_ pagina: PDFPage) {
        guard let cont = model?.canvases[pagina]?.superview as? PaginaTela else { return }
        let box = pagina.bounds(for: .cropBox)
        let percorso = UIBezierPath()
        for (i, p) in tracciatoContorno.enumerated() {
            let q = CGPoint(x: p.x - box.minX, y: box.maxY - p.y)
            if i == 0 { percorso.move(to: q) } else { percorso.addLine(to: q) }
        }
        var strato = cont.layer.sublayers?.first { $0.name == Self.nomeContorno } as? CAShapeLayer
        if strato == nil {
            let l = CAShapeLayer()
            let colore = UIColor(AptTema.accento)
            l.name = Self.nomeContorno
            l.strokeColor = colore.cgColor
            l.fillColor = colore.withAlphaComponent(0.10).cgColor
            l.lineWidth = 2 * unita
            l.lineDashPattern = [NSNumber(value: Double(6 * unita)), NSNumber(value: Double(4 * unita))]
            l.lineJoin = .round
            l.lineCap = .round
            l.zPosition = 10_000
            cont.layer.addSublayer(l)
            strato = l
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strato?.path = percorso.cgPath
        CATransaction.commit()
    }

    func cancellaContorno() {
        let pagine: [PDFPage] = model.map { Array($0.canvases.keys) } ?? []
        for pagina in pagine {
            guard let cont = model?.canvases[pagina]?.superview as? PaginaTela else { continue }
            cont.layer.sublayers?.filter { $0.name == Self.nomeContorno }.forEach { $0.removeFromSuperlayer() }
        }
    }

    // MARK: Tocco su un punto vuoto della pagina

    @objc func toccato(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let model else { return }
        let pv = g.location(in: g.view)
        guard let (pg, pp) = pagina(in: pv) else { return }
        let strumento = model.corrente?.tipo
        // Maniglie e immagine già scelta: lavora il gesto di trascinamento
        if let s = scelta, s.pagina === pg, let e = elemento(pg, s.id),
           maniglia(e, vicino: pp) != nil || e.contiene(pp, margine: 4 * unita) { return }
        if let e = sotto(pp, in: pg) {
            if strumento == .immagine {
                // Lo afferra il gesto di trascinamento; un tocco semplice del dito la sceglie comunque (senza aspettare la pressione)
                if tipoTocco != .pencil, scelta?.id != e.id {
                    scelta = (pg, e.id)
                    ritagliando = false
                    model.lazo?.deseleziona()
                    mostraSelezione()
                }
                return
            }
            if tipoTocco != .pencil { return }              // col dito si sceglie solo con la pressione lunga
            scelta = (pg, e.id)
            sceltaDaLazo = strumento == .lazo               // con la Pencil e il lazo: la scelta si toglie cambiando strumento
            ritagliando = false
            model.lazo?.deseleziona()
            mostraSelezione()
            return
        }
        if scelta != nil {
            scelta = nil
            ritagliando = false
            mostraSelezione()
            return
        }
        guard strumento == .immagine else { return }
        puntoVuoto = (pg, pp)
        if AppuntiInterni.pieno {
            modoMenu = .vuoto
            menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
        } else {
            model.richiediImmagine(pagina: pg, punto: pp)
        }
    }

    // MARK: Inserimento (dopo la scelta del file)

    /// `documento`: pagina di un documento o scansione, messa grande (80% della pagina) e con più dettaglio
    func inserisci(_ dati: Data, pagina: PDFPage, punto: CGPoint, documento: Bool = false, larghezza: CGFloat? = nil) -> Bool {
        guard let (img, d) = ElementoImmagine.prepara(dati, massimo: documento ? 2000 : 1400) else { return false }
        let box = pagina.bounds(for: .cropBox)
        let w = larghezza.map { min(max($0, 20), box.width) } ?? (documento ? box.width * 0.8 : min(260, box.width * 0.5))
        let h = w * img.size.height / max(img.size.width, 1)
        let c = Self.dentro(punto, mezzaLarghezza: w / 2, mezzaAltezza: h / 2, pagina)
        let e = ElementoImmagine(dati: d, base: img, centro: c, larghezza: w, creazione: Date())
        scelta = (pagina, e.id)
        ritagliando = false
        cambia(pagina, togli: nil, metti: e)
        return true
    }

    static func dentro(_ c: CGPoint, mezzaLarghezza: CGFloat, mezzaAltezza: CGFloat, _ pagina: PDFPage) -> CGPoint {
        let box = pagina.bounds(for: .cropBox)
        return CGPoint(x: min(max(c.x, box.minX + mezzaLarghezza), max(box.minX + mezzaLarghezza, box.maxX - mezzaLarghezza)),
                       y: min(max(c.y, box.minY + mezzaAltezza), max(box.minY + mezzaAltezza, box.maxY - mezzaAltezza)))
    }
}
