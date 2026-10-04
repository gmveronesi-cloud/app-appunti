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
        caricaTratti(da: doc)
        document = doc
        message = ""
    }

    func close() {
        closeCurrent()
    }

    func closeCurrent() {
        lazo?.deseleziona()
        controlloImmagini?.resetta()
        if hasSecurityScope, let u = fileURL { u.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
        fileURL = nil
        canvases.removeAll()
        contenitori.removeAll()
        trattiSalvati.removeAll()
        testi.removeAll()
        immagini.removeAll()
        sotto.removeAll()
        destinazioneImmagine = nil
        document = nil
        fileName = ""
        modificato = false
    }

    // MARK: Overlay Pencil per ogni pagina

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        if let esistente = contenitori[page] { return esistente }

        let contenitore = PaginaTela(dimensione: page.bounds(for: .cropBox).size, k: Self.risoluzione)
        let canvas = contenitore.canvas
        canvas.delegate = self
        canvas.drawingPolicy = ditoDisegna ? .anyInput : .pencilOnly   // di base il dito scorre/zooma il PDF, la Pencil disegna
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false              // così i gesti del dito arrivano al PDF
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = strumentoCorrente
        canvas.isUserInteractionEnabled = pencilMode && tela
        contenitori[page] = contenitore
        canvases[page] = canvas
        return contenitore
    }

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = (overlayView as? PaginaTela)?.canvas else { return }
        DispatchQueue.main.async { [weak self] in
            self?.ripartisci(page, pulisciUndo: false)
            self?.controlloTesto?.ridisegna(page)
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
                }
            }
        }
    }

    // MARK: Aggiungi pagine

    /// Mette in fondo al documento le pagine scelte di un altro PDF (copie: l'originale non si tocca).
    /// Tratti, immagini e testi che l'app aveva salvato in quelle pagine tornano modificabili.
    func aggiungiPagine(da altro: PDFDocument, indici: [Int]) {
        guard let document else { message = "Nessun PDF aperto."; return }
        let primaNuova = document.pageCount
        var aggiunte = 0
        for i in indici.sorted() {
            guard let copia = altro.page(at: i)?.copy() as? PDFPage else { continue }
            document.insert(copia, at: document.pageCount)
            aggiunte += 1
        }
        guard aggiunte > 0 else { message = "Nessuna pagina leggibile."; return }
        caricaTratti(da: document, dalla: primaNuova)
        modificato = true
        pdfView?.layoutDocumentView()
        if let p = document.page(at: primaNuova) { pdfView?.go(to: p) }
        message = aggiunte == 1 ? "Aggiunta 1 pagina in fondo al documento." : "Aggiunte \(aggiunte) pagine in fondo al documento."
    }

    // MARK: Scarta

    func discardUnsaved() {
        guard let url = fileURL else { return }
        pdfView?.undoManager?.removeAllActions()
        open(url: url)              // riapre dal file: tornano solo i tratti già salvati
        message = "Tratti non salvati scartati."
    }
}
