// Prova: un'annotazione Stamp con dati grandi in chiavi personalizzate sopravvive a write + riapertura? (macOS, PDFKit)
import PDFKit
import AppKit

final class Sub: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(bounds)
    }
}

func casuale(_ n: Int) -> String {
    var b = [UInt8](repeating: 0, count: n)
    for i in 0..<n { b[i] = UInt8.random(in: 0...255) }
    return Data(b).base64EncodedString()
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("provapdf", isDirectory: true)
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let base = tmp.appendingPathComponent("base.pdf")
let d0 = PDFDocument(); d0.insert(PDFPage(), at: 0); d0.write(to: base)

let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")
let chiaveInfo = PDFAnnotationKey(rawValue: "/AptInfo")

for (nome, byte, sottoclasse) in [("piccolo 0.3MB sub", 300_000, true), ("medio 2MB sub", 2_000_000, true), ("grande 8MB sub", 8_000_000, true),
                                  ("medio 2MB senza sub", 2_000_000, false), ("grande 8MB senza sub", 8_000_000, false)] {
    let testo = casuale(byte)
    let doc = PDFDocument(url: base)!
    let pag = doc.page(at: 0)!
    let r = CGRect(x: 50, y: 50, width: 200, height: 150)
    let a: PDFAnnotation = sottoclasse ? Sub(bounds: r, forType: .stamp, withProperties: nil) : PDFAnnotation(bounds: r, forType: .stamp, withProperties: nil)
    a.userName = "AptImmagine"
    let ok1 = a.setValue(testo, forAnnotationKey: chiaveDati)
    let ok2 = a.setValue("1,2,3,4,5,6,7,8,9", forAnnotationKey: chiaveInfo)
    pag.addAnnotation(a)
    let out = tmp.appendingPathComponent("out.pdf")
    let scritto = doc.write(to: out)
    let dim = ((try? out.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    var esito = "scritto=\(scritto) file=\(dim / 1024)KB set=\(ok1)/\(ok2)"
    if let r2 = PDFDocument(url: out), let p2 = r2.page(at: 0) {
        esito += " annotazioni=\(p2.annotations.count)"
        for x in p2.annotations {
            let v = x.value(forAnnotationKey: chiaveDati)
            let tipo = v == nil ? "nil" : "\(type(of: v!))"
            let lun = (v as? String)?.count ?? -1
            esito += " [user=\(x.userName ?? "nil") tipo=\(x.type ?? "?") dati=\(tipo) lun=\(lun)/\(testo.count) uguale=\((v as? String) == testo) info=\((x.value(forAnnotationKey: chiaveInfo) as? String) ?? "nil")]"
        }
    } else { esito += " RIAPERTURA FALLITA" }
    print("\(nome): \(esito)")
}
