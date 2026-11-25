// PROVA «tratti come linee vere» (25/11/2026). Serve solo a CONFRONTARE: non tocca i documenti e non cambia come si salva.
// Dalla finestra «Condividi o esporta» → «Prova: tratti come linee». Per la pagina aperta fa due PDF di prova:
//   • «immagini»: i tratti come oggi (immagini disegnate da PencilKit, 4 px/pt);
//   • «linee»: gli stessi tratti ricostruiti come sagome vere (contorno punto per punto, spessore come PencilKit).
// Poi misura quanto le due versioni si somigliano (pixel in comune / pixel totali) e cerca da sola il fattore di spessore migliore.
import SwiftUI
import PDFKit
import PencilKit

struct CondivisioneProva: Identifiable {
    let id = UUID()
    let urls: [URL]
}

enum LineeVere {
    enum Gruppo: Int, CaseIterable {
        case stilografica, penna, evidenziatore
        var nome: String {
            switch self {
            case .stilografica: return "Stilografica"
            case .penna: return "Penna"
            case .evidenziatore: return "Evidenziatore"
            }
        }
        static func di(_ t: PKStroke) -> Gruppo {
            if NotesModel.eEvidenziatore(t) { return .evidenziatore }
            return t.ink.inkType == .fountainPen ? .stilografica : .penna
        }
    }

    /// Spessore (in punti della tela) di un punto. Stilografica: come misurato in `TrattoStilografico` (1,575 × (grandezza − 2) × fattore della direzione).
    /// Altri inchiostri: la grandezza del punto. `c` = fattore di aggiustamento cercato dalla prova.
    static func larghezza(_ g: Gruppo, size: CGFloat, gradi: Double, c: CGFloat) -> CGFloat {
        switch g {
        case .stilografica: return c * 1.575 * max(size - 2, 0) * CGFloat(TrattoStilografico.fattoreDirezione(gradi))
        default: return c * size
        }
    }

    static func percorso(_ s: PKStroke, g: Gruppo, c: CGFloat, passo: CGFloat) -> (CGPath, CGFloat)? {
        let t = s.transform
        let sc = hypot(t.a, t.b)
        var pts: [(p: CGPoint, size: CGFloat, op: CGFloat)] = []
        for q in s.path.interpolatedPoints(by: .distance(passo)) {
            pts.append((q.location.applying(t), q.size.width * sc, q.opacity))
        }
        let n = pts.count
        guard n > 0 else { return nil }
        let opacita = pts.map { $0.op }.reduce(0, +) / CGFloat(n)
        let path = CGMutablePath()
        if n == 1 {
            let w = larghezza(g, size: pts[0].size, gradi: 0, c: c)
            path.addEllipse(in: CGRect(x: pts[0].p.x - w / 2, y: pts[0].p.y - w / 2, width: w, height: w))
            return (path, opacita)
        }
        var sinistra: [CGPoint] = [], destra: [CGPoint] = [], larghi: [CGFloat] = []
        var ultimo = CGPoint(x: 1, y: 0)
        for i in 0..<n {
            let a = pts[max(0, i - 2)].p, b = pts[min(n - 1, i + 2)].p
            var dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            if len < 1e-6 { dx = ultimo.x; dy = ultimo.y } else { dx /= len; dy /= len; ultimo = CGPoint(x: dx, y: dy) }
            let gradi = Double(atan2(dy, dx)) * 180 / .pi
            let w = larghezza(g, size: pts[i].size, gradi: gradi, c: c)
            larghi.append(w)
            let p = pts[i].p
            sinistra.append(CGPoint(x: p.x - dy * w / 2, y: p.y + dx * w / 2))
            destra.append(CGPoint(x: p.x + dy * w / 2, y: p.y - dx * w / 2))
        }
        path.move(to: sinistra[0])
        for i in 1..<n { path.addLine(to: sinistra[i]) }
        for i in stride(from: n - 1, through: 0, by: -1) { path.addLine(to: destra[i]) }
        path.closeSubpath()
        for i in [0, n - 1] {
            let w = larghi[i], p = pts[i].p
            if w > 0.01 { path.addEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w)) }
        }
        return (path, opacita)
    }

    static func disegna(_ tratti: [PKStroke], g: Gruppo, c: CGFloat, passo: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        if g == .evidenziatore { ctx.setBlendMode(.multiply) }
        for s in tratti {
            guard let (p, op) = percorso(s, g: g, c: c, passo: passo) else { continue }
            let col = s.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            ctx.setFillColor(col.withAlphaComponent(col.cgColor.alpha * op).cgColor)
            ctx.addPath(p)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    static func immaginePencilKit(_ tratti: [PKStroke], rect: CGRect, scala: CGFloat) -> UIImage? {
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = PKDrawing(strokes: tratti).image(from: rect, scale: scala)
        }
        return img
    }

    static func immagineLinee(_ tratti: [PKStroke], g: Gruppo, c: CGFloat, passo: CGFloat, rect: CGRect, scala: CGFloat) -> UIImage {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = scala
        formato.opaque = false
        return UIGraphicsImageRenderer(size: rect.size, format: formato).image { r in
            r.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            disegna(tratti, g: g, c: c, passo: passo, in: r.cgContext)
        }
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

    /// (somiglianza 0…1 = pixel in comune / pixel di almeno uno dei due, rapporto area linee / area PencilKit)
    static func somiglianza(_ a: [UInt8], _ b: [UInt8]) -> (Double, Double) {
        var comune = 0, unione = 0, sa = 0, sb = 0
        for k in 0..<min(a.count, b.count) {
            let x = a[k] > 40, y = b[k] > 40
            if x && y { comune += 1 }
            if x || y { unione += 1 }
            if x { sa += 1 }
            if y { sb += 1 }
        }
        return (unione > 0 ? Double(comune) / Double(unione) : 1, sa > 0 ? Double(sb) / Double(sa) : 0)
    }
}

extension NotesModel {
    /// Prova: due PDF della pagina corrente (immagini e linee) e misura della somiglianza. Non scrive nulla nei documenti.
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
        let passo = 0.5 / max(f, 0.0001)
        let base = (fileName as NSString).deletingPathExtension

        var gruppi: [LineeVere.Gruppo: [PKStroke]] = [:]
        for t in tratti { gruppi[LineeVere.Gruppo.di(t), default: []].append(t) }

        var scelti: [LineeVere.Gruppo: CGFloat] = [:]
        var rettangoli: [LineeVere.Gruppo: CGRect] = [:]
        var righe: [String] = []
        for g in LineeVere.Gruppo.allCases {
            guard let ts = gruppi[g] else { continue }
            let limite = canvas.bounds
            let r = PKDrawing(strokes: ts).bounds.insetBy(dx: -6, dy: -6).intersection(limite).integral
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            rettangoli[g] = r
            let scalaConfronto = min(2 / max(f, 0.0001), sqrt(3_000_000 / (r.width * r.height)))
            guard let a = LineeVere.immaginePencilKit(ts, rect: r, scala: scalaConfronto), let cg = a.cgImage else { continue }
            let alfaA = LineeVere.alfa(a, larg: cg.width, alt: cg.height)
            var migliore: (c: CGFloat, iou: Double, rapporto: Double) = (1, -1, 0)
            for k in stride(from: 0.5, through: 1.7, by: 0.1) {
                let c = CGFloat(k)
                let b = LineeVere.immagineLinee(ts, g: g, c: c, passo: passo, rect: r, scala: scalaConfronto)
                let (iou, rap) = LineeVere.somiglianza(alfaA, LineeVere.alfa(b, larg: cg.width, alt: cg.height))
                if iou > migliore.iou { migliore = (c, iou, rap) }
            }
            scelti[g] = migliore.c
            righe.append("\(g.nome): \(ts.count) tratti, somiglianza \(Int((migliore.iou * 100).rounded()))% con spessore ×\(String(format: "%.1f", migliore.c)) (area linee/PencilKit \(String(format: "%.2f", migliore.rapporto)))")
        }

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

        let nomeBase = base.isEmpty ? "Pagina" : base
        let urlImmagini = pdf("\(nomeBase) - prova immagini.pdf") { cg in
            for g in LineeVere.Gruppo.allCases {
                guard let ts = gruppi[g], let r = rettangoli[g] else { continue }
                let px = min(4 / max(f, 0.0001), sqrt(Self.pixelMassimiTratti / (r.width * r.height)))
                guard let img = LineeVere.immaginePencilKit(ts, rect: r, scala: px) else { continue }
                img.draw(in: CGRect(x: r.minX * f, y: r.minY * f, width: r.width * f, height: r.height * f),
                         blendMode: g == .evidenziatore ? .multiply : .normal, alpha: 1)
            }
        }
        let urlLinee = pdf("\(nomeBase) - prova linee.pdf") { cg in
            cg.saveGState()
            cg.scaleBy(x: f, y: f)
            for g in LineeVere.Gruppo.allCases {
                guard let ts = gruppi[g], let c = scelti[g] else { continue }
                LineeVere.disegna(ts, g: g, c: c, passo: passo, in: cg)
            }
            cg.restoreGState()
        }
        let urls = [urlImmagini, urlLinee].compactMap { $0 }
        func peso(_ u: URL?) -> String {
            guard let u, let n = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size]) as? Int else { return "?" }
            return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
        }
        righe.append("Peso: immagini \(peso(urlImmagini)), linee \(peso(urlLinee))")
        message = righe.joined(separator: "\n")
        Diagnostica.nota("prova-linee", righe.joined(separator: " | "))
        fine(urls)
    }
}
