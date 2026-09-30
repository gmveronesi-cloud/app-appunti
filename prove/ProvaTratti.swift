// Prova su macOS (stesso PDFKit dell'iPad): si possono conservare i tratti modificabili
// dentro il PDF, in un'annotazione nascosta, e ritrovarli dopo salvataggio e riapertura?
// Non fa parte dell'app: gira solo nel workflow GitHub Actions e scrive prova.txt.
import Foundation
import PDFKit
import AppKit

func riga(_ s: String) { print(s) }

func creaPDF() -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    for _ in 1...2 {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(box)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return data as Data
}

func contiene(_ data: Data, _ testo: String) -> Bool {
    data.range(of: Data(testo.utf8)) != nil
}

riga("== PROVA: tratti modificabili dentro il PDF ==")
let blob = Data((0..<400_000).map { UInt8($0 % 251) })
let b64 = blob.base64EncodedString()
riga("Dati di prova: \(blob.count) byte, \(b64.count) caratteri in base64")

let doc = PDFDocument(data: creaPDF())!
let page = doc.page(at: 0)!
riga("PDF creato: \(doc.pageCount) pagine")

// A. Annotazione di testo nascosta con i dati nel campo /Contents
let nota = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .text, withProperties: nil)
nota.userName = "AptDati"
nota.contents = b64
nota.shouldDisplay = false
nota.shouldPrint = false
page.addAnnotation(nota)

// B. Chiave personalizzata su una seconda annotazione
let chiave = PDFAnnotationKey(rawValue: "/AptDatiExtra")
let nota2 = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .text, withProperties: nil)
nota2.userName = "AptExtra"
nota2.shouldDisplay = false
let okString = nota2.setValue("valore-di-prova", forAnnotationKey: chiave)
riga("setValue con stringa su chiave personalizzata: \(okString)")
page.addAnnotation(nota2)

// C. Tratto ink visibile marcato con chiave personalizzata
let ink = PDFAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 50), forType: .ink, withProperties: nil)
let path = NSBezierPath()
path.move(to: CGPoint(x: 0, y: 0))
path.line(to: CGPoint(x: 200, y: 50))
ink.add(path)
ink.color = NSColor.systemYellow.withAlphaComponent(0.4)
let border = PDFBorder(); border.lineWidth = 12; ink.border = border
let okInk = ink.setValue("pagina-1", forAnnotationKey: PDFAnnotationKey(rawValue: "/AptTratto"))
riga("setValue con stringa su ink: \(okInk)")
page.addAnnotation(ink)

// Salva e riapri
guard let salvato = doc.dataRepresentation() else { riga("ERRORE: dataRepresentation nil"); exit(1) }
riga("PDF salvato: \(salvato.count) byte")
riga("Nel file grezzo: /AptDati=\(contiene(salvato, "AptDati")) /AptDatiExtra=\(contiene(salvato, "/AptDatiExtra")) /AptTratto=\(contiene(salvato, "/AptTratto"))")

let riaperto = PDFDocument(data: salvato)!
let p0 = riaperto.page(at: 0)!
riga("Riaperto: pagina 1 ha \(p0.annotations.count) annotazioni")
for a in p0.annotations {
    let tipo = a.type ?? "?"
    let nome = a.userName ?? "-"
    let cont = a.contents ?? ""
    let extra = a.value(forAnnotationKey: chiave) as? String
    let tratto = a.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/AptTratto")) as? String
    riga("- tipo=\(tipo) utente=\(nome) contenuto=\(cont.count) car. uguale=\(cont == b64) mostra=\(a.shouldDisplay) stampa=\(a.shouldPrint) extra=\(extra ?? "nil") tratto=\(tratto ?? "nil")")
}

// Decodifica finale: i byte tornano identici?
if let a = p0.annotations.first(where: { $0.userName == "AptDati" }), let c = a.contents, let d = Data(base64Encoded: c) {
    riga("Dati ricostruiti identici: \(d == blob)")
} else {
    riga("Dati ricostruiti identici: NO (annotazione o contenuto mancante)")
}

// Rimozione e nuovo salvataggio (per sostituire i dati a ogni salvataggio)
for a in p0.annotations where a.userName == "AptDati" { p0.removeAnnotation(a) }
let dopo = riaperto.dataRepresentation()!
riga("Dopo la rimozione: \(dopo.count) byte, /AptDati nel file=\(contiene(dopo, "AptDati"))")
riga("== FINE PROVA ==")
