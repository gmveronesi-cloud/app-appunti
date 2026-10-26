// Salvataggio «per aggiunta» (solo Foundation).
//
// Riscrivere tutto il PDF a ogni salvataggio è lento e pesante: un PDF da 500 MB richiede più di un minuto, due scritture
// complete e tanta memoria. Lo standard PDF prevede però l'«aggiornamento incrementale»: in fondo al file si aggiungono
// i soli oggetti nuovi, una nuova tabella xref e un nuovo «startxref»; quello che c'era prima non si tocca.
//
// Qui si fa così:
//  1. PDFKit scrive un piccolo PDF «miniatura» che contiene solo le annotazioni nuove delle pagine cambiate
//     (così le annotazioni sono fatte da PDFKit, identiche a quelle del salvataggio completo);
//  2. i loro oggetti vengono copiati in fondo al PDF vero con numeri nuovi;
//  3. per ogni pagina cambiata si riscrive l'elenco /Annots: restano le annotazioni che non sono dell'app
//     (nome che non comincia per «Apt») e si aggiungono quelle nuove; le vecchie dell'app restano nel file come scarto
//     (dopo `massimoSezioni` aggiornamenti si riscrive tutto il file, e lo scarto sparisce).
// Se qualcosa non torna (struttura sconosciuta, file diverso da quello atteso, verifica finale fallita) si lancia un errore
// e il file torna esattamente com'era (si taglia in fondo): chi chiama ripiega sulla scrittura completa.
import Foundation

enum PDFAggiunta {
    /// Quante sezioni xref al massimo prima di riscrivere tutto il file (compattandolo)
    static let massimoSezioni = 12

    struct Esito {
        var byteAggiunti: Int
        var oggetti: Int
        var sezioni: Int
    }

    // MARK: Costruzione dei byte da aggiungere

    private struct Estratto {
        var valore: Range<Int>
        var fine: Int
        var rif: [(span: Range<Int>, numero: Int)]
    }

    private static func riferimentiIn(_ m: LettorePDF, _ r: Range<Int>) -> [(span: Range<Int>, numero: Int)] {
        var lex = LessicoPDF(m.buf, da: r.lowerBound, fino: r.upperBound)
        var prima: LessicoPDF.Gettone?
        var prima2: LessicoPDF.Gettone?
        var out: [(span: Range<Int>, numero: Int)] = []
        while let g = lex.prossimo() {
            if lex.eParola(g, "R"), let a = prima2, let b = prima, a.tipo == .numero, b.tipo == .numero,
               let n = lex.intero(a), lex.intero(b) != nil {
                out.append((span: a.r.lowerBound..<g.r.upperBound, numero: n))
            }
            prima2 = prima
            prima = g
        }
        return out
    }

    private static func estrai(_ m: LettorePDF, _ n: Int) throws -> Estratto {
        let c = try m.corpo(n)
        var fine = c.valore.upperBound
        if c.flusso {
            var lex = LessicoPDF(m.buf, da: c.valore.upperBound)
            guard let s = lex.prossimo(), lex.eParola(s, "stream") else { throw ErrorePDF.nonSupportato("Flusso illeggibile.") }
            var q = lex.p
            if q < m.buf.count, m.buf[q] == 13 {
                q += 1
                if q < m.buf.count, m.buf[q] == 10 { q += 1 }
            } else if q < m.buf.count, m.buf[q] == 10 {
                q += 1
            }
            guard let lung = m.voci(c.valore).first(where: { $0.chiave == "/Length" }) else {
                throw ErrorePDF.nonSupportato("Flusso senza lunghezza.")
            }
            var lunghezza = Int(m.testo(lung.valore))
            if lunghezza == nil, let ref = m.riferimento(lung.valore) {
                let cl = try m.corpo(ref)
                lunghezza = Int(m.testo(cl.valore))
            }
            guard let len = lunghezza, len >= 0, q + len <= m.buf.count else {
                throw ErrorePDF.nonSupportato("Lunghezza del flusso non valida.")
            }
            var lex2 = LessicoPDF(m.buf, da: q + len)
            guard let a = lex2.prossimo(), lex2.eParola(a, "endstream"), let b = lex2.prossimo(), lex2.eParola(b, "endobj") else {
                throw ErrorePDF.nonSupportato("Fine del flusso non trovata dove attesa.")
            }
            fine = lex2.p
        } else {
            var lex = LessicoPDF(m.buf, da: c.valore.upperBound)
            guard let e = lex.prossimo(), lex.eParola(e, "endobj") else { throw ErrorePDF.nonSupportato("endobj mancante.") }
            fine = lex.p
        }
        return Estratto(valore: c.valore, fine: fine, rif: riferimentiIn(m, c.valore))
    }

    private static func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    private static func zeri(_ n: Int, _ cifre: Int) -> String {
        let s = String(n)
        return s.count >= cifre ? s : String(repeating: "0", count: cifre - s.count) + s
    }

    /// I byte da aggiungere in fondo a `lettore` per sostituire le annotazioni dell'app delle `pagine` (indici nel documento)
    /// con quelle che stanno nelle pagine corrispondenti di `miniatura` (stesso ordine di `pagine`).
    static func prepara(lettore: LettorePDF, miniatura: LettorePDF, pagine: [Int]) throws -> (byte: [UInt8], oggetti: Int) {
        guard !pagine.isEmpty, Set(pagine).count == pagine.count else { throw ErrorePDF.nonSupportato("Elenco pagine non valido.") }
        let principali = try lettore.numeriPagine()
        let dellaMini = try miniatura.numeriPagine()
        guard dellaMini.count == pagine.count else { throw ErrorePDF.nonSupportato("La miniatura ha un numero di pagine diverso.") }

        var paginaMini: [Int: Int] = [:]          // oggetto pagina nella miniatura -> oggetto pagina nel PDF
        for (k, idx) in pagine.enumerated() {
            guard idx >= 0, idx < principali.count else { throw ErrorePDF.nonSupportato("Pagina \(idx) fuori dal documento.") }
            paginaMini[dellaMini[k]] = principali[idx]
        }

        // Pagine del PDF vero: elenco /Annots attuale
        struct Pagina {
            var numero: Int
            var arrayAnnots: Int?
            var mantenute: [Int]
        }
        var info: [Pagina] = []
        var arrayUsati = Set<Int>()
        for idx in pagine {
            let n = principali[idx]
            let c = try lettore.corpo(n)
            guard !c.flusso, c.gen == 0 else { throw ErrorePDF.nonSupportato("Pagina non modificabile per aggiunta.") }
            let v = lettore.voci(c.valore)
            if let rot = v.first(where: { $0.chiave == "/Rotate" }), let gradi = Int(lettore.testo(rot.valore)), gradi % 360 != 0 {
                throw ErrorePDF.nonSupportato("Pagina ruotata.")
            }
            var p = Pagina(numero: n, arrayAnnots: nil, mantenute: [])
            if let an = v.first(where: { $0.chiave == "/Annots" }) {
                guard let k = lettore.riferimento(an.valore) else { throw ErrorePDF.nonSupportato("Elenco annotazioni diretto nella pagina.") }
                let ca = try lettore.corpo(k)
                guard !ca.flusso, ca.gen == 0, let rif = lettore.riferimenti(in: ca.valore), arrayUsati.insert(k).inserted else {
                    throw ErrorePDF.nonSupportato("Elenco annotazioni non semplice.")
                }
                p.arrayAnnots = k
                for r in rif {
                    if try !lettore.eAnnotazioneApp(r) { p.mantenute.append(r) }
                }
            }
            info.append(p)
        }

        // Annotazioni nuove, nella miniatura
        var nuoveMini: [[Int]] = []
        for k in 0..<pagine.count {
            let c = try miniatura.corpo(dellaMini[k])
            var rif: [Int] = []
            if let an = miniatura.voci(c.valore).first(where: { $0.chiave == "/Annots" }) {
                if let kk = miniatura.riferimento(an.valore) {
                    let ca = try miniatura.corpo(kk)
                    guard let r = miniatura.riferimenti(in: ca.valore) else { throw ErrorePDF.nonSupportato("Annotazioni della miniatura illeggibili.") }
                    rif = r
                } else {
                    guard let r = miniatura.riferimenti(in: an.valore) else { throw ErrorePDF.nonSupportato("Annotazioni della miniatura illeggibili.") }
                    rif = r
                }
            }
            nuoveMini.append(rif)
        }

        // Tutti gli oggetti raggiunti dalle annotazioni nuove, con il loro numero nel PDF vero
        let base = max(lettore.coda.size, (lettore.voci.keys.max() ?? 0) + 1)
        var prossimoNumero = base
        var mappa: [Int: Int] = [:]
        var ordine: [Int] = []
        for lista in nuoveMini {
            for n in lista where mappa[n] == nil {
                mappa[n] = prossimoNumero
                prossimoNumero += 1
                ordine.append(n)
            }
        }
        var estratti: [Int: Estratto] = [:]
        var i = 0
        while i < ordine.count {
            let n = ordine[i]
            i += 1
            let e = try estrai(miniatura, n)
            estratti[n] = e
            for r in e.rif {
                if paginaMini[r.numero] != nil { continue }
                if mappa[r.numero] == nil {
                    mappa[r.numero] = prossimoNumero
                    prossimoNumero += 1
                    ordine.append(r.numero)
                }
            }
        }

        // Si compone ciò che va in fondo al file
        let lunghezza = lettore.f.dimensione
        var prefisso: [UInt8] = []
        let ultimo = lettore.buf[lunghezza - 1]
        if ultimo != 10 && ultimo != 13 { prefisso = [10] }
        var blob: [UInt8] = []
        var nuove: [(numero: Int, offset: Int)] = []

        for n in ordine {
            guard let e = estratti[n], let nuovo = mappa[n] else { continue }
            nuove.append((numero: nuovo, offset: lunghezza + prefisso.count + blob.count))
            blob.append(contentsOf: bytes("\(nuovo) 0 obj\n"))
            var da = e.valore.lowerBound
            for r in e.rif {
                blob.append(contentsOf: miniatura.buf[da..<r.span.lowerBound])
                guard let nn = mappa[r.numero] ?? paginaMini[r.numero] else { throw ErrorePDF.nonSupportato("Riferimento a un oggetto escluso.") }
                blob.append(contentsOf: bytes("\(nn) 0 R"))
                da = r.span.upperBound
            }
            blob.append(contentsOf: miniatura.buf[da..<e.fine])      // il resto dell'oggetto (anche il flusso) com'è
            blob.append(10)
        }

        for (k, p) in info.enumerated() {
            var elenco = p.mantenute
            for n in nuoveMini[k] { if let nn = mappa[n] { elenco.append(nn) } }
            var testo = "["
            for n in elenco { testo += " \(n) 0 R" }
            testo += " ]"
            if let arr = p.arrayAnnots {
                nuove.append((numero: arr, offset: lunghezza + prefisso.count + blob.count))
                blob.append(contentsOf: bytes("\(arr) 0 obj\n\(testo)\nendobj\n"))
            } else {
                let arr = prossimoNumero
                prossimoNumero += 1
                nuove.append((numero: arr, offset: lunghezza + prefisso.count + blob.count))
                blob.append(contentsOf: bytes("\(arr) 0 obj\n\(testo)\nendobj\n"))
                // la pagina riceve /Annots
                let c = try lettore.corpo(p.numero)
                let v = c.valore
                guard v.count > 4, lettore.buf[v.upperBound - 1] == 62, lettore.buf[v.upperBound - 2] == 62 else {
                    throw ErrorePDF.nonSupportato("Dizionario della pagina inatteso.")
                }
                nuove.append((numero: p.numero, offset: lunghezza + prefisso.count + blob.count))
                blob.append(contentsOf: bytes("\(p.numero) 0 obj\n"))
                blob.append(contentsOf: lettore.buf[v.lowerBound..<(v.upperBound - 2)])
                blob.append(contentsOf: bytes(" /Annots \(arr) 0 R >>\nendobj\n"))
            }
        }

        // Tabella xref nuova (solo gli oggetti toccati) e trailer
        let ordinate = nuove.sorted { $0.numero < $1.numero }
        for k in 1..<max(ordinate.count, 1) where ordinate[k].numero == ordinate[k - 1].numero {
            throw ErrorePDF.nonSupportato("Oggetto scritto due volte.")
        }
        let offsetXref = lunghezza + prefisso.count + blob.count
        var xref = "xref\n"
        var a = 0
        while a < ordinate.count {
            var b = a
            while b + 1 < ordinate.count, ordinate[b + 1].numero == ordinate[b].numero + 1 { b += 1 }
            xref += "\(ordinate[a].numero) \(b - a + 1)\n"
            var k = a
            while k <= b {
                xref += "\(zeri(ordinate[k].offset, 10)) 00000 n \n"
                k += 1
            }
            a = b + 1
        }
        let dimensione = max(base, prossimoNumero, lettore.coda.size)
        var trailer = "trailer\n<< /Size \(dimensione) /Root \(lettore.coda.root)"
        if let info = lettore.coda.info { trailer += " /Info \(info)" }
        if let id = lettore.coda.id { trailer += " /ID \(id)" }
        trailer += " /Prev \(lettore.ultimoStartXref) >>\nstartxref\n\(offsetXref)\n%%EOF\n"

        var tutto = prefisso
        tutto.append(contentsOf: blob)
        tutto.append(contentsOf: bytes(xref))
        tutto.append(contentsOf: bytes(trailer))
        return (tutto, nuove.count)
    }

    // MARK: Scrittura in coda, con ritorno allo stato di prima se qualcosa non va

    /// Aggiunge in fondo a `url` le annotazioni nuove delle `pagine`. `verifica` si chiama a scrittura fatta (rilegge il file):
    /// se ritorna false il file viene riportato com'era e si lancia un errore.
    /// `marcatore`: file che dice, finché la scrittura non è finita, a che lunghezza tornare se l'app si chiude nel mezzo.
    static func applica(url: URL, miniatura: URL, pagine: [Int], marcatore: URL?, verifica: () -> Bool) throws -> Esito {
        let lettore = try LettorePDF(url: url)
        if lettore.sezioni >= massimoSezioni {
            throw ErrorePDF.nonSupportato("Troppi aggiornamenti in coda: conviene riscrivere il file.")
        }
        let mini = try LettorePDF(url: miniatura)
        let (byte, oggetti) = try prepara(lettore: lettore, miniatura: mini, pagine: pagine)
        let prima = lettore.f.dimensione
        let sezioniPrima = lettore.sezioni
        let fm = FileManager.default
        let attributi = try fm.attributesOfItem(atPath: url.path)
        guard let dataPrima = attributi[.modificationDate] as? Date, (attributi[.size] as? NSNumber)?.intValue == prima else {
            throw ErrorePDF.nonSupportato("Il file è cambiato mentre lo si leggeva.")
        }
        if let m = marcatore {
            try? fm.createDirectory(at: m.deletingLastPathComponent(), withIntermediateDirectories: true)
            let riga = "\(prima) \(prima + byte.count) \(dataPrima.timeIntervalSince1970)"
            try riga.write(to: m, atomically: true, encoding: .utf8)
        }
        do {
            let h = try FileHandle(forUpdating: url)
            defer { try? h.close() }
            let fine = try h.seekToEnd()
            guard fine == UInt64(prima) else { throw ErrorePDF.nonSupportato("Il file è cambiato prima della scrittura.") }
            try h.write(contentsOf: Data(byte))
            try h.synchronize()
        } catch {
            tronca(url: url, a: prima, data: dataPrima)
            if let m = marcatore { try? fm.removeItem(at: m) }
            throw error
        }
        if !verifica() {
            tronca(url: url, a: prima, data: dataPrima)
            if let m = marcatore { try? fm.removeItem(at: m) }
            throw ErrorePDF.nonSupportato("La verifica dopo la scrittura non è riuscita: file riportato com'era.")
        }
        if let m = marcatore { try? fm.removeItem(at: m) }
        return Esito(byteAggiunti: byte.count, oggetti: oggetti, sezioni: sezioniPrima + 1)
    }

    /// Riporta il file alla lunghezza di prima (e alla data di modifica di prima: serve al diario di recupero)
    static func tronca(url: URL, a lunghezza: Int, data: Date) {
        if let h = try? FileHandle(forUpdating: url) {
            try? h.truncate(atOffset: UInt64(lunghezza))
            try? h.synchronize()
            try? h.close()
        }
        try? FileManager.default.setAttributes([.modificationDate: data], ofItemAtPath: url.path)
    }

    /// All'apertura di un file: se la scrittura per aggiunta fu interrotta a metà (app chiusa di colpo), si taglia la coda incompleta.
    static func ripristina(url: URL, marcatore: URL) {
        let fm = FileManager.default
        guard let testo = try? String(contentsOf: marcatore, encoding: .utf8) else { return }
        let v = testo.split(separator: " ")
        defer { try? fm.removeItem(at: marcatore) }
        guard v.count == 3, let prima = Int(v[0]), let dopo = Int(v[1]), let t = Double(v[2]),
              let a = try? fm.attributesOfItem(atPath: url.path), let dim = (a[.size] as? NSNumber)?.intValue else { return }
        if dim == dopo || dim <= prima { return }          // finita, o il file è già altro
        tronca(url: url, a: prima, data: Date(timeIntervalSince1970: t))
    }
}
