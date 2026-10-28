// Editor: apertura, tele per pagina, lettura tratti, aggiungi pagine, scarta
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

extension NotesModel {
    // MARK: Apertura

    func open(url: URL) {
        closeCurrent()
        // Se il file si sta ancora scrivendo (salvataggio in sottofondo, anche dall'altro riquadro), si apre appena ha finito: senza bloccare niente
        if Self.inScrittura(url) {
            inAttesaScrittura = true
            Self.dopoScrittura(di: url) { [weak self] in self?.apriFile(url: url) }
            return
        }
        apriFile(url: url)
    }

    private func apriFile(url: URL) {
        guard document == nil, fileURL == nil else { return }       // nel frattempo è stato aperto altro: la richiesta è superata
        inAttesaScrittura = false

        // Se il file sta dentro la cartella radice già autorizzata, la richiesta può
        // restituire false pur avendo accesso: si prosegue comunque e si prova a leggere.
        hasSecurityScope = url.startAccessingSecurityScopedResource()
        fileURL = url
        // Una scrittura per aggiunta interrotta (app chiusa di colpo) lascia una coda incompleta: si taglia prima di leggere
        PDFAggiunta.ripristina(url: url, marcatore: Self.marcatoreAggiunta(per: url))

        var coordError: NSError?
        var readError: Error?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            // Mappato: un PDF da 450 MB non occupa 450 MB di memoria (il rapporto del 26/10 mostrava la chiusura a ~3 GB aprendo due volte lo stesso file)
            do { data = try Data(contentsOf: readURL, options: .alwaysMapped) } catch { readError = error }
        }

        if let err = coordError ?? (readError as NSError?) {
            message = "Errore di lettura: \(err.localizedDescription)"
            closeCurrent()
            return
        }
        guard let data, let doc = PDFDocument(data: data) else {
            message = "Il file non è un PDF leggibile."
            closeCurrent()
            return
        }

        fileName = url.lastPathComponent
        lettureFallite = 0
        estensioniVecchie = [:]
        let uniformate = uniformaPagine(in: doc)       // tutte le pagine della stessa larghezza (nel file cambia solo al primo salvataggio)
        caricaTratti(da: doc)
        var riparate = riparaEstensioniVecchie(in: doc)
        riparate += riconciliaEstensioni(in: doc)
        estensione = leggiEstensione(doc)
        let recuperate = ripristinaRecupero(in: doc, url: url)      // modifiche non ancora scritte nel PDF (app chiusa di colpo)
        document = doc
        firmaFile = Self.firmaPrecisa(url)
        metaFile = metaCorrente(doc)
        scritturaCompleta = uniformate > 0
        if let c = daConservare {
            daConservare = nil
            for (i, l) in c.immagini { if let p = doc.page(at: i) { immagini[p] = l; pagineSporche.insert(p); pagineDaSalvare.insert(p) } }
            for (i, l) in c.testi { if let p = doc.page(at: i) { testi[p] = l; pagineSporche.insert(p); pagineDaSalvare.insert(p) } }
            if !c.immagini.isEmpty || !c.testi.isEmpty { modificato = true }
        }
        let nImm = immagini.values.reduce(0) { $0 + $1.count }
        notaEstensioni("apertura")
        Diagnostica.nota("documento-aperto", "\(doc.pageCount) pagine, recuperate \(recuperate), immagini lette \(nImm), NON leggibili \(lettureFallite)")
        if lettureFallite > 0 { avviso("\(lettureFallite) immagini nel file non si leggono.") }
        message = ""
        versionePagine += 1
        if uniformate > 0 && recuperate == 0 { avviso("Pagine portate alla stessa larghezza.") }
        if !riparate.isEmpty {
            for p in riparate { pagineSporche.insert(p); pagineDaSalvare.insert(p) }
            strutturaCambiata = true
            scritturaCompleta = true
            modificato = true
            avviso("Ho ripristinato la misura delle pagine allargate di questo file (le foto rimaste indietro: tre puntini → «Sposta le foto»).")
        }
        if recuperate > 0 {
            modificato = true                                        // verranno scritte nel PDF a breve
            avviso("Recuperate le modifiche non salvate.")
        }
        alleggerisciImmagini()
    }

    func close() {
        closeCurrent()
    }

    func closeCurrent() {
        inAttesaScrittura = false
        lazo?.deseleziona()
        controlloImmagini?.resetta()
        controlloTesto?.resetta()
        controlloTesto?.livelli.removeAll()
        controlloImmagini?.livelli.removeAll()
        pulisciCronologia(motivo: "documento chiuso")   // la cronologia di annulla riguarda solo il documento aperto
        undoPagine.removeAll()
        ultimiTratti.removeAll()
        voceInCorso.removeAll()
        paginaLavoro = nil
        pagineScritte.removeAll()
        if hasSecurityScope, let u = fileURL { u.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
        fileURL = nil
        canvases.removeAll()
        contenitori.removeAll()
        fuoriVista.removeAll()
        ultimaPaginaModificata = nil
        pagineDaSincro.removeAll()
        trattiSalvati.removeAll()
        testi.removeAll()
        immagini.removeAll()
        sotto.removeAll()
        originali.removeAll()
        modelli.removeAll()
        quaderno = nil
        paginaUno = nil
        estensione = Estensione(lati: .nessuno, misura: estensione.misura)
        destinazioneImmagine = nil
        document = nil
        fileName = ""
        modificato = false
        pagineDaSalvare.removeAll()
        scritturaCompleta = false
        aggiuntaVietata = false
        firmaFile = nil
        metaFile = ""
        griglia = false
    }

    // MARK: Overlay Pencil per ogni pagina

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let esistente = contenitori[page] { return esistente }

        ProvaContatori.overlayCreati += 1
        let misura = page.bounds(for: .cropBox).size
        let contenitore = PaginaTela(dimensione: misura, k: Self.fattore(per: misura, massimo: min(risoluzioneConsentita, risoluzionePerZoom)))
        let canvas = contenitore.canvas
        canvas.delegate = self
        canvas.gestoreAnnulla = gestoreUndo(per: page)         // annulla e ripeti di questa pagina
        canvas.drawingPolicy = ditoDisegna ? .anyInput : .pencilOnly   // di base il dito scorre/zooma il PDF, la Pencil disegna
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false              // così i gesti del dito arrivano al PDF
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = strumentoCorrente(scala: canvas.fattoreRisoluzione)
        canvas.isUserInteractionEnabled = pencilMode && tela
        contenitori[page] = contenitore
        canvases[page] = canvas
        return contenitore
    }

    func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        fuoriVista.insert(page)
    }

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = (overlayView as? PaginaTela)?.canvas else { return }
        ProvaContatori.overlayMostrati += 1
        fuoriVista.remove(page)
        DispatchQueue.main.async { [weak self] in
            self?.ripartisci(page, pulisciUndo: false)       // ridisegna anche immagini e testi
            self?.limitaTele()                               // più di tante tele insieme non servono: le lontane si buttano
        }
        guard let salvato = trattiSalvati[page] else { return }
        let larghezza = canvas.bounds.width
        guard larghezza > 0 else { return }
        let larghezzaPagina = page.bounds(for: .cropBox).width
        guard larghezzaPagina > 0 else { return }
        let fattore = larghezza / larghezzaPagina
        caricando = true
        canvas.drawing = salvato.transformed(using: CGAffineTransform(scaleX: fattore, y: fattore))
        caricando = false
        trattiSalvati[page] = nil
    }

    @objc func zoomCambiato() {
        ProvaContatori.zoom += 1
        attesaZoom?.invalidate()
        attesaZoom = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.controlloTesto?.ridisegnaTutte()
            self?.controlloImmagini?.mostraSelezione()
            self?.controllaRisoluzioneTele()
        }
    }

    // MARK: Lettura dei tratti salvati nel PDF


    /// Toglie dal documento in memoria le annotazioni dell'app (tratti visibili e dati nascosti):
    /// i tratti tornano modificabili sulla tela e a ogni salvataggio vengono rigenerati.
    func caricaTratti(da doc: PDFDocument, dalla prima: Int = 0, fino: Int? = nil) {
        guard prima < doc.pageCount else { return }
        for i in prima..<min(fino ?? doc.pageCount, doc.pageCount) {
            guard let page = doc.page(at: i) else { continue }
            for a in page.annotations {
                if a.userName == Self.nomeDati {
                    if let testo = a.value(forAnnotationKey: Self.chiaveDati) as? String,
                       let dati = Data(base64Encoded: testo),
                       let disegno = try? PKDrawing(data: dati) {
                        trattiSalvati[page] = disegno
                    }
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomeTratto {
                    page.removeAnnotation(a)
                } else if a.userName == ImmagineControllo.nome {
                    if let e = ImmagineControllo.elemento(da: a, origine: page.bounds(for: .cropBox).origin) { immagini[page, default: []].append(e) }
                    else { lettureFallite += 1; Diagnostica.nota("immagine-illeggibile", "pagina \(i), tipo valore \(String(describing: a.value(forAnnotationKey: ImmagineControllo.chiaveDati).map { "\(type(of: $0))" }))") }
                    page.removeAnnotation(a)
                } else if a.userName == TestoControllo.nome {
                    testi[page, default: []].append(TestoControllo.elemento(da: a, origine: page.bounds(for: .cropBox).origin))
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomeModello {
                    if let t = a.value(forAnnotationKey: Self.chiaveModello) as? String, let m = ModelloPagina(codice: t) { modelli[page] = m }
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomeQuaderno {
                    // solo quello del documento aperto: le pagine prese da un altro quaderno non lo cambiano
                    if prima == 0, fino == nil, let t = a.value(forAnnotationKey: Self.chiaveQuaderno) as? String { quaderno = Quaderno(codice: t) }
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomePrima {
                    paginaUno = page
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomeEstensione {
                    if let t = a.value(forAnnotationKey: Self.chiaveOriginale) as? String, let r = rettangolo(da: t, box: page.bounds(for: .cropBox)) {
                        originali[page] = r
                        if t.split(separator: ",").count == 4 { estensioniVecchie[page] = max(0, page.bounds(for: .cropBox).minX - a.bounds.minX) }      // salvata prima del 27/10: senza l'angolo del foglio
                    }
                    page.removeAnnotation(a)
                }
            }
        }
    }

    // MARK: Aggiungi pagine (annullabile)

    /// Una pagina con ciò che l'app ci aveva salvato (tratti, immagini, testi), per toglierla e rimetterla con annulla e ripeti
    struct DatiPagina {
        let pagina: PDFPage
        let tratti: PKDrawing?
        let immagini: [ElementoImmagine]
        let testi: [ElementoTesto]
    }

    /// Mette nel documento le pagine scelte di un altro PDF (copie: l'originale non si tocca): dopo la pagina `inserisciDopo`, altrimenti in fondo.
    /// Tratti, immagini e testi che l'app aveva salvato in quelle pagine tornano modificabili.
    func aggiungiPagine(da altro: PDFDocument, indici: [Int]) {
        guard let document else { message = "Nessun PDF aperto."; return }
        let primaNuova = inserisciDopo.map { min(max($0 + 1, 0), document.pageCount) } ?? document.pageCount
        inserisciDopo = nil
        var nuove: [PDFPage] = []
        for i in indici.sorted() {
            guard var copia = altro.page(at: i)?.copy() as? PDFPage else { continue }
            if estensione.lati == .nessuno, let std = Self.paginaStandard(da: copia, larghezza: larghezzaPagina) { copia = std }
            document.insert(copia, at: primaNuova + nuove.count)
            nuove.append(copia)
        }
        guard !nuove.isEmpty else { message = "Nessuna pagina leggibile."; return }
        caricaTratti(da: document, dalla: primaNuova, fino: primaNuova + nuove.count)
        // Stato di partenza delle pagine nuove (prima che vengano mostrate): serve a «Ripeti»
        let dati = nuove.map { DatiPagina(pagina: $0, tratti: trattiSalvati[$0], immagini: immagini[$0] ?? [], testi: testi[$0] ?? []) }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        if let p = document.page(at: primaNuova) { pdfView?.go(to: p) }
        message = nuove.count == 1 ? "Aggiunta 1 pagina." : "Aggiunte \(nuove.count) pagine."
        undoGenerale.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
    }

    /// Annulla «Aggiungi PDF»: le pagine escono dal documento (e «Ripeti» le rimette)
    func togliPagine(_ dati: [DatiPagina]) {
        guard let document else { return }
        lazo?.deseleziona()
        controlloImmagini?.annullaSelezione()
        controlloTesto?.resetta()
        var inizio = document.pageCount
        for d in dati {
            let i = document.index(for: d.pagina)
            if i != NSNotFound {
                inizio = min(inizio, i)
                document.removePage(at: i)
            }
            trattiSalvati[d.pagina] = nil
            immagini[d.pagina] = nil
            testi[d.pagina] = nil
            azzeraStrati(d.pagina)
            canvases[d.pagina] = nil
            contenitori[d.pagina] = nil
            scartaUndo(d.pagina)
        }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        undoGenerale.registerUndo(withTarget: self) { s in s.rimettiPagine(dati, da: inizio) }
        avviso("Pagine tolte.")
    }

    func rimettiPagine(_ dati: [DatiPagina], da inizio: Int) {
        guard let document else { return }
        for (n, d) in dati.enumerated() {
            document.insert(d.pagina, at: min(inizio + n, document.pageCount))
            trattiSalvati[d.pagina] = d.tratti
            if !d.immagini.isEmpty { immagini[d.pagina] = d.immagini }
            if !d.testi.isEmpty { testi[d.pagina] = d.testi }
        }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        if let p = dati.first?.pagina { pdfView?.go(to: p) }
        undoGenerale.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
        avviso("Pagine rimesse.")
    }

    // MARK: Riordino delle pagine (annullabile)

    /// Sposta la pagina `da` in modo che finisca nella posizione `a`. Tratti, immagini e testi seguono la pagina.
    func muoviPagina(da: Int, a: Int) {
        guard let document, da != a, (0..<document.pageCount).contains(da), (0..<document.pageCount).contains(a),
              let pagina = document.page(at: da) else { return }
        lazo?.deseleziona()
        controlloImmagini?.annullaSelezione()
        controlloTesto?.resetta()
        document.removePage(at: da)
        document.insert(pagina, at: a)
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        pdfView?.go(to: pagina)
        undoGenerale.registerUndo(withTarget: self) { s in s.muoviPagina(da: a, a: da) }
    }

    // MARK: Scarta

    func discardUnsaved() {
        guard let url = fileURL, let doc = document else { return }
        // Si scartano i TRATTI: scansioni, foto, file e testi aggiunti restano (si rimettono dopo la riapertura)
        var imm: [Int: [ElementoImmagine]] = [:]
        var tes: [Int: [ElementoTesto]] = [:]
        for (p, l) in immagini where !l.isEmpty { let i = doc.index(for: p); if i != NSNotFound { imm[i] = l } }
        for (p, l) in testi where !l.isEmpty { let i = doc.index(for: p); if i != NSNotFound { tes[i] = l } }
        daConservare = (imm, tes)
        cancellaRecupero()          // anche il diario di recupero: si torna al file com'è
        open(url: url)              // riapre dal file: tornano solo i tratti già salvati
        message = "Tratti non salvati scartati (immagini e testi tenuti)."
    }
}
