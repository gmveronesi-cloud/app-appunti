// Prova: una pagina con cropBox/mediaBox allargati a sinistra (minX negativo) e un'annotazione: dopo scrittura e rilettura cosa cambia?
import Foundation
import PDFKit

func box(_ p: PDFPage, _ t: String) {
    print(t, "media", p.bounds(for: .mediaBox), "crop", p.bounds(for: .cropBox))
    for a in p.annotations { print("   annot", a.userName ?? "-", a.bounds, a.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/AptInfo")) ?? "nil") }
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let url = URL(fileURLWithPath: dir).appendingPathComponent("a.pdf")
var r = CGRect(x: 0, y: 0, width: 595, height: 842)
let d = NSMutableData()
let c = CGContext(consumer: CGDataConsumer(data: d)!, mediaBox: &r, nil)!
c.beginPDFPage(nil); c.setFillColor(CGColor(gray: 0.5, alpha: 1)); c.fill(CGRect(x: 100, y: 100, width: 50, height: 50)); c.endPDFPage(); c.closePDF()
let doc = PDFDocument(data: d as Data)!
let p = doc.page(at: 0)!
box(p, "originale")
let nuovo = CGRect(x: -150, y: 0, width: 745, height: 842)
p.setBounds(nuovo, for: .mediaBox); p.setBounds(nuovo, for: .cropBox)
let a = PDFAnnotation(bounds: CGRect(x: 100, y: 300, width: 80, height: 80), forType: .stamp, withProperties: nil)
a.userName = "AptImmagine"
_ = a.setValue("100.0,300.0", forAnnotationKey: PDFAnnotationKey(rawValue: "/AptInfo"))
p.addAnnotation(a)
box(p, "allargata in memoria")
print("scrittura:", doc.write(to: url))
let d2 = PDFDocument(url: url)!
box(d2.page(at: 0)!, "riletta")
// seconda scrittura/rilettura
let url2 = URL(fileURLWithPath: dir).appendingPathComponent("b.pdf")
print("scrittura 2:", d2.write(to: url2))
box(PDFDocument(url: url2)!.page(at: 0)!, "riletta 2")
