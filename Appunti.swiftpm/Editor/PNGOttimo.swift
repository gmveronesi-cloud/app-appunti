// Compressione SENZA PERDITA di PNG e di immagini Flate dei PDF (solo Foundation + Compression).
//
// Il codificatore PNG di iPadOS (ImageIO) scrive file molto più grandi del necessario: non sceglie bene i «filtri» riga per
// riga, e una schermata 1400×973 pesa 5 MB invece di 1,5 MB. Qui si rifanno gli stessi identici pixel con il filtro migliore
// per ogni riga e una compressione deflate. Nulla è approssimato: il risultato viene sempre riletto e confrontato byte per
// byte con l'originale prima di essere usato; al minimo dubbio si tengono i dati di prima.
import Foundation
#if canImport(Compression)
import Compression
#endif

/// Flussi zlib (2 byte di intestazione + deflate + adler32)
enum Zlib {
    static func adler32(_ d: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        d.withUnsafeBufferPointer { p in
            var i = 0
            let n = p.count
            while i < n {
                let fine = min(i + 5552, n)
                while i < fine {
                    a = a &+ UInt32(p[i])
                    b = b &+ a
                    i += 1
                }
                a %= 65521
                b %= 65521
            }
        }
        return (b << 16) | a
    }

    /// Decomprime un flusso zlib. `capacita`: il risultato deve stare in meno di questi byte (altrimenti nil).
    static func gonfia(_ z: UnsafeRawBufferPointer, capacita: Int) -> [UInt8]? {
        #if canImport(Compression)
        guard z.count > 6, capacita > 1, let base = z.baseAddress else { return nil }
        let cmf = z[0], flg = z[1]
        guard cmf & 0x0F == 8, (Int(cmf) * 256 + Int(flg)) % 31 == 0, flg & 0x20 == 0 else { return nil }
        var out = [UInt8](repeating: 0, count: capacita)
        let n: Int = out.withUnsafeMutableBufferPointer { dst in
            compression_decode_buffer(dst.baseAddress!, capacita, base.assumingMemoryBound(to: UInt8.self) + 2, z.count - 6,
                                      nil, COMPRESSION_ZLIB)
        }
        guard n > 0, n < capacita else { return nil }
        out.removeSubrange(n...)
        return out
        #else
        return nil
        #endif
    }

    static func comprimi(_ d: [UInt8]) -> [UInt8]? {
        #if canImport(Compression)
        guard !d.isEmpty else { return nil }
        let capacita = d.count + d.count / 8 + 1024
        var out = [UInt8](repeating: 0, count: capacita + 6)
        let n: Int = d.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress! + 2, capacita, src.baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        out[0] = 0x78
        out[1] = 0x9C
        out.removeSubrange((2 + n)...)
        let ad = adler32(d)
        out.append(UInt8((ad >> 24) & 255))
        out.append(UInt8((ad >> 16) & 255))
        out.append(UInt8((ad >> 8) & 255))
        out.append(UInt8(ad & 255))
        return out
        #else
        return nil
        #endif
    }
}

/// Filtri PNG (0 nessuno, 1 sinistra, 2 sopra, 3 media, 4 Paeth): stessi del predittore 15 dei PDF
enum FiltriPNG {
    @inline(__always) static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    /// Per ogni riga sceglie il filtro che rende i numeri più piccoli. Ritorna `alt * (rowb + 1)` byte.
    static func filtra(_ raw: [UInt8], rowb: Int, alt: Int, bpp: Int) -> [UInt8]? {
        guard rowb > 0, alt > 0, bpp > 0, raw.count == rowb * alt else { return nil }
        var out = [UInt8](repeating: 0, count: alt * (rowb + 1))
        let cand = UnsafeMutablePointer<UInt8>.allocate(capacity: rowb * 5)
        let zero = UnsafeMutablePointer<UInt8>.allocate(capacity: rowb)
        zero.initialize(repeating: 0, count: rowb)
        defer { cand.deallocate(); zero.deallocate() }
        raw.withUnsafeBufferPointer { r in
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<alt {
                    let cur = r.baseAddress! + y * rowb
                    let prev: UnsafePointer<UInt8> = y == 0 ? UnsafePointer(zero) : r.baseAddress! + (y - 1) * rowb
                    let c0 = cand, c1 = cand + rowb, c2 = cand + 2 * rowb, c3 = cand + 3 * rowb, c4 = cand + 4 * rowb
                    var s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0
                    for i in 0..<rowb {
                        let x = Int(cur[i])
                        let a = i >= bpp ? Int(cur[i - bpp]) : 0
                        let b = Int(prev[i])
                        let c = i >= bpp ? Int(prev[i - bpp]) : 0
                        let v0 = UInt8(truncatingIfNeeded: x)
                        let v1 = UInt8(truncatingIfNeeded: x - a)
                        let v2 = UInt8(truncatingIfNeeded: x - b)
                        let v3 = UInt8(truncatingIfNeeded: x - ((a + b) >> 1))
                        let v4 = UInt8(truncatingIfNeeded: x - paeth(a, b, c))
                        c0[i] = v0; c1[i] = v1; c2[i] = v2; c3[i] = v3; c4[i] = v4
                        s0 += abs(Int(Int8(bitPattern: v0)))
                        s1 += abs(Int(Int8(bitPattern: v1)))
                        s2 += abs(Int(Int8(bitPattern: v2)))
                        s3 += abs(Int(Int8(bitPattern: v3)))
                        s4 += abs(Int(Int8(bitPattern: v4)))
                    }
                    var migliore = 0
                    var minimo = s0
                    if s1 < minimo { minimo = s1; migliore = 1 }
                    if s2 < minimo { minimo = s2; migliore = 2 }
                    if s3 < minimo { minimo = s3; migliore = 3 }
                    if s4 < minimo { minimo = s4; migliore = 4 }
                    let riga = o.baseAddress! + y * (rowb + 1)
                    riga[0] = UInt8(migliore)
                    (riga + 1).update(from: cand + migliore * rowb, count: rowb)
                }
            }
        }
        return out
    }

    /// Inverso di `filtra` (e di qualunque PNG non interlacciato). nil se i dati non tornano.
    static func sfiltra(_ f: [UInt8], rowb: Int, alt: Int, bpp: Int) -> [UInt8]? {
        guard rowb > 0, alt > 0, bpp > 0, f.count == alt * (rowb + 1) else { return nil }
        var out = [UInt8](repeating: 0, count: rowb * alt)
        var valido = true
        f.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<alt {
                    let riga = src.baseAddress! + y * (rowb + 1)
                    let tipo = riga[0]
                    let dati = riga + 1
                    let cur = dst.baseAddress! + y * rowb
                    let prev: UnsafeMutablePointer<UInt8>? = y == 0 ? nil : dst.baseAddress! + (y - 1) * rowb
                    switch tipo {
                    case 0:
                        for i in 0..<rowb { cur[i] = dati[i] }
                    case 1:
                        for i in 0..<rowb {
                            let a = i >= bpp ? cur[i - bpp] : 0
                            cur[i] = dati[i] &+ a
                        }
                    case 2:
                        for i in 0..<rowb {
                            let b = prev?[i] ?? 0
                            cur[i] = dati[i] &+ b
                        }
                    case 3:
                        for i in 0..<rowb {
                            let a = i >= bpp ? Int(cur[i - bpp]) : 0
                            let b = Int(prev?[i] ?? 0)
                            cur[i] = dati[i] &+ UInt8(truncatingIfNeeded: (a + b) >> 1)
                        }
                    case 4:
                        for i in 0..<rowb {
                            let a = i >= bpp ? Int(cur[i - bpp]) : 0
                            let b = Int(prev?[i] ?? 0)
                            let c = (i >= bpp && prev != nil) ? Int(prev![i - bpp]) : 0
                            cur[i] = dati[i] &+ UInt8(truncatingIfNeeded: paeth(a, b, c))
                        }
                    default:
                        valido = false
                        return
                    }
                }
            }
        }
        return valido ? out : nil
    }
}

enum PNGOttimo {
    private static let firma: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    private static let lock = NSLock()
    /// Impronte di PNG già provati (ottimizzati o non migliorabili): non si rifà il lavoro
    private static var giaProvati = Set<Int>()

    private static let tabellaCRC: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    private static func crc32(_ parti: [[UInt8]]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for parte in parti {
            parte.withUnsafeBufferPointer { p in
                for b in p { c = tabellaCRC[Int((c ^ UInt32(b)) & 255)] ^ (c >> 8) }
            }
        }
        return c ^ 0xFFFFFFFF
    }

    private static func impronta(_ d: Data) -> Int {
        var h = Hasher()
        h.combine(d.count)
        h.combine(d)
        return h.finalize()
    }

    /// Stessi pixel, meno byte. Ritorna `dati` così com'è se non è un PNG adatto o se si guadagna meno del 10%.
    static func ottimizza(_ dati: Data) -> Data {
        guard dati.count > 30_000, dati.starts(with: firma) else { return dati }
        let imp = impronta(dati)
        lock.lock()
        let visto = giaProvati.contains(imp)
        lock.unlock()
        if visto { return dati }
        let nuovo = trascodifica(dati)
        let risultato = nuovo ?? dati
        lock.lock()
        giaProvati.insert(imp)
        if nuovo != nil { giaProvati.insert(impronta(risultato)) }
        lock.unlock()
        return risultato
    }

    private static func trascodifica(_ dati: Data) -> Data? {
        let b = [UInt8](dati)
        func u32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
        var pos = 8
        var larg = 0, alt = 0, prof = 0, tipoColore = -1, interlaccia = 0
        var idat: [UInt8] = []
        var pezzi: [(r: Range<Int>, idat: Bool)] = []
        var finito = false
        while pos + 12 <= b.count {
            let len = u32(pos)
            guard len >= 0, pos + 12 + len <= b.count else { return nil }
            let tipo = String(decoding: b[(pos + 4)..<(pos + 8)], as: UTF8.self)
            if tipo == "IHDR" {
                guard len == 13 else { return nil }
                larg = u32(pos + 8)
                alt = u32(pos + 12)
                prof = Int(b[pos + 16])
                tipoColore = Int(b[pos + 17])
                interlaccia = Int(b[pos + 20])
            }
            let eIDAT = tipo == "IDAT"
            if eIDAT { idat.append(contentsOf: b[(pos + 8)..<(pos + 8 + len)]) }
            pezzi.append((pos..<(pos + 12 + len), eIDAT))
            pos += 12 + len
            if tipo == "IEND" { finito = true; break }
        }
        guard finito, larg > 0, alt > 0, interlaccia == 0, !idat.isEmpty else { return nil }
        guard prof == 8 || prof == 16 else { return nil }
        let canali: Int
        switch tipoColore {
        case 0: canali = 1
        case 2: canali = 3
        case 3: canali = 1
        case 4: canali = 2
        case 6: canali = 4
        default: return nil
        }
        if tipoColore == 3 && prof != 8 { return nil }
        let bpp = canali * prof / 8
        let rowb = larg * bpp
        let attesi = (rowb + 1) * alt
        guard attesi > 0, attesi < 300_000_000 else { return nil }

        let originale: [UInt8]? = idat.withUnsafeBytes { Zlib.gonfia($0, capacita: attesi + 1) }
        guard let filtrato0 = originale, filtrato0.count == attesi,
              let raw = FiltriPNG.sfiltra(filtrato0, rowb: rowb, alt: alt, bpp: bpp) else { return nil }
        guard let filtrato = FiltriPNG.filtra(raw, rowb: rowb, alt: alt, bpp: bpp),
              let z = Zlib.comprimi(filtrato) else { return nil }
        guard z.count * 10 < idat.count * 9 else { return nil }          // meno del 10% di guadagno: non vale il rischio
        // Verifica: riletto e confrontato con i pixel originali
        let riletto: [UInt8]? = z.withUnsafeBytes { Zlib.gonfia($0, capacita: attesi + 1) }
        guard let r2 = riletto, r2.count == attesi, let raw2 = FiltriPNG.sfiltra(r2, rowb: rowb, alt: alt, bpp: bpp),
              raw2 == raw else { return nil }

        var out = [UInt8]()
        out.reserveCapacity(b.count)
        out.append(contentsOf: firma)
        var scritto = false
        for p in pezzi {
            if p.idat {
                if scritto { continue }
                scritto = true
                let tipo: [UInt8] = [73, 68, 65, 84]                // «IDAT»
                let n = z.count
                out.append(contentsOf: [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
                out.append(contentsOf: tipo)
                out.append(contentsOf: z)
                let crc = crc32([tipo, z])
                out.append(contentsOf: [UInt8((crc >> 24) & 255), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255)])
            } else {
                out.append(contentsOf: b[p.r])
            }
        }
        return Data(out)
    }
}
