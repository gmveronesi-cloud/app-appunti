// Prova immagini: quale annotazione PDF conserva davvero l'immagine nel file (visibile in altri lettori)?
// Si salva, si riapre, si disegna la pagina e si guarda il colore nel punto dell'immagine; si cerca anche
// un flusso immagine (/Subtype /Image) nei byte del file.
import Foundation
import PDFKit
import AppKit

func riga(_ s: String) { print(s) }

func creaPDF() -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(box)
    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

func immagineRossa() -> NSImage {
    let img = NSImage(size: NSSize(width: 120, height: 80))
    img.lockFocus()
    NSColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 120, height: 80)).fill()
    img.unlockFocus()
    return img
}

/// Colore della pagina (con annotazioni) al centro del rettangolo
func colore(_ page: PDFPage, _ r: CGRect) -> String {
    let w = 595, h = 842
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return "ctx nil" }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    page.draw(with: .cropBox, to: ctx)
    guard let d = ctx.data else { return "dati nil" }
    let p = d.assumingMemoryBound(to: UInt8.self)
    let x = Int(r.midX), y = h - 1 - Int(r.midY)
    let i = y * ctx.bytesPerRow + x * 4
    return "rgb(\(p[i]),\(p[i+1]),\(p[i+2]))"
}

final class AnnotazioneImmagine: PDFAnnotation {
    var immagine: NSImage?
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = immagine?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.draw(cg, in: bounds)
    }
}

let rett = CGRect(x: 100, y: 500, width: 120, height: 80)

func verifica(_ nome: String, _ crea: (PDFPage) -> Void) {
    riga("--- \(nome) ---")
    let doc = PDFDocument(data: creaPDF())!
    let page = doc.page(at: 0)!
    crea(page)
    riga("prima di salvare: \(colore(page, rett))")
    guard let salvato = doc.dataRepresentation() else { riga("dataRepresentation nil"); return }
    let testo = String(decoding: salvato, as: UTF8.self)
    riga("salvato \(salvato.count) byte; flusso /Image nel file: \(testo.contains("/Subtype /Image") || testo.contains("/Subtype/Image"))")
    let r = PDFDocument(data: salvato)!
    let p = r.page(at: 0)!
    riga("annotazioni dopo riapertura: \(p.annotations.map { $0.type ?? "?" })")
    riga("dopo riapertura: \(colore(p, rett))  (rosso = immagine visibile)")
}

verifica("A: Stamp con draw personalizzato") { page in
    let a = AnnotazioneImmagine(bounds: rett, forType: .stamp, withProperties: nil)
    a.immagine = immagineRossa()
    page.addAnnotation(a)
}

verifica("C: Stamp semplice con nome") { page in
    let a = PDFAnnotation(bounds: rett, forType: .stamp, withProperties: nil)
    a.stampName = "Approved"
    page.addAnnotation(a)
}

verifica("D: Stamp con draw personalizzato + chiave /AP vuota (controllo byte)") { page in
    let a = AnnotazioneImmagine(bounds: rett, forType: .stamp, withProperties: nil)
    a.immagine = immagineRossa()
    a.userName = "AptImmagine"
    page.addAnnotation(a)
}
