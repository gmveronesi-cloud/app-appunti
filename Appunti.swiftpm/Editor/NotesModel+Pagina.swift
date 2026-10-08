// Editor: vista del documento (una o due pagine, scorrimento), estensione dei fogli ai lati,
// vai a pagina, pagina bianca, allineamento degli strumenti tra due riquadri.
import SwiftUI
import PDFKit
import PencilKit

enum LatiEstensione: String, CaseIterable, Identifiable {
    case nessuno, sinistra, destra, entrambi
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .nessuno: return "Nessun riempimento"
        case .sinistra: return "Sinistra"
        case .destra: return "Destra"
        case .entrambi: return "Sinistra e Destra"
        }
    }
}

enum MisuraEstensione: String, CaseIterable, Identifiable {
    case piccolo, medio, grande
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .piccolo: return "Piccolo"
        case .medio: return "Medio"
        case .grande: return "Grande"
        }
    }
    /// Spazio aggiunto per ogni lato, in rapporto alla larghezza della pagina originale
    var frazione: CGFloat {
        switch self {
        case .piccolo: return 0.3
        case .medio: return 0.5
        case .grande: return 0.8
        }
    }
}

struct Estensione: Equatable {
    var lati = LatiEstensione.nessuno
    var misura = MisuraEstensione.piccolo
}

extension NotesModel {
    static let nomeEstensione = "AptEstensione"                      // annotazione nascosta: misura originale della pagina
    static let chiaveOriginale = PDFAnnotationKey(rawValue: "/AptOrig")

    // MARK: Vista del documento

    /// Una pagina o due, scorrimento verticale o orizzontale, continuo o pagina per pagina
    func applicaVista() {
        guard let v = pdfView else { return }
        let continuo = scorrimentoContinuo
        if paginaDoppia {
            v.displayMode = continuo ? .twoUpContinuous : .twoUp
        } else {
            v.displayMode = continuo ? .singlePageContinuous : .singlePage
        }
        v.displayDirection = scorrimentoOrizzontale ? .horizontal : .vertical
        v.displaysPageBreaks = !(quaderno?.unite ?? false)        // quaderno con pagine unite: nessuno spazio tra una pagina e l'altra
        let vuoleSfoglio = !continuo && !paginaDoppia
        if v.isUsingPageViewController != vuoleSfoglio {
            v.usePageViewController(vuoleSfoglio, withViewOptions: nil)
        }
        v.layoutDocumentView()
        DispatchQueue.main.async { [weak self] in self?.collegaSuperaFine() }
    }

    /// Posizione (da 0) della pagina che si vede
    var paginaCorrente: Int {
        guard let d = document, let p = pdfView?.currentPage else { return 0 }
        let i = d.index(for: p)
        return i == NSNotFound ? 0 : i
    }

    func vaiAPagina(_ indice: Int) {
        guard let document, let p = document.page(at: indice) else { return }
        pdfView?.go(to: p)
    }

    // MARK: Estensione dei fogli ai lati

    /// Allarga (o riporta alla misura originale) tutte le pagine. Tratti, immagini e testi restano dove sono sulla pagina.
    func impostaEstensione(_ nuova: Estensione) {
        Self.d.set(nuova.misura.rawValue, forKey: "ed.estMisura")
        guard let document, document.pageCount > 0 else { estensione = nuova; return }
        if nuova == estensione { return }
        lazo?.deseleziona()
        controlloImmagini?.resetta()
        controlloTesto?.resetta()
        let zoom = pdfView?.scaleFactor ?? 1
        let corrente = pdfView?.currentPage
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            allarga(page, a: nuova)
        }
        controlloTesto?.livelli.removeAll()
        controlloImmagini?.livelli.removeAll()
        pulisciCronologia()
        estensione = nuova
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        ricaricaVista(zoom: zoom, pagina: corrente)
    }

    private func allarga(_ page: PDFPage, a nuova: Estensione) {
        let attuale = page.bounds(for: .cropBox)
        let orig = originali[page] ?? attuale
        let extra = orig.width * nuova.misura.frazione
        let aSinistra = nuova.lati == .sinistra || nuova.lati == .entrambi
        let aDestra = nuova.lati == .destra || nuova.lati == .entrambi
        let sx: CGFloat = aSinistra ? extra : 0
        let dx: CGFloat = aDestra ? extra : 0
        let box = CGRect(x: orig.minX - sx, y: orig.minY, width: orig.width + sx + dx, height: orig.height)
        if box == attuale { return }

        // I tratti stanno in coordinate della tela (dal bordo in alto a sinistra): in punti di pagina e spostati
        // dello stesso scarto del bordo sinistro, poi la tela si rifà da sola quando la pagina torna in vista
        var disegno: PKDrawing?
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = attuale.width / canvas.bounds.width
            disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
        } else {
            disegno = trattiSalvati[page]
        }
        if let d = disegno, !d.strokes.isEmpty {
            let scarto = CGAffineTransform(translationX: attuale.minX - box.minX, y: 0)
            trattiSalvati[page] = d.transformed(using: scarto)
        }
        canvases[page] = nil
        contenitori[page] = nil
        sotto[page] = nil

        page.setBounds(box, for: .mediaBox)
        page.setBounds(box, for: .cropBox)
        originali[page] = nuova.lati == .nessuno ? nil : orig
    }

    /// Ricostruisce la vista (le tele delle pagine si rifanno) tenendo zoom e pagina
    private func ricaricaVista(zoom: CGFloat, pagina: PDFPage?) {
        guard let v = pdfView, let doc = document else { return }
        v.document = nil
        v.document = doc
        v.layoutDocumentView()
        v.autoScales = false
        v.scaleFactor = zoom
        if let p = pagina { v.go(to: p) }
    }

    /// Cambia la risoluzione delle tele (4 da soli, 2 in vista doppia). Le tele già create si rifanno alla nuova misura:
    /// i tratti passano in punti di pagina e tornano sulle tele nuove; la cronologia di annulla si azzera.
    func impostaRisoluzione(_ r: CGFloat) {
        guard r != risoluzioneMax else { return }
        risoluzioneMax = r
        guard let v = pdfView, let doc = document, doc.pageCount > 0, !canvases.isEmpty else { return }
        lazo?.deseleziona()
        controlloImmagini?.resetta()
        controlloTesto?.resetta()
        let corrente = v.currentPage
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let canvas = canvases[page] else { continue }
            if canvas.bounds.width > 0 {
                let f = page.bounds(for: .cropBox).width / canvas.bounds.width
                let d = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
                if !d.strokes.isEmpty { trattiSalvati[page] = d }
            }
            canvases[page] = nil
            contenitori[page] = nil
            sotto[page] = nil
        }
        controlloTesto?.livelli.removeAll()
        controlloImmagini?.livelli.removeAll()
        pulisciCronologia()
        v.document = nil
        v.document = doc
        v.autoScales = true          // la larghezza del riquadro cambia: la pagina si adatta di nuovo
        v.layoutDocumentView()
        if let p = corrente { v.go(to: p) }
    }

    /// Dopo l'apertura: com'è allargato il documento (si legge dalle pagine, non si salva a parte)
    func leggiEstensione(_ doc: PDFDocument) -> Estensione {
        var e = Estensione()
        e.misura = MisuraEstensione(rawValue: Self.d.string(forKey: "ed.estMisura") ?? "") ?? .piccolo
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let orig = originali[page] else { continue }
            let box = page.bounds(for: .cropBox)
            let sx = orig.minX - box.minX
            let dx = box.maxX - orig.maxX
            let aSinistra = sx > 1
            let aDestra = dx > 1
            if aSinistra && aDestra { e.lati = .entrambi }
            else if aSinistra { e.lati = .sinistra }
            else if aDestra { e.lati = .destra }
            else { continue }
            let rapporto = orig.width > 0 ? max(sx, dx) / orig.width : 0
            var migliore = MisuraEstensione.piccolo
            var scarto = CGFloat.greatestFiniteMagnitude
            for m in MisuraEstensione.allCases {
                let s = abs(m.frazione - rapporto)
                if s < scarto { scarto = s; migliore = m }
            }
            e.misura = migliore
            return e
        }
        return e
    }

    /// Annotazione nascosta con la misura originale, scritta nel PDF per ogni pagina allargata
    func annotazioneEstensione(per page: PDFPage, box: CGRect) -> PDFAnnotation? {
        guard let o = originali[page], o != box else { return nil }
        let a = PDFAnnotation(bounds: CGRect(x: box.minX, y: box.minY, width: 1, height: 1), forType: .square, withProperties: nil)
        a.userName = Self.nomeEstensione
        a.shouldDisplay = false
        a.shouldPrint = false
        let testo = "\(o.minX),\(o.minY),\(o.width),\(o.height)"
        _ = a.setValue(testo, forAnnotationKey: Self.chiaveOriginale)
        return a
    }

    func rettangolo(da testo: String) -> CGRect? {
        let n = testo.split(separator: ",").compactMap { Double($0) }
        guard n.count == 4, n[2] > 0, n[3] > 0 else { return nil }
        return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
    }

    // MARK: Vista doppia dei documenti: stessi strumenti in entrambi i riquadri

    /// Copia gli strumenti dall'altro riquadro. Avviene proprio quando si tocca il riquadro, quindi deve essere leggero:
    /// si cambia solo il pennino delle tele; il resto (gesti, ripartizione dei tratti) si rifà solo se è cambiato il TIPO di strumento.
    func allineaStrumenti(da altro: NotesModel) {
        let tipoPrima = corrente?.tipo
        var cambiato = false
        var rifaInterazione = false
        inAllineamento = true
        if strumenti != altro.strumenti { strumenti = altro.strumenti; cambiato = true }
        if selezionato != altro.selezionato { selezionato = altro.selezionato; cambiato = true }
        if pallini != altro.pallini { pallini = altro.pallini }
        if ditoDisegna != altro.ditoDisegna { ditoDisegna = altro.ditoDisegna; rifaInterazione = true }
        if dueDitaAnnulla != altro.dueDitaAnnulla { dueDitaAnnulla = altro.dueDitaAnnulla }
        if formeFerma != altro.formeFerma { formeFerma = altro.formeFerma; rifaInterazione = true }
        if salvataggioAutomatico != altro.salvataggioAutomatico { salvataggioAutomatico = altro.salvataggioAutomatico }
        if doppioTocco != altro.doppioTocco { doppioTocco = altro.doppioTocco }
        if destinazioneCattura != altro.destinazioneCattura { destinazioneCattura = altro.destinazioneCattura }
        inAllineamento = false
        if corrente?.tipo != tipoPrima { rifaInterazione = true }
        if rifaInterazione {
            applicaStrumento()                    // completo: pennino, gesti, ripartizione dei tratti
        } else if cambiato {
            for canvas in canvases.values { canvas.tool = strumentoCorrente(scala: canvas.fattoreRisoluzione) }
        }
    }
}

/// Osserva i tocchi senza intercettarli: serve a sapere in quale riquadro si sta lavorando
final class OsservaTocchi: UIGestureRecognizer {
    var quando: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        quando?()
        state = .failed
    }
}
