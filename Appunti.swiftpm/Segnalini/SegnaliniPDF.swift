// Formato «a segnalini» (progetto: docs/formato-segnalini.md) — parte PDF, solo Foundation/CoreGraphics.
//
// Nel contenuto della pagina c'è un blocco disegnato (tratti, foto, testi) racchiuso fra due testi invisibili:
//   «APT-INIZIO v2 p<pagina> e<elementi> n<operazioni grafiche> h<impronta> k<pezzi>», «APT-D i/k <base64>» …, «APT-FINE h<impronta>».
// Qui si fa: lettura dei flussi di contenuto (operatori, mai confronto di byte), ricerca dei blocchi, controlli,
// «neutralizzazione» (si tolgono SOLO le operazioni che disegnano: lo stato grafico resta identico, perché Anteprima
// sposta le parentesi q/Q attorno al blocco — Prova 4 del 27/11) e scrittura per aggiunta (aggiornamento incrementale).
import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Compressione Flate (zlib con intestazione, come nei PDF)

enum Flate {
    static func adler32(_ d: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            var i = 0
            let n = p.count
            while i < n {
                let fine = min(i + 5552, n)
                while i < fine {
                    a &+= UInt32(p[i])
                    b &+= a
                    i += 1
                }
                a %= 65521
                b %= 65521
            }
        }
        return (b << 16) | a
    }

    static func comprimi(_ d: Data) -> Data? {
        let sorgente = d.isEmpty ? Data([32]) : d
        guard let raw = try? (sorgente as NSData).compressed(using: .zlib) as Data else { return nil }
        var out = Data([0x78, 0x9C])
        out.append(raw)
        let ad = adler32(sorgente)
        out.append(contentsOf: [UInt8(ad >> 24), UInt8((ad >> 16) & 0xFF), UInt8((ad >> 8) & 0xFF), UInt8(ad & 0xFF)])
        return out
    }

    static func decomprimi(_ d: Data) -> Data? {
        guard d.count > 2 else { return nil }
        let s = d.startIndex
        // intestazione zlib: CMF con metodo 8 e (CMF*256+FLG) multiplo di 31
        let haIntestazione = (d[s] & 0x0F) == 8 && ((Int(d[s]) << 8) | Int(d[s + 1])) % 31 == 0
        let corpo = haIntestazione ? d.subdata(in: (s + 2)..<d.endIndex) : d
        if corpo.count > 4, let x = try? (corpo.subdata(in: corpo.startIndex..<(corpo.endIndex - 4)) as NSData).decompressed(using: .zlib) as Data {
            return x
        }
        return try? (corpo as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - Operazioni di un flusso di contenuto

struct OpPDF {
    var nome: String
    var r: Range<Int>                         // dal primo operando alla fine dell'operatore
    var operandi: [LessicoPDF.Gettone]
}

enum ContenutoPDF {
    static let pittura: Set<String> = ["S", "s", "f", "F", "f*", "B", "B*", "b", "b*"]
    static let mostraTesto: Set<String> = ["Tj", "TJ", "'", "\""]
    /// Operazioni che lasciano un segno sulla pagina (le contiamo nel blocco: «n»). I testi visibili NON si contano:
    /// Anteprima spezza un testo in un BT…ET per riga.
    static func eGrafica(_ nome: String) -> Bool { pittura.contains(nome) || nome == "Do" || nome == "sh" || nome == "BI" }

    static func operazioni(_ b: UnsafeRawBufferPointer) -> [OpPDF] {
        var lex = LessicoPDF(b)
        var ops: [OpPDF] = []
        var operandi: [LessicoPDF.Gettone] = []
        var inizio: Int?
        while let g = lex.prossimo() {
            if inizio == nil { inizio = g.r.lowerBound }
            switch g.tipo {
            case .aprArr, .aprDiz:
                lex.p = g.r.lowerBound
                guard let r = lex.valore() else { return ops }
                operandi.append(LessicoPDF.Gettone(tipo: g.tipo, r: r))
            case .chiArr, .chiDiz:
                continue
            case .parola:
                let nome = lex.testo(g)
                if nome == "true" || nome == "false" || nome == "null" {
                    operandi.append(g)
                    continue
                }
                if nome == "BI" {
                    // immagine in linea: «BI <dizionario> ID <dati> EI»
                    var fine = b.count
                    var trovato = false
                    while let x = lex.prossimo() {
                        if x.tipo == .parola, lex.testo(x) == "ID" { trovato = true; break }
                        if x.tipo == .aprArr || x.tipo == .aprDiz { lex.p = x.r.lowerBound; _ = lex.valore() }
                    }
                    if trovato {
                        var q = lex.p + 1
                        while q + 1 < b.count {
                            if b[q] == 69, b[q + 1] == 73, LessicoPDF.spazio(b[q - 1]),
                               q + 2 >= b.count || LessicoPDF.spazio(b[q + 2]) || LessicoPDF.delimitatore(b[q + 2]) {
                                fine = q + 2
                                break
                            }
                            q += 1
                        }
                    }
                    lex.p = fine
                    ops.append(OpPDF(nome: "BI", r: (inizio ?? g.r.lowerBound)..<fine, operandi: []))
                } else {
                    ops.append(OpPDF(nome: nome, r: (inizio ?? g.r.lowerBound)..<g.r.upperBound, operandi: operandi))
                }
                operandi = []
                inizio = nil
            default:
                operandi.append(g)
            }
        }
        return ops
    }

    static func bytesStringa(_ b: UnsafeRawBufferPointer, _ r: Range<Int>) -> [UInt8] {
        guard r.count >= 2 else { return [] }
        if b[r.lowerBound] == 60 {          // <esadecimale>
            var out: [UInt8] = []
            var alto: Int?
            for i in (r.lowerBound + 1)..<r.upperBound {
                let c = b[i]
                let v: Int
                switch c {
                case 48...57: v = Int(c) - 48
                case 65...70: v = Int(c) - 55
                case 97...102: v = Int(c) - 87
                default: continue
                }
                if let a = alto { out.append(UInt8(a * 16 + v)); alto = nil } else { alto = v }
            }
            if let a = alto { out.append(UInt8(a * 16)) }
            return out
        }
        var out: [UInt8] = []
        var i = r.lowerBound + 1
        let fine = r.upperBound - 1
        while i < fine {
            let c = b[i]
            if c == 92, i + 1 < fine {
                let n = b[i + 1]
                switch n {
                case 110: out.append(10); i += 2
                case 114: out.append(13); i += 2
                case 116: out.append(9); i += 2
                case 98: out.append(8); i += 2
                case 102: out.append(12); i += 2
                case 13:
                    i += 2
                    if i < fine, b[i] == 10 { i += 1 }
                case 10: i += 2
                case 48...55:
                    var v = 0, k = 0, j = i + 1
                    while k < 3, j < fine, b[j] >= 48, b[j] <= 55 { v = v * 8 + Int(b[j] - 48); j += 1; k += 1 }
                    out.append(UInt8(v & 255))
                    i = j
                default:
                    out.append(n)
                    i += 2
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// Testo mostrato da Tj/TJ/'/" (byte come caratteri: i segnalini sono solo ASCII)
    static func testoMostrato(_ b: UnsafeRawBufferPointer, _ op: OpPDF) -> String? {
        guard mostraTesto.contains(op.nome), let ultimo = op.operandi.last else { return nil }
        var byte: [UInt8] = []
        if ultimo.tipo == .stringa {
            byte = bytesStringa(b, ultimo.r)
        } else if ultimo.tipo == .aprArr {
            var lex = LessicoPDF(b, da: ultimo.r.lowerBound, fino: ultimo.r.upperBound)
            while let g = lex.prossimo() {
                if g.tipo == .stringa { byte += bytesStringa(b, g.r) }
            }
        } else {
            return nil
        }
        return String(decoding: byte, as: UTF8.self)
    }

    static func nome(_ b: UnsafeRawBufferPointer, _ g: LessicoPDF.Gettone) -> String {
        String(decoding: UnsafeRawBufferPointer(rebasing: b[g.r]), as: UTF8.self)
    }
}

// MARK: - Blocchi trovati in una pagina

struct BloccoTrovato {
    var flusso: Int                 // indice del flusso nell'elenco /Contents
    var primo: Int                  // indice della prima operazione (BT del segnalino d'inizio)
    var ultimo: Int                 // indice dell'ultima (ET del segnalino di fine)
    var intestazione: [Character: String] = [:]
    var dati: Data?                 // contenuto di D: (decompresso) se i controlli tornano
    var errore: String?
    var grafiche = 0                // operazioni grafiche contate nel blocco
    var nomiDo: [String] = []       // immagini disegnate nel blocco, in ordine
    var impronta: String { intestazione["h"] ?? "" }
    var disegnoDiverso: Bool { Int(intestazione["n"] ?? "") != grafiche }
}

enum Segnalini {
    static let versione = "2"
    static let pezzo = 30_000

    static func impronta(_ d: Data) -> String {
        SHA256.hash(data: d).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Cerca i blocchi in un flusso già decompresso. Più blocchi per pagina sono ammessi (uno valido + vecchi «congelati»).
    static func trovaBlocchi(_ b: UnsafeRawBufferPointer, ops: [OpPDF], flusso: Int) -> [BloccoTrovato] {
        var out: [BloccoTrovato] = []
        var corrente: BloccoTrovato?
        var pezzi: [Int: String] = [:]
        var fineTesto = ""
        var ultimoBT: Int?
        for (i, op) in ops.enumerated() {
            if op.nome == "BT" { ultimoBT = i }
            guard let t = ContenutoPDF.testoMostrato(b, op), t.hasPrefix("APT-") else { continue }
            if t.hasPrefix("APT-INIZIO") {
                if var c = corrente {          // inizio senza fine: il vecchio si chiude qui come illeggibile
                    c.ultimo = max(c.primo, (ultimoBT ?? i) - 1)
                    c.errore = "segnalino di fine mancante"
                    out.append(c)
                }
                var c = BloccoTrovato(flusso: flusso, primo: ultimoBT ?? i, ultimo: i)
                for parte in t.split(separator: " ").dropFirst() {
                    guard let k = parte.first else { continue }
                    c.intestazione[k] = String(parte.dropFirst())
                }
                corrente = c
                pezzi = [:]
            } else if t.hasPrefix("APT-D "), corrente != nil {
                let parti = t.split(separator: " ", maxSplits: 2)
                if parti.count == 3 {
                    let ik = parti[1].split(separator: "/")
                    if ik.count == 2, let i1 = Int(ik[0]) { pezzi[i1] = String(parti[2]) }
                }
            } else if t.hasPrefix("APT-FINE"), var c = corrente {
                var j = i
                while j < ops.count, ops[j].nome != "ET" { j += 1 }
                c.ultimo = j < ops.count ? j : i
                fineTesto = t
                for k in c.primo...c.ultimo where ContenutoPDF.eGrafica(ops[k].nome) {
                    c.grafiche += 1
                    if ops[k].nome == "Do", let n = ops[k].operandi.last, n.tipo == .nome { c.nomiDo.append(ContenutoPDF.nome(b, n)) }
                }
                controlla(&c, pezzi: pezzi, fine: fineTesto)
                out.append(c)
                corrente = nil
            }
        }
        if var c = corrente {
            c.ultimo = ops.count - 1
            c.errore = "segnalino di fine mancante"
            out.append(c)
        }
        return out
    }

    private static func controlla(_ c: inout BloccoTrovato, pezzi: [Int: String], fine: String) {
        guard c.intestazione["v"] == versione else { c.errore = "versione del formato sconosciuta"; return }
        guard let k = Int(c.intestazione["k"] ?? ""), k >= 1, k < 10_000 else { c.errore = "numero di pezzi illeggibile"; return }
        var testo = ""
        for i in 1...k {
            guard let p = pezzi[i] else { c.errore = "manca il pezzo \(i) di \(k)"; return }
            testo += p
        }
        guard let z = Data(base64Encoded: testo), let dati = Flate.decomprimi(z) else { c.errore = "dati illeggibili"; return }
        guard impronta(dati) == c.impronta, fine.hasSuffix("h" + c.impronta) else { c.errore = "impronta dei dati diversa"; return }
        c.dati = dati
    }

    /// Toglie dal flusso, nei blocchi indicati, ciò che disegna. `tutto` = blocco valido (si toglie il disegno: lo rifà l'app);
    /// altrimenti si tolgono solo i segnalini (il disegno resta, fisso: blocco «congelato»).
    static func neutralizza(_ b: UnsafeRawBufferPointer, ops: [OpPDF], blocchi: [(primo: Int, ultimo: Int, tutto: Bool)]) -> Data {
        var sostituzioni: [(r: Range<Int>, con: String)] = []
        for bl in blocchi {
            for k in bl.primo...bl.ultimo {
                let op = ops[k]
                var con: String?
                if bl.tutto {
                    if ContenutoPDF.pittura.contains(op.nome) { con = "n" }
                    else if op.nome == "Do" || op.nome == "sh" || op.nome == "BI" || op.nome == "Tj" || op.nome == "TJ"
                                || op.nome == "gs" || op.nome == "Tf" { con = "" }
                    else if op.nome == "'" { con = "T*" }
                    else if op.nome == "\"" { con = op.operandi.count >= 3
                        ? "\(ContenutoPDF.nome(b, op.operandi[0])) Tw \(ContenutoPDF.nome(b, op.operandi[1])) Tc T*" : "T*" }
                } else if let t = ContenutoPDF.testoMostrato(b, op), t.hasPrefix("APT-") {
                    con = op.nome == "'" || op.nome == "\"" ? "T*" : ""
                }
                if let con { sostituzioni.append((op.r, con)) }
            }
        }
        sostituzioni.sort { $0.r.lowerBound < $1.r.lowerBound }
        var out = Data()
        out.reserveCapacity(b.count)
        var da = 0
        for s in sostituzioni where s.r.lowerBound >= da {
            out.append(contentsOf: b[da..<s.r.lowerBound])
            out.append(contentsOf: Array((" " + s.con + " ").utf8))
            da = s.r.upperBound
        }
        out.append(contentsOf: b[da..<b.count])
        return out
    }
}

// MARK: - Lettura delle pagine con il lettore minimo (oggetti, flussi, risorse)

extension LettorePDF {
    /// Byte grezzi e dizionario di un oggetto flusso
    func flusso(_ n: Int) throws -> (dizionario: Range<Int>, byte: Range<Int>) {
        let e = try PDFAggiunta.estrai(self, n)
        guard let f = e.flusso else { throw ErrorePDF.nonSupportato("L'oggetto \(n) non è un flusso.") }
        return (e.valore, f)
    }

    func dati(_ r: Range<Int>) -> Data { Data(UnsafeRawBufferPointer(rebasing: buf[r])) }

    /// Contenuto decompresso di un flusso (nessun filtro o solo FlateDecode); nil se il filtro non è gestito
    func flussoDecompresso(_ n: Int) throws -> Data? {
        let (diz, byte) = try flusso(n)
        let v = voci(diz)
        if v.contains(where: { $0.chiave == "/DecodeParms" }) { return nil }
        guard let filtro = v.first(where: { $0.chiave == "/Filter" }) else { return dati(byte) }
        let t = testo(filtro.valore).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard t == "/FlateDecode" else { return nil }
        return Flate.decomprimi(dati(byte))
    }

    /// Il valore di un dizionario (diretto o tramite riferimento)
    func dizionario(_ r: Range<Int>) throws -> Range<Int> {
        if let n = riferimento(r) {
            let c = try corpo(n)
            guard !c.flusso else { throw ErrorePDF.nonSupportato("Atteso un dizionario, trovato un flusso.") }
            return c.valore
        }
        return r
    }

    /// Oggetti flusso del contenuto di una pagina, in ordine
    func flussiContenuto(pagina n: Int) throws -> [Int] {
        let c = try corpo(n)
        guard let cont = voci(c.valore).first(where: { $0.chiave == "/Contents" }) else { return [] }
        if let k = riferimento(cont.valore) {
            let ck = try corpo(k)
            if ck.flusso { return [k] }
            guard let rif = riferimenti(in: ck.valore) else { throw ErrorePDF.nonSupportato("Contenuto della pagina non semplice.") }
            return rif
        }
        guard let rif = riferimenti(in: cont.valore) else { throw ErrorePDF.nonSupportato("Contenuto della pagina non semplice.") }
        return rif
    }

    /// Le risorse della pagina (anche ereditate dai nodi superiori)
    func risorse(pagina n: Int) throws -> Range<Int>? {
        var corrente = n
        for _ in 0..<40 {
            let c = try corpo(corrente)
            let v = voci(c.valore)
            if let r = v.first(where: { $0.chiave == "/Resources" }) { return try dizionario(r.valore) }
            guard let p = v.first(where: { $0.chiave == "/Parent" }), let up = riferimento(p.valore) else { return nil }
            corrente = up
        }
        return nil
    }

    /// Voci di una sottosezione delle risorse (/XObject, /Font, /ExtGState)
    func vociRisorse(_ ris: Range<Int>?, _ chiave: String) throws -> [(chiave: String, valore: Range<Int>)] {
        guard let ris, let s = voci(ris).first(where: { $0.chiave == chiave }) else { return [] }
        return voci(try dizionario(s.valore))
    }
}

// MARK: - Analisi di una pagina

struct PaginaAnalizzata {
    var numero: Int                         // oggetto pagina
    var flussi: [Int]                       // oggetti dei flussi di contenuto
    var decompressi: [Data?]
    var operazioni: [[OpPDF]]
    var blocchi: [BloccoTrovato]

    static func analizza(_ m: LettorePDF, numero: Int) throws -> PaginaAnalizzata {
        let flussi = try m.flussiContenuto(pagina: numero)
        var dec: [Data?] = []
        var ops: [[OpPDF]] = []
        var blocchi: [BloccoTrovato] = []
        for (i, f) in flussi.enumerated() {
            let d = try m.flussoDecompresso(f)
            dec.append(d)
            guard let d else { ops.append([]); continue }
            let o = d.withUnsafeBytes { ContenutoPDF.operazioni($0) }
            ops.append(o)
            blocchi += d.withUnsafeBytes { Segnalini.trovaBlocchi($0, ops: o, flusso: i) }
        }
        return PaginaAnalizzata(numero: numero, flussi: flussi, decompressi: dec, operazioni: ops, blocchi: blocchi)
    }

    var validi: [BloccoTrovato] { blocchi.filter { $0.dati != nil } }
}

// MARK: - Lavoro di scrittura di una pagina (preparato dall'app sul thread principale)

struct ImmagineSegnalino {
    var nome: String                        // nome nelle risorse, es. «/AptI3fa21»
    var chiave: String                      // impronta dei dati dell'elemento: stessa foto = stesso oggetto
    var esistente: Int?                     // oggetto già nel file da riusare
    var jpeg: Data?                         // byte JPEG (DCTDecode, non ricompresso)
    var componenti = 3                      // 1 = grigi, 3 = RGB
    var pixel: Data?                        // pixel non compressi (immagini non JPEG)
    var alfa: Data?                         // trasparenza (SMask), nil se opaca
    var larghezza = 0
    var altezza = 0
}

struct LavoroPagina {
    var indice: Int
    var contenuto: Data?                    // blocco da aggiungere (non compresso); nil = solo togliere i vecchi
    var font: String?                       // nome del font Helvetica nelle risorse
    var trasparenze: [(nome: String, alfa: Double)] = []
    var immagini: [ImmagineSegnalino] = []
    var impronta = ""
    var grafiche = 0
    var elementi = 0
}

// MARK: - Scrittura per aggiunta

enum ScritturaSegnalini {
    struct Esito {
        var byte: [UInt8]
        var numeri: [String: Int]           // chiave immagine → oggetto nel file
        var pagine: Int
    }

    private static func zeri(_ n: Int, _ cifre: Int) -> String {
        let s = String(n)
        return s.count >= cifre ? s : String(repeating: "0", count: cifre - s.count) + s
    }

    /// Byte da aggiungere in fondo al file. `congela`: i blocchi non leggibili perdono i segnalini (il disegno resta fisso).
    static func prepara(_ m: LettorePDF, lavori: [LavoroPagina], congela: Bool) throws -> Esito {
        let pagine = try m.numeriPagine()
        let lunghezza = m.f.dimensione
        var prossimo = max(m.coda.size, (m.voci.keys.max() ?? 0) + 1)
        var blob: [UInt8] = []
        var nuove: [(numero: Int, offset: Int)] = []
        var prefisso: [UInt8] = []
        if m.buf[lunghezza - 1] != 10 && m.buf[lunghezza - 1] != 13 { prefisso = [10] }

        func nuovo() -> Int { prossimo += 1; return prossimo - 1 }
        func inizioOggetto(_ n: Int) {
            nuove.append((n, lunghezza + prefisso.count + blob.count))
            blob += Array("\(n) 0 obj\n".utf8)
        }
        func oggetto(_ n: Int, _ testo: String) {
            inizioOggetto(n)
            blob += Array(testo.utf8)
            blob += Array("\nendobj\n".utf8)
        }
        func flusso(_ n: Int, dizionario: String, _ dati: Data) {
            inizioOggetto(n)
            blob += Array("<< \(dizionario) /Length \(dati.count) >>\nstream\n".utf8)
            blob += [UInt8](dati)
            blob += Array("\nendstream\nendobj\n".utf8)
        }
        func flussoCompresso(_ n: Int, _ dati: Data, extra: String = "") throws {
            guard let z = Flate.comprimi(dati) else { throw ErrorePDF.nonSupportato("Compressione non riuscita.") }
            flusso(n, dizionario: "\(extra) /Filter /FlateDecode".trimmingCharacters(in: .whitespaces), z)
        }

        var font: Int?
        var trasparenze: [String: Int] = [:]
        var numeri: [String: Int] = [:]
        var scritte = 0

        for lavoro in lavori {
            guard lavoro.indice >= 0, lavoro.indice < pagine.count else { throw ErrorePDF.nonSupportato("Pagina \(lavoro.indice + 1) fuori dal documento.") }
            let np = pagine[lavoro.indice]
            let cp = try m.corpo(np)
            guard !cp.flusso, cp.gen == 0 else { throw ErrorePDF.nonSupportato("Pagina non modificabile per aggiunta.") }
            let vp = m.voci(cp.valore)
            if lavoro.contenuto != nil, let rot = vp.first(where: { $0.chiave == "/Rotate" }),
               let g = Int(m.testo(rot.valore)), g % 360 != 0 {
                throw ErrorePDF.nonSupportato("Pagina ruotata: il formato a segnalini non la gestisce ancora.")
            }
            let an = try PaginaAnalizzata.analizza(m, numero: np)

            // Blocchi da togliere per flusso
            var perFlusso: [Int: [(primo: Int, ultimo: Int, tutto: Bool)]] = [:]
            for b in an.blocchi {
                if b.dati != nil { perFlusso[b.flusso, default: []].append((b.primo, b.ultimo, true)) }
                else if congela { perFlusso[b.flusso, default: []].append((b.primo, b.ultimo, false)) }
            }
            if perFlusso.isEmpty && lavoro.contenuto == nil { continue }

            // Nomi usati dentro e fuori dai blocchi tolti (per togliere dalle risorse ciò che resta inutile)
            var dentro = Set<String>(), fuori = Set<String>()
            var serveCornice = false
            var profondita = 0
            var togliFlusso = Set<Int>()
            for (i, ops) in an.operazioni.enumerated() {
                guard let d = an.decompressi[i] else { serveCornice = true; continue }
                let tolti = (perFlusso[i] ?? []).filter { $0.tutto }
                d.withUnsafeBytes { b in
                    var soloParentesi = !tolti.isEmpty
                    var q = 0, Q = 0
                    for (k, op) in ops.enumerated() {
                        let nelBlocco = tolti.contains { k >= $0.primo && k <= $0.ultimo }
                        if op.nome == "q" { q += 1 } else if op.nome == "Q" { Q += 1 }
                        if !nelBlocco && op.nome != "q" && op.nome != "Q" { soloParentesi = false }
                        if ["Do", "gs", "Tf"].contains(op.nome) {
                            let nomeR = op.nome == "Tf" ? op.operandi.first : op.operandi.last
                            if let g = nomeR, g.tipo == .nome {
                                let s = ContenutoPDF.nome(b, g)
                                if nelBlocco { dentro.insert(s) } else { fuori.insert(s) }
                            }
                        }
                    }
                    if soloParentesi && q == Q { togliFlusso.insert(i) }
                }
                if togliFlusso.contains(i) { continue }
                for (k, op) in ops.enumerated() {
                    if op.nome == "q" { profondita += 1 }
                    else if op.nome == "Q" { profondita = max(0, profondita - 1) }
                    else if profondita == 0 && (op.nome == "cm" || op.nome == "W" || op.nome == "W*") {
                        let nelBlocco = (perFlusso[i] ?? []).contains { $0.tutto && k >= $0.primo && k <= $0.ultimo }
                        if !nelBlocco { serveCornice = true }
                    }
                }
            }
            if profondita > 0 { serveCornice = true }
            let daTogliere = dentro.subtracting(fuori)
            if lavoro.contenuto == nil { serveCornice = false }

            // Nuovo elenco dei flussi
            var elenco: [Int] = []
            if serveCornice {
                let n = nuovo()
                flusso(n, dizionario: "", Data("q\n".utf8))
                elenco.append(n)
            }
            for (i, f) in an.flussi.enumerated() {
                if togliFlusso.contains(i) { continue }
                if let bl = perFlusso[i], let d = an.decompressi[i] {
                    let ops = an.operazioni[i]
                    let nuovoDato = d.withUnsafeBytes { Segnalini.neutralizza($0, ops: ops, blocchi: bl) }
                    let n = nuovo()
                    try flussoCompresso(n, nuovoDato)
                    elenco.append(n)
                } else {
                    elenco.append(f)
                }
            }
            if serveCornice {
                let n = nuovo()
                flusso(n, dizionario: "", Data(String(repeating: "Q\n", count: profondita + 1).utf8))
                elenco.append(n)
            }

            // Risorse: originali meno quelle rimaste inutili, più le nostre
            let ris = try m.risorse(pagina: np)
            var xobj = try m.vociRisorse(ris, "/XObject").filter { !daTogliere.contains($0.chiave) }.map { ($0.chiave, m.testo($0.valore)) }
            var fonts = try m.vociRisorse(ris, "/Font").filter { !daTogliere.contains($0.chiave) }.map { ($0.chiave, m.testo($0.valore)) }
            var stati = try m.vociRisorse(ris, "/ExtGState").filter { !daTogliere.contains($0.chiave) }.map { ($0.chiave, m.testo($0.valore)) }
            func controllaNome(_ s: String, _ in_: [(String, String)]) throws {
                if in_.contains(where: { $0.0 == s }) { throw ErrorePDF.nonSupportato("Nome di risorsa già usato: \(s).") }
            }

            if let contenuto = lavoro.contenuto {
                if let nf = lavoro.font {
                    if font == nil {
                        let n = nuovo()
                        oggetto(n, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
                        font = n
                    }
                    try controllaNome(nf, fonts)
                    fonts.append((nf, "\(font!) 0 R"))
                }
                for t in lavoro.trasparenze {
                    let chiave = String(format: "%.3f", t.alfa)
                    if trasparenze[chiave] == nil {
                        let n = nuovo()
                        oggetto(n, "<< /Type /ExtGState /ca \(chiave) /CA \(chiave) >>")
                        trasparenze[chiave] = n
                    }
                    try controllaNome(t.nome, stati)
                    stati.append((t.nome, "\(trasparenze[chiave]!) 0 R"))
                }
                for im in lavoro.immagini {
                    try controllaNome(im.nome, xobj)
                    var num = numeri[im.chiave]
                    if num == nil, let e = im.esistente {
                        // riuso solo se l'oggetto c'è ancora ed è un'immagine
                        if let fl = try? m.flusso(e), m.voci(fl.dizionario).contains(where: { $0.chiave == "/Subtype" && m.testo($0.valore) == "/Image" }) {
                            num = e
                        }
                    }
                    if num == nil {
                        let n = nuovo()
                        if let j = im.jpeg {
                            let cs = im.componenti == 1 ? "/DeviceGray" : "/DeviceRGB"
                            flusso(n, dizionario: "/Type /XObject /Subtype /Image /Width \(im.larghezza) /Height \(im.altezza) /ColorSpace \(cs) /BitsPerComponent 8 /Filter /DCTDecode", j)
                        } else if let px = im.pixel {
                            var maschera = ""
                            if let a = im.alfa {
                                let ns = nuovo()
                                try flussoCompresso(ns, a, extra: "/Type /XObject /Subtype /Image /Width \(im.larghezza) /Height \(im.altezza) /ColorSpace /DeviceGray /BitsPerComponent 8")
                                maschera = " /SMask \(ns) 0 R"
                            }
                            let cs = im.componenti == 1 ? "/DeviceGray" : "/DeviceRGB"
                            try flussoCompresso(n, px, extra: "/Type /XObject /Subtype /Image /Width \(im.larghezza) /Height \(im.altezza) /ColorSpace \(cs) /BitsPerComponent 8\(maschera)")
                        } else {
                            throw ErrorePDF.nonSupportato("Immagine senza dati.")
                        }
                        num = n
                    }
                    numeri[im.chiave] = num
                    xobj.append((im.nome, "\(num!) 0 R"))
                }
                let n = nuovo()
                try flussoCompresso(n, contenuto)
                elenco.append(n)
            }

            // Pagina riscritta con lo stesso numero
            func sotto(_ voci: [(String, String)]) -> String {
                "<< " + voci.map { "\($0.0) \($0.1)" }.joined(separator: " ") + " >>"
            }
            var risorse = "<<"
            var visti = Set<String>()
            if let ris {
                for v in m.voci(ris) {
                    visti.insert(v.chiave)
                    switch v.chiave {
                    case "/XObject": risorse += " /XObject " + sotto(xobj)
                    case "/Font": risorse += " /Font " + sotto(fonts)
                    case "/ExtGState": risorse += " /ExtGState " + sotto(stati)
                    default: risorse += " \(v.chiave) \(m.testo(v.valore))"
                    }
                }
            }
            if !visti.contains("/XObject") && !xobj.isEmpty { risorse += " /XObject " + sotto(xobj) }
            if !visti.contains("/Font") && !fonts.isEmpty { risorse += " /Font " + sotto(fonts) }
            if !visti.contains("/ExtGState") && !stati.isEmpty { risorse += " /ExtGState " + sotto(stati) }
            risorse += " >>"

            var testoPagina = "<<"
            var conRisorse = false
            for v in vp {
                switch v.chiave {
                case "/Contents": testoPagina += " /Contents [" + elenco.map { " \($0) 0 R" }.joined() + " ]"
                case "/Resources": testoPagina += " /Resources " + risorse; conRisorse = true
                default: testoPagina += " \(v.chiave) \(m.testo(v.valore))"
                }
            }
            if !vp.contains(where: { $0.chiave == "/Contents" }) { testoPagina += " /Contents [" + elenco.map { " \($0) 0 R" }.joined() + " ]" }
            if !conRisorse { testoPagina += " /Resources " + risorse }
            testoPagina += " >>"
            oggetto(np, testoPagina)
            scritte += 1
        }

        if nuove.isEmpty { return Esito(byte: [], numeri: numeri, pagine: 0) }

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
            for k in a...b { xref += "\(zeri(ordinate[k].offset, 10)) 00000 n \n" }
            a = b + 1
        }
        var trailer = "trailer\n<< /Size \(max(prossimo, m.coda.size)) /Root \(m.coda.root)"
        if let info = m.coda.info { trailer += " /Info \(info)" }
        if let id = m.coda.id { trailer += " /ID \(id)" }
        trailer += " /Prev \(m.ultimoStartXref) >>\nstartxref\n\(offsetXref)\n%%EOF\n"
        var tutto = prefisso
        tutto += blob
        tutto += Array(xref.utf8)
        tutto += Array(trailer.utf8)
        return Esito(byte: tutto, numeri: numeri, pagine: scritte)
    }

    /// Controllo del file scritto: ogni pagina con un blocco nuovo ha UN blocco valido con l'impronta e i conti attesi;
    /// le altre non hanno più blocchi validi.
    static func verifica(_ url: URL, lavori: [LavoroPagina]) -> String? {
        do {
            let m = try LettorePDF(url: url)
            let pagine = try m.numeriPagine()
            for l in lavori {
                guard l.indice < pagine.count else { return "pagina \(l.indice + 1) mancante" }
                let an = try PaginaAnalizzata.analizza(m, numero: pagine[l.indice])
                let validi = an.validi
                if l.contenuto == nil {
                    if !validi.isEmpty { return "pagina \(l.indice + 1): blocco vecchio ancora presente" }
                } else {
                    guard validi.count == 1, let b = validi.first else { return "pagina \(l.indice + 1): \(validi.count) blocchi validi" }
                    guard b.impronta == l.impronta else { return "pagina \(l.indice + 1): impronta diversa" }
                    guard b.grafiche == l.grafiche, !b.disegnoDiverso else { return "pagina \(l.indice + 1): \(b.grafiche) operazioni invece di \(l.grafiche)" }
                    guard b.nomiDo.count == l.immagini.count else { return "pagina \(l.indice + 1): immagini diverse" }
                }
            }
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Scrive in fondo a `url`, verifica e, se qualcosa non torna, riporta il file com'era. Ritorna le immagini scritte.
    static func applica(url: URL, lavori: [LavoroPagina], congela: Bool, marcatore: URL?, controlloFinale: () -> Bool) throws -> Esito {
        let m = try LettorePDF(url: url)
        let e = try prepara(m, lavori: lavori, congela: congela)
        if e.byte.isEmpty { return e }
        let prima = m.f.dimensione
        let fm = FileManager.default
        let attributi = try fm.attributesOfItem(atPath: url.path)
        guard let dataPrima = attributi[.modificationDate] as? Date, (attributi[.size] as? NSNumber)?.intValue == prima else {
            throw ErrorePDF.nonSupportato("Il file è cambiato mentre lo si leggeva.")
        }
        if let marcatore {
            try? fm.createDirectory(at: marcatore.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "\(prima) \(prima + e.byte.count) \(dataPrima.timeIntervalSince1970)".write(to: marcatore, atomically: true, encoding: .utf8)
        }
        defer { if let marcatore { try? fm.removeItem(at: marcatore) } }
        do {
            let h = try FileHandle(forUpdating: url)
            defer { try? h.close() }
            let fine = try h.seekToEnd()
            guard fine == UInt64(prima) else { throw ErrorePDF.nonSupportato("Il file è cambiato prima della scrittura.") }
            try h.write(contentsOf: Data(e.byte))
            try h.synchronize()
        } catch {
            PDFAggiunta.tronca(url: url, a: prima, data: dataPrima)
            throw error
        }
        if let motivo = verifica(url, lavori: lavori) {
            PDFAggiunta.tronca(url: url, a: prima, data: dataPrima)
            throw ErrorePDF.nonSupportato("Verifica dei segnalini non riuscita (\(motivo)): file riportato com'era.")
        }
        if !controlloFinale() {
            PDFAggiunta.tronca(url: url, a: prima, data: dataPrima)
            throw ErrorePDF.nonSupportato("Il PDF scritto non si apre come atteso: file riportato com'era.")
        }
        return e
    }
}

// MARK: - Apertura: blocchi letti e copia di lavoro pulita

struct ImmagineLetta {
    var dati: Data
    var numero: Int?
}

struct PaginaLetta {
    var indice: Int
    var dati: Data
    var immagini: [Int: ImmagineLetta]      // indice della «Do» nel blocco → immagine
    var disegnoDiverso: Bool
}

struct AperturaSegnalini {
    var copia: URL?
    var pagine: [PaginaLetta] = []
    var avvisi: [String] = []
}

enum LetturaSegnalini {
    /// Legge i blocchi del file. Se ce ne sono di validi prepara una COPIA del file (cartella temporanea dell'app) con i blocchi
    /// tolti: l'app apre la copia, il file vero non si tocca. nil = file non gestito dal lettore (si apre come sempre).
    static func apri(url: URL, cartella: URL) -> AperturaSegnalini? {
        guard let m = try? LettorePDF(url: url), let pagine = try? m.numeriPagine() else { return nil }
        var esito = AperturaSegnalini()
        var lavori: [LavoroPagina] = []
        let cg = CGPDFDocument(url as CFURL)
        for (i, np) in pagine.enumerated() {
            guard let an = try? PaginaAnalizzata.analizza(m, numero: np), !an.blocchi.isEmpty else { continue }
            for b in an.blocchi where b.dati == nil {
                esito.avvisi.append("Pagina \(i + 1): i dati dell'app non si leggono (\(b.errore ?? "?")). La pagina resta com'è.")
            }
            let validi = an.validi
            guard let b = validi.last, let dati = b.dati else { continue }
            if validi.count > 1 { esito.avvisi.append("Pagina \(i + 1): più blocchi dell'app, uso l'ultimo.") }
            var immagini: [Int: ImmagineLetta] = [:]
            let xo = (try? m.vociRisorse(try m.risorse(pagina: np), "/XObject")) ?? []
            for (k, nome) in b.nomiDo.enumerated() {
                let numero = xo.first(where: { $0.chiave == nome }).flatMap { m.riferimento($0.valore) }
                if let d = immagine(m, numero: numero, cg: cg, pagina: i + 1, nome: nome) {
                    immagini[k] = ImmagineLetta(dati: d, numero: numero)
                }
            }
            esito.pagine.append(PaginaLetta(indice: i, dati: dati, immagini: immagini, disegnoDiverso: b.disegnoDiverso))
            lavori.append(LavoroPagina(indice: i, contenuto: nil))
        }
        guard !lavori.isEmpty else { return esito }
        do {
            let e = try ScritturaSegnalini.prepara(m, lavori: lavori, congela: false)
            let fm = FileManager.default
            try fm.createDirectory(at: cartella, withIntermediateDirectories: true)
            let copia = cartella.appendingPathComponent("lavoro.pdf")
            try? fm.removeItem(at: copia)
            try fm.copyItem(at: url, to: copia)          // copia istantanea (APFS): non occupa spazio finché non cambia
            let h = try FileHandle(forUpdating: copia)
            defer { try? h.close() }
            _ = try h.seekToEnd()
            try h.write(contentsOf: Data(e.byte))
            esito.copia = copia
        } catch {
            esito.avvisi.append("Non riesco a preparare la copia di lavoro: \(error). Le scritte si vedono ma non si modificano.")
            esito.pagine = []
        }
        return esito
    }

    /// Byte dell'immagine: JPEG così com'è nel file; le altre ricostruite in PNG (stessi pixel)
    static func immagine(_ m: LettorePDF, numero: Int?, cg: CGPDFDocument?, pagina: Int, nome: String) -> Data? {
        if let numero, let fl = try? m.flusso(numero) {
            let f = m.voci(fl.dizionario).first(where: { $0.chiave == "/Filter" }).map { m.testo($0.valore) } ?? ""
            if f.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces) == "/DCTDecode" {
                return m.dati(fl.byte)
            }
        }
        guard let cg, let pg = cg.page(at: pagina), let pd = pg.dictionary else { return nil }
        var ris: CGPDFDictionaryRef?
        var corrente: CGPDFDictionaryRef? = pd
        for _ in 0..<40 {
            guard let c = corrente else { break }
            if CGPDFDictionaryGetDictionary(c, "Resources", &ris) { break }
            var su: CGPDFDictionaryRef?
            corrente = CGPDFDictionaryGetDictionary(c, "Parent", &su) ? su : nil
        }
        var xo: CGPDFDictionaryRef?
        guard let ris, CGPDFDictionaryGetDictionary(ris, "XObject", &xo), let xo else { return nil }
        var s: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(xo, String(nome.dropFirst()), &s), let s else { return nil }
        var formato = CGPDFDataFormat.raw
        guard let d = CGPDFStreamCopyData(s, &formato) as Data? else { return nil }
        if formato == .jpegEncoded { return d }
        guard formato == .raw, let sd = CGPDFStreamGetDictionary(s) else { return nil }
        var w = 0, h = 0, bpc = 0
        guard CGPDFDictionaryGetInteger(sd, "Width", &w), CGPDFDictionaryGetInteger(sd, "Height", &h),
              CGPDFDictionaryGetInteger(sd, "BitsPerComponent", &bpc), bpc == 8, w > 0, h > 0 else { return nil }
        let comp = componenti(sd)
        guard comp == 1 || comp == 3, d.count >= w * h * comp else { return nil }
        var alfa: Data?
        var sm: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(sd, "SMask", &sm), let sm, let smd = CGPDFStreamGetDictionary(sm) {
            var f2 = CGPDFDataFormat.raw
            var w2 = 0, h2 = 0
            if CGPDFDictionaryGetInteger(smd, "Width", &w2), CGPDFDictionaryGetInteger(smd, "Height", &h2), w2 == w, h2 == h,
               let a = CGPDFStreamCopyData(sm, &f2) as Data?, f2 == .raw, a.count >= w * h {
                alfa = a
            }
        }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            for i in 0..<(w * h) {
                if comp == 3 {
                    rgba[i * 4] = p[i * 3]; rgba[i * 4 + 1] = p[i * 3 + 1]; rgba[i * 4 + 2] = p[i * 3 + 2]
                } else {
                    rgba[i * 4] = p[i]; rgba[i * 4 + 1] = p[i]; rgba[i * 4 + 2] = p[i]
                }
            }
        }
        if let alfa { alfa.withUnsafeBytes { p in for i in 0..<(w * h) { rgba[i * 4 + 3] = p[i] } } }
        let info = CGBitmapInfo(rawValue: (alfa == nil ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.last).rawValue)
        guard let prov = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                                provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private static func componenti(_ sd: CGPDFDictionaryRef) -> Int {
        var nome: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(sd, "ColorSpace", &nome), let nome {
            switch String(cString: nome) {
            case "DeviceRGB", "CalRGB": return 3
            case "DeviceGray", "CalGray": return 1
            default: return 0
            }
        }
        var arr: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(sd, "ColorSpace", &arr), let arr {
            var tipo: UnsafePointer<CChar>?
            if CGPDFArrayGetName(arr, 0, &tipo), let tipo, String(cString: tipo) == "ICCBased" {
                var s: CGPDFStreamRef?
                if CGPDFArrayGetStream(arr, 1, &s), let s, let d = CGPDFStreamGetDictionary(s) {
                    var n = 0
                    if CGPDFDictionaryGetInteger(d, "N", &n) { return n }
                }
            }
            if CGPDFArrayGetName(arr, 0, &tipo), let tipo, ["CalRGB"].contains(String(cString: tipo)) { return 3 }
            if CGPDFArrayGetName(arr, 0, &tipo), let tipo, ["CalGray"].contains(String(cString: tipo)) { return 1 }
        }
        return 0
    }
}
