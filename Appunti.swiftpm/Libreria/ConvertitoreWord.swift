// Importazione di file Word (.docx e .doc): il file diventa un PDF normale (testo, immagini e tabelle come li vede Apple),
// che poi si annota come ogni altro PDF. Il testo del Word non resta modificabile: è questa la scelta.
//
// Come funziona (solo strumenti Apple gratuiti, offline):
// 1. iPadOS sa mostrare i file Word dentro una vista web (WKWebView): è lo stesso motore dell'anteprima di File.
// 2. Il contenuto mostrato viene impaginato in PDF con il sistema di stampa di iPadOS (UIPrintPageRenderer),
//    sulla carta e con i margini scritti nel file Word (formato pagina e margini si leggono da `word/document.xml`).
// Non esiste un modo gratuito di avere il motore di Word sull'iPad: l'impaginazione dipende da come Apple mostra il file.
import UIKit
import WebKit
import Compression
import UniformTypeIdentifiers

enum TipoWord {
    static func eWord(_ url: URL) -> Bool { ["docx", "doc"].contains(url.pathExtension.lowercased()) }

    /// Tipi da ammettere nel selettore file di sistema (oltre al PDF)
    static var tipi: [UTType] {
        var l: [UTType] = []
        for e in ["docx", "doc"] { if let t = UTType(filenameExtension: e) { l.append(t) } }
        for id in ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc"] {
            if let t = UTType(id) { l.append(t) }
        }
        return l
    }
}

/// Formato carta e margini, in punti (1 pt = 1/72 di pollice)
struct GeometriaPagina {
    var carta: CGSize
    var margini: UIEdgeInsets

    static let a4 = GeometriaPagina(carta: CGSize(width: 595.28, height: 841.89),
                                    margini: UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72))
}

/// Legge dal file .docx (che è un archivio ZIP) solo ciò che serve: il formato della pagina e i margini.
enum LettoreDocx {
    static func geometria(_ dati: Data) -> GeometriaPagina? {
        guard let xml = voce("word/document.xml", in: dati), let testo = String(data: xml, encoding: .utf8) else { return nil }
        // Vale l'ultima sezione del documento (quella in fondo)
        guard let sz = etichetta("pgSz", in: testo),
              let w = numero("w", in: sz), let h = numero("h", in: sz), w > 100, h > 100, w < 3000, h < 3000 else { return nil }
        var g = GeometriaPagina(carta: CGSize(width: w, height: h), margini: GeometriaPagina.a4.margini)
        if let mar = etichetta("pgMar", in: testo) {
            let t = numero("top", in: mar), d = numero("right", in: mar), b = numero("bottom", in: mar), s = numero("left", in: mar)
            if let t, let d, let b, let s,
               t >= 0, d >= 0, b >= 0, s >= 0, s + d < w - 100, t + b < h - 100 {
                g.margini = UIEdgeInsets(top: t, left: s, bottom: b, right: d)
            }
        }
        return g
    }

    /// L'ultima etichetta XML con quel nome (per esempio `<w:pgSz .../>`)
    private static func etichetta(_ nome: String, in testo: String) -> String? {
        guard let r = testo.range(of: "<w:\(nome)", options: .backwards),
              let fine = testo[r.lowerBound...].firstIndex(of: ">") else { return nil }
        return String(testo[r.lowerBound...fine])
    }

    /// Valore numerico di un attributo `w:nome="…"`, da ventesimi di punto a punti
    private static func numero(_ nome: String, in etichetta: String) -> CGFloat? {
        guard let r = etichetta.range(of: " w:\(nome)=\"") else { return nil }
        let dopo = etichetta[r.upperBound...]
        guard let q = dopo.firstIndex(of: "\""), let v = Double(dopo[..<q]) else { return nil }
        return CGFloat(v) / 20
    }

    // MARK: Archivio ZIP minimo (solo lettura di una voce, non compressa o deflate)

    static func voce(_ nome: String, in originale: Data) -> Data? {
        let d = Data(originale)         // indici da 0
        func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard d.count > 22 else { return nil }
        var i = d.count - 22
        var fineElenco = -1
        while i >= max(0, d.count - 65_557) {
            if u32(i) == 0x0605_4b50 { fineElenco = i; break }
            i -= 1
        }
        guard fineElenco >= 0 else { return nil }
        let quante = u16(fineElenco + 10)
        var p = u32(fineElenco + 16)
        for _ in 0..<quante {
            guard p >= 0, p + 46 <= d.count, u32(p) == 0x0201_4b50 else { return nil }
            let metodo = u16(p + 10), compresso = u32(p + 20), reale = u32(p + 24)
            let n = u16(p + 28), e = u16(p + 30), c = u16(p + 32), locale = u32(p + 42)
            guard p + 46 + n <= d.count else { return nil }
            let nomeVoce = String(data: d.subdata(in: (p + 46)..<(p + 46 + n)), encoding: .utf8)
            if nomeVoce == nome {
                guard locale + 30 <= d.count, u32(locale) == 0x0403_4b50 else { return nil }
                let inizio = locale + 30 + u16(locale + 26) + u16(locale + 28)
                guard inizio + compresso <= d.count else { return nil }
                let grezzo = d.subdata(in: inizio..<(inizio + compresso))
                if metodo == 0 { return grezzo }
                guard metodo == 8 else { return nil }
                return espandi(grezzo, dimensione: reale)
            }
            p += 46 + n + e + c
        }
        return nil
    }

    private static func espandi(_ d: Data, dimensione: Int) -> Data? {
        guard dimensione > 0, dimensione < 200_000_000, !d.isEmpty else { return nil }
        var fuori = Data(count: dimensione)
        let scritti: Int = fuori.withUnsafeMutableBytes { o in
            d.withUnsafeBytes { i in
                guard let dst = o.bindMemory(to: UInt8.self).baseAddress,
                      let src = i.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, dimensione, src, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard scritti > 0 else { return nil }
        return scritti == dimensione ? fuori : fuori.prefix(scritti)
    }
}

/// Impaginazione su carta di formato e margini voluti
private final class RendererCarta: UIPrintPageRenderer {
    let carta: CGRect
    let area: CGRect

    init(carta: CGRect, area: CGRect) {
        self.carta = carta
        self.area = area
        super.init()
    }

    override var paperRect: CGRect { carta }
    override var printableRect: CGRect { area }
}

@MainActor
final class ConvertitoreWord: NSObject, WKNavigationDelegate {
    private static var attivi: [ConvertitoreWord] = []

    private var vista: WKWebView?
    private var fine: ((Data?) -> Void)?
    private var cartella: URL?
    private var geometria = GeometriaPagina.a4
    private var scadenza: Timer?
    private var avviata = false
    private var concluso = false

    /// Copia il file in una cartella temporanea (il file originale può stare in iCloud o in una cartella protetta).
    nonisolated static func copiaTemporanea(_ url: URL) -> URL? {
        let acc = url.startAccessingSecurityScopedResource()
        defer { if acc { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Word-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("documento." + url.pathExtension.lowercased())
            try AptFS.copy(url, to: dest)
            return dest
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }

    /// Converte la copia temporanea in PDF. `fine` riceve i dati del PDF o nil se la conversione non è riuscita.
    /// La copia temporanea viene tolta alla fine.
    nonisolated static func converti(_ copia: URL, fine: @escaping (Data?) -> Void) {
        Task { @MainActor in
            let c = ConvertitoreWord()
            attivi.append(c)
            c.avvia(copia) { dati in
                attivi.removeAll { $0 === c }
                fine(dati)
            }
        }
    }

    private func finestra() -> UIWindow? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    }

    private func avvia(_ copia: URL, fine: @escaping (Data?) -> Void) {
        self.fine = fine
        cartella = copia.deletingLastPathComponent()
        if let d = try? Data(contentsOf: copia, options: .mappedIfSafe), let g = LettoreDocx.geometria(d) { geometria = g }
        guard let finestra = finestra() else { concludi(nil); return }
        // La vista web deve stare in una finestra per disegnare; è dietro a tutto e invisibile
        let v = WKWebView(frame: CGRect(origin: .zero, size: geometria.carta), configuration: WKWebViewConfiguration())
        v.navigationDelegate = self
        v.isUserInteractionEnabled = false
        v.alpha = 0.01
        finestra.insertSubview(v, at: 0)
        vista = v
        scadenza = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.concludi(nil) }
        }
        v.loadFileURL(copia, allowingReadAccessTo: copia.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !avviata else { return }
        avviata = true
        // Un momento perché immagini e caratteri siano pronti, poi si impagina
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.genera() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { concludi(nil) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { concludi(nil) }

    private func genera() {
        guard !concluso, let v = vista else { return }
        let carta = CGRect(origin: .zero, size: geometria.carta)
        let m = geometria.margini
        let area = CGRect(x: m.left, y: m.top, width: carta.width - m.left - m.right, height: carta.height - m.top - m.bottom)
        let r = RendererCarta(carta: carta, area: area)
        r.addPrintFormatter(v.viewPrintFormatter(), startingAtPageAt: 0)
        let pagine = r.numberOfPages
        if pagine > 0 {
            let dati = NSMutableData()
            UIGraphicsBeginPDFContextToData(dati, carta, nil)
            r.prepare(forDrawingPages: NSRange(location: 0, length: pagine))
            let bordo = UIGraphicsGetPDFContextBounds()
            for i in 0..<pagine {
                UIGraphicsBeginPDFPage()
                r.drawPage(at: i, in: bordo)
            }
            UIGraphicsEndPDFContext()
            concludi(dati as Data)
            return
        }
        // Ripiego: tutto il contenuto in una sola pagina lunga
        v.createPDF(configuration: WKPDFConfiguration()) { [weak self] esito in
            MainActor.assumeIsolated {
                if case .success(let d) = esito { self?.concludi(d) } else { self?.concludi(nil) }
            }
        }
    }

    private func concludi(_ dati: Data?) {
        guard !concluso else { return }
        concluso = true
        scadenza?.invalidate()
        scadenza = nil
        vista?.navigationDelegate = nil
        vista?.removeFromSuperview()
        vista = nil
        if let cartella { try? FileManager.default.removeItem(at: cartella) }
        let f = fine
        fine = nil
        f?(dati)
    }
}
