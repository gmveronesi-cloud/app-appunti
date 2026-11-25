// PROVA «tratti come contorni vettoriali» (25/11/2026). Serve solo a CONFRONTARE: non tocca i documenti e non cambia come si salva.
// Dalla finestra «Condividi o esporta» → «Prova: tratti come linee». Per la pagina aperta fa tre PDF di prova (la terza, «livelli», è del 26/11: evidenziatore senza Multiply):
//   • «immagini»: i tratti come oggi (immagini disegnate da PencilKit, 4 px/pt);
//   • «contorni»: PencilKit disegna i tratti ad alta risoluzione, se ne ricava il CONTORNO (marching squares + semplificazione)
//     e il contorno si scrive come figura vera del PDF (nitida a ogni zoom). La forma è quella di PencilKit per costruzione.
// Poi misura la somiglianza, il tempo di calcolo e il peso. Inchiostri con texture (matita, pastello, acquerello) restano immagini.
// (La prima versione, con lo spessore calcolato punto per punto, dava 68–86%: scartata il 25/11.)
import SwiftUI
import PDFKit
import PencilKit

struct CondivisioneProva: Identifiable {
    let id = UUID()
    let urls: [URL]
}

enum Contorni {
    struct Campo {
        let larg: Int
        let alt: Int
        let a: [UInt8]
    }

    /// Canale alfa dell'immagine, con 1 pixel vuoto di bordo (così ogni contorno si chiude)
    static func campo(da img: UIImage) -> Campo? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width + 2, h = cg.height + 2
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 1, y: 1, width: cg.width, height: cg.height))
            return true
        }
        guard ok else { return nil }
        var a = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { a[i] = buf[i * 4 + 3] }
        return Campo(larg: w, alt: h, a: a)
    }

    /// Contorni (marching squares con interpolazione: posizione sotto il pixel). Coordinate: indici del campo.
    static func contorni(_ c: Campo, soglia: Float = 127.5) -> [[CGPoint]] {
        let w = c.larg, h = c.alt
        guard w > 2, h > 2 else { return [] }
        func v(_ x: Int, _ y: Int) -> Float { Float(c.a[y * w + x]) }
        var vicini: [Int: [Int]] = [:]
        func collega(_ p: Int, _ q: Int) {
            vicini[p, default: []].append(q)
            vicini[q, default: []].append(p)
        }
        for y in 0..<(h - 1) {
            for x in 0..<(w - 1) {
                let tl = v(x, y) >= soglia, tr = v(x + 1, y) >= soglia, br = v(x + 1, y + 1) >= soglia, bl = v(x, y + 1) >= soglia
                let caso = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
                if caso == 0 || caso == 15 { continue }
                let T = (y * w + x) * 2
                let B = ((y + 1) * w + x) * 2
                let L = (y * w + x) * 2 + 1
                let R = (y * w + x + 1) * 2 + 1
                switch caso {
                case 1, 14: collega(L, B)
                case 2, 13: collega(B, R)
                case 3, 12: collega(L, R)
                case 4, 11: collega(T, R)
                case 5: collega(T, L); collega(B, R)
                case 6, 9: collega(T, B)
                case 7, 8: collega(T, L)
                case 10: collega(T, R); collega(L, B)
                default: break
                }
            }
        }
        func pos(_ id: Int) -> CGPoint {
            let k = id & 1, cella = id >> 1
            let x = cella % w, y = cella / w
            if k == 0 {
                let v0 = v(x, y), v1 = v(x + 1, y)
                let t = v1 == v0 ? 0.5 : (soglia - v0) / (v1 - v0)
                return CGPoint(x: CGFloat(x) + CGFloat(t), y: CGFloat(y))
            } else {
                let v0 = v(x, y), v1 = v(x, y + 1)
                let t = v1 == v0 ? 0.5 : (soglia - v0) / (v1 - v0)
                return CGPoint(x: CGFloat(x), y: CGFloat(y) + CGFloat(t))
            }
        }
        var visitati = Set<Int>()
        var cicli: [[CGPoint]] = []
        for (inizio, _) in vicini where !visitati.contains(inizio) {
            var ciclo: [CGPoint] = []
            var prec = -1, cur = inizio
            while true {
                visitati.insert(cur)
                ciclo.append(pos(cur))
                var prossimo = -1
                for n in vicini[cur] ?? [] where n != prec { prossimo = n; break }
                if prossimo == -1 || prossimo == inizio || visitati.contains(prossimo) { break }
                prec = cur
                cur = prossimo
            }
            if ciclo.count >= 3 { cicli.append(ciclo) }
        }
        return cicli
    }

    private static func distanza(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        if l2 < 1e-12 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func douglasPeucker(_ p: [CGPoint], _ tol: CGFloat) -> [CGPoint] {
        guard p.count > 2 else { return p }
        var tieni = [Bool](repeating: false, count: p.count)
        tieni[0] = true
        tieni[p.count - 1] = true
        var pila = [(0, p.count - 1)]
        while let (i, j) = pila.popLast() {
            if j <= i + 1 { continue }
            var dmax: CGFloat = -1, k = i
            for m in (i + 1)..<j {
                let d = distanza(p[m], p[i], p[j])
                if d > dmax { dmax = d; k = m }
            }
            if dmax > tol {
                tieni[k] = true
                pila.append((i, k))
                pila.append((k, j))
            }
        }
        var out: [CGPoint] = []
        for i in 0..<p.count where tieni[i] { out.append(p[i]) }
        return out
    }

    /// Semplifica un contorno chiuso (tolleranza in pixel)
    static func semplifica(_ p: [CGPoint], tol: CGFloat) -> [CGPoint] {
        guard p.count > 8 else { return p }
        var j = 1
        var dmax: CGFloat = -1
        for i in 1..<p.count {
            let d = hypot(p[i].x - p[0].x, p[i].y - p[0].y)
            if d > dmax { dmax = d; j = i }
        }
        let a = Array(p[0...j])
        let b = Array(p[j...]) + [p[0]]
        return Array(douglasPeucker(a, tol).dropLast()) + Array(douglasPeucker(b, tol).dropLast())
    }

    static func alfa(_ img: UIImage, larg: Int, alt: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: larg * alt * 4)
        buf.withUnsafeMutableBytes { raw in
            guard let cg = img.cgImage,
                  let ctx = CGContext(data: raw.baseAddress, width: larg, height: alt, bitsPerComponent: 8, bytesPerRow: larg * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: larg, height: alt))
        }
        return stride(from: 3, to: buf.count, by: 4).map { buf[$0] }
    }
}

extension NotesModel {
    private struct ChiaveColore: Hashable {
        let r: Int, g: Int, b: Int, a: Int
        let evidenziatore: Bool
    }

    private struct GruppoContorni {
        var tratti: [PKStroke]
        let colore: UIColor
        let evidenziatore: Bool
        var rettangolo: CGRect = .zero
        var path = CGMutablePath()
        var opacita: CGFloat = 1
        var punti = 0
        var primo: Date = .distantFuture
    }

    private static func texture(_ t: PKStroke) -> Bool {
        [PKInk.InkType.pencil, .crayon, .watercolor].contains(t.ink.inkType)
    }

    /// Un livello dell'evidenziatore: forma piena riempita con trasparenza normale (senza Multiply)
    private struct LivelloEvidenziatore {
        let path: CGPath
        let colore: UIColor
    }

    /// Evidenziatore «a livelli» (prova del 26/11): tutti i tratti dello stesso colore vengono disegnati insieme da PencilKit,
    /// com'è nell'app. Dall'immagine si misurano l'opacità di un tratto singolo e, se ci sono, quella delle sovrapposizioni;
    /// ogni livello è un contorno riempito con trasparenza normale. Dove due tratti si incrociano il colore si scurisce poco, come in PencilKit.
    private func livelliEvidenziatore(_ tratti: [PKStroke], canvas: PKCanvasView, f: CGFloat, luce: UITraitCollection) -> [LivelloEvidenziatore] {
        var mappa: [ChiaveColore: (col: UIColor, ts: [PKStroke])] = [:]
        for t in tratti where !Self.texture(t) && Self.eEvidenziatore(t) {
            let col = t.ink.color.resolvedColor(with: luce)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            col.getRed(&r, green: &g, blue: &b, alpha: &a)
            let k = ChiaveColore(r: Int(r * 255), g: Int(g * 255), b: Int(b * 255), a: Int(a * 100), evidenziatore: true)
            var v = mappa[k] ?? (col: col, ts: [PKStroke]())
            v.ts.append(t)
            mappa[k] = v
        }
        var livelli: [LivelloEvidenziatore] = []
        for (_, v) in mappa {
            let ts = v.ts
            let r = PKDrawing(strokes: ts).bounds.insetBy(dx: -6, dy: -6).intersection(canvas.bounds).integral
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            let areaPagina = r.width * f * r.height * f
            let pp = min(6, sqrt(4_000_000 / max(areaPagina, 1)))
            let scala = pp / max(f, 0.0001)
            var img: UIImage?
            luce.performAsCurrent { img = PKDrawing(strokes: ts).image(from: r, scale: scala) }
            guard let immagine = img, let cg = immagine.cgImage, let campo = Contorni.campo(da: immagine) else { continue }
            var istogramma = [Int](repeating: 0, count: 256)
            for x in campo.a where x > 10 { istogramma[Int(x)] += 1 }
            let totale = istogramma.reduce(0, +)
            guard totale > 0 else { continue }
            // Opacità di un tratto singolo = valore più frequente (ignorando i bordi sfumati)
            var tipica = 25
            for i in 25..<256 where istogramma[i] > istogramma[tipica] { tipica = i }
            // Sovrapposizioni: pixel nettamente più opachi del tratto singolo
            let limite = Int(Float(tipica) * 1.15) + 1
            var n2 = 0, somma = 0
            if limite < 256 { for i in limite..<256 { n2 += istogramma[i]; somma += istogramma[i] * i } }
            var colore = [CGFloat](repeating: 0, count: 4)
            v.col.getRed(&colore[0], green: &colore[1], blue: &colore[2], alpha: &colore[3])
            let sx = CGFloat(cg.width) / r.width, sy = CGFloat(cg.height) / r.height
            func forma(_ soglia: Float) -> CGPath {
                let path = CGMutablePath()
                for ciclo in Contorni.contorni(campo, soglia: soglia) {
                    let semplice = Contorni.semplifica(ciclo, tol: 0.35)
                    guard semplice.count >= 3 else { continue }
                    path.addLines(between: semplice.map { CGPoint(x: r.minX + ($0.x - 0.5) / sx, y: r.minY + ($0.y - 0.5) / sy) })
                    path.closeSubpath()
                }
                return path
            }
            let a1 = CGFloat(tipica) / 255
            livelli.append(LivelloEvidenziatore(path: forma(max(Float(tipica) / 2, 6)),
                                                colore: UIColor(red: colore[0], green: colore[1], blue: colore[2], alpha: a1)))
            if n2 * 500 >= totale {            // almeno lo 0,2% del tratto è sovrapposto
                let a2 = CGFloat(somma) / CGFloat(n2) / 255
                let extra = max(0, min(1, 1 - (1 - a2) / (1 - a1)))     // trasparenza da aggiungere perché il totale sia a2
                livelli.append(LivelloEvidenziatore(path: forma((Float(tipica) + Float(somma) / Float(n2)) / 2),
                                                    colore: UIColor(red: colore[0], green: colore[1], blue: colore[2], alpha: extra)))
            }
        }
        return livelli
    }

    /// Prova: tre PDF della pagina corrente (immagini e contorni) e misura di somiglianza, tempo e peso. Non scrive nulla nei documenti.
    func provaLinee(pagina indice: Int, fine: @escaping ([URL]) -> Void) {
        guard let document, let page = document.page(at: indice) else { fine([]); return }
        guard let canvas = canvases[page], canvas.bounds.width > 0 else {
            message = "Apri la pagina con i tratti e riprova."
            fine([]); return
        }
        let tratti = tuttiITratti(page)
        guard !tratti.isEmpty else { message = "Questa pagina non ha tratti: scrivi qualcosa e riprova."; fine([]); return }
        let box = page.bounds(for: .cropBox)
        let f = box.width / canvas.bounds.width
        let base = (fileName as NSString).deletingPathExtension
        let luce = UITraitCollection(userInterfaceStyle: .light)

        // Gruppi per colore (e per evidenziatore); gli inchiostri con texture restano immagini
        var mappa: [ChiaveColore: GruppoContorni] = [:]
        var texturati: [PKStroke] = []
        var singoli: [GruppoContorni] = []
        for t in tratti {
            if Self.texture(t) { texturati.append(t); continue }
            let col = t.ink.color.resolvedColor(with: luce)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            col.getRed(&r, green: &g, blue: &b, alpha: &a)
            let k = ChiaveColore(r: Int(r * 255), g: Int(g * 255), b: Int(b * 255), a: Int(a * 100), evidenziatore: Self.eEvidenziatore(t))
            if k.evidenziatore {
                // Ogni tratto di evidenziatore è un gruppo a sé: dove due si sovrappongono il colore si scurisce (multiply), come in PencilKit
                singoli.append(GruppoContorni(tratti: [t], colore: col, evidenziatore: true, primo: t.path.creationDate))
                continue
            }
            var gr = mappa[k] ?? GruppoContorni(tratti: [], colore: col, evidenziatore: false)
            gr.tratti.append(t)
            gr.primo = min(gr.primo, t.path.creationDate)
            mappa[k] = gr
        }
        var gruppi = (Array(mappa.values) + singoli).sorted { $0.primo < $1.primo }

        let inizio = CFAbsoluteTimeGetCurrent()
        var comune = 0, unione = 0
        var peggiore = 1.0
        for n in gruppi.indices {
            let ts = gruppi[n].tratti
            let r = PKDrawing(strokes: ts).bounds.insetBy(dx: -6, dy: -6).intersection(canvas.bounds).integral
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            gruppi[n].rettangolo = r
            let areaPagina = r.width * f * r.height * f
            let pp = min(6, sqrt(4_000_000 / max(areaPagina, 1)))      // pixel per punto della pagina
            let scala = pp / max(f, 0.0001)                              // pixel per punto della tela
            var img: UIImage?
            luce.performAsCurrent { img = PKDrawing(strokes: ts).image(from: r, scale: scala) }
            guard let immagine = img, let cg = immagine.cgImage, let campo = Contorni.campo(da: immagine) else { continue }
            // Soglia del contorno: metà dell'opacità tipica del gruppo (l'evidenziatore è trasparente, spesso sotto il 50%:
            // con la soglia fissa a 127,5 il contorno non si trovava — errore della prima prova del 25/11, gruppo al 0%)
            // (vale per ogni gruppo: con inchiostro pieno l'opacità tipica è 255 e la soglia torna 127,5)
            var istogramma = [Int](repeating: 0, count: 256)
            for v in campo.a where v > 10 { istogramma[Int(v)] += 1 }
            let totale = istogramma.reduce(0, +)
            var cumulo = 0, tipica = 255
            for i in 0..<256 {
                cumulo += istogramma[i]
                if totale > 0 && cumulo * 100 >= totale * 90 { tipica = i; break }
            }
            let soglia = max(Float(tipica) / 2, 6)
            gruppi[n].opacita = CGFloat(tipica) / 255
            let sx = CGFloat(cg.width) / r.width, sy = CGFloat(cg.height) / r.height
            for ciclo in Contorni.contorni(campo, soglia: soglia) {
                let semplice = Contorni.semplifica(ciclo, tol: 0.35)
                guard semplice.count >= 3 else { continue }
                // indice del campo → pixel dell'immagine (−0,5) → punti della tela
                let punti = semplice.map { CGPoint(x: r.minX + ($0.x - 0.5) / sx, y: r.minY + ($0.y - 0.5) / sy) }
                gruppi[n].path.addLines(between: punti)
                gruppi[n].path.closeSubpath()
                gruppi[n].punti += punti.count
            }
            // Somiglianza: contorno ridisegnato a 2 px/pt contro l'immagine di PencilKit alla stessa misura
            let sc2 = 2 / max(f, 0.0001)
            var confronto: UIImage?
            luce.performAsCurrent { confronto = PKDrawing(strokes: ts).image(from: r, scale: sc2) }
            if let ref = confronto, let refCG = ref.cgImage {
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = CGFloat(refCG.width) / r.width
                fmt.opaque = false
                let mio = UIGraphicsImageRenderer(size: r.size, format: fmt).image { rc in
                    rc.cgContext.translateBy(x: -r.minX, y: -r.minY)
                    rc.cgContext.setFillColor(UIColor.black.cgColor)
                    rc.cgContext.addPath(gruppi[n].path)
                    rc.cgContext.fillPath(using: .evenOdd)
                }
                let a1 = Contorni.alfa(ref, larg: refCG.width, alt: refCG.height)
                let a2 = Contorni.alfa(mio, larg: refCG.width, alt: refCG.height)
                var c = 0, u = 0
                for i in 0..<min(a1.count, a2.count) {
                    let x = a1[i] > 40, y = a2[i] > 40
                    if x && y { c += 1 }
                    if x || y { u += 1 }
                }
                comune += c; unione += u
                if u > 0 { peggiore = min(peggiore, Double(c) / Double(u)) }
            }
        }
        let tempo = CFAbsoluteTimeGetCurrent() - inizio

        func pdf(_ nome: String, _ disegna: (CGContext) -> Void) -> URL? {
            let rend = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: box.size))
            let dati = rend.pdfData { ctx in
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: box.height); cg.scaleBy(x: 1, y: -1); cg.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .cropBox, to: cg)
                cg.restoreGState()
                disegna(cg)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(nome)
            do { try dati.write(to: url, options: .atomic); return url } catch { return nil }
        }
        func immagineTratti(_ ts: [PKStroke], multiply: Bool) {
            let r = PKDrawing(strokes: ts).bounds.insetBy(dx: -6, dy: -6).intersection(canvas.bounds).integral
            guard !r.isNull, r.width > 0, r.height > 0 else { return }
            let px = min(4 / max(f, 0.0001), sqrt(Self.pixelMassimiTratti / (r.width * r.height)))
            var img: UIImage?
            luce.performAsCurrent { img = PKDrawing(strokes: ts).image(from: r, scale: px) }
            img?.draw(in: CGRect(x: r.minX * f, y: r.minY * f, width: r.width * f, height: r.height * f),
                      blendMode: multiply ? .multiply : .normal, alpha: 1)
        }

        let nomeBase = base.isEmpty ? "Pagina" : base
        let urlImmagini = pdf("\(nomeBase) - prova immagini.pdf") { _ in
            // Riferimento «come l'app»: inchiostri nell'ordine, poi gli evidenziatori dello stesso colore disegnati insieme da PencilKit (trasparenza normale)
            for g in gruppi where !g.evidenziatore { immagineTratti(g.tratti, multiply: false) }
            var perColore: [String: [PKStroke]] = [:]
            for g in gruppi where g.evidenziatore { perColore[g.colore.description, default: []] += g.tratti }
            for ts in perColore.values { immagineTratti(ts, multiply: false) }
            if !texturati.isEmpty { immagineTratti(texturati, multiply: false) }
        }
        let urlContorni = pdf("\(nomeBase) - prova contorni.pdf") { cg in
            for g in gruppi where !g.path.isEmpty {
                cg.saveGState()
                if g.evidenziatore { cg.setBlendMode(.multiply) }
                cg.scaleBy(x: f, y: f)
                cg.setFillColor(g.colore.withAlphaComponent(g.opacita).cgColor)
                cg.addPath(g.path)
                cg.fillPath(using: .evenOdd)
                cg.restoreGState()
            }
            if !texturati.isEmpty { immagineTratti(texturati, multiply: false) }
        }
        // Terza variante (26/11): evidenziatore a livelli, trasparenza normale, sempre sopra l'inchiostro
        let livelli = livelliEvidenziatore(tratti, canvas: canvas, f: f, luce: luce)
        let urlLivelli = pdf("\(nomeBase) - prova livelli.pdf") { cg in
            for g in gruppi where !g.evidenziatore && !g.path.isEmpty {
                cg.saveGState()
                cg.scaleBy(x: f, y: f)
                cg.setFillColor(g.colore.withAlphaComponent(g.opacita).cgColor)
                cg.addPath(g.path)
                cg.fillPath(using: .evenOdd)
                cg.restoreGState()
            }
            for l in livelli {
                cg.saveGState()
                cg.scaleBy(x: f, y: f)
                cg.setFillColor(l.colore.cgColor)
                cg.addPath(l.path)
                cg.fillPath(using: .evenOdd)
                cg.restoreGState()
            }
            if !texturati.isEmpty { immagineTratti(texturati, multiply: false) }
        }
        let urls = [urlImmagini, urlContorni, urlLivelli].compactMap { $0 }
        func peso(_ u: URL?) -> String {
            guard let u, let n = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size]) as? Int else { return "?" }
            return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
        }
        let punti = gruppi.reduce(0) { $0 + $1.punti }
        let somiglianza = unione > 0 ? Int((Double(comune) / Double(unione) * 100).rounded()) : 0
        let righe = [
            "Contorni: \(gruppi.count) gruppi di colore, \(tratti.count) tratti, \(punti) punti",
            "Somiglianza con PencilKit: \(somiglianza)% (gruppo peggiore \(Int((peggiore * 100).rounded()))%)",
            "Tempo di calcolo: \(String(format: "%.1f", tempo)) s",
            "Peso: immagini \(peso(urlImmagini)), contorni \(peso(urlContorni)), livelli \(peso(urlLivelli))",
            "Livelli evidenziatore: \(livelli.count)"
        ]
        message = righe.joined(separator: "\n")
        Diagnostica.nota("prova-linee", righe.joined(separator: " | "))
        fine(urls)
    }
}
