// Editor: apertura, tele per pagina, lettura tratti, aggiungi pagine, scarta
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

extension NotesModel {
    // MARK: Apertura

    func open(url: URL) {
        closeCurrent()

        // Se il file sta dentro la cartella radice già autorizzata, la richiesta può
        // restituire false pur avendo accesso: si prosegue comunque e si prova a leggere.
        hasSecurityScope = url.startAccessingSecurityScopedResource()
        fileURL = url

        var coordError: NSError?
        var readError: Error?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            do { data = try Data(contentsOf: readURL) } catch { readError = error }
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
        let uniformate = uniformaPagine(in: doc)       // tutte le pagine della stessa larghezza (nel file cambia solo al primo salvataggio)
        caricaTratti(da: doc)
        estensione = leggiEstensione(doc)
        let recuperate = ripristinaRecupero(in: doc, url: url)      // modifiche non ancora scritte nel PDF (app chiusa di colpo)
        document = doc
        message = ""
        versionePagine += 1
        if uniformate > 0 && recuperate == 0 { avviso("Pagine portate alla stessa larghezza.") }
        if recuperate > 0 {
            modificato = true                                        // verranno scritte nel PDF a breve
            avviso("Recuperate le modifiche non salvate.")
        }
    }

    func close() {
        closeCurrent()
    }

    func closeCurrent() {
        lazo?.deseleziona()
        controlloImmagini?.resetta()
        controlloTesto?.resetta()
        controlloTesto?.livelli.removeAll()
        controlloImmagini?.livelli.removeAll()
        pulisciCronologia()            // la cronologia di annulla riguarda solo il documento aperto
        if hasSecurityScope, let u = fileURL { u.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
        fileURL = nil
        canvases.removeAll()
        contenitori.removeAll()
        trattiSalvati.removeAll()
        testi.removeAll()
        immagini.removeAll()
        sotto.removeAll()
        originali.removeAll()
        estensione = Estensione(lati: .nessuno, misura: estensione.misura)
        destinazioneImmagine = nil
        document = nil
        fileName = ""
        modificato = false
        griglia = false
    }

    // MARK: Overlay Pencil per ogni pagina

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let esistente = contenitori[page] { return esistente }

        let misura = page.bounds(for: .cropBox).size
        let contenitore = PaginaTela(dimensione: misura, k: Self.fattore(per: misura))
        let canvas = contenitore.canvas
        canvas.delegate = self
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

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = (overlayView as? PaginaTela)?.canvas else { return }
        DispatchQueue.main.async { [weak self] in
            self?.ripartisci(page, pulisciUndo: false)       // ridisegna anche immagini e testi
        }
        guard let salvato = trattiSalvati[page] else { return }
        let larghezza = canvas.bounds.width
        guard larghezza > 0 else { return }
        let fattore = larghezza / page.bounds(for: .cropBox).width
        caricando = true
        canvas.drawing = salvato.transformed(using: CGAffineTransform(scaleX: fattore, y: fattore))
        caricando = false
        trattiSalvati[page] = nil
    }

    @objc func zoomCambiato() {
        attesaZoom?.invalidate()
        attesaZoom = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.controlloTesto?.ridisegnaTutte()
            self?.controlloImmagini?.mostraSelezione()
        }
    }

    // MARK: Lettura dei tratti salvati nel PDF


    /// Toglie dal documento in memoria le annotazioni dell'app (tratti visibili e dati nascosti):
    /// i tratti tornano modificabili sulla tela e a ogni salvataggio vengono rigenerati.
    func caricaTratti(da doc: PDFDocument, dalla prima: Int = 0) {
        guard prima < doc.pageCount else { return }
        for i in prima..<doc.pageCount {
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
                    if let e = ImmagineControllo.elemento(da: a) { immagini[page, default: []].append(e) }
                    page.removeAnnotation(a)
                } else if a.userName == TestoControllo.nome {
                    testi[page, default: []].append(TestoControllo.elemento(da: a))
                    page.removeAnnotation(a)
                } else if a.userName == Self.nomeEstensione {
                    if let t = a.value(forAnnotationKey: Self.chiaveOriginale) as? String, let r = rettangolo(da: t) {
                        originali[page] = r
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

    /// Mette in fondo al documento le pagine scelte di un altro PDF (copie: l'originale non si tocca).
    /// Tratti, immagini e testi che l'app aveva salvato in quelle pagine tornano modificabili.
    func aggiungiPagine(da altro: PDFDocument, indici: [Int]) {
        guard let document else { message = "Nessun PDF aperto."; return }
        let primaNuova = document.pageCount
        var nuove: [PDFPage] = []
        for i in indici.sorted() {
            guard var copia = altro.page(at: i)?.copy() as? PDFPage else { continue }
            if estensione.lati == .nessuno, let std = Self.paginaStandard(da: copia, larghezza: larghezzaPagina) { copia = std }
            document.insert(copia, at: document.pageCount)
            nuove.append(copia)
        }
        guard !nuove.isEmpty else { message = "Nessuna pagina leggibile."; return }
        caricaTratti(da: document, dalla: primaNuova)
        // Stato di partenza delle pagine nuove (prima che vengano mostrate): serve a «Ripeti»
        let dati = nuove.map { DatiPagina(pagina: $0, tratti: trattiSalvati[$0], immagini: immagini[$0] ?? [], testi: testi[$0] ?? []) }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        if let p = document.page(at: primaNuova) { pdfView?.go(to: p) }
        message = nuove.count == 1 ? "Aggiunta 1 pagina in fondo al documento." : "Aggiunte \(nuove.count) pagine in fondo al documento."
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
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
            sotto[d.pagina] = nil
            canvases[d.pagina] = nil
            contenitori[d.pagina] = nil
        }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.rimettiPagine(dati, da: inizio) }
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
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
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
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.muoviPagina(da: a, a: da) }
    }

    // MARK: Scarta

    func discardUnsaved() {
        guard let url = fileURL else { return }
        cancellaRecupero()          // anche il diario di recupero: si torna al file com'è
        open(url: url)              // riapre dal file: tornano solo i tratti già salvati
        message = "Tratti non salvati scartati."
    }
}
