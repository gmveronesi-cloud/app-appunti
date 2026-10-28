// Prova 2: dopo doc.write la pagina IN MEMORIA cambia riquadro? Dove sta il contenuto (quadrato grigio originale a x=100..150)
// rispetto al riquadro, in memoria e riletto? Poi un secondo allargamento come fa l'app.
import Foundation
import PDFKit
import AppKit

func quadrato(_ p: PDFPage) -> String {
    let b = p.bounds(for: .cropBox)
    let w = Int(b.width), h = Int(b.height)
    guard w > 0, h > 0 else { return "box vuoto" }
    let img = p.thumbnail(of: NSSize(width: w, height: h), for: .cropBox)
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "no img" }
    var px = [UInt8](repeating: 255, count: w * h)
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var minX = w, maxX = -1
    for y in 0..<h { for x in 0..<w where px[y * w + x] < 200 { minX = min(minX, x); maxX = max(maxX, x) } }
    return maxX < 0 ? "quadrato non trovato" : "quadrato x \(minX)...\(maxX) dal bordo sinistro del box (box \(b))"
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
var r = CGRect(x: 0, y: 0, width: 595, height: 842)
let d = NSMutableData()
let c = CGContext(consumer: CGDataConsumer(data: d)!, mediaBox: &r, nil)!
c.beginPDFPage(nil); c.setFillColor(CGColor(gray: 0.3, alpha: 1)); c.fill(CGRect(x: 100, y: 100, width: 50, height: 50)); c.endPDFPage(); c.closePDF()
let doc = PDFDocument(data: d as Data)!
let p = doc.page(at: 0)!
print("1 originale:", quadrato(p))
let nuovo = CGRect(x: -150, y: 0, width: 745, height: 842)
p.setBounds(nuovo, for: .mediaBox); p.setBounds(nuovo, for: .cropBox)
print("2 allargata in memoria:", quadrato(p))
let u1 = URL(fileURLWithPath: dir).appendingPathComponent("a.pdf")
print("scrittura:", doc.write(to: u1))
print("3 IN MEMORIA dopo write: media", p.bounds(for: .mediaBox), "crop", p.bounds(for: .cropBox), quadrato(p))
let riletto = PDFDocument(url: u1)!
print("4 riletto:", quadrato(riletto.page(at: 0)!))
// secondo allargamento come l'app: dal documento IN MEMORIA (non riletto), box nuovo calcolato sul 'vecchio originale' (0,0,595,842) con 200 per lato
let b2 = CGRect(x: -200, y: 0, width: 995, height: 842)
p.setBounds(b2, for: .mediaBox); p.setBounds(b2, for: .cropBox)
print("5 secondo allargamento in memoria:", quadrato(p), "(atteso: quadrato a 300...350)")
let u2 = URL(fileURLWithPath: dir).appendingPathComponent("b.pdf")
print("scrittura 2:", doc.write(to: u2))
print("6 riletto 2:", quadrato(PDFDocument(url: u2)!.page(at: 0)!))
