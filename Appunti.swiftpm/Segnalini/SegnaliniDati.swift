// Formato «a segnalini»: contenuto di «D:» (docs/formato-segnalini.md §2).
// Binario nostro (non il formato interno di PencilKit): numeri interi a lunghezza variabile, punti dei tratti scritti come
// differenze dal punto precedente. Coordinate relative all'angolo del foglio (cropBox), come le vecchie annotazioni.
import UIKit
import PencilKit

struct ScrittoreBinario {
    var b: [UInt8] = []
    mutating func u(_ v: UInt64) {
        var x = v
        while x >= 0x80 { b.append(UInt8(x & 0x7F) | 0x80); x >>= 7 }
        b.append(UInt8(x))
    }
    mutating func n(_ v: Int) { u(UInt64(max(0, v))) }
    mutating func i(_ v: Int64) { u(UInt64(bitPattern: (v << 1) ^ (v >> 63))) }
    mutating func d(_ v: Double) {
        let x = v.bitPattern
        for k in 0..<8 { b.append(UInt8((x >> (8 * UInt64(k))) & 0xFF)) }
    }
    mutating func s(_ t: String) {
        let a = Array(t.utf8)
        n(a.count)
        b += a
    }
    /// Numero con la virgola, arrotondato a 1/scala
    static func q(_ v: Double, _ scala: Double) -> Int64 {
        guard v.isFinite else { return 0 }
        return Int64(max(-1e15, min(1e15, (v * scala).rounded())))
    }
    mutating func f(_ v: Double, _ scala: Double) { i(Self.q(v, scala)) }
}

enum ErroreDatiSegnalini: Error { case corto, valore(String) }

struct LettoreBinario {
    let b: [UInt8]
    var p = 0
    init(_ d: Data) { b = [UInt8](d) }
    mutating func u() throws -> UInt64 {
        var v: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard p < b.count else { throw ErroreDatiSegnalini.corto }
            let x = b[p]
            p += 1
            guard shift < 64 else { throw ErroreDatiSegnalini.valore("numero troppo lungo") }
            v |= UInt64(x & 0x7F) << shift
            if x < 0x80 { return v }
            shift += 7
        }
    }
    mutating func n() throws -> Int {
        let v = try u()
        guard v < (1 << 40) else { throw ErroreDatiSegnalini.valore("quantità") }
        return Int(v)
    }
    mutating func i() throws -> Int64 {
        let v = try u()
        return Int64(bitPattern: v >> 1) ^ -Int64(bitPattern: v & 1)
    }
    mutating func d() throws -> Double {
        guard p + 8 <= b.count else { throw ErroreDatiSegnalini.corto }
        var x: UInt64 = 0
        for k in 0..<8 { x |= UInt64(b[p + k]) << (8 * UInt64(k)) }
        p += 8
        return Double(bitPattern: x)
    }
    mutating func s() throws -> String {
        let n = try n()
        guard p + n <= b.count else { throw ErroreDatiSegnalini.corto }
        let t = String(decoding: b[p..<(p + n)], as: UTF8.self)
        p += n
        return t
    }
    mutating func f(_ scala: Double) throws -> Double { Double(try i()) / scala }
}

/// Immagine come descritta in «D:» (i byte stanno nel PDF, nell'immagine disegnata dalla «Do» numero `indiceDo` del blocco)
struct SpecImmagine {
    var id: UUID
    var creazione: Date
    var centro: CGPoint             // coordinate PDF assolute
    var larghezza: CGFloat
    var angolo: CGFloat
    var ritaglio: CGRect
    var maschera: [[CGPoint]]
    var indiceDo: Int
}

enum DatiSegnalini {
    static let magia: [UInt8] = Array("APTD".utf8)
    static let versione = 1

    private static func rgba(_ c: UIColor) -> [Double] {
        let col = c.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !col.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            if col.getWhite(&w, alpha: &a) { r = w; g = w; b = w } else { a = 1 }
        }
        return [Double(r), Double(g), Double(b), Double(a)]
    }

    private static func scriviColore(_ w: inout ScrittoreBinario, _ c: UIColor) {
        for v in rgba(c) { w.f(v, 10_000) }
    }

    private static func leggiColore(_ r: inout LettoreBinario) throws -> UIColor {
        let v = try (0..<4).map { _ in try r.f(10_000) }
        return UIColor(red: v[0], green: v[1], blue: v[2], alpha: v[3])
    }

    private static func scriviPercorso(_ w: inout ScrittoreBinario, _ p: CGPath) {
        var el: [(Int, [CGPoint])] = []
        p.applyWithBlock { e in
            let pt = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: el.append((0, [pt[0]]))
            case .addLineToPoint: el.append((1, [pt[0]]))
            case .addQuadCurveToPoint: el.append((2, [pt[0], pt[1]]))
            case .addCurveToPoint: el.append((3, [pt[0], pt[1], pt[2]]))
            case .closeSubpath: el.append((4, []))
            @unknown default: break
            }
        }
        w.n(el.count)
        for (t, pts) in el {
            w.n(t)
            for q in pts { w.f(Double(q.x), 100); w.f(Double(q.y), 100) }
        }
    }

    private static func leggiPercorso(_ r: inout LettoreBinario) throws -> UIBezierPath {
        let p = UIBezierPath()
        let n = try r.n()
        func pt() throws -> CGPoint { CGPoint(x: try r.f(100), y: try r.f(100)) }
        for _ in 0..<n {
            switch try r.n() {
            case 0: p.move(to: try pt())
            case 1: p.addLine(to: try pt())
            case 2: let a = try pt(); let b = try pt(); p.addQuadCurve(to: b, controlPoint: a)
            case 3: let a = try pt(); let b = try pt(); let c = try pt(); p.addCurve(to: c, controlPoint1: a, controlPoint2: b)
            case 4: p.close()
            default: throw ErroreDatiSegnalini.valore("percorso")
            }
        }
        return p
    }

    /// `tratti` in punti di pagina con origine in alto a sinistra del foglio (come `AptDati`); `immagini` con l'indice della loro «Do»
    static func codifica(tratti: [PKStroke], immagini: [(ElementoImmagine, Int)], testi: [ElementoTesto], box: CGRect) -> Data {
        var w = ScrittoreBinario()
        w.b += magia
        w.n(versione)
        w.f(Double(box.width), 100)
        w.f(Double(box.height), 100)

        w.n(tratti.count)
        for t in tratti {
            w.s(t.ink.inkType.rawValue)
            scriviColore(&w, t.ink.color)
            if t.transform.isIdentity { w.n(0) } else {
                w.n(1)
                let m = t.transform
                for v in [m.a, m.b, m.c, m.d, m.tx, m.ty] { w.d(Double(v)) }
            }
            if let mask = t.mask { w.n(1); scriviPercorso(&w, mask.cgPath) } else { w.n(0) }
            w.u(UInt64(t.randomSeed))
            w.d(t.path.creationDate.timeIntervalSinceReferenceDate)
            let punti = Array(t.path)
            w.n(punti.count)
            var prima = [Int64](repeating: 0, count: 10)
            for p in punti {
                let v: [Int64] = [
                    ScrittoreBinario.q(Double(p.location.x), 100), ScrittoreBinario.q(Double(p.location.y), 100),
                    ScrittoreBinario.q(p.timeOffset, 1000),
                    ScrittoreBinario.q(Double(p.size.width), 100), ScrittoreBinario.q(Double(p.size.height), 100),
                    ScrittoreBinario.q(Double(p.opacity), 1000), ScrittoreBinario.q(Double(p.force), 1000),
                    ScrittoreBinario.q(Double(p.azimuth), 1000), ScrittoreBinario.q(Double(p.altitude), 1000),
                    ScrittoreBinario.q(Double(p.secondaryScale), 1000)
                ]
                for k in 0..<10 { w.i(v[k] - prima[k]) }
                prima = v
            }
        }

        w.n(immagini.count)
        for (e, k) in immagini {
            w.s(e.id.uuidString)
            w.d(e.creazione.timeIntervalSinceReferenceDate)
            w.f(Double(e.centro.x - box.minX), 100)
            w.f(Double(e.centro.y - box.minY), 100)
            w.f(Double(e.larghezza), 100)
            w.d(Double(e.angolo))
            for v in [e.ritaglio.minX, e.ritaglio.minY, e.ritaglio.width, e.ritaglio.height] { w.f(Double(v), 100) }
            w.n(e.maschera.count)
            for poligono in e.maschera {
                w.n(poligono.count)
                for q in poligono { w.f(Double(q.x), 10); w.f(Double(q.y), 10) }
            }
            w.n(k)
        }

        w.n(testi.count)
        for e in testi {
            w.s(e.id.uuidString)
            w.s(e.testo)
            w.f(Double(e.punto.x - box.minX), 100)
            w.f(Double(e.punto.y - box.minY), 100)
            w.f(Double(e.corpo), 100)
            scriviColore(&w, e.colore)
            if let l = e.larghezza { w.n(1); w.f(Double(l), 100) } else { w.n(0) }
            w.d(e.creazione.timeIntervalSinceReferenceDate)
        }
        return Data(w.b)
    }

    static func decodifica(_ d: Data, box: CGRect) throws -> (tratti: [PKStroke], immagini: [SpecImmagine], testi: [ElementoTesto]) {
        var r = LettoreBinario(d)
        guard r.b.count >= 4, Array(r.b[0..<4]) == magia else { throw ErroreDatiSegnalini.valore("intestazione") }
        r.p = 4
        guard try r.n() == versione else { throw ErroreDatiSegnalini.valore("versione dei dati") }
        _ = try r.f(100)
        _ = try r.f(100)

        var tratti: [PKStroke] = []
        let nt = try r.n()
        for _ in 0..<nt {
            let tipo = PKInk.InkType(rawValue: try r.s())
            let colore = try leggiColore(&r)
            var transform = CGAffineTransform.identity
            if try r.n() == 1 {
                let v = try (0..<6).map { _ in CGFloat(try r.d()) }
                transform = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            }
            let mask: UIBezierPath? = try r.n() == 1 ? try leggiPercorso(&r) : nil
            let seme = UInt32(truncatingIfNeeded: try r.u())
            let data = Date(timeIntervalSinceReferenceDate: try r.d())
            let np = try r.n()
            var punti: [PKStrokePoint] = []
            punti.reserveCapacity(np)
            var v = [Int64](repeating: 0, count: 10)
            for _ in 0..<np {
                for k in 0..<10 { v[k] += try r.i() }
                punti.append(PKStrokePoint(location: CGPoint(x: Double(v[0]) / 100, y: Double(v[1]) / 100),
                                           timeOffset: Double(v[2]) / 1000,
                                           size: CGSize(width: Double(v[3]) / 100, height: Double(v[4]) / 100),
                                           opacity: CGFloat(Double(v[5]) / 1000), force: CGFloat(Double(v[6]) / 1000),
                                           azimuth: CGFloat(Double(v[7]) / 1000), altitude: CGFloat(Double(v[8]) / 1000),
                                           secondaryScale: CGFloat(Double(v[9]) / 1000)))
            }
            guard let tipo else { continue }      // inchiostro sconosciuto (versione futura di iPadOS): si salta
            let ink = PKInk(tipo, color: colore)
            tratti.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: punti, creationDate: data),
                                   transform: transform, mask: mask, randomSeed: seme))
        }

        var immagini: [SpecImmagine] = []
        let ni = try r.n()
        for _ in 0..<ni {
            let id = UUID(uuidString: try r.s()) ?? UUID()
            let creazione = Date(timeIntervalSinceReferenceDate: try r.d())
            let cx = try r.f(100), cy = try r.f(100)
            let larghezza = try r.f(100)
            let angolo = try r.d()
            let rv = try (0..<4).map { _ in try r.f(100) }
            var maschera: [[CGPoint]] = []
            let nm = try r.n()
            for _ in 0..<nm {
                let n = try r.n()
                maschera.append(try (0..<n).map { _ in CGPoint(x: try r.f(10), y: try r.f(10)) })
            }
            let k = try r.n()
            immagini.append(SpecImmagine(id: id, creazione: creazione, centro: CGPoint(x: cx + Double(box.minX), y: cy + Double(box.minY)),
                                         larghezza: CGFloat(larghezza), angolo: CGFloat(angolo),
                                         ritaglio: CGRect(x: rv[0], y: rv[1], width: rv[2], height: rv[3]), maschera: maschera, indiceDo: k))
        }

        var testi: [ElementoTesto] = []
        let nx = try r.n()
        for _ in 0..<nx {
            let id = UUID(uuidString: try r.s()) ?? UUID()
            let testo = try r.s()
            let x = try r.f(100), y = try r.f(100)
            let corpo = try r.f(100)
            let colore = try leggiColore(&r)
            let larghezza: CGFloat? = try r.n() == 1 ? CGFloat(try r.f(100)) : nil
            let creazione = Date(timeIntervalSinceReferenceDate: try r.d())
            testi.append(ElementoTesto(id: id, testo: testo, punto: CGPoint(x: x + Double(box.minX), y: y + Double(box.minY)),
                                       corpo: CGFloat(corpo), colore: colore, larghezza: larghezza, creazione: creazione))
        }
        return (tratti, immagini, testi)
    }
}
