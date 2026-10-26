// Prova: in che formato scrive i PDF il PDFKit di macOS (tabella xref o flusso, flussi di oggetti, lunghezze dirette o no)
import PDFKit
import AppKit

final class Sub: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(bounds)
    }
}

let tmp = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func nuovaPagina(_ w: CGFloat, _ h: CGFloat) -> PDFPage {
    let p = PDFPage()
    p.setBounds(CGRect(x: 0, y: 0, width: w, height: h), for: .mediaBox)
    p.setBounds(CGRect(x: 0, y: 0, width: w, height: h), for: .cropBox)
    return p
}

func riassunto(_ url: URL, _ nome: String) {
    guard let d = try? Data(contentsOf: url) else { print("\(nome): illeggibile"); return }
    let testa = String(decoding: d.prefix(40), as: UTF8.self).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
    let coda = String(decoding: d.suffix(300), as: UTF8.self).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
    let tutto = String(decoding: d, as: UTF8.self)
    print("== \(nome): \(d.count) byte")
    print("testa: \(testa)")
    print("coda: \(coda)")
    print("ObjStm=\(tutto.contains("/ObjStm")) XRef=\(tutto.contains("/Type /XRef") || tutto.contains("/Type/XRef")) tabella=\(tutto.contains("\nxref")) Encrypt=\(tutto.contains("/Encrypt"))")
}

// 1) Documento con pagine, annotazioni di vari tipi
let doc = PDFDocument()
for i in 0..<3 { doc.insert(nuovaPagina(595, 842), at: i) }
let p0 = doc.page(at: 0)!
let st = Sub(bounds: CGRect(x: 50, y: 50, width: 200, height: 150), forType: .stamp, withProperties: nil)
st.userName = "AptTratto"
p0.addAnnotation(st)
let ft = PDFAnnotation(bounds: CGRect(x: 60, y: 300, width: 200, height: 40), forType: .freeText, withProperties: nil)
ft.contents = "Ciao mondo"
ft.userName = "AptTesto"
ft.font = NSFont.systemFont(ofSize: 14)
p0.addAnnotation(ft)
let nasc = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .square, withProperties: nil)
nasc.userName = "AptDati"
nasc.shouldDisplay = false
nasc.shouldPrint = false
_ = nasc.setValue(Data((0..<3000).map { UInt8($0 % 251) }).base64EncodedString(), forAnnotationKey: PDFAnnotationKey(rawValue: "/AptDati"))
p0.addAnnotation(nasc)
let a = tmp.appendingPathComponent("a-nuovo.pdf")
print("scrittura a: \(doc.write(to: a))")
riassunto(a, "a-nuovo.pdf (documento fatto da zero)")

// 2) Lo stesso file riletto, modificato e riscritto (come fa l'app)
let doc2 = PDFDocument(url: a)!
doc2.page(at: 1)!.addAnnotation(Sub(bounds: CGRect(x: 10, y: 10, width: 50, height: 50), forType: .stamp, withProperties: nil))
let b = tmp.appendingPathComponent("b-riscritto.pdf")
print("scrittura b: \(doc2.write(to: b))")
riassunto(b, "b-riscritto.pdf")
