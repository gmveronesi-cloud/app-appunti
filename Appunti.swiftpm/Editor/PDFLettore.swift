// Lettore minimo di PDF (solo Foundation): serve al salvataggio «per aggiunta» (vedi PDFAggiunta.swift).
//
// Capisce solo i PDF scritti da PDFKit/Quartz: tabella xref classica (anche con aggiornamenti in coda), oggetti normali,
// lunghezza dei flussi scritta in chiaro. Per qualsiasi altra struttura lancia un errore e chi lo usa ripiega
// sulla scrittura completa del PDF.
import Foundation

enum ErrorePDF: Error, CustomStringConvertible {
    case nonSupportato(String)
    var description: String {
        switch self { case .nonSupportato(let m): return m }
    }
}

/// File letto in memoria virtuale (mmap): non occupa RAM vera, nemmeno per centinaia di MB.
final class FileMappato {
    let buf: UnsafeRawBufferPointer
    let dimensione: Int
    private let base: UnsafeMutableRawPointer

    init(url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ErrorePDF.nonSupportato("Non riesco ad aprire il file.") }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 0 else { throw ErrorePDF.nonSupportato("File vuoto o illeggibile.") }
        let n = Int(st.st_size)
        guard let p = mmap(nil, n, PROT_READ, MAP_PRIVATE, fd, 0), p != UnsafeMutableRawPointer(bitPattern: -1) else {
            throw ErrorePDF.nonSupportato("Non riesco a mappare il file.")
        }
        base = p
        dimensione = n
        buf = UnsafeRawBufferPointer(start: p, count: n)
    }

    deinit { munmap(base, dimensione) }
}

/// Scorre i byte di un PDF e restituisce i «gettoni» (numeri, nomi, stringhe, parentesi) senza copiarli
struct LessicoPDF {
    enum Tipo { case aprDiz, chiDiz, aprArr, chiArr, stringa, nome, numero, parola }
    struct Gettone {
        var tipo: Tipo
        var r: Range<Int>
    }

    let b: UnsafeRawBufferPointer
    var p: Int
    let fine: Int

    init(_ b: UnsafeRawBufferPointer, da: Int = 0, fino: Int? = nil) {
        self.b = b
        self.p = max(0, da)
        self.fine = min(fino ?? b.count, b.count)
    }

    static func spazio(_ c: UInt8) -> Bool { c == 32 || c == 10 || c == 13 || c == 9 || c == 12 || c == 0 }

    static func delimitatore(_ c: UInt8) -> Bool {
        switch c {
        case 40, 41, 60, 62, 91, 93, 123, 125, 47, 37: return true
        default: return false
        }
    }

    mutating func saltaSpazi() {
        while p < fine {
            let c = b[p]
            if Self.spazio(c) {
                p += 1
            } else if c == 37 {
                while p < fine, b[p] != 10, b[p] != 13 { p += 1 }
            } else {
                break
            }
        }
    }

    mutating func prossimo() -> Gettone? {
        while true {
            saltaSpazi()
            guard p < fine else { return nil }
            let c = b[p]
            let inizio = p
            switch c {
            case 60:        // <
                if p + 1 < fine, b[p + 1] == 60 {
                    p += 2
                    return Gettone(tipo: .aprDiz, r: inizio..<p)
                }
                p += 1
                while p < fine, b[p] != 62 { p += 1 }
                if p < fine { p += 1 }
                return Gettone(tipo: .stringa, r: inizio..<p)
            case 62:        // >
                if p + 1 < fine, b[p + 1] == 62 {
                    p += 2
                    return Gettone(tipo: .chiDiz, r: inizio..<p)
                }
                p += 1      // «>» isolato: si ignora
                continue
            case 91:
                p += 1
                return Gettone(tipo: .aprArr, r: inizio..<p)
            case 93:
                p += 1
                return Gettone(tipo: .chiArr, r: inizio..<p)
            case 40:        // stringa tra parentesi, con parentesi annidate e barre rovesciate
                var prof = 0
                while p < fine {
                    let x = b[p]
                    if x == 92 {
                        p += 2
                        continue
                    }
                    if x == 40 {
                        prof += 1
                    } else if x == 41 {
                        prof -= 1
                        if prof == 0 {
                            p += 1
                            break
                        }
                    }
                    p += 1
                }
                if p > fine { p = fine }
                return Gettone(tipo: .stringa, r: inizio..<p)
            case 47:        // nome
                p += 1
                while p < fine, !Self.spazio(b[p]), !Self.delimitatore(b[p]) { p += 1 }
                return Gettone(tipo: .nome, r: inizio..<p)
            case 41, 123, 125:
                p += 1
                return Gettone(tipo: .parola, r: inizio..<p)
            default:
                while p < fine, !Self.spazio(b[p]), !Self.delimitatore(b[p]) { p += 1 }
                var cifre = 0
                var puntini = 0
                var valido = true
                var i = inizio
                while i < p {
                    let x = b[i]
                    if x >= 48 && x <= 57 {
                        cifre += 1
                    } else if x == 46 {
                        puntini += 1
                    } else if (x == 43 || x == 45) && i == inizio {
                        // segno iniziale
                    } else {
                        valido = false
                        break
                    }
                    i += 1
                }
                let numero = valido && cifre > 0 && puntini <= 1
                return Gettone(tipo: numero ? .numero : .parola, r: inizio..<p)
            }
        }
    }

    func testo(_ g: Gettone) -> String {
        String(decoding: UnsafeRawBufferPointer(rebasing: b[g.r]), as: UTF8.self)
    }

    func intero(_ g: Gettone) -> Int? {
        guard g.tipo == .numero else { return nil }
        var v = 0
        var negativo = false
        var i = g.r.lowerBound
        if b[i] == 45 { negativo = true; i += 1 } else if b[i] == 43 { i += 1 }
        while i < g.r.upperBound {
            let x = b[i]
            if x < 48 || x > 57 { return nil }       // numero con la virgola: non è un intero
            v = v &* 10 &+ Int(x - 48)
            i += 1
        }
        return negativo ? -v : v
    }

    func eParola(_ g: Gettone, _ s: String) -> Bool {
        g.tipo == .parola && testo(g) == s
    }

    /// Legge un valore intero (dizionario, array, stringa, riferimento «n g R», numero, nome…): ne ritorna i byte.
    mutating func valore() -> Range<Int>? {
        guard let g = prossimo() else { return nil }
        let inizio = g.r.lowerBound
        switch g.tipo {
        case .aprDiz, .aprArr:
            var prof = 1
            var ultimo = g.r.upperBound
            while prof > 0, let x = prossimo() {
                switch x.tipo {
                case .aprDiz, .aprArr: prof += 1
                case .chiDiz, .chiArr: prof -= 1
                default: break
                }
                ultimo = x.r.upperBound
            }
            return inizio..<ultimo
        case .numero:
            var copia = self
            if let g2 = copia.prossimo(), g2.tipo == .numero, let g3 = copia.prossimo(), eParola(g3, "R") {
                self = copia
                return inizio..<g3.r.upperBound
            }
            return g.r
        default:
            return g.r
        }
    }

    /// Le coppie chiave/valore di un dizionario (il prossimo gettone deve essere «<<»)
    mutating func voci() -> [(chiave: String, valore: Range<Int>)] {
        guard let g = prossimo(), g.tipo == .aprDiz else { return [] }
        var out: [(chiave: String, valore: Range<Int>)] = []
        while let k = prossimo() {
            if k.tipo == .chiDiz { break }
            guard k.tipo == .nome else { continue }
            guard let v = valore() else { break }
            out.append((testo(k), v))
        }
        return out
    }
}

struct VoceXref {
    var offset: Int
    var gen: Int
}

struct CodaPDF {
    var size = 0
    var root = ""
    var info: String?
    var id: String?
    var prev: Int?
}

/// Un PDF (scritto da PDFKit) letto abbastanza da trovare le pagine e i loro oggetti
final class LettorePDF {
    let f: FileMappato
    var buf: UnsafeRawBufferPointer { f.buf }
    var voci: [Int: VoceXref] = [:]
    var liberi = Set<Int>()
    var sezioni = 0
    var ultimoStartXref = 0
    var coda = CodaPDF()

    init(url: URL) throws {
        f = try FileMappato(url: url)
        try leggiIndice()
    }

    // MARK: Tabella xref

    private func ultimaOccorrenza(_ s: String, da: Int, a: Int) -> Int? {
        let c = Array(s.utf8)
        guard a - da >= c.count else { return nil }
        var i = a - c.count
        while i >= da {
            var uguale = true
            var k = 0
            while k < c.count {
                if buf[i + k] != c[k] { uguale = false; break }
                k += 1
            }
            if uguale { return i }
            i -= 1
        }
        return nil
    }

    private func leggiIndice() throws {
        let n = buf.count
        guard n > 20, buf[0] == 37, buf[1] == 80, buf[2] == 68, buf[3] == 70 else {         // «%PDF»
            throw ErrorePDF.nonSupportato("Non è un PDF.")
        }
        guard let posSx = ultimaOccorrenza("startxref", da: max(0, n - 2048), a: n) else {
            throw ErrorePDF.nonSupportato("startxref non trovato.")
        }
        var lex = LessicoPDF(buf, da: posSx + 9)
        guard let g = lex.prossimo(), let off = lex.intero(g) else { throw ErrorePDF.nonSupportato("startxref illeggibile.") }
        ultimoStartXref = off
        var corrente: Int? = off
        var visitati = Set<Int>()
        var primo = true
        while let o = corrente {
            guard o >= 0, o < n, !visitati.contains(o) else { throw ErrorePDF.nonSupportato("Catena xref non valida.") }
            visitati.insert(o)
            sezioni += 1
            if sezioni > 1000 { throw ErrorePDF.nonSupportato("Troppe sezioni xref.") }
            let c = try leggiSezione(o)
            if primo {
                coda = c
                primo = false
            }
            corrente = c.prev
        }
        if coda.root.isEmpty || coda.size <= 0 { throw ErrorePDF.nonSupportato("Trailer incompleto.") }
    }

    private func leggiSezione(_ o: Int) throws -> CodaPDF {
        var lex = LessicoPDF(buf, da: o)
        guard let g = lex.prossimo(), lex.eParola(g, "xref") else {
            throw ErrorePDF.nonSupportato("La tabella xref non è classica (flusso xref o struttura diversa).")
        }
        while true {
            guard let a = lex.prossimo() else { throw ErrorePDF.nonSupportato("xref troncata.") }
            if lex.eParola(a, "trailer") { break }
            guard let inizio = lex.intero(a), let b = lex.prossimo(), let quanti = lex.intero(b), quanti >= 0 else {
                throw ErrorePDF.nonSupportato("Sezione xref illeggibile.")
            }
            var numero = inizio
            var k = 0
            while k < quanti {
                guard let x = lex.prossimo(), let y = lex.prossimo(), let z = lex.prossimo(),
                      let off = lex.intero(x), let gen = lex.intero(y), z.tipo == .parola else {
                    throw ErrorePDF.nonSupportato("Voce xref illeggibile.")
                }
                if voci[numero] == nil && !liberi.contains(numero) {
                    if lex.testo(z) == "n" {
                        voci[numero] = VoceXref(offset: off, gen: gen)
                    } else {
                        liberi.insert(numero)
                    }
                }
                numero += 1
                k += 1
            }
        }
        var c = CodaPDF()
        let dizionario = lex.voci()
        for (chiave, r) in dizionario {
            let testo = String(decoding: UnsafeRawBufferPointer(rebasing: buf[r]), as: UTF8.self)
            switch chiave {
            case "/Size":
                c.size = Int(testo) ?? 0
            case "/Root":
                c.root = testo
            case "/Info":
                c.info = testo
            case "/ID":
                c.id = testo
            case "/Prev":
                // alcuni scrittori usano un numero con la virgola per /Prev
                c.prev = Int(testo) ?? Int(Double(testo) ?? -1)
                if c.prev ?? -1 < 0 { c.prev = nil }
            case "/Encrypt":
                throw ErrorePDF.nonSupportato("PDF cifrato.")
            case "/XRefStm":
                throw ErrorePDF.nonSupportato("xref ibrida.")
            default:
                break
            }
        }
        return c
    }

    // MARK: Oggetti

    struct Corpo {
        var valore: Range<Int>      // byte del valore (dizionario, array…) dopo «n g obj»
        var inizio: Int             // dove comincia «n g obj»
        var gen: Int
        var flusso: Bool
        var fineValoreDopo: Int     // subito dopo il valore
    }

    func corpo(_ n: Int) throws -> Corpo {
        guard let v = voci[n] else { throw ErrorePDF.nonSupportato("Oggetto \(n) non presente.") }
        guard v.offset >= 0, v.offset < buf.count else { throw ErrorePDF.nonSupportato("Oggetto \(n) fuori dal file.") }
        var lex = LessicoPDF(buf, da: v.offset)
        guard let a = lex.prossimo(), lex.intero(a) == n, let b = lex.prossimo(), lex.intero(b) != nil,
              let c = lex.prossimo(), lex.eParola(c, "obj") else {
            throw ErrorePDF.nonSupportato("Oggetto \(n) non trovato dove dice la tabella.")
        }
        guard let r = lex.valore() else { throw ErrorePDF.nonSupportato("Oggetto \(n) illeggibile.") }
        var dopo = lex
        let t = dopo.prossimo()
        var flusso = false
        if let t = t, lex.eParola(t, "stream") { flusso = true }
        return Corpo(valore: r, inizio: v.offset, gen: v.gen, flusso: flusso, fineValoreDopo: r.upperBound)
    }

    func voci(_ r: Range<Int>) -> [(chiave: String, valore: Range<Int>)] {
        var lex = LessicoPDF(buf, da: r.lowerBound, fino: r.upperBound)
        return lex.voci()
    }

    func testo(_ r: Range<Int>) -> String {
        String(decoding: UnsafeRawBufferPointer(rebasing: buf[r]), as: UTF8.self)
    }

    /// «n g R» → n
    func riferimento(_ r: Range<Int>) -> Int? {
        var lex = LessicoPDF(buf, da: r.lowerBound, fino: r.upperBound)
        guard let a = lex.prossimo(), let n = lex.intero(a), let b = lex.prossimo(), lex.intero(b) != nil,
              let c = lex.prossimo(), lex.eParola(c, "R") else { return nil }
        return n
    }

    /// Elenco dei riferimenti di un array di soli «n g R»; nil se contiene altro
    func riferimenti(in r: Range<Int>) -> [Int]? {
        var lex = LessicoPDF(buf, da: r.lowerBound, fino: r.upperBound)
        guard let g = lex.prossimo(), g.tipo == .aprArr else { return nil }
        var out: [Int] = []
        while true {
            var copia = lex
            guard let x = copia.prossimo() else { return nil }
            if x.tipo == .chiArr { break }
            guard let v = lex.valore(), let n = riferimento(v) else { return nil }
            out.append(n)
        }
        return out
    }

    /// Numeri degli oggetti pagina, nell'ordine del documento
    func numeriPagine() throws -> [Int] {
        guard let rootNum = Int(coda.root.split(separator: " ").first ?? "") else {
            throw ErrorePDF.nonSupportato("Root illeggibile.")
        }
        let r = try corpo(rootNum)
        guard !r.flusso, let pagine = voci(r.valore).first(where: { $0.chiave == "/Pages" }),
              let radice = riferimento(pagine.valore) else {
            throw ErrorePDF.nonSupportato("Albero delle pagine non trovato.")
        }
        var out: [Int] = []
        var visitati = Set<Int>()
        try visita(radice, 0, &visitati, &out)
        return out
    }

    private func visita(_ n: Int, _ prof: Int, _ visitati: inout Set<Int>, _ out: inout [Int]) throws {
        guard prof < 40, !visitati.contains(n) else { throw ErrorePDF.nonSupportato("Albero delle pagine non valido.") }
        visitati.insert(n)
        let c = try corpo(n)
        guard !c.flusso else { throw ErrorePDF.nonSupportato("Nodo pagine con flusso.") }
        let v = voci(c.valore)
        if let kids = v.first(where: { $0.chiave == "/Kids" }) {
            guard let figli = riferimenti(in: kids.valore) else { throw ErrorePDF.nonSupportato("Kids non semplice.") }
            for figlio in figli { try visita(figlio, prof + 1, &visitati, &out) }
        } else {
            out.append(n)
        }
    }

    /// Le annotazioni dell'app hanno il nome (/T) che comincia per «Apt»
    func eAnnotazioneApp(_ n: Int) throws -> Bool {
        let c = try corpo(n)
        if c.flusso { return false }
        guard let t = voci(c.valore).first(where: { $0.chiave == "/T" }) else { return false }
        let r = t.valore
        guard r.count >= 5, buf[r.lowerBound] == 40 else { return false }
        return buf[r.lowerBound + 1] == 65 && buf[r.lowerBound + 2] == 112 && buf[r.lowerBound + 3] == 116     // «Apt»
    }
}
