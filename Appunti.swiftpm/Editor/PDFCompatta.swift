// Compattazione del PDF senza perdita (solo Foundation + Compression).
//
// Due cose che fanno crescere i file:
//  1. Il salvataggio «per aggiunta» (PDFAggiunta) lascia in fondo al file le vecchie versioni delle annotazioni, che non
//     servono più ma restano: in un file da 400 MB erano circa 175 MB di scarto.
//  2. Le immagini interne scritte da PDFKit sono compresse senza «predittore»: con il predittore PNG (15) lo stesso
//     identico contenuto pesa il 20-40% in meno.
// Qui si riscrive il file con i soli oggetti raggiungibili dalla radice (stessi numeri, stessi byte) e si ricomprimono le
// immagini Flate con il predittore, controllando ogni volta che i pixel siano identici. Tabella xref classica come prima,
// quindi il file resta leggibile da PDFKit e dal salvataggio per aggiunta. Non tocca JPEG, testi, contenuti delle pagine.
import Foundation

enum PDFCompatta {
    struct Analisi {
        var totale: Int
        var vivi: Int
        var daRicomprimere: Int          // byte di immagini Flate senza predittore (candidate)
        var scarto: Int { max(0, totale - vivi) }
    }

    struct Esito {
        var prima: Int
        var dopo: Int
        var oggetti: Int
        var scartati: Int
        var immagini: Int
    }

    /// Immagini più piccole di questo non si ricomprimono (il guadagno sarebbe trascurabile)
    static let minimoImmagine = 40_000

    /// Quando conviene compattare. `soglieAlte`: dopo un salvataggio per aggiunta (riscrivere il file intero costa tempo e
    /// scritture sul disco, quindi si aspetta di avere almeno 25 MB di scarto o 20 MB di immagini ricomprimibili);
    /// altrimenti (il file viene comunque riscritto) basta poco.
    static func conviene(_ a: Analisi, soglieAlte: Bool) -> Bool {
        if soglieAlte { return (a.scarto > 25_000_000 && a.scarto * 10 > a.vivi) || a.daRicomprimere > 20_000_000 }
        return a.scarto > 1_000_000 || a.daRicomprimere > 1_500_000
    }

    // MARK: Raggiungibilità

    private static func numero(_ testo: String) -> Int? {
        Int(testo.split(separator: " ").first ?? "")
    }

    private static func raggiungibili(_ m: LettorePDF) throws -> [Int] {
        var coda: [Int] = []
        var visti = Set<Int>()
        for t in [m.coda.root, m.coda.info ?? ""] {
            if let n = numero(t), visti.insert(n).inserted { coda.append(n) }
        }
        var i = 0
        while i < coda.count {
            let n = coda[i]
            i += 1
            guard m.voci[n] != nil else { continue }
            let c = try m.corpo(n)
            for r in PDFAggiunta.riferimentiIn(m, c.valore) where visti.insert(r.numero).inserted {
                coda.append(r.numero)
            }
        }
        return coda.filter { m.voci[$0] != nil }.sorted()
    }

    private static func chiave(_ v: [(chiave: String, valore: Range<Int>)], _ k: String) -> Range<Int>? {
        v.first(where: { $0.chiave == k })?.valore
    }

    /// Un'immagine Flate «nuda» (senza predittore) abbastanza grande da valere la ricompressione?
    private static func candidata(_ m: LettorePDF, _ e: PDFAggiunta.Estratto) -> (larg: Int, alt: Int, bpc: Int)? {
        guard let fl = e.flusso, fl.count >= minimoImmagine else { return nil }
        let v = m.voci(e.valore)
        guard let sub = chiave(v, "/Subtype"), m.testo(sub) == "/Image",
              let filtro = chiave(v, "/Filter"), m.testo(filtro) == "/FlateDecode",
              chiave(v, "/DecodeParms") == nil, chiave(v, "/DP") == nil, chiave(v, "/F") == nil,
              let w = chiave(v, "/Width").flatMap({ Int(m.testo($0)) }),
              let h = chiave(v, "/Height").flatMap({ Int(m.testo($0)) }),
              let bpc = chiave(v, "/BitsPerComponent").flatMap({ Int(m.testo($0)) }),
              w > 0, h > 0, bpc == 8 || bpc == 16 else { return nil }
        if let mask = chiave(v, "/ImageMask"), m.testo(mask) == "true" { return nil }
        return (w, h, bpc)
    }

    static func analizza(url: URL) throws -> Analisi {
        let m = try LettorePDF(url: url)
        var vivi = 0
        var da = 0
        for n in try raggiungibili(m) {
            let e = try PDFAggiunta.estrai(m, n)
            let c = try m.corpo(n)
            vivi += e.fine - c.inizio
            if let fl = e.flusso, candidata(m, e) != nil { da += fl.count }
        }
        return Analisi(totale: m.f.dimensione, vivi: vivi, daRicomprimere: da)
    }

    // MARK: Scrittura

    private final class Scrittore {
        let h: FileHandle
        var buffer: [UInt8] = []
        var posizione = 0
        init(h: FileHandle) { self.h = h; buffer.reserveCapacity(4_200_000) }
        func scrivi<S: Sequence>(_ s: S) throws where S.Element == UInt8 {
            let prima = buffer.count
            buffer.append(contentsOf: s)
            posizione += buffer.count - prima
            if buffer.count >= 4_000_000 { try svuota() }
        }
        func testo(_ s: String) throws { try scrivi(Array(s.utf8)) }
        func svuota() throws {
            if buffer.isEmpty { return }
            try h.write(contentsOf: Data(buffer))
            buffer.removeAll(keepingCapacity: true)
        }
    }

    /// Ricomprime i dati di un'immagine con il predittore PNG; nil se non conviene o se la verifica non torna.
    private static func ricomprimi(_ m: LettorePDF, flusso: Range<Int>, larg: Int, alt: Int, bpc: Int) -> (dati: [UInt8], colori: Int)? {
        guard larg < 40_000, alt < 40_000 else { return nil }
        let byteCanale = bpc / 8
        let massimo = larg * alt * byteCanale * 4 + 1
        guard massimo > 1, massimo < 400_000_000 else { return nil }
        let z = UnsafeRawBufferPointer(rebasing: m.buf[flusso])
        guard let dec = Zlib.gonfia(z, capacita: massimo + 1) else { return nil }
        let rowb = dec.count / alt
        guard rowb * alt == dec.count, rowb % (larg * byteCanale) == 0 else { return nil }
        let colori = rowb / (larg * byteCanale)
        guard (1...4).contains(colori) else { return nil }
        let bpp = colori * byteCanale
        guard let f = FiltriPNG.filtra(dec, rowb: rowb, alt: alt, bpp: bpp), let nuovo = Zlib.comprimi(f) else { return nil }
        guard nuovo.count * 100 < flusso.count * 92 else { return nil }                 // almeno l'8% in meno
        let attesi = f.count
        let riletto: [UInt8]? = nuovo.withUnsafeBytes { Zlib.gonfia($0, capacita: attesi + 1) }
        guard let r2 = riletto, r2.count == attesi, let raw2 = FiltriPNG.sfiltra(r2, rowb: rowb, alt: alt, bpp: bpp), raw2 == dec else {
            return nil
        }
        return (nuovo, colori)
    }

    /// Riscrive `da` in `a` con i soli oggetti raggiungibili e le immagini ricompresse. Non tocca `da`.
    static func compatta(da: URL, a: URL) throws -> Esito {
        let m = try LettorePDF(url: da)
        let vivi = try raggiungibili(m)
        guard let ultimo = vivi.last else { throw ErrorePDF.nonSupportato("Nessun oggetto.") }
        let fm = FileManager.default
        try? fm.removeItem(at: a)
        guard fm.createFile(atPath: a.path, contents: nil) else { throw ErrorePDF.nonSupportato("Non riesco a creare il file.") }
        let h = try FileHandle(forWritingTo: a)
        defer { try? h.close() }
        let w = Scrittore(h: h)

        // Intestazione: la prima riga dell'originale («%PDF-1.x») e il commento binario
        var finePrimaRiga = 0
        while finePrimaRiga < min(m.f.dimensione, 32), m.buf[finePrimaRiga] != 10, m.buf[finePrimaRiga] != 13 { finePrimaRiga += 1 }
        try w.scrivi(m.buf[0..<finePrimaRiga])
        try w.scrivi([10, 37, 226, 227, 207, 211, 10])

        var offset: [Int: Int] = [:]
        var gens: [Int: Int] = [:]
        var immagini = 0
        for n in vivi {
            let e = try PDFAggiunta.estrai(m, n)
            let c = try m.corpo(n)
            offset[n] = w.posizione
            try w.testo("\(n) \(c.gen) obj\n")
            gens[n] = c.gen
            if let fl = e.flusso, let lung = e.lunghezza, let cand = candidata(m, e),
               let r = autoreleasepoolRicomprimi(m, fl, cand.larg, cand.alt, cand.bpc) {
                let larg = cand.larg, bpc = cand.bpc
                // dizionario con /Length nuovo e il predittore; il resto dell'oggetto com'era
                let dizionario = e.valore
                guard dizionario.upperBound - dizionario.lowerBound > 4,
                      m.buf[dizionario.upperBound - 1] == 62, m.buf[dizionario.upperBound - 2] == 62 else {
                    // struttura inattesa: l'oggetto resta com'era
                    try w.scrivi(m.buf[e.valore.lowerBound..<e.fine])
                    try w.testo("\n")
                    continue
                }
                try w.scrivi(m.buf[dizionario.lowerBound..<lung.lowerBound])
                try w.testo("\(r.dati.count)")
                try w.scrivi(m.buf[lung.upperBound..<(dizionario.upperBound - 2)])
                try w.testo(" /DecodeParms << /Predictor 15 /Colors \(r.colori) /BitsPerComponent \(bpc) /Columns \(larg) >> >>\nstream\n")
                try w.scrivi(r.dati)
                try w.testo("\nendstream\nendobj\n")
                immagini += 1
            } else {
                try w.scrivi(m.buf[e.valore.lowerBound..<e.fine])
                try w.testo("\n")
            }
        }

        // Tabella xref classica con l'elenco degli oggetti liberi
        let dimensione = ultimo + 1
        var liberi: [Int] = [0]
        for n in 1..<dimensione where offset[n] == nil { liberi.append(n) }
        var successivo: [Int: Int] = [:]
        for (k, n) in liberi.enumerated() { successivo[n] = k + 1 < liberi.count ? liberi[k + 1] : 0 }
        let posXref = w.posizione
        var x = "xref\n0 \(dimensione)\n"
        for n in 0..<dimensione {
            if let o = offset[n] {
                let gen = gens[n] ?? 0
                x += String(repeating: "0", count: max(0, 10 - String(o).count)) + String(o) + " " + zeriGen(gen) + " n \n"
            } else {
                let s = successivo[n] ?? 0
                x += String(repeating: "0", count: max(0, 10 - String(s).count)) + String(s) + (n == 0 ? " 65535 f \n" : " 00000 f \n")
            }
        }
        try w.testo(x)
        var trailer = "trailer\n<< /Size \(dimensione) /Root \(m.coda.root)"
        if let info = m.coda.info { trailer += " /Info \(info)" }
        if let id = m.coda.id { trailer += " /ID \(id)" }
        trailer += " >>\nstartxref\n\(posXref)\n%%EOF\n"
        try w.testo(trailer)
        try w.svuota()
        try h.synchronize()
        return Esito(prima: m.f.dimensione, dopo: w.posizione, oggetti: vivi.count, scartati: max(0, m.voci.count - vivi.count), immagini: immagini)
    }

    // MARK: Controllo

    private static func uguali(_ a: LettorePDF, _ ra: Range<Int>, _ b: LettorePDF, _ rb: Range<Int>) -> Bool {
        guard ra.count == rb.count else { return false }
        if ra.isEmpty { return true }
        return memcmp(a.buf.baseAddress! + ra.lowerBound, b.buf.baseAddress! + rb.lowerBound, ra.count) == 0
    }

    /// Le pagine, i loro elenchi di annotazioni e ogni annotazione devono essere identici, byte per byte, nei due file
    static func verifica(originale: URL, nuovo: URL) -> Bool {
        guard let a = try? LettorePDF(url: originale), let b = try? LettorePDF(url: nuovo),
              let pa = try? a.numeriPagine(), let pb = try? b.numeriPagine(), pa == pb, !pa.isEmpty else { return false }
        for n in pa {
            guard let ca = try? a.corpo(n), let cb = try? b.corpo(n), uguali(a, ca.valore, b, cb.valore) else { return false }
            guard let an = a.voci(ca.valore).first(where: { $0.chiave == "/Annots" }) else { continue }
            var elenco: [Int] = []
            if let k = a.riferimento(an.valore) {
                guard let x = try? a.corpo(k), let y = try? b.corpo(k), uguali(a, x.valore, b, y.valore),
                      let rif = a.riferimenti(in: x.valore) else { return false }
                elenco = rif
            } else if let rif = a.riferimenti(in: an.valore) {
                elenco = rif
            }
            for r in elenco {
                guard let x = try? a.corpo(r), let y = try? b.corpo(r), uguali(a, x.valore, b, y.valore) else { return false }
            }
        }
        return true
    }

    private static func zeriGen(_ g: Int) -> String {
        let s = String(g)
        return String(repeating: "0", count: max(0, 5 - s.count)) + s
    }

    private static func autoreleasepoolRicomprimi(_ m: LettorePDF, _ fl: Range<Int>, _ larg: Int, _ alt: Int, _ bpc: Int) -> (dati: [UInt8], colori: Int)? {
        autoreleasepool { ricomprimi(m, flusso: fl, larg: larg, alt: alt, bpc: bpc) }
    }
}
