// Editor: salvataggio e conversione tratti Pencil -> annotazioni PDF
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

extension NotesModel {
    // MARK: Salvataggio
    //
    // Regola: il thread principale non serializza mai il PDF e non aspetta mai la scrittura (niente `sync`).
    // Qui, sul principale, si prepara soltanto l'elenco delle annotazioni da scrivere (leggero); la serializzazione
    // del PDF e la scrittura del file avvengono sulla coda `codaSalvataggio`, dentro un «lavoro in sottofondo» di iPadOS
    // (così continuano anche se l'app passa in secondo piano). Chi deve aspettare la fine (aprire o spostare lo stesso
    // file) usa `dopoScrittura(di:)`, che non blocca nulla.
    //
    // Due modi di scrivere:
    //  - PER AGGIUNTA (file grandi, già scritti da PDFKit): si aggiungono in coda al file solo le annotazioni delle pagine
    //    cambiate (PDFAggiunta.swift). Costa pochi MB, non qualche centinaio.
    //  - COMPLETA (file piccoli, pagine aggiunte/tolte/spostate/allargate, file non adatto, ripiego dopo un errore):
    //    si riscrive tutto il PDF, come prima.

    /// Salvataggio chiesto a mano («Salva», conferma di uscita): scrive anche se non risulta modificato.
    /// `completamento(true)` parte sul thread principale a scrittura finita; `false` se è fallita.
    func salva(completamento: ((Bool) -> Void)? = nil) {
        avviaSalvataggio(forzato: true, completamento: completamento)
    }

    /// Dimensione e data di modifica (esatta) del file
    static func firmaPrecisa(_ url: URL) -> (dimensione: Int, data: Double)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let s = (a[.size] as? NSNumber)?.intValue,
              let m = a[.modificationDate] as? Date else { return nil }
        return (s, m.timeIntervalSince1970)
    }

    /// Quaderno e prima pagina, come vanno scritti nel file
    func metaCorrente(_ doc: PDFDocument) -> String {
        var s = quaderno?.codice ?? ""
        if let u = paginaUno { s += "|" + String(doc.index(for: u)) }
        return s
    }

    /// Dove si tiene il segnalino di una scrittura per aggiunta in corso (serve a tagliare la coda incompleta se l'app si chiude nel mezzo)
    static func marcatoreAggiunta(per url: URL) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aggiunte", isDirectory: true)
        let nome = Self.cartellaRecupero(per: url).lastPathComponent
        return base.appendingPathComponent(nome + ".txt")
    }

    /// Le pagine da scrivere se si può salvare per aggiunta; nil se serve la scrittura completa
    private func pagineDaAggiungere(_ document: PDFDocument, url: URL, struttura: Bool, meta: String,
                                    sporche: Set<PDFPage>) -> [Int]? {
        guard !scritturaCompleta, !aggiuntaVietata, !struttura, meta == metaFile,
              let f = firmaFile, f.dimensione >= Self.sogliaAggiunta,
              let ora = Self.firmaPrecisa(url), ora.dimensione == f.dimensione, abs(ora.data - f.data) < 0.002 else { return nil }
        var indici: [Int] = []
        for p in sporche {
            let i = document.index(for: p)
            if i == NSNotFound { return nil }
            indici.append(i)
        }
        if indici.isEmpty { return modificato ? nil : [] }
        return indici.sorted()
    }

    /// Avvia il salvataggio in sottofondo. Se ne è già in corso uno, questo parte appena finisce.
    func avviaSalvataggio(forzato: Bool = false, completamento: ((Bool) -> Void)? = nil) {
        guard let document, let url = fileURL else {
            if forzato { message = "Nessun PDF aperto." }
            completamento?(false)
            return
        }
        // Salvare solo se serve: niente scritture inutili (il disco ha un limite di scritture al giorno)
        guard forzato || modificato else {
            completamento?(true)
            return
        }

        // Il lavoro è nel diario anche se il salvataggio non dovesse finire (tempo scaduto, app chiusa, errore)
        scriviRecupero(forza: true)

        // Va letto prima: con `modificato = false` queste cose si azzerano
        let struttura = strutturaCambiata
        let sporche = pagineDaSalvare
        let meta = metaCorrente(document)
        let indici = pagineDaAggiungere(document, url: url, struttura: struttura, meta: meta, sporche: sporche)
        if let indici, indici.isEmpty {
            completamento?(true)            // niente è cambiato dall'ultima scrittura
            return
        }

        let aggiunte = costruisciAnnotazioni(document, soloIndici: indici.map { Set($0) })
        var lavori: [(Int, PDFAnnotation)] = []
        for (page, a) in aggiunte {
            let i = document.index(for: page)
            if i != NSNotFound { lavori.append((i, a)) }
        }
        modificato = false                      // da qui in poi ogni nuova modifica conta come successiva a questo salvataggio
        primaModificaNonSalvata = nil
        // L'elenco da scrivere si prepara SUBITO, anche se un altro salvataggio è in corso: se nel frattempo si esce dal PDF
        // (il documento si svuota) la scrittura in coda ha già tutto. Prima si metteva in coda la richiesta e, a coda sbloccata,
        // il documento era già chiuso: immagini e tratti aggiunti durante un salvataggio lungo andavano persi.
        scriviIstantanea(document: document, url: url, lavori: lavori, struttura: struttura, indici: indici, meta: meta,
                         sporche: sporche, completamento: completamento)
    }

    /// Scrive un'istantanea già preparata; se un'altra scrittura è in corso, parte appena finisce.
    private func scriviIstantanea(document: PDFDocument, url: URL, lavori: [(Int, PDFAnnotation)], struttura: Bool,
                                  indici: [Int]?, meta: String, sporche: Set<PDFPage>,
                                  completamento: ((Bool) -> Void)?) {
        if salvataggioInCorso {
            salvataggiInAttesa.append { [weak self] in
                self?.scriviIstantanea(document: document, url: url, lavori: lavori, struttura: struttura, indici: indici,
                                       meta: meta, sporche: sporche, completamento: completamento)
            }
            return
        }
        salvataggioInCorso = true
        let stato = StatoScrittura()
        scritturaCorrente = stato
        Self.iniziaScrittura(url)
        // Il permesso di scrivere nella cartella resta valido anche se nel frattempo il documento viene chiuso
        let permesso = url.startAccessingSecurityScopedResource()
        var compito = UIBackgroundTaskIdentifier.invalid
        compito = UIApplication.shared.beginBackgroundTask(withName: "Salvataggio PDF") {
            // Tempo scaduto: iPadOS sta per sospendere l'app, si chiude il lavoro (il diario di recupero resta)
            if compito != .invalid { UIApplication.shared.endBackgroundTask(compito); compito = .invalid }
        }
        let nImm = immagini.values.reduce(0) { $0 + $1.count }
        let mbImm = immagini.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.dati.count } } / 1_048_576
        let modo = indici == nil ? "completo" : "per aggiunta (\(indici?.count ?? 0) pagine)"
        Diagnostica.nota("salva-inizio", "\(modo): \(document.pageCount) pagine, \(lavori.count) annotazioni da scrivere, \(nImm) immagini (\(mbImm) MB)")
        Self.codaSalvataggio.async { [weak self] in
            var errore: String?
            autoreleasepool {
                if let indici {
                    errore = Self.scriviAggiunta(document: document, lavori: lavori, indici: indici, url: url, stato: stato)
                } else {
                    errore = Self.scrivi(document: document, lavori: lavori, url: url, stato: stato)
                }
            }
            Diagnostica.nota("salva-fine", errore == nil ? "ok" : "ERRORE")
            DispatchQueue.main.async {
                if compito != .invalid { UIApplication.shared.endBackgroundTask(compito); compito = .invalid }
                if permesso { url.stopAccessingSecurityScopedResource() }
                self?.finisciSalvataggio(errore: errore, struttura: struttura, url: url, document: document,
                                         stato: stato, aggiunta: indici != nil, meta: meta, sporche: sporche,
                                         completamento: completamento)
                Self.finisciScrittura(url)       // per ultimo: chi aspettava il file lo trova scritto
            }
        }
    }

    /// Compatibilità con il timer: parte solo se non c'è già un salvataggio in corso
    func salvaInSottofondo() {
        guard !salvataggioInCorso else { return }
        avviaSalvataggio()
    }

    /// Scrittura per aggiunta, fuori dal thread principale: PDFKit scrive un piccolo PDF con le sole annotazioni nuove delle pagine
    /// cambiate, che `PDFAggiunta` copia in fondo al file. Ritorna il motivo se non è riuscita (il file resta com'era).
    private static func scriviAggiunta(document: PDFDocument, lavori: [(Int, PDFAnnotation)], indici: [Int], url: URL,
                                       stato: StatoScrittura) -> String? {
        let fm = FileManager.default
        let lavoro = fm.temporaryDirectory.appendingPathComponent("salva-" + UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: lavoro, withIntermediateDirectories: true) } catch {
            return "Non riesco a preparare la cartella di lavoro: \(error.localizedDescription)"
        }
        defer { try? fm.removeItem(at: lavoro) }

        var perPagina: [Int: [PDFAnnotation]] = [:]
        for (i, a) in lavori { perPagina[i, default: []].append(a) }
        var attese: [Int: Int] = [:]
        let mini = PDFDocument()
        for (k, idx) in indici.enumerated() {
            guard let pagina = document.page(at: idx) else { return "Pagina \(idx) non trovata." }
            let box = pagina.bounds(for: .cropBox)
            let nuova = PDFPage()
            nuova.setBounds(box, for: .mediaBox)
            nuova.setBounds(box, for: .cropBox)
            let elenco = perPagina[idx] ?? []
            for a in elenco { nuova.addAnnotation(a) }
            attese[idx] = elenco.count
            mini.insert(nuova, at: k)
        }
        let miniURL = lavoro.appendingPathComponent("mini.pdf")
        let miniOk: Bool = autoreleasepool { mini.write(to: miniURL) }
        guard miniOk else { return "Impossibile preparare le annotazioni." }

        let totale = document.pageCount
        let marcatore = marcatoreAggiunta(per: url)
        var coordError: NSError?
        var motivo: String?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { scrivibile in
            if stato.annullata || !fm.fileExists(atPath: scrivibile.path) {
                stato.annulla()          // il file è stato eliminato o spostato: non va ricreato
                return
            }
            do {
                let e = try PDFAggiunta.applica(url: scrivibile, miniatura: miniURL, pagine: indici, marcatore: marcatore) {
                    // Si rilegge il file appena scritto: pagine e annotazioni dell'app devono essere quelle attese
                    guard let d = PDFDocument(url: scrivibile), d.pageCount == totale else { return false }
                    for idx in indici {
                        guard let p = d.page(at: idx) else { return false }
                        var n = 0
                        for a in p.annotations where (a.userName ?? "").hasPrefix("Apt") { n += 1 }
                        if n != (attese[idx] ?? 0) { return false }
                    }
                    return true
                }
                Diagnostica.nota("salva-aggiunta", "\(indici.count) pagine, \(e.byteAggiunti) byte aggiunti in coda, \(e.oggetti) oggetti, sezioni xref \(e.sezioni)")
            } catch {
                motivo = "\(error)"
            }
        }
        if stato.annullata { return nil }
        if let coordError { return "Errore di scrittura: \(coordError.localizedDescription)" }
        return motivo
    }

    /// Lavoro pesante, fuori dal thread principale. Ritorna il messaggio d'errore, o nil se tutto è andato bene.
    private static func scrivi(document: PDFDocument, lavori: [(Int, PDFAnnotation)], url: URL, stato: StatoScrittura) -> String? {
        AnnotazioneTratti.disegnati = 0
        let fm = FileManager.default
        // I passaggi intermedi vanno su file temporanei, non in memoria: con un PDF da centinaia di MB due copie intere in
        // memoria portavano l'app oltre il limite di iPadOS (rapporto di diagnosi del 17/10: 539 MB, chiusura a 3 GB).
        let lavoro = fm.temporaryDirectory.appendingPathComponent("salva-" + UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: lavoro, withIntermediateDirectories: true) } catch {
            return "Non riesco a preparare la cartella di lavoro: \(error.localizedDescription)"
        }
        defer { try? fm.removeItem(at: lavoro) }
        let originale = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        let base = lavoro.appendingPathComponent("base.pdf")
        let baseOk: Bool = autoreleasepool { document.write(to: base) }
        guard baseOk else { return "Impossibile generare il PDF." }
        let dimBase = ((try? base.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) / 1_048_576
        Diagnostica.nota("salva-fase", "PDF di base scritto su disco (\(dimBase) MB; il file originale era \(originale / 1_048_576) MB), \(lavori.count) annotazioni da aggiungere")

        var pronto = base
        // Le annotazioni dei tratti si aggiungono a una copia: il documento che si vede non viene toccato
        if !lavori.isEmpty {
            let finale = lavoro.appendingPathComponent("finale.pdf")
            let finaleOk: Bool = autoreleasepool {
                guard let copia = PDFDocument(url: base) else { return false }
                for (i, a) in lavori {
                    if let p = copia.page(at: i) { p.addAnnotation(a) }
                }
                Diagnostica.nota("salva-fase", "annotazioni aggiunte alla copia, scrivo il PDF finale")
                return copia.write(to: finale)
            }
            guard finaleOk else { return "Impossibile generare il PDF." }
            try? fm.removeItem(at: base)         // serve spazio e memoria di cache: il passaggio intermedio non serve più
            pronto = finale
            let dimFinale = ((try? finale.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) / 1_048_576
            Diagnostica.nota("salva-fase", "PDF finale scritto su disco (\(dimFinale) MB), tratti disegnati \(AnnotazioneTratti.disegnati)")
        }
        // Il file è stato eliminato o spostato nel frattempo: non va ricreato
        if stato.annullata || !fm.fileExists(atPath: url.path) { stato.annulla(); return nil }
        var coordError: NSError?
        var writeError: Error?
        let daSostituire = pronto
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                // Prima si sostituisce il file in un colpo solo (un file interrotto a metà non può rovinare il PDF);
                // se la cartella non lo permette, si copia a pezzi senza caricare tutto in memoria
                do {
                    _ = try fm.replaceItemAt(writeURL, withItemAt: daSostituire)
                } catch {
                    let dati = try Data(contentsOf: daSostituire, options: .mappedIfSafe)
                    try dati.write(to: writeURL)
                }
            } catch { writeError = error }
        }
        if let err = coordError ?? (writeError as NSError?) { return "Errore di scrittura: \(err.localizedDescription)" }
        return nil
    }

    private func finisciSalvataggio(errore: String?, struttura: Bool, url: URL, document scritto: PDFDocument,
                                    stato: StatoScrittura, aggiunta: Bool, meta: String, sporche: Set<PDFPage>,
                                    completamento: ((Bool) -> Void)?) {
        salvataggioInCorso = false
        scritturaCorrente = nil
        let attese = salvataggiInAttesa
        salvataggiInAttesa = []
        // Il documento può essere stato chiuso (o sostituito) mentre si scriveva: allora non si tocca lo stato di quello nuovo
        let ancora = document === scritto && fileURL?.standardizedFileURL == url.standardizedFileURL
        if stato.annullata {
            completamento?(false)          // file eliminato: niente da salvare
        } else if let errore, aggiunta {
            // La scrittura per aggiunta non è riuscita (il file è com'era): si ripiega sulla scrittura completa.
            // Se il documento è già chiuso il lavoro resta nel diario di recupero e torna alla riapertura.
            Diagnostica.nota("salva-aggiunta-ripiego", errore)
            if ancora {
                aggiuntaVietata = true
                pagineDaSalvare.formUnion(sporche)
                pagineSporche.formUnion(sporche)
                if struttura { strutturaCambiata = true }
                modificato = true
                DispatchQueue.main.async { [weak self] in
                    self?.avviaSalvataggio(forzato: true, completamento: completamento)
                }
            } else {
                completamento?(false)
            }
        } else if let errore {
            if ancora {
                message = errore
                if struttura { strutturaCambiata = true }
                pagineDaSalvare.formUnion(sporche)
                pagineSporche.formUnion(sporche)
                modificato = true               // non è stato scritto: resta da salvare
            }
            completamento?(false)
        } else {
            if ancora {
                // Il file contiene ora tutto ciò che c'era all'inizio del salvataggio: il vecchio diario non serve più
                // (e non va tenuto: ridarebbe pagine più vecchie di quelle del file).
                cancellaRecupero()
                firmaFile = Self.firmaPrecisa(url)
                metaFile = meta
                if !aggiunta { scritturaCompleta = false }
                if modificato {
                    // Lavoro fatto mentre si scriveva: va nel diario, contro il file com'è adesso
                    pagineSporche.formUnion(pagineDaSalvare)
                    scriviRecupero(forza: true)
                }
                if struttura { sincro?.struttura(salvataDa: self) }
            } else {
                cancellaRecupero(url: url)
            }
            completamento?(true)
        }
        for a in attese { a() }
        if ancora, modificato { programmaSalvataggio() }
    }

    // MARK: Scritture in corso (per aspettare senza bloccare)

    /// Chiave del file e quante scritture lo stanno riguardando, con chi aspetta la fine
    private static var scritture: [String: (quante: Int, attese: [() -> Void])] = [:]

    private static func chiave(_ url: URL) -> String { url.standardizedFileURL.path }

    static func iniziaScrittura(_ url: URL) {
        let k = chiave(url)
        var v = scritture[k] ?? (0, [])
        v.quante += 1
        scritture[k] = v
    }

    static func finisciScrittura(_ url: URL) {
        let k = chiave(url)
        guard var v = scritture[k] else { return }
        v.quante -= 1
        if v.quante > 0 { scritture[k] = v; return }
        scritture[k] = nil
        for a in v.attese { a() }
    }

    static func inScrittura(_ url: URL) -> Bool { scritture[chiave(url)] != nil }

    /// Esegue `blocco` subito se il file non si sta scrivendo, altrimenti appena la scrittura finisce (sempre sul thread principale)
    static func dopoScrittura(di url: URL, _ blocco: @escaping () -> Void) {
        let k = chiave(url)
        guard var v = scritture[k] else { blocco(); return }
        v.attese.append(blocco)
        scritture[k] = v
    }

    /// Costruisce (senza aggiungerle alle pagine) tutte le annotazioni da scrivere nel PDF
    /// `soloIndici`: solo queste pagine (salvataggio per aggiunta); nil = tutte
    private func costruisciAnnotazioni(_ document: PDFDocument, soloIndici: Set<Int>? = nil) -> [(PDFPage, PDFAnnotation)] {
        // Per ogni pagina: tratti visibili (ink) + disegno modificabile in un'annotazione nascosta
        var aggiunte: [(PDFPage, PDFAnnotation)] = []
        for i in 0..<document.pageCount {
            if let soloIndici, !soloIndici.contains(i) { continue }
            guard let page = document.page(at: i) else { continue }
            let box = page.bounds(for: .cropBox)
            var disegno: PKDrawing?
            if let canvas = canvases[page], canvas.bounds.width > 0 {
                let f = box.width / canvas.bounds.width
                // tutti i tratti: quelli sotto le immagini e quelli della tela
                disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
            } else if let ancora = trattiSalvati[page] {
                disegno = ancora          // pagina mai mostrata: i tratti letti restano com'erano
            }

            // Tratti e immagini nell'ordine di creazione: gli altri lettori mostrano gli stessi livelli
            var voci: [(Date, PDFAnnotation)] = []
            if let d = disegno, !d.strokes.isEmpty {
                let confini = (immagini[page] ?? []).map { $0.creazione } + (testi[page] ?? []).map { $0.creazione }
                voci += creaAnnotazioni(from: d, canvasSize: box.size, page: page, confini: confini)
            }
            for e in immagini[page] ?? [] { voci.append((e.creazione, ImmagineControllo.annotazione(da: e, origine: box.origin))) }
            for e in testi[page] ?? [] { voci.append((e.creazione, TestoControllo.annotazione(da: e, origine: box.origin))) }
            voci.sort { $0.0 < $1.0 }
            for (_, a) in voci {
                aggiunte.append((page, a))
            }

            if let ext = annotazioneEstensione(per: page, box: box) {
                aggiunte.append((page, ext))
            }

            if let m = modelli[page] {
                let a = Self.annotazioneNascosta(nome: Self.nomeModello, chiave: Self.chiaveModello, valore: m.codice, box: box)
                aggiunte.append((page, a))
            }
            if i == 0, let q = quaderno {
                let a = Self.annotazioneNascosta(nome: Self.nomeQuaderno, chiave: Self.chiaveQuaderno, valore: q.codice, box: box)
                aggiunte.append((page, a))
            }
            if paginaUno === page {
                let a = Self.annotazioneNascosta(nome: Self.nomePrima, chiave: Self.chiavePrima, valore: "1", box: box)
                aggiunte.append((page, a))
            }

            guard let d = disegno, !d.strokes.isEmpty else { continue }
            let dati = PDFAnnotation(bounds: CGRect(x: box.minX, y: box.minY, width: 1, height: 1), forType: .square, withProperties: nil)
            dati.userName = Self.nomeDati
            dati.shouldDisplay = false
            dati.shouldPrint = false
            _ = dati.setValue(d.dataRepresentation().base64EncodedString(), forAnnotationKey: Self.chiaveDati)
            aggiunte.append((page, dati))
        }

        return aggiunte
    }

    // MARK: Conversione tratti Pencil -> annotazioni PDF (ink)

    /// I tratti diventano immagini trasparenti disegnate esattamente come le vede PencilKit (stesso spessore, stessi colori):
    /// le annotazioni «ink» di PDF non possono riprodurre lo spessore variabile della penna e uscivano più grosse.
    /// `confini` = date di creazione di immagini e testi della pagina: i tratti tra due confini formano un'immagine,
    /// così i livelli (tratti sotto/sopra le immagini) restano quelli scritti.
    func creaAnnotazioni(from drawing: PKDrawing, canvasSize: CGSize, page: PDFPage,
                         confini: [Date] = [], pixelPerPunto: CGFloat = 3) -> [(Date, PDFAnnotation)] {
        let pageBounds = page.bounds(for: .cropBox)
        let size = canvasSize.width > 0 ? canvasSize : pageBounds.size
        let scale = pageBounds.width / size.width
        let ordinati = confini.sorted()

        // Un gruppo di tratti per ogni intervallo tra due confini
        // Gli evidenziatori stanno in immagini a parte, fuse con la pagina (multiply) come nell'app: le lettere restano nere
        var gruppi: [Int: [PKStroke]] = [:]
        for t in drawing.strokes {
            let n = ordinati.filter { $0 < t.path.creationDate }.count
            let evid = Self.eEvidenziatore(t)
            gruppi[n * 2 + (evid ? 1 : 0), default: []].append(t)
        }

        var create: [(Date, PDFAnnotation)] = []
        let paginaDisegno = CGRect(origin: .zero, size: size)
        for n in gruppi.keys.sorted() {
            let tratti = gruppi[n] ?? []
            let d = PKDrawing(strokes: tratti)
            let r = d.bounds.insetBy(dx: -4, dy: -4).intersection(paginaDisegno).integral
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            let px = min(pixelPerPunto / max(scale, 0.0001), sqrt(12_000_000 / (r.width * r.height)))

            let bounds = CGRect(x: pageBounds.minX + r.minX * scale, y: pageBounds.maxY - r.maxY * scale,
                                width: r.width * scale, height: r.height * scale)
            let annotation = AnnotazioneTratti(bounds: bounds, forType: .stamp, withProperties: nil)
            // L'immagine non si fa qui: si disegna al momento di scrivere il PDF (una alla volta). Prima tutte le immagini
            // di tutte le pagine restavano in memoria insieme (decine di MB l'una): con molte pagine scritte il salvataggio
            // automatico faceva chiudere l'app.
            annotation.disegno = d
            annotation.rettangolo = r
            annotation.pixel = px
            annotation.fonde = (n % 2 == 1)
            annotation.userName = Self.nomeTratto
            create.append((tratti.map { $0.path.creationDate }.min() ?? Date(), annotation))
        }
        return create
    }
}

/// Stato di un salvataggio in corso, condiviso tra il thread principale e la coda di scrittura
final class StatoScrittura {
    private let blocco = NSLock()
    private var fermata = false
    var annullata: Bool { blocco.lock(); defer { blocco.unlock() }; return fermata }
    /// Il file sparisce (eliminato o spostato): la scrittura non deve ricrearlo
    func annulla() { blocco.lock(); fermata = true; blocco.unlock() }
}

/// Annotazione Stamp che disegna l'immagine dei tratti nel suo riquadro: PDFKit la salva nel file con il suo aspetto.
final class AnnotazioneTratti: PDFAnnotation {
    var disegno: PKDrawing?        // i tratti (leggeri); l'immagine si crea solo quando serve disegnarla
    var rettangolo: CGRect = .zero // la zona del disegno da rendere, in punti
    var pixel: CGFloat = 3         // pixel per punto
    var fonde = false          // evidenziatore: si mescola al colore della pagina (multiply)
    /// Quanti tratti sono stati disegnati nel salvataggio in corso (solo per la diagnosi; si scrive da un solo thread)
    static var disegnati = 0

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let d = disegno, rettangolo.width > 0, rettangolo.height > 0 else { return }
        // Ogni immagine (decine di MB) va liberata subito dopo l'uso: senza questo gestore le immagini di TUTTI i tratti
        // restavano in memoria fino alla fine della scrittura del PDF, e iPadOS chiudeva l'app (rapporto di diagnosi del 17/10).
        autoreleasepool {
            var immagine: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                immagine = d.image(from: rettangolo, scale: pixel)
            }
            guard let cg = immagine?.cgImage else { return }
            context.saveGState()
            if fonde { context.setBlendMode(.multiply) }
            context.interpolationQuality = .high
            context.draw(cg, in: bounds)
            context.restoreGState()
        }
        Self.disegnati += 1
        if Self.disegnati % 10 == 0 { Diagnostica.nota("salva-tratti", "disegnati \(Self.disegnati)") }
    }
}
