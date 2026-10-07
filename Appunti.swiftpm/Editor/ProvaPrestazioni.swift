// Prova automatica di prestazioni, SOLO per il simulatore di GitHub (si attiva con la variabile d'ambiente APT_PROVA).
// Apre due PDF di prova in vista doppia e scrive in Documents/prova.txt quanto lavora il processore, quanti
// aggiornamenti di schermata ci sono e quanto resta bloccata l'app. Sull'iPad di Cristina non parte mai.
import SwiftUI
import PDFKit
import QuartzCore
import Darwin

/// Contatori di eventi (solo diagnostica): quante volte succede qualcosa mentre si misura
enum ProvaContatori {
    static var layout = 0        // layoutSubviews del PDF
    static var limiti = 0        // cambi di zoom minimo/massimo
    static var overlayCreati = 0 // tele create
    static var overlayMostrati = 0
    static var ripartisci = 0
    static var zoom = 0

    static var riga: String {
        "layout \(layout), limiti \(limiti), tele create \(overlayCreati), tele mostrate \(overlayMostrati), ripartisci \(ripartisci), zoom \(zoom)"
    }
    static var valori: [Int] { [layout, limiti, overlayCreati, overlayMostrati, ripartisci, zoom] }
}

@MainActor
enum ProvaPrestazioni {
    static var attiva: Bool { ProcessInfo.processInfo.environment["APT_PROVA"] != nil }
    static var corpi = 0
    static var righe: [String] = []
    static var secondo: AptDoc?

    static var cartella: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Crea due PDF di prova (40 pagine ciascuno, con testo) e restituisce il primo
    static func preparaPDF() -> AptDoc? {
        let dir = cartella.appendingPathComponent("ProvaAppunti", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func crea(_ nome: String) -> AptDoc? {
            let url = dir.appendingPathComponent(nome + ".pdf")
            let area = CGRect(x: 0, y: 0, width: 595, height: 842)
            let dati = UIGraphicsPDFRenderer(bounds: area).pdfData { ctx in
                for p in 1...40 {
                    ctx.beginPage()
                    let attr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
                    for riga in 0..<45 {
                        ("Pagina \(p) riga \(riga): testo di prova per il documento \(nome)" as NSString)
                            .draw(at: CGPoint(x: 40, y: 40 + CGFloat(riga) * 17), withAttributes: attr)
                    }
                }
            }
            guard (try? dati.write(to: url, options: .atomic)) != nil else { return nil }
            return AptDoc(id: nome + ".pdf", url: url, name: nome, modDate: Date(), folderPath: "")
        }
        secondo = crea("Prova due")
        return crea("Prova uno")
    }

    static func scrivi(_ riga: String) {
        righe.append(riga)
        try? righe.joined(separator: "\n").write(to: cartella.appendingPathComponent("prova.txt"), atomically: true, encoding: .utf8)
    }

    static func tempoProcessore() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(u.ru_utime) + s(u.ru_stime)
    }

    static func memoriaMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }

    /// Misura per `secondi`; se c'è `azione`, la esegue ogni 0,1 s (per esempio scorrere le pagine)
    static func misura(_ nome: String, secondi: Double, azione: ((Int) -> Void)? = nil) async {
        let m = Misuratore()
        m.inizia()
        let t0 = CACurrentMediaTime()
        var i = 0
        while CACurrentMediaTime() - t0 < secondi {
            azione?(i)
            i += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        scrivi(m.fine(nome))
    }
}

@MainActor
final class Misuratore: NSObject {
    private var link: CADisplayLink?
    private var frame = 0
    private var ultimo: CFTimeInterval = 0
    private var maxPausa: Double = 0
    private var pauseLunghe = 0
    private var t0: CFTimeInterval = 0
    private var cpu0: Double = 0
    private var corpi0 = 0
    private var cont0: [Int] = []

    func inizia() {
        t0 = CACurrentMediaTime()
        cpu0 = ProvaPrestazioni.tempoProcessore()
        corpi0 = ProvaPrestazioni.corpi
        cont0 = ProvaContatori.valori
        let l = CADisplayLink(target: self, selector: #selector(tic))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tic(_ l: CADisplayLink) {
        if ultimo > 0 {
            let pausa = l.timestamp - ultimo
            maxPausa = max(maxPausa, pausa)
            if pausa > 0.1 { pauseLunghe += 1 }
        }
        ultimo = l.timestamp
        frame += 1
    }

    func fine(_ nome: String) -> String {
        link?.invalidate()
        link = nil
        let durata = max(CACurrentMediaTime() - t0, 0.001)
        let cpu = (ProvaPrestazioni.tempoProcessore() - cpu0) / durata * 100
        let d = zip(ProvaContatori.valori, cont0).map { $0 - $1 }
        let eventi = "layout \(d[0]), limiti \(d[1]), tele create \(d[2]), tele mostrate \(d[3]), ripartisci \(d[4]), zoom \(d[5])"
        return String(format: "%@ | CPU %.0f%% | schermate/s %.1f | pausa max %.0f ms | pause >100ms: %d | body EditorView: %d | memoria %.0f MB",
                      nome, cpu, Double(frame) / durata, maxPausa * 1000, pauseLunghe,
                      ProvaPrestazioni.corpi - corpi0, ProvaPrestazioni.memoriaMB()) + "\n    " + eventi
    }
}

/// Radice usata solo dalla prova: apre direttamente l'Editor sul primo PDF di prova
struct ProvaRadice: View {
    @StateObject private var store = AptStore()
    let doc: AptDoc

    var body: some View {
        EditorView(doc: doc).environmentObject(store)
    }
}

extension EditorView {
    /// Copione: un documento a riposo e in scorrimento, poi vista doppia vuota, poi con due documenti, a riposo e in scorrimento
    @MainActor
    func eseguiProva() async {
        guard ProvaPrestazioni.attiva, let d2 = ProvaPrestazioni.secondo else { return }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        await ProvaPrestazioni.misura("A  un documento, a riposo", secondi: 4)
        await ProvaPrestazioni.misura("A2 un documento, scorrimento", secondi: 4) { i in model.vaiAPagina(i % 40) }
        alternaVistaDoppia()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await ProvaPrestazioni.misura("B  vista doppia, riquadro vuoto, a riposo", secondi: 4)
        apriSecondario(d2)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await ProvaPrestazioni.misura("C  vista doppia, due documenti, a riposo", secondi: 4)
        await ProvaPrestazioni.misura("D  vista doppia, scorrimento dei due", secondi: 4) { i in
            model.vaiAPagina(i % 40)
            secondario.vaiAPagina((i * 3) % 40)
        }
        await ProvaPrestazioni.misura("E  vista doppia, a riposo dopo lo scorrimento", secondi: 4)
        ProvaPrestazioni.scrivi("FINE")
    }
}
