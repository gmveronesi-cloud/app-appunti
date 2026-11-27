// Formato «a segnalini» nell'app (Binario A, punto 2 — 27/11/2026): attivo SOLO sui documenti di prova,
// cioè i file con «segnalini» nel nome. Tutti gli altri si salvano e si aprono come sempre (annotazioni).
// Qui: disegno del blocco della pagina (tratti come contorni, foto, testi veri), lettura all'apertura.
import SwiftUI
import PDFKit
import PencilKit
import CoreText

/// Ciò che il salvataggio deve scrivere con il formato a segnalini (preparato sul thread principale, scritto in sottofondo)
final class LavoroSegnalini {
    let pagine: [LavoroPagina]
    let elementiImmagine: [String: [UUID]]      // chiave dell'immagine → elementi che la usano
    var numeri: [String: Int] = [:]             // dopo la scrittura: chiave → oggetto nel file
    init(pagine: [LavoroPagina], elementiImmagine: [String: [UUID]]) {
        self.pagine = pagine
        self.elementiImmagine = elementiImmagine
    }
}

/// Costruisce il testo del blocco di una pagina
private struct CostruttoreBlocco {
    let box: CGRect
    let tag: String
    var corpo = ""
    var grafiche = 0
    var trasparenze: [String: String] = [:]          // alfa → nome
    var immagini: [ImmagineSegnalino] = []
    var font: String { "/AptF" + tag }

    static func n(_ v: CGFloat) -> String { n(Double(v)) }
    static func n(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let x = Int((v * 100).rounded())
        let a = abs(x), ip = a / 100, dp = a % 100
        let dec = dp == 0 ? "" : (dp % 10 == 0 ? ".\(dp / 10)" : (dp < 10 ? ".0\(dp)" : ".\(dp)"))
        return (x < 0 ? "-" : "") + String(ip) + dec
    }

    /// Da punti di pagina con origine in alto a sinistra a coordinate PDF
    func pdf(_ p: CGPoint) -> CGPoint { CGPoint(x: box.minX + p.x, y: box.maxY - p.y) }

    mutating func nomeTrasparenza(_ alfa: Double) -> String {
        let k = String(format: "%.3f", alfa)
        if let n = trasparenze[k] { return n }
        let n = "/AptG\(tag)\(trasparenze.count + 1)"
        trasparenze[k] = n
        return n
    }

    mutating func colore(_ rgb: [Double], alfa: Double) -> Bool {
        let semi = alfa < 0.995
        if semi { corpo += "q \(nomeTrasparenza(max(0, alfa))) gs " }
        corpo += "\(Self.n(rgb[0])) \(Self.n(rgb[1])) \(Self.n(rgb[2])) rg\n"
        return semi
    }

    mutating func riempi(_ cicli: [[CGPoint]], rgb: [Double], alfa: Double) {
        guard !cicli.isEmpty else { return }
        let semi = colore(rgb, alfa: alfa)
        for c in cicli {
            for (k, q) in c.enumerated() {
                let p = pdf(q)
                corpo += "\(Self.n(p.x)) \(Self.n(p.y)) \(k == 0 ? "m" : "l") "
            }
            corpo += "h\n"
        }
        corpo += "f*\n"
        if semi { corpo += "Q\n" }
        grafiche += 1
    }

    /// Percorso CoreGraphics (già in coordinate PDF) come operazioni del PDF
    static func operazioni(_ p: CGPath) -> String {
        var s = ""
        var corrente = CGPoint.zero
        var inizio = CGPoint.zero
        p.applyWithBlock { e in
            let pt = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint:
                corrente = pt[0]; inizio = pt[0]
                s += "\(n(pt[0].x)) \(n(pt[0].y)) m "
            case .addLineToPoint:
                corrente = pt[0]
                s += "\(n(pt[0].x)) \(n(pt[0].y)) l "
            case .addQuadCurveToPoint:
                let c1 = CGPoint(x: corrente.x + 2 / 3 * (pt[0].x - corrente.x), y: corrente.y + 2 / 3 * (pt[0].y - corrente.y))
                let c2 = CGPoint(x: pt[1].x + 2 / 3 * (pt[0].x - pt[1].x), y: pt[1].y + 2 / 3 * (pt[0].y - pt[1].y))
                corrente = pt[1]
                s += "\(n(c1.x)) \(n(c1.y)) \(n(c2.x)) \(n(c2.y)) \(n(pt[1].x)) \(n(pt[1].y)) c "
            case .addCurveToPoint:
                corrente = pt[2]
                s += "\(n(pt[0].x)) \(n(pt[0].y)) \(n(pt[1].x)) \(n(pt[1].y)) \(n(pt[2].x)) \(n(pt[2].y)) c "
            case .closeSubpath:
                corrente = inizio
                s += "h\n"
            @unknown default:
                break
            }
        }
        return s
    }
}

extension NotesModel {
    /// Documento di prova del formato a segnalini: «segnalini» nel nome del file
    static func eFormatoSegnalini(_ url: URL?) -> Bool {
        url?.lastPathComponent.range(of: "segnalini", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var formatoSegnalini: Bool { Self.eFormatoSegnalini(fileURL) && !segnaliniNonModificabili }

    /// Tratti della pagina in punti di pagina (origine in alto a sinistra), come per il salvataggio ad annotazioni
    func disegnoPagina(_ page: PDFPage) -> PKDrawing? {
        let box = page.bounds(for: .cropBox)
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = box.width / canvas.bounds.width
            return PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
        }
        return trattiSalvati[page]
    }

    // MARK: Salvataggio

    /// `riusa`: le foto già scritte nel file si riusano (solo nel salvataggio per aggiunta: il file è quello letto)
    func costruisciSegnalini(_ document: PDFDocument, soloIndici: Set<Int>?, riusa: Bool) -> LavoroSegnalini {
        let tag = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4))
        var pagine: [LavoroPagina] = []
        var elementi: [String: [UUID]] = [:]
        let inizio = CFAbsoluteTimeGetCurrent()
        for i in 0..<document.pageCount {
            if let soloIndici, !soloIndici.contains(i) { continue }
            guard let page = document.page(at: i) else { continue }
            autoreleasepool {
                let (l, el) = lavoroPagina(indice: i, page: page, tag: tag, riusa: riusa)
                pagine.append(l)
                for (k, v) in el { elementi[k, default: []] += v }
            }
        }
        let conBlocco = pagine.filter { $0.contenuto != nil }
        Diagnostica.nota("segnalini-prepara", "\(conBlocco.count) pagine con blocco su \(pagine.count), \(conBlocco.reduce(0) { $0 + ($1.contenuto?.count ?? 0) } / 1024) KB, \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - inizio)) s")
        return LavoroSegnalini(pagine: pagine, elementiImmagine: elementi)
    }

    private func lavoroPagina(indice: Int, page: PDFPage, tag: String, riusa: Bool) -> (LavoroPagina, [String: [UUID]]) {
        let box = page.bounds(for: .cropBox)
        let tratti = disegnoPagina(page)?.strokes ?? []
        let imm = (immagini[page] ?? []).sorted { $0.creazione < $1.creazione }
        let txt = (testi[page] ?? []).sorted { $0.creazione < $1.creazione }
        guard !tratti.isEmpty || !imm.isEmpty || !txt.isEmpty else { return (LavoroPagina(indice: indice, contenuto: nil), [:]) }

        var c = CostruttoreBlocco(box: box, tag: tag)

        // Livelli: tratti fra due «confini» (foto/testi in ordine di creazione); in ogni intervallo prima gli evidenziatori, poi gli inchiostri
        enum Oggetto { case immagine(ElementoImmagine), testo(ElementoTesto) }
        var oggetti: [(Date, Oggetto)] = imm.map { ($0.creazione, .immagine($0)) } + txt.map { ($0.creazione, .testo($0)) }
        oggetti.sort { $0.0 < $1.0 }
        let confini = oggetti.map { $0.0 }
        var segmenti = [[PKStroke]](repeating: [], count: confini.count + 1)
        for t in tratti {
            segmenti[confini.filter { $0 < t.path.creationDate }.count].append(t)
        }

        var ordineImmagini: [(ElementoImmagine, Int)] = []
        var elementi: [String: [UUID]] = [:]
        for s in 0...confini.count {
            disegnaTratti(segmenti[s], in: &c)
            guard s < oggetti.count else { break }
            switch oggetti[s].1 {
            case .immagine(let e):
                guard let im = immagineSegnalino(e, nome: "/AptI\(tag)\(c.immagini.count + 1)", riusa: riusa) else {
                    Diagnostica.nota("segnalini-immagine", "pagina \(indice + 1): immagine non preparata, salto")
                    continue
                }
                ordineImmagini.append((e, c.immagini.count))
                c.immagini.append(im)
                elementi[im.chiave, default: []].append(e.id)
                disegnaImmagine(e, nome: im.nome, in: &c)
            case .testo(let e):
                _ = disegnaTesto(e, in: &c)
            }
        }

        let dati = DatiSegnalini.codifica(tratti: tratti, immagini: ordineImmagini, testi: txt, box: box)
        let h = Segnalini.impronta(dati)
        let b64 = (Flate.comprimi(dati) ?? Data()).base64EncodedString()
        var pezzi: [Substring] = []
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: Segnalini.pezzo, limitedBy: b64.endIndex) ?? b64.endIndex
            pezzi.append(b64[i..<j])
            i = j
        }
        if pezzi.isEmpty { pezzi = [""] }
        let elementiTot = tratti.count + ordineImmagini.count + txt.count
        func segnalino(_ t: String) -> String {
            "BT \(c.font) 1 Tf 3 Tr 1 0 0 1 \(CostruttoreBlocco.n(box.minX + 2)) \(CostruttoreBlocco.n(box.minY + 2)) Tm (\(t)) Tj ET\n"
        }
        var blocco = "q\n"
        blocco += segnalino("APT-INIZIO v\(Segnalini.versione) p\(indice + 1) e\(elementiTot) n\(c.grafiche) h\(h) k\(pezzi.count)")
        for (k, p) in pezzi.enumerated() { blocco += segnalino("APT-D \(k + 1)/\(pezzi.count) \(p)") }
        blocco += c.corpo
        blocco += segnalino("APT-FINE h\(h)")
        blocco += "Q\n"

        var l = LavoroPagina(indice: indice, contenuto: Data(blocco.utf8))
        l.font = c.font
        l.trasparenze = c.trasparenze.map { (nome: $0.value, alfa: Double($0.key) ?? 1) }
        l.immagini = c.immagini
        l.impronta = h
        l.grafiche = c.grafiche
        l.elementi = elementiTot
        return (l, elementi)
    }

    // MARK: Tratti come contorni (metodo della prova del 25–26/11)

    private func disegnaTratti(_ tratti: [PKStroke], in c: inout CostruttoreBlocco) {
        guard !tratti.isEmpty else { return }
        let luce = UITraitCollection(userInterfaceStyle: .light)
        struct Gruppo { var tratti: [PKStroke]; var primo: Date }
        func chiave(_ t: PKStroke) -> String {
            let col = t.ink.color.resolvedColor(with: luce)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            col.getRed(&r, green: &g, blue: &b, alpha: &a)
            return "\(Int(r * 255)) \(Int(g * 255)) \(Int(b * 255)) \(Int(a * 100))"
        }
        var evid: [String: Gruppo] = [:], ink: [String: Gruppo] = [:]
        for t in tratti {
            let k = chiave(t)
            if Self.eEvidenziatore(t) {
                evid[k, default: Gruppo(tratti: [], primo: .distantFuture)].tratti.append(t)
                evid[k]!.primo = min(evid[k]!.primo, t.path.creationDate)
            } else {
                ink[k, default: Gruppo(tratti: [], primo: .distantFuture)].tratti.append(t)
                ink[k]!.primo = min(ink[k]!.primo, t.path.creationDate)
            }
        }
        for g in evid.values.sorted(by: { $0.primo < $1.primo }) {
            if let f = contorni(g.tratti, box: c.box, evidenziatore: true) { c.riempi(f.cicli, rgb: f.rgb, alfa: f.alfa) }
        }
        for g in ink.values.sorted(by: { $0.primo < $1.primo }) {
            if let f = contorni(g.tratti, box: c.box, evidenziatore: false) { c.riempi(f.cicli, rgb: f.rgb, alfa: f.alfa) }
        }
    }

    /// Contorno di un gruppo di tratti dello stesso colore: forma piena (evidenziatori uniti: negli incroci non si scuriscono)
    private func contorni(_ ts: [PKStroke], box: CGRect, evidenziatore: Bool) -> (cicli: [[CGPoint]], rgb: [Double], alfa: Double)? {
        let luce = UITraitCollection(userInterfaceStyle: .light)
        let d = PKDrawing(strokes: ts)
        let foglio = CGRect(origin: .zero, size: box.size)
        let r = d.bounds.insetBy(dx: -6, dy: -6).intersection(foglio).integral
        guard !r.isNull, r.width > 0, r.height > 0 else { return nil }
        let pp = min(6, sqrt(2_500_000 / max(r.width * r.height, 1)))
        var img: UIImage?
        luce.performAsCurrent { img = d.image(from: r, scale: pp) }
        guard let immagine = img, let cg = immagine.cgImage else { return nil }
        let sx = CGFloat(cg.width) / r.width, sy = CGFloat(cg.height) / r.height
        func cicli(_ campo: Contorni.Campo, _ soglia: Float) -> [[CGPoint]] {
            Contorni.contorni(campo, soglia: soglia).compactMap { ciclo in
                let s = Contorni.semplifica(ciclo, tol: 0.35)
                guard s.count >= 3 else { return nil }
                return s.map { CGPoint(x: r.minX + ($0.x - 0.5) / sx, y: r.minY + ($0.y - 0.5) / sy) }
            }
        }
        if evidenziatore, let cs = Contorni.campoScuro(da: immagine) {
            // colore e trasparenza di UN tratto misurati sull'immagine di PencilKit (valore più frequente del campo «scuro»)
            let campo = cs.scuro, buf = cs.buf
            var istogramma = [Int](repeating: 0, count: 256)
            for v in campo.a where v > 10 { istogramma[Int(v)] += 1 }
            var f1 = 15
            for i in 15..<256 where istogramma[i] > istogramma[f1] { f1 = i }
            if istogramma[f1] > 0 {
                let basso = Float(f1) * 0.9, alto = Float(f1) * 1.1
                var n1 = 0
                var s1 = [Double](repeating: 0, count: 4)
                for i in 0..<(campo.larg * campo.alt) {
                    let v = Float(campo.a[i])
                    if v >= basso && v <= alto {
                        n1 += 1
                        for k in 0..<4 { s1[k] += Double(buf[i * 4 + k]) }
                    }
                }
                if n1 > 0, s1[3] > 0 {
                    let f = cicli(campo, max(Float(f1) / 2, 6))
                    if !f.isEmpty {
                        return (f, [s1[0] / s1[3], s1[1] / s1[3], s1[2] / s1[3]], s1[3] / Double(n1) / 255)
                    }
                }
            }
        }
        guard let campo = Contorni.campo(da: immagine) else { return nil }
        var istogramma = [Int](repeating: 0, count: 256)
        for v in campo.a where v > 10 { istogramma[Int(v)] += 1 }
        let totale = istogramma.reduce(0, +)
        var cumulo = 0, tipica = 255
        for i in 0..<256 {
            cumulo += istogramma[i]
            if totale > 0 && cumulo * 100 >= totale * 90 { tipica = i; break }
        }
        let col = (ts.first?.ink.color ?? .black).resolvedColor(with: luce)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        col.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        let f = cicli(campo, max(Float(tipica) / 2, 6))
        guard !f.isEmpty else { return nil }
        return (f, [Double(rr), Double(gg), Double(bb)].map { max(0, min(1, $0)) }, Double(tipica) / 255)
    }

    // MARK: Foto

    /// Larghezza, altezza e componenti di un JPEG (dal marcatore SOF); nil se non è un JPEG semplice a 8 bit
    static func infoJPEG(_ d: Data) -> (larghezza: Int, altezza: Int, componenti: Int)? {
        let b = [UInt8](d.prefix(200_000))
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { return nil }
            let m = b[i + 1]
            if m == 0xFF { i += 1; continue }
            if m == 0x01 || (0xD0...0xD8).contains(m) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xCF).contains(m) && m != 0xC4 && m != 0xC8 && m != 0xCC {
                let precisione = b[i + 4]
                let h = Int(b[i + 5]) << 8 | Int(b[i + 6])
                let w = Int(b[i + 7]) << 8 | Int(b[i + 8])
                let comp = Int(b[i + 9])
                guard precisione == 8, comp == 1 || comp == 3, w > 0, h > 0 else { return nil }
                return (w, h, comp)
            }
            i += 2 + len
        }
        return nil
    }

    private func immagineSegnalino(_ e: ElementoImmagine, nome: String, riusa: Bool) -> ImmagineSegnalino? {
        let chiave = Segnalini.impronta(e.dati)
        var im = ImmagineSegnalino(nome: nome, chiave: chiave)
        if riusa, let o = oggettiSegnalini[e.id], o.chiave == chiave { im.esistente = o.numero }
        if let j = Self.infoJPEG(e.dati) {
            im.jpeg = e.dati
            im.larghezza = j.larghezza
            im.altezza = j.altezza
            im.componenti = j.componenti
            return im
        }
        // Altri formati (PNG…): pixel senza perdita, con la trasparenza a parte
        guard let cg = e.base.cgImage ?? UIImage(data: e.dati)?.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        var alfa = [UInt8](repeating: 255, count: w * h)
        var trasparente = false
        for i in 0..<(w * h) {
            let a = buf[i * 4 + 3]
            alfa[i] = a
            if a < 255 { trasparente = true }
            for k in 0..<3 {
                let v = buf[i * 4 + k]
                rgb[i * 3 + k] = a == 0 ? 255 : (a == 255 ? v : UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a))))
            }
        }
        im.pixel = Data(rgb)
        im.alfa = trasparente ? Data(alfa) : nil
        im.larghezza = w
        im.altezza = h
        im.componenti = 3
        return im
    }

    private func disegnaImmagine(_ e: ElementoImmagine, nome: String, in c: inout CostruttoreBlocco) {
        typealias N = CostruttoreBlocco
        let sc = e.scala
        let w = e.larghezza, h = e.altezza
        let W = e.base.size.width, H = e.base.size.height      // `ritaglio` è in queste unità
        let co = cos(e.angolo), si = sin(e.angolo)
        var s = "q \(N.n(co)) \(N.n(si)) \(N.n(-si)) \(N.n(co)) \(N.n(e.centro.x)) \(N.n(e.centro.y)) cm\n"
        s += "\(N.n(-w / 2)) \(N.n(-h / 2)) \(N.n(w)) \(N.n(h)) re W n\n"
        for poligono in e.maschera where poligono.count >= 3 {
            for (k, q) in poligono.enumerated() {
                let x = -w / 2 + (q.x - e.ritaglio.minX) * sc
                let y = h / 2 - (q.y - e.ritaglio.minY) * sc
                s += "\(N.n(x)) \(N.n(y)) \(k == 0 ? "m" : "l") "
            }
            s += "h W n\n"
        }
        let x0 = -w / 2 - e.ritaglio.minX * sc
        let y0 = h / 2 + e.ritaglio.minY * sc - H * sc
        // 4 decimali per la scala dell'immagine: con 2 si vedrebbe uno spostamento sulle foto grandi
        s += "q \(String(format: "%.4f", Double(W * sc))) 0 0 \(String(format: "%.4f", Double(H * sc))) \(N.n(x0)) \(N.n(y0)) cm \(nome) Do Q\nQ\n"
        c.corpo += s
        c.grafiche += 1
    }

    // MARK: Testi (testo vero, Helvetica; se ci sono caratteri fuori da WinAnsi, contorni delle lettere)

    /// Vero se il testo è scritto come testo (font usato)
    private func disegnaTesto(_ e: ElementoTesto, in c: inout CostruttoreBlocco) -> Bool {
        typealias N = CostruttoreBlocco
        let rett = e.rettangolo
        let font = CTFontCreateWithName("Helvetica" as CFString, e.corpo, nil)
        var allinea: CTTextAlignment = e.larghezza != nil ? .justified : .left
        let stile: CTParagraphStyle = withUnsafeBytes(of: &allinea) { p in
            var impostazioni = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: p.baseAddress!)]
            return CTParagraphStyleCreate(&impostazioni, 1)
        }
        let attributi: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): stile
        ]
        let largo: CGFloat = e.larghezza != nil ? rett.width : 100_000
        let alto: CGFloat = 100_000
        let testo = e.testo as NSString
        let fs = CTFramesetterCreateWithAttributedString(NSAttributedString(string: e.testo, attributes: attributi))
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: largo, height: alto), transform: nil), nil)
        guard let righe = CTFrameGetLines(frame) as? [CTLine], !righe.isEmpty else { return false }
        var origini = [CGPoint](repeating: .zero, count: righe.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origini)
        let col = e.colore.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        col.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb = [Double(r), Double(g), Double(b)].map { max(0, min(1, $0)) }
        let fineRiga = CharacterSet(charactersIn: "\n\r\u{2028}\u{2029}")

        if e.testo.data(using: .windowsCP1252) != nil {
            let semi = a < 0.995
            if semi { c.corpo += "q \(c.nomeTrasparenza(Double(a))) gs\n" }
            c.corpo += "BT \(c.font) \(N.n(e.corpo)) Tf 0 Tr 0 Tc 100 Tz 0 Ts "
            c.corpo += "\(N.n(rgb[0])) \(N.n(rgb[1])) \(N.n(rgb[2])) rg\n"
            for (k, riga) in righe.enumerated() {
                let rg = CTLineGetStringRange(riga)
                let pezzo = testo.substring(with: NSRange(location: rg.location, length: rg.length))
                let ultimaDelParagrafo = k == righe.count - 1 || pezzo.rangeOfCharacter(from: fineRiga) != nil
                let pulito = pezzo.trimmingCharacters(in: fineRiga)
                let stampato = e.larghezza != nil ? String(pulito.reversed().drop(while: { $0 == " " }).reversed()) : pulito
                var tw = 0.0
                if e.larghezza != nil && !ultimaDelParagrafo {
                    let spazi = stampato.filter { $0 == " " }.count
                    if spazi > 0 {
                        let naturale = CTLineCreateWithAttributedString(NSAttributedString(string: stampato, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                        let larghezzaNaturale = CTLineGetTypographicBounds(naturale, nil, nil, nil)
                        tw = max(0, (Double(largo) - larghezzaNaturale) / Double(spazi))
                    }
                }
                let x = rett.minX + origini[k].x
                let y = rett.maxY - (alto - origini[k].y)
                let hex = (stampato.data(using: .windowsCP1252) ?? Data()).map { String(format: "%02x", $0) }.joined()
                c.corpo += "\(N.n(tw)) Tw 1 0 0 1 \(N.n(x)) \(N.n(y)) Tm <\(hex)> Tj\n"
            }
            c.corpo += "ET\n"
            if semi { c.corpo += "Q\n" }
            return true
        }

        // Contorni delle lettere: si vede uguale, ma non si trova cercando
        let percorso = CGMutablePath()
        for (k, riga) in righe.enumerated() {
            let x = rett.minX + origini[k].x
            let y = rett.maxY - (alto - origini[k].y)
            guard let runs = CTLineGetGlyphRuns(riga) as? [CTRun] else { continue }
            for run in runs {
                let n = CTRunGetGlyphCount(run)
                guard n > 0 else { continue }
                var glifi = [CGGlyph](repeating: 0, count: n)
                var pos = [CGPoint](repeating: .zero, count: n)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glifi)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
                let att = CTRunGetAttributes(run) as NSDictionary
                let fr = att[kCTFontAttributeName as String] as! CTFont? ?? font
                for j in 0..<n {
                    guard let gp = CTFontCreatePathForGlyph(fr, glifi[j], nil) else { continue }
                    percorso.addPath(gp, transform: CGAffineTransform(translationX: x + pos[j].x, y: y + pos[j].y))
                }
            }
        }
        guard !percorso.isEmpty else { return false }
        let semi = c.colore(rgb, alfa: Double(a))
        c.corpo += CostruttoreBlocco.operazioni(percorso) + "f\n"
        if semi { c.corpo += "Q\n" }
        c.grafiche += 1
        return false
    }

    // MARK: Apertura

    /// Elementi letti dai blocchi (dopo `caricaTratti`, sul documento aperto dalla copia di lavoro)
    func caricaSegnalini(_ a: AperturaSegnalini, in doc: PDFDocument) {
        var nTratti = 0, nImm = 0, nTesti = 0
        var avvisi = a.avvisi
        for pl in a.pagine {
            guard let page = doc.page(at: pl.indice) else { continue }
            let box = page.bounds(for: .cropBox)
            do {
                let (tratti, specs, txt) = try DatiSegnalini.decodifica(pl.dati, box: box)
                if !tratti.isEmpty {
                    trattiSalvati[page] = PKDrawing(strokes: (trattiSalvati[page]?.strokes ?? []) + tratti)
                    nTratti += tratti.count
                }
                for s in specs {
                    guard let im = pl.immagini[s.indiceDo], let base = UIImage(data: im.dati) else {
                        lettureFallite += 1
                        continue
                    }
                    var e = ElementoImmagine(dati: im.dati, base: base, ritaglio: s.ritaglio, centro: s.centro, larghezza: s.larghezza,
                                             angolo: s.angolo, creazione: s.creazione)
                    e.id = s.id
                    if !s.maschera.isEmpty {
                        e.maschera = s.maschera
                        e.impostaRitaglio(e.ritaglio)
                    }
                    immagini[page, default: []].append(e)
                    if let n = im.numero { oggettiSegnalini[e.id] = (n, Segnalini.impronta(im.dati)) }
                    nImm += 1
                }
                testi[page, default: []] += txt
                nTesti += txt.count
                if pl.disegnoDiverso { avvisi.append("Pagina \(pl.indice + 1): il disegno era stato modificato fuori dall'app; l'ho rifatto dai dati.") }
            } catch {
                avvisi.append("Pagina \(pl.indice + 1): dati dell'app illeggibili (\(error)).")
            }
        }
        Diagnostica.nota("segnalini-letti", "\(a.pagine.count) pagine, \(nTratti) tratti, \(nImm) foto, \(nTesti) testi, copia di lavoro \(a.copia != nil ? "sì" : "no"), avvisi \(avvisi.count)")
        if !avvisi.isEmpty { avviso(avvisi.prefix(3).joined(separator: "\n")) }
    }

    /// Dopo un salvataggio riuscito: le foto scritte ora si possono riusare nel prossimo salvataggio per aggiunta
    /// `completo`: il file è stato riscritto da capo, i numeri di prima non valgono più
    func registraSegnalini(_ l: LavoroSegnalini, completo: Bool) {
        if completo { oggettiSegnalini = [:] }
        for (chiave, ids) in l.elementiImmagine {
            guard let n = l.numeri[chiave] else { continue }
            for id in ids { oggettiSegnalini[id] = (n, chiave) }
        }
    }
}
