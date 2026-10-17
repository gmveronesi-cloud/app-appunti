// Diagnostica: il «registro di bordo» dell'app, per capire perché a volte si chiude all'improvviso.
//
// Tutto resta sull'iPad (Application Support/Diagnostica: fuori da iCloud, mai nel repository). L'unico modo per farlo uscire
// è «Prepara rapporto», che crea un file di testo da mandare a Claude. Nel registro NON finiscono nomi di file né contenuti:
// solo numeri (pagine, memoria, durate) e il nome delle operazioni.
//
// Cosa si registra:
//  - registro.txt: una riga per ogni fatto importante (apertura e salvataggio dei documenti, memoria, avvisi di iPadOS, blocchi)
//    con l'ora e la memoria occupata in quel momento («occupata M / ancora disponibile M»).
//  - stato.txt: com'è finita l'ultima volta (se l'app era in uso quando si è chiusa = chiusura improvvisa) e esiti.txt: lo storico.
//  - arresto.txt: se l'app si ferma per un errore del programma (o un'eccezione), la funzione in cui è successo e perché.
//  - Blocchi: ogni secondo si controlla che la schermata risponda; se resta ferma più di 2 secondi si scrive DOVE è bloccata
//    (la pila delle funzioni del thread principale), prima che iPadOS la chiuda per «app non risponde».
//  - MetricKit: i rapporti di memoria e di arresto che iPadOS consegna da solo (a volte il giorno dopo).
import UIKit
import Darwin
import MachO
import MetricKit

// MARK: - Parti a basso livello (nei gestori dei segnali non si può allocare memoria: tutto è preparato prima)

@_silgen_name("backtrace")
private func aptBacktrace(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ size: Int32) -> Int32

@_silgen_name("backtrace_symbols_fd")
private func aptBacktraceSymbolsFd(_ buffer: UnsafePointer<UnsafeMutableRawPointer?>?, _ size: Int32, _ fd: Int32)

@_silgen_name("swift_demangle")
private func aptSwiftDemangle(_ nome: UnsafePointer<CChar>?, _ lunghezza: UInt,
                              _ uscita: UnsafeMutablePointer<CChar>?, _ lunghezzaUscita: UnsafeMutablePointer<UInt>?,
                              _ flag: UInt32) -> UnsafeMutablePointer<CChar>?

private let aptMaxFrames: Int32 = 64
private var aptFdArresto: Int32 = -1
private var aptBuffer: UnsafeMutablePointer<UInt8>? = nil
private var aptFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
private var aptBloccoFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
private var aptBloccoQuanti: Int32 = 0
private var aptBloccoPronto: Int32 = 0
private var aptBase: UInt = 0
private var aptThreadPrincipale: pthread_t? = nil

private func aptScrivi(_ testo: StaticString) {
    guard aptFdArresto >= 0, testo.utf8CodeUnitCount > 0 else { return }
    _ = write(aptFdArresto, testo.utf8Start, testo.utf8CodeUnitCount)
}

/// Scrive un numero (decimale o esadecimale) senza allocare memoria
private func aptScriviNumero(_ valore: UInt, base: UInt) {
    guard aptFdArresto >= 0, let b = aptBuffer else { return }
    var n = valore
    var i = 63
    if n == 0 {
        b[i] = 48
        i -= 1
    }
    while n > 0 && i >= 0 {
        let cifra = UInt8(n % base)
        b[i] = cifra < 10 ? 48 + cifra : 87 + cifra
        n /= base
        i -= 1
    }
    _ = write(aptFdArresto, b + (i + 1), 63 - i)
}

/// L'app sta per fermarsi per un errore (indice fuori misura, valore mancante, memoria rovinata…): si scrive dove, poi si lascia
/// che iPadOS faccia il suo rapporto come al solito.
private func aptGestoreSegnale(_ numero: Int32) {
    alarm(3)                              // se qualcosa si incastra qui dentro, tra 3 secondi l'app si chiude comunque
    aptScrivi("\n=== SEGNALE ")
    aptScriviNumero(UInt(numero), base: 10)
    aptScrivi(" ===\nbase 0x")
    aptScriviNumero(aptBase, base: 16)
    aptScrivi("\n")
    if let f = aptFrames {
        let n = aptBacktrace(f, aptMaxFrames)
        if n > 0 {
            aptBacktraceSymbolsFd(UnsafePointer(f), n, aptFdArresto)
        }
    }
    aptScrivi("=== FINE ===\n")
    signal(numero, SIG_DFL)
    raise(numero)
}

/// Il controllo dei blocchi chiede al thread principale (che non risponde) di scrivere dove si trova
private func aptGestoreBlocco(_ numero: Int32) {
    if let f = aptBloccoFrames {
        aptBloccoQuanti = aptBacktrace(f, aptMaxFrames)
        aptBloccoPronto = 1
    }
}

private func aptInstallaGestori() {
    aptBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    let quanti = Int(aptMaxFrames)
    let a = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: quanti)
    a.initialize(repeating: nil, count: quanti)
    aptFrames = a
    let b = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: quanti)
    b.initialize(repeating: nil, count: quanti)
    aptBloccoFrames = b
    aptBase = UInt(bitPattern: _dyld_get_image_header(0))

    // Pila di riserva: serve a scrivere il rapporto anche se l'errore è una pila piena (troppe funzioni dentro funzioni)
    let dimensione = 64 * 1024
    var pila = stack_t(ss_sp: malloc(dimensione), ss_size: dimensione, ss_flags: 0)
    sigaltstack(&pila, nil)

    var azione = sigaction()
    azione.__sigaction_u.__sa_handler = aptGestoreSegnale
    sigemptyset(&azione.sa_mask)
    azione.sa_flags = SA_ONSTACK
    let segnali: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
    for s in segnali { sigaction(s, &azione, nil) }

    var azioneBlocco = sigaction()
    azioneBlocco.__sigaction_u.__sa_handler = aptGestoreBlocco
    sigemptyset(&azioneBlocco.sa_mask)
    azioneBlocco.sa_flags = SA_RESTART
    sigaction(SIGUSR2, &azioneBlocco, nil)
}

// MARK: - MetricKit

/// Riceve da iPadOS i rapporti di memoria e di arresto (arrivano da soli, di solito entro un giorno)
final class RicevitoreMetriche: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { Diagnostica.salvaMetrica(p.jsonRepresentation(), tipo: "metriche", fine: p.timeStampEnd) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { Diagnostica.salvaMetrica(p.jsonRepresentation(), tipo: "diagnostica", fine: p.timeStampEnd) }
    }
}

// MARK: - Diagnostica

enum Diagnostica {
    // MARK: Cartelle e file

    static let cartella: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let c = base.appendingPathComponent("Diagnostica", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }()
    static var fileRegistro: URL { cartella.appendingPathComponent("registro.txt") }
    static var fileRegistroPrec: URL { cartella.appendingPathComponent("registro-prec.txt") }
    static var fileArresto: URL { cartella.appendingPathComponent("arresto.txt") }
    static var fileArrestoUltimo: URL { cartella.appendingPathComponent("arresto-ultimo.txt") }
    static var fileStato: URL { cartella.appendingPathComponent("stato.txt") }
    static var fileEsiti: URL { cartella.appendingPathComponent("esiti.txt") }
    static var cartellaMetriche: URL {
        let c = cartella.appendingPathComponent("MetricKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }

    // MARK: Stato

    private static var avviata = false
    private static let idSessione = String(UUID().uuidString.prefix(8))
    private static let inizioSessione = Date()
    /// Com'è finita l'ultima volta (testo per il rapporto) e se è stata una chiusura improvvisa mentre l'app era in uso
    private(set) static var esitoPrecedente = "Prima esecuzione registrata."
    private(set) static var chiusuraAnomala = false
    private static let ricevitoreMetriche = RicevitoreMetriche()

    // Registro
    private static let blocco = NSLock()
    private static var fdRegistro: Int32 = -1
    private static var byteSessione = 0
    private static let limiteRegistro = 400_000
    private static let formattatoreOra: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.S"
        return f
    }()
    private static var ultimoEvento = ""
    private static var ultimoEventoAlle: TimeInterval = 0

    // Controllo dei blocchi e della memoria (variabili protette da `statoControllo`)
    private static let statoControllo = NSLock()
    private static let codaControllo = DispatchQueue(label: "appunti.diagnostica", qos: .utility)
    private static var timerControllo: DispatchSourceTimer?
    private static var primoPiano = false
    private static var ultimoBattito: TimeInterval = 0
    private static var pingInAttesa = false
    private static var bloccoInCorso = false
    private static var bloccoSoglia: TimeInterval = 2
    private static var bloccoDa: TimeInterval = 0
    private static var contesto = "nessun documento aperto"
    private static var ultimoContesto: TimeInterval = 0
    private static var ultimaMemoriaNotata = 0
    private static var ultimaNotaMemoria: TimeInterval = 0
    private static var ultimoLivello = 0

    /// I riquadri dell'Editor (uno o due): servono solo a descrivere cosa si sta facendo quando succede qualcosa
    private static let registrati = NSHashTable<NotesModel>.weakObjects()

    static func registra(_ modello: NotesModel) {
        registrati.add(modello)
    }

    // MARK: Avvio

    /// Da chiamare per prima cosa all'avvio dell'app (`MyApp.init`)
    static func avvia() {
        guard !avviata else { return }
        avviata = true
        aptThreadPrincipale = pthread_self()
        let fm = FileManager.default

        // 1. Com'era finita l'ultima volta
        let codaRegistro = leggiCoda(fileRegistro, byte: 20_000)
        classificaUltimaChiusura(codaRegistro: codaRegistro)

        // 2. L'eventuale arresto dell'ultima volta si conserva; si prepara il file per questa sessione
        if let a = try? fm.attributesOfItem(atPath: fileArresto.path), ((a[.size] as? NSNumber)?.intValue ?? 0) > 0 {
            try? fm.removeItem(at: fileArrestoUltimo)
            try? fm.moveItem(at: fileArresto, to: fileArrestoUltimo)
        }
        aptFdArresto = open(fileArresto.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        aptInstallaGestori()
        NSSetUncaughtExceptionHandler { eccezione in
            Diagnostica.registraEccezione(eccezione)
        }

        // 3. Registro
        if let a = try? fm.attributesOfItem(atPath: fileRegistro.path), ((a[.size] as? NSNumber)?.intValue ?? 0) > 300_000 {
            ruotaFile(fileRegistro, fileRegistroPrec)
        }
        apriRegistro()
        scriviIntestazione()
        scriviStato("avvio")

        // 4. Eventi dell'app
        osservaEventi()
        avviaControllo()
        avviaMetriche()
    }

    private static func scriviIntestazione() {
        let versione = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        nota("AVVIO", "sessione \(idSessione), versione \(versione) (\(build)), \(modelloDispositivo()), iPadOS \(UIDevice.current.systemVersion)")
        nota("avvio-esito-precedente", esitoPrecedente)
    }

    // MARK: Com'è finita l'ultima volta

    private static func classificaUltimaChiusura(codaRegistro: String) {
        let versione = versioneCorrente()
        let sistema = UIDevice.current.systemVersion
        var testo = "Prima esecuzione registrata."
        var anomala = false
        if let riga = try? String(contentsOf: fileStato, encoding: .utf8) {
            let p = riga.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
            // stato | sessione | versione | iPadOS | avvio del sistema | ora
            if p.count >= 6 {
                let stato = p[0]
                let stessaApp = p[2] == versione && p[3] == sistema
                let avvioPrima = Int(p[4]) ?? 0
                let riavviato = abs(avvioPrima - avvioSistema()) > 5
                let interrotto = salvataggioInterrotto(codaRegistro)
                if stato == "uscita" {
                    testo = "L'app era stata chiusa normalmente."
                } else if !stessaApp {
                    testo = "L'app è stata aggiornata o reinstallata dopo l'ultima volta (versione o iPadOS cambiati)."
                } else if riavviato {
                    testo = "L'iPad si è riavviato (o spento) dopo l'ultima volta."
                } else if stato == "avvio" || stato == "primoPiano" {
                    testo = "CHIUSURA IMPROVVISA: l'app era aperta e in uso quando si è chiusa (errore del programma, memoria esaurita o app bloccata)."
                    anomala = true
                } else if interrotto {
                    testo = "L'app era in secondo piano ma stava ancora scrivendo un file quando si è chiusa (salvataggio o esportazione interrotti)."
                    anomala = true
                } else {
                    testo = "L'app era in secondo piano quando si è chiusa (iPadOS lo fa per fare spazio; oppure è stata chiusa dal selettore delle app)."
                }
            }
        }
        esitoPrecedente = testo
        chiusuraAnomala = anomala
        aggiungiEsito(testo)
    }

    /// Nelle ultime righe del registro c'è un salvataggio (o un'esportazione) iniziato e mai finito?
    private static func salvataggioInterrotto(_ coda: String) -> Bool {
        var aperti = 0
        for riga in coda.split(separator: "\n") {
            if riga.contains("| salva-inizio") || riga.contains("| esporta-inizio") { aperti += 1 }
            if riga.contains("| salva-fine") || riga.contains("| esporta-fine") { aperti = max(0, aperti - 1) }
        }
        return aperti > 0
    }

    private static func aggiungiEsito(_ testo: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        let riga = f.string(from: Date()) + " | " + testo
        var righe = ((try? String(contentsOf: fileEsiti, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        righe.append(riga)
        if righe.count > 40 { righe.removeFirst(righe.count - 40) }
        try? (righe.joined(separator: "\n") + "\n").write(to: fileEsiti, atomically: true, encoding: .utf8)
    }

    private static func versioneCorrente() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return v + "." + b + "." + improntaEseguibile()
    }

    /// Dimensione e data del programma: cambia a ogni nuova versione installata
    private static func improntaEseguibile() -> String {
        guard let u = Bundle.main.executableURL, let a = try? FileManager.default.attributesOfItem(atPath: u.path) else { return "?" }
        let dim = (a[.size] as? NSNumber)?.intValue ?? 0
        let data = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(dim)-\(Int(sicuro: data))"
    }

    private static func scriviStato(_ stato: String) {
        let campi: [String] = [stato, idSessione, versioneCorrente(), UIDevice.current.systemVersion,
                               String(avvioSistema()), String(Int(sicuro: Date().timeIntervalSince1970))]
        try? campi.joined(separator: "|").write(to: fileStato, atomically: true, encoding: .utf8)
    }

    /// Quando si è acceso l'iPad l'ultima volta (secondi dal 1970)
    private static func avvioSistema() -> Int {
        var t = timeval()
        var dimensione = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &t, &dimensione, nil, 0) == 0 else { return 0 }
        return Int(t.tv_sec)
    }

    private static func modelloDispositivo() -> String {
        var info = utsname()
        uname(&info)
        var nome = ""
        for elemento in Mirror(reflecting: info.machine).children {
            guard let v = elemento.value as? Int8, v != 0 else { continue }
            nome.append(Character(UnicodeScalar(UInt8(v))))
        }
        return nome
    }

    // MARK: Registro (una riga per fatto)

    /// Scrive una riga nel registro. Va bene da qualsiasi thread; da usare per fatti rari (non per ogni tratto).
    static func nota(_ evento: String, _ dettaglio: String = "") {
        guard avviata else { return }
        let usata = GuardiaMemoria.usata
        let libera = GuardiaMemoria.disponibile
        let adesso = ProcessInfo.processInfo.systemUptime
        blocco.lock()
        defer { blocco.unlock() }
        ultimoEvento = evento
        ultimoEventoAlle = adesso
        let ora = formattatoreOra.string(from: Date())
        var riga = ora + " | " + String(usata / 1_048_576) + "M/" + String(libera / 1_048_576) + "M | " + evento
        if !dettaglio.isEmpty { riga += " | " + dettaglio }
        scriviRigaSenzaBlocco(riga + "\n")
    }

    /// Più righe insieme (per esempio la pila di un blocco), senza ora né memoria
    private static func notaTesto(_ testo: String) {
        guard avviata else { return }
        blocco.lock()
        defer { blocco.unlock() }
        scriviRigaSenzaBlocco(testo.hasSuffix("\n") ? testo : testo + "\n")
    }

    private static func scriviRigaSenzaBlocco(_ riga: String) {
        if fdRegistro < 0 { apriRegistro() }
        guard fdRegistro >= 0 else { return }
        let dati = Array(riga.utf8)
        dati.withUnsafeBufferPointer { p in
            if let base = p.baseAddress { _ = write(fdRegistro, base, p.count) }
        }
        byteSessione += dati.count
        if byteSessione > limiteRegistro {
            close(fdRegistro)
            fdRegistro = -1
            ruotaFile(fileRegistro, fileRegistroPrec)
            apriRegistro()
            byteSessione = 0
        }
    }

    private static func apriRegistro() {
        if fdRegistro >= 0 { close(fdRegistro) }
        fdRegistro = open(fileRegistro.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }

    private static func ruotaFile(_ da: URL, _ a: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: a)
        try? fm.moveItem(at: da, to: a)
    }

    /// Cambio del livello di scarsità di memoria (0 normale … 3 critica): si scrive solo quando cambia
    static func livelloMemoria(_ livello: Int) {
        statoControllo.lock()
        let cambiato = livello != ultimoLivello
        ultimoLivello = livello
        statoControllo.unlock()
        if cambiato { nota("memoria-livello", "\(livello) (0 normale, 3 critica)") }
    }

    /// Il segno che mette Cristina quando nota un problema: serve a ritrovare il punto nel registro
    static func segnalaProblema() {
        let adesso = descrizioneContestoPrincipale()
        nota("PROBLEMA-SEGNALATO-DALL-UTENTE", adesso)
    }

    // MARK: Eventi dell'app

    private static func osservaEventi() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Diagnostica.diventaAttiva()
        }
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Diagnostica.impostaPrimoPiano(false)
            Diagnostica.nota("app-inattiva")
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Diagnostica.impostaPrimoPiano(false)
            Diagnostica.scriviStato("secondoPiano")
            Diagnostica.nota("app-in-secondo-piano", Diagnostica.descrizioneContestoPrincipale())
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Diagnostica.nota("app-torna-in-primo-piano")
        }
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Diagnostica.scriviStato("uscita")
            Diagnostica.nota("app-uscita")
        }
        nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Diagnostica.nota("AVVISO-MEMORIA-DI-IPADOS", Diagnostica.descrizioneContestoPrincipale())
        }
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            Diagnostica.nota("temperatura", "stato \(ProcessInfo.processInfo.thermalState.rawValue) (0 normale, 3 critico)")
        }
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            Diagnostica.nota("risparmio-energia", ProcessInfo.processInfo.isLowPowerModeEnabled ? "acceso" : "spento")
        }
    }

    private static func diventaAttiva() {
        statoControllo.lock()
        primoPiano = true
        ultimoBattito = ProcessInfo.processInfo.systemUptime
        pingInAttesa = false
        bloccoInCorso = false
        bloccoSoglia = 2
        statoControllo.unlock()
        scriviStato("primoPiano")
        nota("app-attiva")
    }

    private static func impostaPrimoPiano(_ valore: Bool) {
        statoControllo.lock()
        primoPiano = valore
        bloccoInCorso = false
        bloccoSoglia = 2
        statoControllo.unlock()
    }

    // MARK: Controllo dei blocchi e della memoria

    private static func avviaControllo() {
        let t = DispatchSource.makeTimerSource(queue: codaControllo)
        t.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(100))
        t.setEventHandler { Diagnostica.tic() }
        t.resume()
        timerControllo = t
    }

    /// Ogni secondo, fuori dal thread principale: chiede al principale di rispondere; se non risponde da troppo tempo, è un blocco
    private static func tic() {
        let ora = ProcessInfo.processInfo.systemUptime
        statoControllo.lock()
        let attivo = primoPiano
        let battito = ultimoBattito
        let inAttesa = pingInAttesa
        if attivo && !inAttesa { pingInAttesa = true }
        statoControllo.unlock()
        guard attivo else { return }
        if !inAttesa {
            DispatchQueue.main.async { Diagnostica.battitoDalPrincipale() }
        }
        let fermo = ora - battito

        statoControllo.lock()
        var segnala = false
        var finito: TimeInterval?
        if fermo >= bloccoSoglia {
            if !bloccoInCorso {
                bloccoInCorso = true
                bloccoDa = battito
            }
            segnala = true
            bloccoSoglia = bloccoSoglia < 5 ? 5 : (bloccoSoglia < 10 ? 10 : bloccoSoglia + 10)
        } else if bloccoInCorso && fermo < 1.0 {
            bloccoInCorso = false
            finito = ora - bloccoDa
            bloccoSoglia = 2
        }
        let descrizione = contesto
        statoControllo.unlock()

        if segnala {
            let quando = ProcessInfo.processInfo.systemUptime
            blocco.lock()
            let evento = ultimoEvento
            let fa = quando - ultimoEventoAlle
            blocco.unlock()
            let secondi = String(format: "%.1f", fermo)
            nota("BLOCCO", "la schermata non risponde da \(secondi) s; ultimo evento: \(evento) (\(String(format: "%.1f", fa)) s prima); \(descrizione)")
            let pila = catturaPilaPrincipale()
            notaTesto("    pila del thread principale:\n" + pila)
        } else if let durata = finito {
            nota("blocco-finito", "durato circa \(String(format: "%.1f", durata)) s")
        }
    }

    /// Risposta del thread principale (sul principale): aggiorna il battito e, ogni 5 secondi, il contesto e la memoria
    private static func battitoDalPrincipale() {
        let ora = ProcessInfo.processInfo.systemUptime
        statoControllo.lock()
        ultimoBattito = ora
        pingInAttesa = false
        let aggiorna = ora - ultimoContesto >= 5
        if aggiorna { ultimoContesto = ora }
        statoControllo.unlock()
        guard aggiorna else { return }
        let descrizione = descrizioneContestoPrincipale()
        let usata = GuardiaMemoria.usata
        statoControllo.lock()
        contesto = descrizione
        let differenza = abs(usata - ultimaMemoriaNotata)
        let trascorso = ora - ultimaNotaMemoria
        let notare = differenza >= 25 * 1_048_576 || trascorso >= 60
        if notare {
            ultimaMemoriaNotata = usata
            ultimaNotaMemoria = ora
        }
        statoControllo.unlock()
        if notare { nota("memoria", descrizione) }
    }

    /// Descrizione dei documenti aperti (solo sul thread principale)
    static func descrizioneContestoPrincipale() -> String {
        let aperti = registrati.allObjects.filter { $0.document != nil }
        if aperti.isEmpty { return "nessun documento aperto" }
        var parti: [String] = []
        for (i, m) in aperti.enumerated() {
            parti.append("riquadro \(i + 1): " + m.descrizioneDiagnostica())
        }
        return parti.joined(separator: " || ")
    }

    /// La pila delle funzioni del thread principale in questo momento (si chiede al principale di scriverla con un segnale)
    private static func catturaPilaPrincipale() -> String {
        guard let t = aptThreadPrincipale, let f = aptBloccoFrames else { return "    (non disponibile)" }
        aptBloccoPronto = 0
        aptBloccoQuanti = 0
        guard pthread_kill(t, SIGUSR2) == 0 else { return "    (segnale non inviato)" }
        var tentativi = 0
        while aptBloccoPronto == 0 && tentativi < 50 {
            usleep(10_000)
            tentativi += 1
        }
        guard aptBloccoPronto == 1, aptBloccoQuanti > 0 else { return "    (pila non ottenuta)" }
        var righe: [String] = []
        for i in 0..<Int(aptBloccoQuanti) {
            guard let p = f[i] else { continue }
            righe.append("    " + String(i) + "  " + descrivi(p))
        }
        return righe.joined(separator: "\n")
    }

    private static func descrivi(_ p: UnsafeMutableRawPointer) -> String {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(p), &info) != 0 else { return "0x" + String(UInt(bitPattern: p), radix: 16) }
        var immagine = "?"
        if let nome = info.dli_fname { immagine = (String(cString: nome) as NSString).lastPathComponent }
        var simbolo = "?"
        var scarto: UInt = 0
        if let s = info.dli_sname {
            simbolo = demangla(String(cString: s))
            if let base = info.dli_saddr { scarto = UInt(bitPattern: p) &- UInt(bitPattern: base) }
        } else if let base = info.dli_fbase {
            scarto = UInt(bitPattern: p) &- UInt(bitPattern: base)
        }
        return immagine + " " + simbolo + " +" + String(scarto)
    }

    // MARK: Nomi leggibili delle funzioni

    /// I nomi delle funzioni Swift sono «mangled» (`$s9AppModule…`): qui diventano leggibili
    static func demangla(_ nome: String) -> String {
        guard nome.hasPrefix("$s") || nome.hasPrefix("_$s") || nome.hasPrefix("$S") else { return nome }
        let risultato: String? = nome.withCString { (c: UnsafePointer<CChar>) -> String? in
            guard let uscita = aptSwiftDemangle(c, UInt(strlen(c)), nil, nil, 0) else { return nil }
            let testo = String(cString: uscita)
            free(uscita)
            return testo
        }
        return risultato ?? nome
    }

    private static func demanglaTesto(_ testo: String) -> String {
        var righe: [String] = []
        for riga in testo.split(separator: "\n", omittingEmptySubsequences: false) {
            var parole: [String] = []
            for parola in riga.split(separator: " ", omittingEmptySubsequences: false) {
                parole.append(demangla(String(parola)))
            }
            righe.append(parole.joined(separator: " "))
        }
        return righe.joined(separator: "\n")
    }

    // MARK: Errori

    /// Un'eccezione di sistema non gestita (per esempio un indice fuori misura in PDFKit): si scrive perché, poi l'app si chiude
    fileprivate static func registraEccezione(_ e: NSException) {
        var testo = "\n=== ECCEZIONE ===\n"
        testo += e.name.rawValue + "\n"
        testo += (e.reason ?? "(nessun motivo)") + "\n"
        testo += e.callStackSymbols.joined(separator: "\n") + "\n=== FINE ===\n"
        let dati = Array(testo.utf8)
        if aptFdArresto >= 0 {
            dati.withUnsafeBufferPointer { p in
                if let base = p.baseAddress { _ = write(aptFdArresto, base, p.count) }
            }
        }
    }

    // MARK: MetricKit

    private static func avviaMetriche() {
        MXMetricManager.shared.add(ricevitoreMetriche)
        codaControllo.async {
            for p in MXMetricManager.shared.pastPayloads {
                salvaMetrica(p.jsonRepresentation(), tipo: "metriche", fine: p.timeStampEnd)
            }
            for p in MXMetricManager.shared.pastDiagnosticPayloads {
                salvaMetrica(p.jsonRepresentation(), tipo: "diagnostica", fine: p.timeStampEnd)
            }
        }
    }

    fileprivate static func salvaMetrica(_ json: Data, tipo: String, fine: Date) {
        let nome = tipo + "-" + String(Int(sicuro: fine.timeIntervalSince1970)) + ".json"
        let u = cartellaMetriche.appendingPathComponent(nome)
        if FileManager.default.fileExists(atPath: u.path) { return }
        try? json.write(to: u, options: .atomic)
        nota("metrickit", "\(tipo): rapporto di iPadOS ricevuto (\(json.count / 1024) KB)")
        potaMetriche()
    }

    /// Si tengono solo gli ultimi 10 rapporti di iPadOS
    private static func potaMetriche() {
        let fm = FileManager.default
        guard let elenco = try? fm.contentsOfDirectory(at: cartellaMetriche, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let ordinati = elenco.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return da > db
        }
        if ordinati.count > 10 {
            for u in ordinati.dropFirst(10) { try? fm.removeItem(at: u) }
        }
    }

    // MARK: Rapporto da inviare

    /// Prepara il file di testo da mandare a Claude. `completamento` parte sul thread principale (nil = non riuscito).
    static func preparaRapporto(motivo: String, completamento: @escaping (URL?) -> Void) {
        nota("rapporto-richiesto", motivo)
        let adesso = descrizioneContestoPrincipale()
        let sistema = UIDevice.current.systemVersion
        let modello = modelloDispositivo()
        codaControllo.async {
            let testo = costruisciRapporto(contestoAdesso: adesso, sistema: sistema, modello: modello)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmm"
            let nome = "Diagnosi-Appunti-" + f.string(from: Date()) + ".txt"
            let dir = FileManager.default.temporaryDirectory
            if let vecchi = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for u in vecchi where u.lastPathComponent.hasPrefix("Diagnosi-Appunti-") { try? FileManager.default.removeItem(at: u) }
            }
            let url = dir.appendingPathComponent(nome)
            var riuscito = true
            do { try testo.write(to: url, atomically: true, encoding: .utf8) } catch { riuscito = false }
            DispatchQueue.main.async { completamento(riuscito ? url : nil) }
        }
    }

    private static func costruisciRapporto(contestoAdesso: String, sistema: String, modello: String) -> String {
        var t = ""
        let data = DateFormatter()
        data.locale = Locale(identifier: "it_IT")
        data.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let versione = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let durata = Int(sicuro: Date().timeIntervalSince(inizioSessione))

        t += "RAPPORTO DI DIAGNOSI — App Appunti\n"
        t += "Creato il \(data.string(from: Date()))\n"
        t += "Versione \(versione) (\(build)); programma: \(improntaEseguibile())\n"
        t += "Dispositivo \(modello), iPadOS \(sistema), memoria fisica \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB\n"
        t += "Spazio libero sull'iPad: \(spazioLibero())\n"
        t += "Temperatura (0 normale, 3 critica): \(ProcessInfo.processInfo.thermalState.rawValue); risparmio energia: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "acceso" : "spento")\n"
        t += "Sessione attuale \(idSessione), in corso da \(durata) s\n"
        t += "Righe del registro: ora | memoria occupata / ancora disponibile (0 = non misurabile) | evento | dettagli\n\n"

        t += "== ESITO DELL'ULTIMA VOLTA ==\n\(esitoPrecedente)\n\n"

        t += "== STORICO DEGLI ESITI (ultimi) ==\n"
        let esiti = ((try? String(contentsOf: fileEsiti, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true).suffix(15)
        t += esiti.joined(separator: "\n") + "\n\n"

        t += "== STATO ADESSO ==\n\(contestoAdesso)\n\n"

        let arresto = leggiCoda(fileArrestoUltimo, byte: 20_000)
        let arrestoOra = leggiCoda(fileArresto, byte: 20_000)
        if !arresto.isEmpty || !arrestoOra.isEmpty {
            t += "== ARRESTO DEL PROGRAMMA (errore catturato; la funzione è nelle prime righe dopo SEGNALE o ECCEZIONE) ==\n"
            if !arresto.isEmpty { t += "[sessione precedente]\n" + demanglaTesto(arresto) + "\n" }
            if !arrestoOra.isEmpty { t += "[sessione attuale]\n" + demanglaTesto(arrestoOra) + "\n" }
            t += "\n"
        }

        t += "== RAPPORTI CONSEGNATI DA IPADOS (MetricKit) ==\n"
        t += riassuntoMetriche() + "\n"

        t += "== REGISTRO (le righe più recenti in fondo) ==\n"
        let precedente = leggiCoda(fileRegistroPrec, byte: 60_000)
        if !precedente.isEmpty { t += "--- parte precedente ---\n" + precedente + "\n--- parte più recente ---\n" }
        t += leggiCoda(fileRegistro, byte: 200_000)
        return t
    }

    private static func spazioLibero() -> String {
        let u = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let byte = v.volumeAvailableCapacityForImportantUsage {
            return String(byte / 1_048_576) + " MB"
        }
        return "non disponibile"
    }

    private static func riassuntoMetriche() -> String {
        let fm = FileManager.default
        guard let elenco = try? fm.contentsOfDirectory(at: cartellaMetriche, includingPropertiesForKeys: [.contentModificationDateKey]),
              !elenco.isEmpty else {
            return "Nessun rapporto consegnato da iPadOS finora (di solito arrivano dopo un giorno d'uso).\n"
        }
        let ordinati = elenco.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return da > db
        }
        var t = ""
        var diagnostiche = 0
        var metriche = 0
        for u in ordinati {
            let nome = u.lastPathComponent
            guard let dati = try? Data(contentsOf: u) else { continue }
            if nome.hasPrefix("diagnostica") {
                if diagnostiche >= 3 { continue }
                diagnostiche += 1
                t += "--- \(nome) ---\n" + String(String(decoding: dati, as: UTF8.self).prefix(40_000)) + "\n"
            } else {
                if metriche >= 2 { continue }
                metriche += 1
                t += "--- \(nome) (riassunto) ---\n" + selezionaMetriche(dati) + "\n"
            }
        }
        return t
    }

    /// Dei rapporti di metriche si tengono le parti che interessano: come si è chiusa l'app, memoria, scritture su disco
    private static func selezionaMetriche(_ dati: Data) -> String {
        guard let radice = (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any] else {
            return String(String(decoding: dati, as: UTF8.self).prefix(4_000))
        }
        var scelte: [String: Any] = [:]
        let chiavi = ["metaData", "applicationExitMetrics", "memoryMetrics", "diskIOMetrics", "timeStampBegin", "timeStampEnd"]
        for k in chiavi {
            if let v = radice[k] { scelte[k] = v }
        }
        if scelte.isEmpty { return String(String(decoding: dati, as: UTF8.self).prefix(4_000)) }
        guard let d = try? JSONSerialization.data(withJSONObject: scelte, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(String(decoding: d, as: UTF8.self).prefix(8_000))
    }

    /// Le ultime `byte` byte di un file di testo, a partire da una riga intera
    private static func leggiCoda(_ url: URL, byte: Int) -> String {
        guard let dati = try? Data(contentsOf: url), !dati.isEmpty else { return "" }
        var testo = String(decoding: dati.suffix(byte), as: UTF8.self)
        if dati.count > byte, let a = testo.firstIndex(of: "\n") {
            testo = String(testo[testo.index(after: a)...])
        }
        return testo
    }
}

// MARK: - Descrizione di un riquadro dell'Editor

extension NotesModel {
    /// Una riga con lo stato del documento aperto (solo numeri: niente nomi di file né contenuti)
    func descrizioneDiagnostica() -> String {
        guard let d = document else { return "nessun documento" }
        var imm = 0
        for v in immagini.values { imm += v.count }
        var tes = 0
        for v in testi.values { tes += v.count }
        var parti: [String] = []
        parti.append("\(d.pageCount) pagine")
        parti.append("pagina \(paginaCorrente + 1)")
        parti.append("tele vive \(canvases.count)")
        parti.append("tratti in attesa \(trattiSalvati.count)")
        parti.append("immagini \(imm)")
        parti.append("testi \(tes)")
        parti.append("cronologie \(undoPagine.count)")
        parti.append(modificato ? "modificato" : "non modificato")
        if salvataggioInCorso { parti.append("SALVATAGGIO IN CORSO") }
        parti.append("risoluzione max \(risoluzioneMax), tele max \(teleMassime)")
        if let v = pdfView { parti.append("zoom \(String(format: "%.2f", Double(v.scaleFactor)))") }
        return parti.joined(separator: ", ")
    }
}
