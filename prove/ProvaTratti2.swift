// Seconda prova: i dati vanno in una chiave personalizzata (non in /Contents), così PDFKit
// non crea l'annotazione Popup con la copia. Si confrontano più tipi di annotazione nascosta.
import Foundation
import PDFKit
import AppKit

func riga(_ s: String) { print(s) }

func creaPDF() -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
    ctx.fill(box)
    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

func contiene(_ data: Data, _ testo: String) -> Bool { data.range(of: Data(testo.utf8)) != nil }

let blob = Data((0..<400_000).map { UInt8($0 % 251) })
let b64 = blob.base64EncodedString()
let chiave = PDFAnnotationKey(rawValue: "/AptDati")
let base = creaPDF().count
riga("== PROVA 2: chiave personalizzata, \(b64.count) caratteri, PDF vuoto \(base) byte ==")

let tipi: [(String, PDFAnnotationSubtype)] = [("Text", .text), ("Square", .square), ("Ink", .ink), ("Stamp", .stamp), ("FreeText", .freeText)]
for (nome, tipo) in tipi {
    riga("--- \(nome) ---")
    let doc = PDFDocument(data: creaPDF())!
    let page = doc.page(at: 0)!
    let a = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: tipo, withProperties: nil)
    a.userName = "AptDati"
    a.shouldDisplay = false
    a.shouldPrint = false
    let ok = a.setValue(b64, forAnnotationKey: chiave)
    page.addAnnotation(a)
    guard let salvato = doc.dataRepresentation() else { riga("dataRepresentation nil"); continue }
    riga("setValue=\(ok) salvato=\(salvato.count) byte (aggiunta \(salvato.count - base))")
    let r = PDFDocument(data: salvato)!
    let p = r.page(at: 0)!
    riga("annotazioni dopo riapertura: \(p.annotations.count) -> \(p.annotations.map { $0.type ?? "?" })")
    if let t = p.annotations.first(where: { $0.userName == "AptDati" }) {
        let v = t.value(forAnnotationKey: chiave) as? String
        riga("valore ritrovato uguale=\(v == b64) mostra=\(t.shouldDisplay) stampa=\(t.shouldPrint)")
    } else { riga("annotazione AptDati NON ritrovata") }
    for t in p.annotations where t.userName == "AptDati" { p.removeAnnotation(t) }
    let dopo = r.dataRepresentation()!
    riga("dopo rimozione: \(dopo.count) byte, dati ancora nel file=\(contiene(dopo, "AptDati")) annotazioni=\(r.page(at: 0)!.annotations.count)")

    // sostituzione: rimuovo e riaggiungo con dati diversi, come a ogni salvataggio
    let p2 = r.page(at: 0)!
    let b = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: tipo, withProperties: nil)
    b.userName = "AptDati"; b.shouldDisplay = false; b.shouldPrint = false
    _ = b.setValue("nuovi-dati", forAnnotationKey: chiave)
    p2.addAnnotation(b)
    let s2 = r.dataRepresentation()!
    riga("dopo sostituzione: \(s2.count) byte, vecchi dati nel file=\(contiene(s2, String(b64.prefix(200))))")
}
riga("== FINE PROVA 2 ==")
