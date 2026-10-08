// Editor PDF: apre il file, gestisce le tele Pencil, salva come annotazioni ink
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

final class NotesModel: NSObject, ObservableObject, PDFPageOverlayViewProvider, UIGestureRecognizerDelegate, UIPencilInteractionDelegate, PKCanvasViewDelegate {
    @Published var document: PDFDocument?
    @Published var fileName: String = ""
    @Published var message: String = ""
    /// Annulla e Ripeti attivi solo quando c'è qualcosa da annullare o ripetere
    @Published var puoAnnullare = false
    @Published var puoRipetere = false
    /// Cambia a ogni modifica dell'elenco delle pagine (aggiunta, riordino): le miniature si ridisegnano
    @Published var versionePagine = 0
    /// Griglia di tutte le pagine (si apre pizzicando oltre lo zoom minimo)
    @Published var griglia = false
    /// Vista del documento in questo riquadro (si ricorda tra una sessione e l'altra): una pagina o due, scorrimento, continuo
    @Published var paginaDoppia: Bool { didSet { Self.d.set(paginaDoppia, forKey: "ed.paginaDoppia"); applicaVista() } }
    @Published var scorrimentoOrizzontale: Bool { didSet { Self.d.set(scorrimentoOrizzontale, forKey: "ed.scorrOriz"); applicaVista() } }
    @Published var scorrimentoContinuo: Bool { didSet { Self.d.set(scorrimentoContinuo, forKey: "ed.scorrContinuo"); applicaVista() } }
    /// Estensione dei fogli ai lati (uguale per tutte le pagine del documento): vedi NotesModel+Pagina
    @Published var estensione = Estensione()
    /// Misura originale delle pagine allargate (area visibile prima dell'estensione)
    var originali: [PDFPage: CGRect] = [:]
    /// Pagine «di sola scrittura» (create dall'app): colore e modello; si salvano nel PDF in un'annotazione nascosta
    var modelli: [PDFPage: ModelloPagina] = [:]
    /// Il documento aperto è un quaderno (creato dall'app, solo fogli di scrittura): sfondo delle pagine nuove e pagine unite; nil per gli altri PDF
    @Published var quaderno: Quaderno?
    /// Pagina Modelli richiesta (cambia sfondo, inserisci pagina bianca)
    @Published var modelliRichiesti: RichiestaModelli?
    /// Si sta tirando oltre l'ultima pagina: compare «Rilascia per aggiungere una pagina»
    @Published var suggerisciPagina = false
    var superaFine: SuperaFine?
    /// Pagina da cui comincia il conteggio (la 1); le precedenti si contano in numeri romani
    var paginaUno: PDFPage?
    /// Larghezza comune delle pagine del documento aperto (ogni pagina tiene la propria altezza)
    var larghezzaPagina: CGFloat = 595
    /// Risoluzione massima delle tele di questo riquadro: 4 da soli, 2 in vista doppia (le tele 4× di due documenti pesano troppo)
    var risoluzioneMax: CGFloat = NotesModel.risoluzione
    /// Già c'è un aggiornamento dei pulsanti Annulla/Ripeti in attesa
    var aggiornamentoUndoProgrammato = false
    /// Vero mentre gli strumenti si copiano da un riquadro all'altro (vista doppia): niente lavoro pesante a ogni valore
    var inAllineamento = false
    /// Chiamata quando si tocca questo riquadro (vista doppia: serve a sapere dove lavora chi scrive)
    var quandoToccato: (() -> Void)?
    var osservatoriUndo: [NSObjectProtocol] = []
    @Published var pencilMode: Bool = true {
        didSet { aggiornaInterazione() }
    }

    // MARK: Strumenti (barra dell'Editor)

    // Tutto si ricorda tra una sessione e l'altra (UserDefaults)
    static let d = UserDefaults.standard

    @Published var strumenti: [Strumento] {
        didSet {
            if inAllineamento { return }
            salvaStrumenti()
            applicaStrumento()
        }
    }
    @Published var selezionato: UUID? {
        didSet {
            if let s = selezionato { Self.d.set(s.uuidString, forKey: "ed.selezionato") }
            if inAllineamento { return }
            applicaStrumento()
        }
    }
    /// Pallini colore fissi a lato della barra (numero modificabile)
    @Published var pallini: [ColoreSalvato] { didSet { Self.salva(pallini, "ed.pallini") } }

    @Published var ditoDisegna: Bool {
        didSet {
            Self.d.set(ditoDisegna, forKey: "ed.ditoDisegna")
            for canvas in canvases.values { canvas.drawingPolicy = ditoDisegna ? .anyInput : .pencilOnly }
            if !inAllineamento { aggiornaInterazione() }
        }
    }
    @Published var dueDitaAnnulla: Bool { didSet { Self.d.set(dueDitaAnnulla, forKey: "ed.dueDita") } }
    /// Tenendo ferma la Pencil a fine tratto: retta o forma (rettangolo, quadrato, ellisse, cerchio)
    @Published var formeFerma: Bool {
        didSet {
            Self.d.set(formeFerma, forKey: "ed.formeFerma")
            if !inAllineamento { aggiornaInterazione() }
        }
    }
    /// Dove va la cattura della penna screenshot
    @Published var destinazioneCattura: DestinazioneCattura { didSet { Self.d.set(destinazioneCattura.rawValue, forKey: "ed.cattura2") } }
    @Published var doppioTocco: DoppioTocco { didSet { Self.d.set(doppioTocco.rawValue, forKey: "ed.doppioTocco") } }

    /// Strumento usato subito prima di quello attuale (per il doppio tocco sulla Pencil)
    var precedente: UUID?

    var corrente: Strumento? {
        strumenti.first { $0.id == selezionato } ?? strumenti.first
    }

    override init() {
        let letti: [Tollerante<Strumento>]? = Self.leggi("ed.strumenti2")
        let salvati: [Strumento]? = letti?.compactMap { $0.valore }
        let lista = (salvati?.isEmpty == false) ? salvati! : Strumento.predefiniti
        strumenti = lista
        if let t = Self.d.string(forKey: "ed.selezionato"), let u = UUID(uuidString: t), lista.contains(where: { $0.id == u }) {
            selezionato = u
        } else {
            selezionato = lista.first?.id
        }
        pallini = Self.leggi("ed.pallini") ?? ColoreSalvato.pallini
        ditoDisegna = Self.d.bool(forKey: "ed.ditoDisegna")
        dueDitaAnnulla = Self.d.object(forKey: "ed.dueDita") == nil ? true : Self.d.bool(forKey: "ed.dueDita")
        doppioTocco = DoppioTocco(rawValue: Self.d.string(forKey: "ed.doppioTocco") ?? "") ?? .gomma
        formeFerma = Self.d.object(forKey: "ed.formeFerma") == nil ? true : Self.d.bool(forKey: "ed.formeFerma")
        destinazioneCattura = DestinazioneCattura(rawValue: Self.d.string(forKey: "ed.cattura2") ?? "") ?? .vassoio
        salvataggioAutomatico = Self.d.object(forKey: "ed.salvaAuto") == nil ? true : Self.d.bool(forKey: "ed.salvaAuto")
        paginaDoppia = Self.d.bool(forKey: "ed.paginaDoppia")
        scorrimentoOrizzontale = Self.d.bool(forKey: "ed.scorrOriz")
        scorrimentoContinuo = Self.d.object(forKey: "ed.scorrContinuo") == nil ? true : Self.d.bool(forKey: "ed.scorrContinuo")
        super.init()
    }

    deinit {
        for o in osservatoriUndo { NotificationCenter.default.removeObserver(o) }
    }

    static func salva<T: Encodable>(_ v: T, _ chiave: String) {
        if let dati = try? JSONEncoder().encode(v) { d.set(dati, forKey: chiave) }
    }

    static func leggi<T: Decodable>(_ chiave: String) -> T? {
        guard let dati = d.data(forKey: chiave) else { return nil }
        return try? JSONDecoder().decode(T.self, from: dati)
    }

    func salvaStrumenti() { Self.salva(strumenti, "ed.strumenti2") }

    // Selezione e modifica degli strumenti

    func seleziona(_ id: UUID?) {
        guard let id, id != selezionato else { return }
        precedente = selezionato
        selezionato = id
    }

    func modifica(_ id: UUID, _ cambio: (inout Strumento) -> Void) {
        guard let i = strumenti.firstIndex(where: { $0.id == id }) else { return }
        cambio(&strumenti[i])
    }

    func aggiungi(_ tipo: TipoStrumento) {
        let nuovo = Strumento.nuovo(tipo)
        strumenti.append(nuovo)
        seleziona(nuovo.id)
    }

    func rimuovi(at offsets: IndexSet) {
        strumenti.remove(atOffsets: offsets)
        if !strumenti.contains(where: { $0.id == selezionato }) { selezionato = strumenti.first?.id }
    }

    func sposta(from: IndexSet, to: Int) { strumenti.move(fromOffsets: from, toOffset: to) }

    /// Colore di un pallino: si applica allo strumento attivo (se ha un colore).
    func scegliColore(_ c: ColoreSalvato) {
        guard let id = corrente?.id, corrente?.tipo.haColore == true else { return }
        modifica(id) { $0.colore = c }
    }

    /// Cambia il colore del pallino i; se lo strumento attivo lo usava, lo segue.
    func cambiaPallino(_ i: Int, _ c: ColoreSalvato) {
        guard pallini.indices.contains(i) else { return }
        let vecchio = pallini[i]
        pallini[i] = c
        if let cur = corrente, cur.tipo.haColore, cur.colore.simile(a: vecchio) {
            modifica(cur.id) { $0.colore = c }
        }
    }

    func impostaNumeroPallini(_ n: Int) {
        let n = max(2, min(8, n))
        while pallini.count < n { pallini.append(.grigio) }
        if pallini.count > n { pallini.removeLast(pallini.count - n) }
    }

    weak var pdfView: PDFView?

    /// true se ci sono tratti non ancora salvati nel PDF
    var modificato = false {
        didSet { programmaSalvataggio() }
    }
    var caricando = false

    /// Salvataggio automatico (default) o solo a mano con «Salva».
    @Published var salvataggioAutomatico: Bool {
        didSet {
            Self.d.set(salvataggioAutomatico, forKey: "ed.salvaAuto")
            programmaSalvataggio()
        }
    }
    var timerSalvataggio: Timer?
    var timerRecupero: Timer?
    /// Pagine cambiate dall'ultimo diario di recupero
    var pagineSporche = Set<PDFPage>()
    /// Cambiato l'ordine o il numero delle pagine: il diario non basta, si scrive subito il PDF
    var strutturaCambiata = false
    /// Quando è iniziato il lavoro non ancora scritto nel PDF
    var primaModificaNonSalvata: Date?

    /// Salvataggio automatico del PDF: dopo questa pausa di lavoro (secondi)…
    static let pausaPrimaDelSalvataggio: TimeInterval = 20
    /// …e comunque almeno ogni tanto, anche lavorando di continuo (secondi)
    static let massimoSenzaSalvare: TimeInterval = 600
    /// Il diario di recupero si scrive al più ogni tot secondi mentre si lavora
    static let intervalloRecupero: TimeInterval = 2

    /// Salva solo se serve (cambio scheda, uscita dal documento, app in secondo piano). Solo in modalità automatica.
    func salvaSeModificato() {
        if modificato && salvataggioAutomatico { save() }
    }

    private func timerComune(_ secondi: TimeInterval, _ azione: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: secondi, repeats: false) { _ in azione() }
        RunLoop.main.add(t, forMode: .common)       // scatta anche mentre si scorre o si zooma
        return t
    }

    /// Salvataggio automatico a due livelli (vedi NotesModel+Recupero):
    /// il diario ogni pochi secondi di lavoro (non riparte a ogni tratto), il PDF dopo una pausa.
    func programmaSalvataggio() {
        guard modificato, salvataggioAutomatico else {
            timerSalvataggio?.invalidate(); timerSalvataggio = nil
            timerRecupero?.invalidate(); timerRecupero = nil
            if !modificato {
                pagineSporche.removeAll()
                strutturaCambiata = false
                primaModificaNonSalvata = nil
            }
            return
        }
        let ora = Date()
        if primaModificaNonSalvata == nil { primaModificaNonSalvata = ora }
        let limite = (primaModificaNonSalvata ?? ora).addingTimeInterval(Self.massimoSenzaSalvare).timeIntervalSince(ora)
        let attesa = strutturaCambiata ? 1 : max(1, min(Self.pausaPrimaDelSalvataggio, limite))
        timerSalvataggio?.invalidate()
        timerSalvataggio = timerComune(attesa) { [weak self] in
            guard let self, self.modificato, self.salvataggioAutomatico, !self.caricando else { return }
            self.save()
        }
        if timerRecupero == nil {
            timerRecupero = timerComune(Self.intervalloRecupero) { [weak self] in self?.scriviRecupero() }
        }
    }

    /// Qualcosa è cambiato. Senza indicare la pagina vale per quelle che si vedono (dove lavora chi scrive).
    func segnaModificato(_ pagina: PDFPage? = nil) {
        if let pagina {
            pagineSporche.insert(pagina)
        } else {
            for p in pdfView?.visiblePages ?? [] { pagineSporche.insert(p) }
            if let c = pdfView?.currentPage { pagineSporche.insert(c) }
        }
        modificato = true
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !caricando else { return }
        if let p = pagina(di: canvasView) { pagineSporche.insert(p) }
        modificato = true
    }

    /// Testi messi sulle pagine (disegnati da noi; nel PDF salvato sono annotazioni di testo)
    var testi: [PDFPage: [ElementoTesto]] = [:]
    var fileURL: URL?
    var hasSecurityScope = false
    var canvases: [PDFPage: PKCanvasView] = [:]
    var contenitori: [PDFPage: PaginaTela] = [:]
    // Tratti modificabili letti dal PDF all'apertura, in attesa che la tela della pagina esista
    var trattiSalvati: [PDFPage: PKDrawing] = [:]
    static let nomeDati = "AptDati"        // annotazione nascosta con il disegno modificabile
    static let nomeTratto = "AptTratto"    // annotazioni ink visibili (leggibili da altre app)
    static let chiaveDati = PDFAnnotationKey(rawValue: "/AptDati")

    /// Le tele Pencil sono `risoluzione` volte più grandi della pagina e rimpicciolite di altrettanto
    /// (vedi `PaginaTela`): PencilKit le disegna così con più dettagli e i tratti restano nitidi con lo zoom.
    /// Nitidi fino a uno zoom (scaleFactor del PDFView) pari a `risoluzione`; oltre, il tratto si ammorbidisce un poco.
    static let risoluzione: CGFloat = 4
    /// Ingrandimento massimo della pagina (scaleFactor del PDFView; il predefinito di PDFKit è 4)
    static let zoomMassimo: CGFloat = 6

    /// Fattore di risoluzione di una pagina: `risoluzione`, ridotto per le pagine grandi (per esempio quelle
    /// create da foto, con la misura dei pixel) così la tela non supera ~4096 punti per lato e ~12 milioni di pixel.
    static func fattore(per dimensione: CGSize, massimo: CGFloat = risoluzione) -> CGFloat {
        let w = max(dimensione.width, 1), h = max(dimensione.height, 1)
        let perLato: CGFloat = 4096 / max(w, h)
        let area: CGFloat = w * h
        let perArea: CGFloat = (CGFloat(12_000_000) / area).squareRoot()
        let k: CGFloat = min(massimo, perLato, perArea)
        return max(1, k)
    }

    /// Strumento per una tela con il fattore di risoluzione indicato (spessori moltiplicati per `scala`)
    func strumentoCorrente(scala: CGFloat) -> PKTool {
        corrente?.pkTool(scala: scala) ?? PKInkingTool(.pen, color: .black, width: 3 * scala)
    }

    func applicaStrumento() {
        for canvas in canvases.values { canvas.tool = strumentoCorrente(scala: canvas.fattoreRisoluzione) }
        aggiornaInterazione()
    }

    /// Con il lazo attivo le tele non disegnano: la Pencil è seguita dal gesto del lazo.
    func aggiornaInterazione() {
        let lazoAttivo = corrente?.tipo == .lazo
        for canvas in canvases.values { canvas.isUserInteractionEnabled = pencilMode && tela }
        let testoAttivo = corrente?.tipo == .testo
        controlloTesto?.attiva(testoAttivo)
        // Con gomma e lazo tutti i tratti stanno nella tela attiva; con le altre penne quelli più vecchi di un'immagine stanno sotto
        for p in canvases.keys { ripartisci(p) }

        // Forme con la Pencil ferma: solo con penne, evidenziatori e matite
        var disegna = false
        switch corrente?.tipo {
        case .penna?, .evidenziatore?, .matita?: disegna = true
        default: disegna = false
        }
        forme?.gesto.isEnabled = formeFerma && pencilMode && disegna

        if let cattura {
            cattura.gesto.isEnabled = pencilMode && corrente?.tipo == .catturaSchermo
            let tipiC: [UITouch.TouchType] = ditoDisegna ? [.direct, .pencil] : [.pencil]
            cattura.gesto.allowedTouchTypes = tipiC.map { NSNumber(value: $0.rawValue) }
        }

        guard let lazo else { return }
        lazo.gesto.isEnabled = pencilMode && lazoAttivo
        let tipi: [UITouch.TouchType] = ditoDisegna ? [.direct, .pencil] : [.pencil]
        lazo.gesto.allowedTouchTypes = tipi.map { NSNumber(value: $0.rawValue) }
        if !lazoAttivo { lazo.deseleziona() }
    }

    var lazo: LazoSelezione?
    var forme: FormePencil?
    var cattura: CatturaSchermo?
    var controlloTesto: TestoControllo?
    var controlloImmagini: ImmagineControllo?
    /// Immagini messe sulle pagine (nel PDF salvato sono annotazioni Stamp)
    var immagini: [PDFPage: [ElementoImmagine]] = [:]
    /// Tocco sulla pagina con lo strumento Immagine: la vista chiede da dove prendere il file
    /// Tratti più vecchi dell'immagine più recente della pagina: stanno sotto le immagini, in strati non modificabili
    /// (si ricompongono nella tela quando si usano gomma o lazo). L'ordine si decide con la data di creazione.
    var sotto: [PDFPage: [PKStroke]] = [:]

    var unificato: Bool { corrente?.tipo == .gomma || corrente?.tipo == .lazo }

    func tuttiITratti(_ page: PDFPage) -> [PKStroke] {
        (sotto[page] ?? []) + (canvases[page]?.drawing.strokes ?? [])
    }

    func pagina(di tela: PKCanvasView) -> PDFPage? {
        canvases.first { $0.value === tela }?.key
    }

    /// Divide i tratti della pagina tra «sotto le immagini» (strati) e «sopra» (tela con cui si disegna).
    /// Cambiando la divisione la cronologia di annulla si azzera (a meno di `pulisciUndo: false`).
    func ripartisci(_ page: PDFPage, pulisciUndo: Bool = true) {
        ProvaContatori.ripartisci += 1
        guard let canvas = canvases[page] else { return }
        let immagini = self.immagini[page] ?? []
        let testi = self.testi[page] ?? []
        let vecchi = sotto[page] ?? []
        if immagini.isEmpty && testi.isEmpty && vecchi.isEmpty && !pulisciUndo { controlloImmagini?.ridisegna(page); return }
        let tutti = vecchi + canvas.drawing.strokes
        var bassi: [PKStroke] = []
        var alti = tutti
        if !unificato, let limite = (immagini.map({ $0.creazione }) + testi.map({ $0.creazione })).max() {
            bassi = tutti.filter { $0.path.creationDate < limite }
            alti = tutti.filter { $0.path.creationDate >= limite }
        }
        if bassi.count != vecchi.count {
            caricando = true
            canvas.drawing = PKDrawing(strokes: alti)
            caricando = false
            sotto[page] = bassi
            if pulisciUndo { pulisciCronologia() }
        }
        controlloImmagini?.ridisegna(page)
    }

    @Published var chiediImmagine = false
    var destinazioneImmagine: (PDFPage, CGPoint)?

    /// Da dove prendere l'immagine (richiesta dal pannello dello strumento o dalla finestra sulla pagina)
    @Published var origine: OrigineImmagine?

    /// «Aggiungi pagina» da File o da Immagini: dopo quale pagina vanno le nuove (nil = in fondo al documento)
    var inserisciDopo: Int?

    /// Dal pannello dello strumento: l'immagine va al centro della pagina visibile
    func avvia(_ o: OrigineImmagine) {
        guard let pagina = pdfView?.currentPage ?? document?.page(at: 0) else { return }
        inserisciDopo = nil
        let box = pagina.bounds(for: .cropBox)
        destinazioneImmagine = (pagina, CGPoint(x: box.midX, y: box.midY))
        origine = o
    }

    /// Pagine di un documento o di una scansione: una immagine per pagina, leggermente scalate in cascata
    @discardableResult
    func inserisciDocumento(_ pagine: [Data]) -> Bool {
        guard let (p, pt) = destinazioneImmagine, let c = controlloImmagini else { return false }
        var ok = false
        for (i, d) in pagine.enumerated() {
            let punto = CGPoint(x: pt.x + CGFloat(i) * 18, y: pt.y - CGFloat(i) * 18)
            if c.inserisci(d, pagina: p, punto: punto, documento: true) { ok = true }
        }
        if ok { destinazioneImmagine = nil } else { message = "Nessuna pagina leggibile." }
        return ok
    }

    func richiediImmagine(pagina: PDFPage, punto: CGPoint) {
        destinazioneImmagine = (pagina, punto)
        chiediImmagine = true
    }

    /// Il file scelto (foto o file) arriva qui; false se non è un'immagine leggibile
    @discardableResult
    func inserisciImmagine(dati: Data) -> Bool {
        guard let (p, pt) = destinazioneImmagine, let c = controlloImmagini else { return false }
        let ok = c.inserisci(dati, pagina: p, punto: pt)
        if ok { destinazioneImmagine = nil } else { message = "Il file scelto non è un'immagine leggibile." }
        return ok
    }
    /// Cattura messa nel foglio: immagine alla stessa dimensione che aveva sullo schermo
    func inserisciCattura(_ dati: Data, pagina: PDFPage, punto: CGPoint, larghezza: CGFloat) {
        if controlloImmagini?.inserisci(dati, pagina: pagina, punto: punto, larghezza: larghezza) != true {
            avviso("Impossibile mettere la cattura nel foglio.")
        }
    }

    /// Dal vassoio: l'immagine va al centro di ciò che si vede del foglio attuale (e resta nel vassoio)
    func inserisciDaVassoio(_ dati: Data, larghezzaSchermo: CGFloat?) {
        guard let v = pdfView, let c = controlloImmagini else { return }
        let centro = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        guard let pagina = v.page(for: centro, nearest: true) ?? v.currentPage else { return }
        let punto = v.convert(centro, to: pagina)
        // Stessa grandezza che aveva sullo schermo quando è stata catturata (allo zoom di adesso)
        let larghezza = larghezzaSchermo.map { $0 / max(v.scaleFactor, 0.01) }
        if !c.inserisci(dati, pagina: pagina, punto: punto, larghezza: larghezza) { avviso("Immagine non leggibile.") }
    }

    /// Messaggio breve sopra il foglio, sparisce da solo
    func avviso(_ testo: String) {
        message = testo
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.message == testo { self?.message = "" }
        }
    }

    /// Testo in scrittura (finestra con la nostra tastiera)
    @Published var bozzaTesto: BozzaTesto?

    func confermaTesto(_ b: BozzaTesto, _ t: String, corpo: CGFloat) {
        var b = b
        b.corpo = corpo
        controlloTesto?.conferma(b, testo: t)
        bozzaTesto = nil
    }

    /// Penna, evidenziatore, matita e gomma disegnano sulla tela; lazo e testo no.
    var tela: Bool { corrente?.tipo != .lazo && corrente?.tipo != .testo && corrente?.tipo != .immagine && corrente?.tipo != .catturaSchermo }

    // Lo zoom cambia la nitidezza del testo (disegnato da noi): si ridisegna a zoom fermo
    var attesaZoom: Timer?
}
