// Memoria: ogni pagina mostrata ha una tela Pencil grande (4× la pagina) che resta viva finché il PDF è aperto.
// In un PDF lungo, scorrendo, le tele si accumulano fino a quando iPadOS chiude l'app («crash senza motivo»).
// Qui le tele delle pagine lontane da quelle che si vedono vengono buttate: i tratti passano in `trattiSalvati`
// (in punti di pagina, come appena aperto il PDF) e la tela si rifà da sola quando la pagina torna in vista (`willDisplayOverlayView`).
// Immagini e testi non si toccano: stanno in `immagini` e `testi` e si ridisegnano come al solito.
import UIKit
import PDFKit
import PencilKit
import os
import Darwin

/// Quanta memoria resta all'app prima che iPadOS la chiuda
enum GuardiaMemoria {
    /// Byte ancora disponibili; 0 = non si sa (per esempio nel simulatore): in quel caso non si fa niente di speciale
    static var disponibile: Int { Int(os_proc_available_memory()) }

    /// Memoria che l'app occupa davvero in questo momento (quella che iPadOS conta per chiuderla); 0 = non si sa.
    /// Serve perché con molte app aperte iPadOS chiude l'app ben prima del suo limite: «disponibile» da solo non se ne accorge.
    static var usata: Int {
        var info = task_vm_info_data_t()
        var conteggio = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let esito = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(conteggio)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &conteggio) }
        }
        return esito == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Livello di scarsità: 0 normale, 1 attenzione, 2 scarsa, 3 critica (per il minore tra quanto resta e quanto si occupa)
    static var livello: Int {
        let libera = disponibile
        let usata = Self.usata
        var l = 0
        if libera > 0 {
            if libera < 1_000_000_000 { l = max(l, 1) }
            if libera < 700_000_000 { l = max(l, 2) }
            if libera < 400_000_000 { l = max(l, 3) }
        }
        if usata > 0 {
            if usata > 1_100_000_000 { l = max(l, 1) }
            if usata > 1_500_000_000 { l = max(l, 2) }
            if usata > 1_900_000_000 { l = max(l, 3) }
        }
        return l
    }
}

extension NotesModel {
    /// Quante tele tenere vive insieme (oltre, si buttano le più lontane): `teleMassime` di norma, meno quando la memoria sta finendo
    private var tetto: Int {
        switch GuardiaMemoria.livello {
        case 3: return 2
        case 2: return min(teleMassime, 3)
        case 1: return min(teleMassime, 5)
        default: return teleMassime
        }
    }

    /// Chiamata a ogni pagina mostrata: se le tele sono troppe, si scende un po' sotto il massimo (così non succede a ogni pagina)
    func limitaTele() {
        let t = tetto
        guard canvases.count > t else { return }
        liberaTeleLontane(massimo: max(2, t - 2))
    }

    /// Risoluzione delle tele nuove: quella normale, più bassa solo se la memoria è già scarsa (le tele grandi pesano molto)
    var risoluzioneConsentita: CGFloat {
        // Risparmio energetico o iPad caldo: tele meno grandi, meno lavoro per il disegno
        if ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            return min(risoluzioneMax, 2)
        }
        switch GuardiaMemoria.livello {
        case 3: return min(risoluzioneMax, 2)
        case 2: return min(risoluzioneMax, 3)
        default: return risoluzioneMax
        }
    }

    /// Controllo periodico (ogni pochi secondi, anche mentre si scorre): se la memoria scende troppo si butta ciò che si può
    /// e si scrive subito il diario di recupero, così chiudendosi l'app il lavoro non va perso.
    func controllaMemoria() {
        let livello = GuardiaMemoria.livello
        Diagnostica.livelloMemoria(livello)
        guard livello > 0, document != nil else { return }
        // Non più di una volta ogni 4 secondi: buttare e rifare le tele di continuo farebbe bloccare l'app più del problema stesso.
        let ora = Date()
        if let u = ultimoIntervento, ora.timeIntervalSince(u) < 4 { return }
        ultimoIntervento = ora
        limitaTele()
        if livello >= 2 {
            AptDocInfoLoader.cache.removeAllObjects()
            scriviRecupero()
        }
        if livello >= 3 { alleggerisciUndo() }    // prima si buttava già a livello 2: con file grandi faceva «perdere» l'annulla delle altre pagine
        if livello >= 3 { liberaTeleLontane(massimo: 2) }
    }

    /// Butta le tele delle pagine che PDFKit non sta più mostrando, partendo dalle più lontane da quella corrente, finché ne restano `massimo`.
    /// Le pagine in vista non si toccano mai. La cronologia di annulla si azzera (le azioni puntavano a tele ormai sparite).
    func liberaTeleLontane(massimo: Int) {
        guard let doc = document, canvases.count > massimo else { return }
        let centro = paginaCorrente
        var candidate: [(pagina: PDFPage, distanza: Int)] = []
        for page in fuoriVista where canvases[page] != nil {
            let i = doc.index(for: page)
            if i == NSNotFound { continue }
            candidate.append((page, abs(i - centro)))
        }
        // Prima le pagine senza niente da annullare, poi le altre; a parità, le più lontane
        candidate.sort {
            let a = haCronologia($0.pagina), b = haCronologia($1.pagina)
            return a == b ? $0.distanza > $1.distanza : !a
        }
        let criticaMemoria = GuardiaMemoria.livello >= 3
        var buttate = 0
        for c in candidate {
            if canvases.count <= massimo { break }
            if c.distanza <= 1 { continue }       // la pagina accanto a quella che si legge resta
            // Le ultime pagine su cui si è scritto tengono la tela (e il loro annulla) finché la memoria non è critica
            if !criticaMemoria && eRecenteUndo(c.pagina) && haCronologia(c.pagina) { continue }
            scartaTela(c.pagina)
            buttate += 1
        }
        if buttate > 0 { aggiornaUndo() }
    }

    private func scartaTela(_ page: PDFPage) {
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = page.bounds(for: .cropBox).width / canvas.bounds.width
            let disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
            trattiSalvati[page] = disegno.strokes.isEmpty ? nil : disegno
        }
        canvases[page] = nil
        contenitori[page] = nil
        azzeraStrati(page)
        scartaUndo(page)           // le sue azioni di annulla puntano alla tela appena buttata
    }
}

extension NotesModel {
    /// App mandata in secondo piano (per esempio per aprire il PDF in un'altra app di scrittura): se occupa molta memoria,
    /// iPadOS chiude per prima proprio l'app più grande, e al ritorno sembra un crash. Qui, a salvataggio finito, si buttano tutte le tele
    /// e la vista si ricostruisce (stessa pagina, stesso punto, stesso zoom): al ritorno i tratti si ridisegnano da soli.
    /// Si fa solo se la memoria occupata è tanta, per non perdere inutilmente la cronologia di annulla.
    func alleggerisciInSecondoPiano() {
        guard let v = pdfView, let doc = document, doc.pageCount > 0 else { return }
        if salvataggioInCorso {
            salvataggiInAttesa.append { [weak self] in self?.alleggerisciInSecondoPiano() }
            return
        }
        guard UIApplication.shared.applicationState != .active, !caricando, !canvases.isEmpty else { return }
        AptDocInfoLoader.cache.removeAllObjects()
        let usata = GuardiaMemoria.usata
        guard usata > 600_000_000 else { return }
        rifaiVistaPDF(v, doc)
    }

    /// Dopo un cambio di tema (o altro) PDFKit a volte lascia la vista grigia: le pagine spariscono e resta solo lo sfondo.
    /// `forza`: si rifà comunque; altrimenti solo se non risulta visibile nessuna pagina. Si tengono pagina, punto e zoom.
    func riparaVista(forza: Bool, tentativo: Int = 0) {
        guard let v = pdfView, let doc = document, doc.pageCount > 0, !caricando else { return }
        guard v.window != nil, v.bounds.width > 10, v.bounds.height > 10 else { return }
        if salvataggioInCorso {          // non si tocca il documento mentre lo si scrive: si riprova tra poco
            guard tentativo < 20 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.riparaVista(forza: forza, tentativo: tentativo + 1)
            }
            return
        }
        if !forza && !v.visiblePages.isEmpty { return }
        rifaiVistaPDF(v, doc)
    }

    /// Dopo un cambio di tema la vista PDF va controllata: subito rifatta (così le pagine tornano) e ricontrollata poco dopo
    func dopoCambioTema() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.riparaVista(forza: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.riparaVista(forza: false) }
    }

    /// Butta le tele e rimette il documento nella vista (stessa pagina, punto e zoom); i tratti non salvati passano in `trattiSalvati`
    private func rifaiVistaPDF(_ v: PDFView, _ doc: PDFDocument) {
        lazo?.deseleziona()
        controlloImmagini?.resetta()
        controlloTesto?.resetta()
        let destinazione = v.currentDestination
        let zoom = v.scaleFactor
        let automatico = v.autoScales
        let offset = scorrimentoPDF(v)?.contentOffset
        for page in Array(canvases.keys) { scartaTelaInSecondoPiano(page) }
        controlloTesto?.livelli.removeAll()
        controlloImmagini?.livelli.removeAll()
        pulisciCronologia()
        v.document = nil
        v.document = doc
        v.layoutDocumentView()
        if automatico {
            v.autoScales = true
        } else {
            v.autoScales = false
            v.scaleFactor = zoom
        }
        if let d = destinazione { v.go(to: d) }
        if let offset { ripristinaScorrimento(v, offset, zoom: zoom) }
        DispatchQueue.main.async { [weak self] in self?.collegaSuperaFine() }
    }

    /// Lo scorrimento interno della PDFView
    func scorrimentoPDF(_ v: PDFView) -> UIScrollView? {
        func cerca(_ w: UIView) -> UIScrollView? {
            if let s = w as? UIScrollView { return s }
            for f in w.subviews { if let s = cerca(f) { return s } }
            return nil
        }
        return cerca(v)
    }

    /// Rimette lo scorrimento esatto (go(to:) lo sposta un po' in basso): subito e dopo il ricalcolo della vista
    func ripristinaScorrimento(_ v: PDFView, _ offset: CGPoint, zoom: CGFloat) {
        for ritardo in [0.0, 0.1, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + ritardo) { [weak self, weak v] in
                guard let self, let v, let s = self.scorrimentoPDF(v), v.window != nil else { return }
                guard abs(v.scaleFactor - zoom) < 0.001 else { return }       // zoom cambiato (finestra ridimensionata): non si forza
                let massimo = CGPoint(x: max(s.contentSize.width - s.bounds.width, 0), y: max(s.contentSize.height - s.bounds.height, 0))
                let nuovo = CGPoint(x: min(max(offset.x, 0), massimo.x), y: min(max(offset.y, 0), massimo.y))
                if abs(s.contentOffset.y - nuovo.y) > 0.5 || abs(s.contentOffset.x - nuovo.x) > 0.5 { s.setContentOffset(nuovo, animated: false) }
            }
        }
    }

    /// Chiamata quando l'app passa in secondo piano / inattiva e al ritorno
    func ricordaPosizioneUscita() {
        guard let v = pdfView, let s = scorrimentoPDF(v), v.window != nil else { return }
        posizioneUscita = (s.contentOffset, v.scaleFactor)
    }

    func ripristinaPosizioneUscita() {
        guard let v = pdfView, let p = posizioneUscita else { return }
        posizioneUscita = nil
        ripristinaScorrimento(v, p.offset, zoom: p.zoom)
    }

    private func scartaTelaInSecondoPiano(_ page: PDFPage) {
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = page.bounds(for: .cropBox).width / canvas.bounds.width
            let disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
            trattiSalvati[page] = disegno.strokes.isEmpty ? nil : disegno
        }
        canvases[page] = nil
        contenitori[page] = nil
        azzeraStrati(page)
        scartaUndo(page)
    }
}
