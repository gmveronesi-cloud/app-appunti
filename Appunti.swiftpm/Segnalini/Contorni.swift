// Contorni dei tratti (marching squares + semplificazione): usati dal formato a segnalini per scrivere i tratti come figure vere del PDF.
// Nati nella prova «tratti come linee» del 25–26/11/2026 (tolta il 27/11).
import UIKit

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

    /// Per gli evidenziatori: immagine come pixel premoltiplicati RGBA (con 1 pixel di bordo) e campo «scuro» = alfa − luminanza premoltiplicata,
    /// cioè di quanto il tratto scurisce una carta bianca. Misura insieme trasparenza e scurimento delle sovrapposizioni.
    static func campoScuro(da img: UIImage) -> (scuro: Campo, buf: [UInt8])? {
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
        var f = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Float(buf[i * 4]), g = Float(buf[i * 4 + 1]), b = Float(buf[i * 4 + 2]), a = Float(buf[i * 4 + 3])
            f[i] = UInt8(max(0, min(255, a - (0.299 * r + 0.587 * g + 0.114 * b))))
        }
        return (Campo(larg: w, alt: h, a: f), buf)
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
