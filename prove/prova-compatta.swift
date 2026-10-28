// Prova della compattazione senza perdita (PNGOttimo.swift + PDFCompatta.swift): dati sintetici in prove/dati
import Foundation
import PDFKit
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let dir = URL(fileURLWithPath: "prove/dati")

func mb(_ x: Int) -> String { String(format: "%.2f MB", Double(x) / 1_048_576) }

func render(_ url: URL) -> [Data] {
    guard let d = PDFDocument(url: url) else { return [] }
    var r: [Data] = []
    for i in 0..<d.pageCount {
        guard let p = d.page(at: i) else { continue }
        let b = p.bounds(for: .mediaBox)
        let w = Int(b.width), h = Int(b.height)
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                p.draw(with: .mediaBox, to: ctx)
            }
        }
        r.append(Data(buf))
    }
    return r
}

let src = dir.appendingPathComponent("test1.pdf")
do {
    let a = try PDFCompatta.analizza(url: src)
    print("analisi: totale \(mb(a.totale)), vivi \(mb(a.vivi)), scarto \(mb(a.scarto)), ricomprimibili \(mb(a.daRicomprimere))")
    print("conviene (soglie basse)? \(PDFCompatta.conviene(a, soglieAlte: false))")
    let dst = out.appendingPathComponent("compatto.pdf")
    let t0 = Date()
    let e = try PDFCompatta.compatta(da: src, a: dst)
    print("compatta: \(mb(e.prima)) -> \(mb(e.dopo)), oggetti vivi \(e.oggetti), scartati \(e.scartati), immagini ricompresse \(e.immagini), \(Date().timeIntervalSince(t0)) s")
    print("verifica strutturale: \(PDFCompatta.verifica(originale: src, nuovo: dst))")
    let a2 = try PDFCompatta.analizza(url: dst)
    print("dopo: totale \(mb(a2.totale)), scarto \(mb(a2.scarto)), ricomprimibili \(mb(a2.daRicomprimere))")
    let dst2 = out.appendingPathComponent("compatto2.pdf")
    let e2 = try PDFCompatta.compatta(da: dst, a: dst2)
    print("seconda passata: \(mb(e2.prima)) -> \(mb(e2.dopo)), immagini ricompresse \(e2.immagini)")
    let r1 = render(src), r2 = render(dst)
    print("PDFKit pagine: \(r1.count) / \(r2.count), pagine disegnate identiche: \(r1.count == r2.count && r1 == r2)")
    if let d = PDFDocument(url: dst) {
        var n = 0
        for i in 0..<d.pageCount { n += d.page(at: i)?.annotations.count ?? 0 }
        print("PDFKit annotazioni nel compattato: \(n)")
    }
} catch {
    print("ERRORE PDF: \(error)")
}

for i in 0..<6 {
    guard let d = try? Data(contentsOf: dir.appendingPathComponent("p\(i).png")) else { continue }
    let t0 = Date()
    let n = PNGOttimo.ottimizza(d)
    print("png \(i): \(d.count) -> \(n.count) byte (\(Date().timeIntervalSince(t0)) s)")
    try? n.write(to: out.appendingPathComponent("p\(i).opt.png"))
}
