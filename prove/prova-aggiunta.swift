// Prova del salvataggio «per aggiunta» (PDFAggiunta + PDFLettore) su macOS con PDFKit.
// Si compila insieme a Appunti.swiftpm/Editor/PDFLettore.swift e PDFAggiunta.swift.
import PDFKit
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)

final class Tratto: PDFAnnotation {
    var seme: Int = 0
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // un'immagine di rumore, come i tratti dell'app (un flusso con immagine nell'aspetto)
        let w = 200, h = 200
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var s = UInt32(truncatingIfNeeded: seme &* 2654435761 &+ 12345)
        for i in 0..<px.count {
            s = s &* 1664525 &+ 1013904223
            px[i] = UInt8(truncatingIfNeeded: s >> 24)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        px.withUnsafeMutableBytes { raw in
            if let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let img = c.makeImage() {
                context.draw(img, in: bounds)
            }
        }
    }
}

let cartella = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
let marcatore = cartella.appendingPathComponent("marcatore.txt")
var errori = 0
func controlla(_ ok: Bool, _ cosa: String) {
    print(ok ? "  ok   \(cosa)" : "  ERRORE \(cosa)")
    if !ok { errori += 1 }
}

func casuale(_ n: Int, _ seme: Int) -> String {
    var b = [UInt8](repeating: 0, count: n)
    var s = UInt32(truncatingIfNeeded: seme &* 7919 &+ 1)
    for i in 0..<n { s = s &* 1664525 &+ 1013904223; b[i] = UInt8(truncatingIfNeeded: s >> 24) }
    return Data(b).base64EncodedString()
}

let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")

func nuovaPagina(_ box: CGRect) -> PDFPage {
    let p = PDFPage()
    p.setBounds(box, for: .mediaBox)
    p.setBounds(box, for: .cropBox)
    return p
}

/// Annotazioni dell'app per una pagina: tratti (stamp con immagine), dati nascosti, a volte un testo
func annotazioniApp(_ box: CGRect, seme: Int, testo: Bool, byteDati: Int) -> [PDFAnnotation] {
    var out: [PDFAnnotation] = []
    let t = Tratto(bounds: CGRect(x: box.minX + 40, y: box.minY + 60, width: 300, height: 200), forType: .stamp, withProperties: nil)
    t.seme = seme
    t.userName = "AptTratto"
    out.append(t)
    if testo {
        let f = PDFAnnotation(bounds: CGRect(x: box.minX + 60, y: box.minY + 400, width: 200, height: 40), forType: .freeText, withProperties: nil)
        f.contents = "Testo \(seme) (con parentesi) \\ e barra"
        f.userName = "AptTesto"
        f.font = NSFont.systemFont(ofSize: 14)
        out.append(f)
    }
    let d = PDFAnnotation(bounds: CGRect(x: box.minX, y: box.minY, width: 1, height: 1), forType: .square, withProperties: nil)
    d.userName = "AptDati"
    d.shouldDisplay = false
    d.shouldPrint = false
    _ = d.setValue(casuale(byteDati, seme), forAnnotationKey: chiaveDati)
    out.append(d)
    return out
}

func firma(_ doc: PDFDocument) -> [String] {
    var out: [String] = []
    for i in 0..<doc.pageCount {
        let p = doc.page(at: i)!
        var righe: [String] = []
        for a in p.annotations {
            let v = (a.value(forAnnotationKey: chiaveDati) as? String) ?? ""
            righe.append("\(a.userName ?? "-"):\(a.type ?? "?"):\(v.count):\(v.prefix(12))")
        }
        out.append("p\(i)[" + righe.sorted().joined(separator: "|") + "]")
    }
    return out
}

func dimensione(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? -1 }

// MARK: 1. Base: 40 pagine scritte da PDFKit, con annotazioni dell'app e una non dell'app

let base = cartella.appendingPathComponent("aggiunta.pdf")
let mini = cartella.appendingPathComponent("mini.pdf")
let totale = 40
do {
    let doc = PDFDocument()
    for i in 0..<totale {
        let box = i % 7 == 3 ? CGRect(x: 0, y: 0, width: 612, height: 1000) : CGRect(x: 0, y: 0, width: 595, height: 842)
        doc.insert(nuovaPagina(box), at: i)
    }
    for i in [0, 5, 20] {
        let p = doc.page(at: i)!
        for a in annotazioniApp(p.bounds(for: .cropBox), seme: 100 + i, testo: i == 0, byteDati: 30_000) { p.addAnnotation(a) }
    }
    // annotazione NON dell'app: deve sopravvivere a tutti gli aggiornamenti
    for i in [0, 10] {
        let altro = PDFAnnotation(bounds: CGRect(x: 100, y: 700, width: 80, height: 30), forType: .square, withProperties: nil)
        altro.userName = "Mario"
        doc.page(at: i)!.addAnnotation(altro)
    }
    controlla(doc.write(to: base), "scrittura della base con PDFKit")
}
print("base: \(dimensione(base)) byte")

func giro(_ pagine: [Int], seme: Int, verificaForzata: Bool? = nil) -> String? {
    guard let docPrima = PDFDocument(url: base) else { return "base illeggibile" }
    let firmaPrima = firma(docPrima)
    var attese: [Int] = []
    let m = PDFDocument()
    for (k, idx) in pagine.enumerated() {
        let box = idx < docPrima.pageCount ? docPrima.page(at: idx)!.bounds(for: .cropBox) : CGRect(x: 0, y: 0, width: 595, height: 842)
        let p = nuovaPagina(box)
        let a = annotazioniApp(box, seme: seme + idx, testo: (idx + seme) % 2 == 0, byteDati: 20_000 + idx * 100)
        for x in a { p.addAnnotation(x) }
        attese.append(a.count)
        m.insert(p, at: k)
    }
    _ = m.write(to: mini)
    do {
        let e = try PDFAggiunta.applica(url: base, miniatura: mini, pagine: pagine, marcatore: marcatore) {
            if let f = verificaForzata { return f }
            guard let d = PDFDocument(url: base), d.pageCount == totale else { return false }
            for (k, idx) in pagine.enumerated() {
                let n = d.page(at: idx)!.annotations.filter { ($0.userName ?? "").hasPrefix("Apt") }.count
                if n != attese[k] { return false }
            }
            return true
        }
        // controlli di merito
        let dopo = PDFDocument(url: base)!
        controlla(dopo.pageCount == totale, "pagine ancora \(totale)")
        let firmaDopo = firma(dopo)
        var tuttoBene = true
        for i in 0..<totale where !pagine.contains(i) {
            if firmaDopo[i] != firmaPrima[i] { tuttoBene = false; print("   pagina \(i) cambiata senza motivo: \(firmaPrima[i]) -> \(firmaDopo[i])") }
        }
        controlla(tuttoBene, "pagine non toccate identiche")
        for (k, idx) in pagine.enumerated() {
            let p = dopo.page(at: idx)!
            let app = p.annotations.filter { ($0.userName ?? "").hasPrefix("Apt") }
            let altro = p.annotations.filter { !($0.userName ?? "").hasPrefix("Apt") }
            let altroPrima = docPrima.page(at: idx)!.annotations.filter { !($0.userName ?? "").hasPrefix("Apt") }
            controlla(app.count == attese[k], "pagina \(idx): \(app.count) annotazioni dell'app (attese \(attese[k]))")
            controlla(altro.count == altroPrima.count, "pagina \(idx): annotazioni non dell'app conservate (\(altro.count))")
            if let d = app.first(where: { $0.userName == "AptDati" }), let v = d.value(forAnnotationKey: chiaveDati) as? String {
                controlla(v == casuale(20_000 + idx * 100, seme + idx), "pagina \(idx): dati nascosti identici a quelli scritti")
            } else {
                controlla(false, "pagina \(idx): dati nascosti mancanti")
            }
        }
        print("  aggiunti \(e.byteAggiunti) byte, \(e.oggetti) oggetti, sezioni xref \(e.sezioni), file \(dimensione(base)) byte")
        return nil
    } catch {
        return "\(error)"
    }
}

print("\n== Giro 1: pagine 0 (con annotazioni), 10 (senza), 11, 39")
if let e = giro([0, 10, 11, 39], seme: 1) { controlla(false, "giro 1: \(e)") }
try? FileManager.default.copyItem(at: base, to: cartella.appendingPathComponent("dopo-giro1.pdf"))

print("\n== Giro 2: pagine 5, 10, 20 (già con annotazioni dell'app)")
if let e = giro([5, 10, 20], seme: 2) { controlla(false, "giro 2: \(e)") }

print("\n== Giro 3: una pagina sola")
if let e = giro([7], seme: 3) { controlla(false, "giro 3: \(e)") }

print("\n== Giro 4-6: ancora aggiornamenti")
for g in 4...6 { if let e = giro([g, g + 20], seme: g) { controlla(false, "giro \(g): \(e)") } }
try? FileManager.default.copyItem(at: base, to: cartella.appendingPathComponent("dopo-giro6.pdf"))

print("\n== Rilettura con PDFKit e riscrittura completa (compattazione)")
if let d = PDFDocument(url: base) {
    let f1 = firma(d)
    let completo = cartella.appendingPathComponent("riscritto.pdf")
    controlla(d.write(to: completo), "PDFKit riscrive il file con le sezioni aggiunte")
    if let d2 = PDFDocument(url: completo) {
        controlla(firma(d2) == f1, "il file riscritto ha le stesse annotazioni")
    }
    print("  file con aggiunte \(dimensione(base)) byte, riscritto \(dimensione(completo)) byte")
}

print("\n== Prova di ritorno indietro (verifica che fallisce)")
do {
    let prima = dimensione(base)
    let dataPrima = (try? FileManager.default.attributesOfItem(atPath: base.path))?[.modificationDate] as? Date
    let docPrima = PDFDocument(url: base)!
    let f1 = firma(docPrima)
    let r = giro([2], seme: 50, verificaForzata: false)
    controlla(r != nil, "la verifica negativa dà errore (\(r ?? "nessuno"))")
    controlla(dimensione(base) == prima, "dimensione tornata com'era (\(dimensione(base)) / \(prima))")
    let dataDopo = (try? FileManager.default.attributesOfItem(atPath: base.path))?[.modificationDate] as? Date
    controlla(abs((dataDopo ?? .distantPast).timeIntervalSince(dataPrima ?? .distantFuture)) < 0.002, "data di modifica ripristinata (\(String(describing: dataPrima)) / \(String(describing: dataDopo)))")
    controlla(firma(PDFDocument(url: base)!) == f1, "contenuto uguale a prima")
    controlla(!FileManager.default.fileExists(atPath: marcatore.path), "segnalino tolto")
}

print("\n== Pagina inesistente")
do {
    let prima = dimensione(base)
    let r = giro([999], seme: 60)
    controlla(r != nil, "errore per pagina inesistente (\(r ?? "nessuno"))")
    controlla(dimensione(base) == prima, "file non toccato")
}

print("\n== Troppe sezioni: deve chiedere la riscrittura completa")
do {
    var rifiutato = false
    for g in 7...20 {
        if let e = giro([g % totale], seme: 100 + g) {
            if e.contains("Troppi") { rifiutato = true; print("  al giro \(g): \(e)"); break }
            controlla(false, "giro \(g): \(e)")
            break
        }
    }
    controlla(rifiutato, "dopo molti aggiornamenti si chiede di riscrivere tutto")
}

print("\n== Segnalino di un'aggiunta interrotta")
do {
    // simula: il file è stato allungato di 500 byte di spazzatura e il segnalino dice dove tornare
    let u = cartella.appendingPathComponent("interrotto.pdf")
    try? FileManager.default.copyItem(at: cartella.appendingPathComponent("dopo-giro1.pdf"), to: u)
    let prima = dimensione(u)
    let dataPrima = ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date) ?? Date()
    let h = try! FileHandle(forUpdating: u)
    _ = try! h.seekToEnd()
    try! h.write(contentsOf: Data(repeating: 65, count: 500))
    try! h.close()
    try! "\(prima) \(prima + 4000) \(dataPrima.timeIntervalSince1970)".write(to: marcatore, atomically: true, encoding: .utf8)
    PDFAggiunta.ripristina(url: u, marcatore: marcatore)
    controlla(dimensione(u) == prima, "tagliata la coda incompleta (\(dimensione(u)) / \(prima))")
    controlla(PDFDocument(url: u) != nil, "il file si apre")
    controlla(!FileManager.default.fileExists(atPath: marcatore.path), "segnalino tolto")
}

// MARK: Un PDF grosso (tipo i quaderni da centinaia di MB): quanto costa aggiungere

print("\n== PDF grosso")
do {
    let grosso = cartella.appendingPathComponent("grosso.pdf")
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    if let c = CGContext(grosso as CFURL, mediaBox: &box, nil) {
        for pg in 0..<6 {
            c.beginPDFPage(nil)
            let w = 3000, h = 3000
            var px = [UInt8](repeating: 0, count: w * h * 4)
            var s = UInt32(pg + 1)
            for i in 0..<px.count { s = s &* 1664525 &+ 1013904223; px[i] = UInt8(truncatingIfNeeded: s >> 24) }
            let cs = CGColorSpaceCreateDeviceRGB()
            px.withUnsafeMutableBytes { raw in
                if let ic = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let img = ic.makeImage() {
                    c.draw(img, in: box)
                }
            }
            c.endPDFPage()
        }
        c.closePDF()
    }
    let dimGrosso = dimensione(grosso)
    print("  PDF grosso scritto da Quartz (CGContext): \(dimGrosso / 1_048_576) MB")
    // lo riscrive PDFKit come fa l'app la prima volta
    let ridotto = cartella.appendingPathComponent("grosso2.pdf")
    let t0 = Date()
    if let d = PDFDocument(url: grosso) {
        controlla(d.write(to: ridotto), "PDFKit riscrive il PDF grosso (\(String(format: "%.1f", Date().timeIntervalSince(t0))) s)")
    }
    try? FileManager.default.removeItem(at: grosso)
    // da qui il file grosso è «ridotto» (scritto da PDFKit)
    let docG = PDFDocument(url: ridotto)!
    let n = docG.pageCount
    let mg = PDFDocument()
    let pg = nuovaPagina(docG.page(at: 2)!.bounds(for: .cropBox))
    for x in annotazioniApp(docG.page(at: 2)!.bounds(for: .cropBox), seme: 9, testo: true, byteDati: 100_000) { pg.addAnnotation(x) }
    mg.insert(pg, at: 0)
    _ = mg.write(to: mini)
    let t1 = Date()
    do {
        let e = try PDFAggiunta.applica(url: ridotto, miniatura: mini, pagine: [2], marcatore: marcatore) {
            guard let d = PDFDocument(url: ridotto), d.pageCount == n else { return false }
            return d.page(at: 2)!.annotations.filter { ($0.userName ?? "").hasPrefix("Apt") }.count == 3
        }
        print("  aggiunta su file da \(dimensione(ridotto) / 1_048_576) MB: \(e.byteAggiunti) byte aggiunti in \(String(format: "%.2f", Date().timeIntervalSince(t1))) s")
        controlla(true, "aggiunta su PDF grosso")
    } catch {
        controlla(false, "aggiunta su PDF grosso: \(error)")
    }
    // lo tengo per il controllo con qpdf, ma lo rendo piccolo per non pesare sul ramo: il controllo gira prima della pubblicazione
    try? FileManager.default.copyItem(at: ridotto, to: cartella.appendingPathComponent("grosso-controllo.bin"))
    try? FileManager.default.removeItem(at: ridotto)
}

print("\nErrori totali: \(errori)")
exit(errori == 0 ? 0 : 1)
