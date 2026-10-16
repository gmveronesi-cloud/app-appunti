// Memoria: ogni pagina mostrata ha una tela Pencil grande (4× la pagina) che resta viva finché il PDF è aperto.
// In un PDF lungo, scorrendo, le tele si accumulano fino a quando iPadOS chiude l'app («crash senza motivo»).
// Qui le tele delle pagine lontane da quelle che si vedono vengono buttate: i tratti passano in `trattiSalvati`
// (in punti di pagina, come appena aperto il PDF) e la tela si rifà da sola quando la pagina torna in vista (`willDisplayOverlayView`).
// Immagini e testi non si toccano: stanno in `immagini` e `testi` e si ridisegnano come al solito.
import UIKit
import PDFKit
import PencilKit
import os

/// Quanta memoria resta all'app prima che iPadOS la chiuda
enum GuardiaMemoria {
    /// Byte ancora disponibili; 0 = non si sa (per esempio nel simulatore): in quel caso non si fa niente di speciale
    static var disponibile: Int { Int(os_proc_available_memory()) }
}

extension NotesModel {
    /// Quante tele tenere vive insieme (oltre, si buttano le più lontane): `teleMassime` di norma, meno quando la memoria sta finendo
    private var tetto: Int {
        let libera = GuardiaMemoria.disponibile
        guard libera > 0 else { return teleMassime }
        if libera < 200_000_000 { return 3 }
        if libera < 350_000_000 { return min(teleMassime, 5) }
        if libera < 550_000_000 { return min(teleMassime, 7) }
        return teleMassime
    }

    /// Chiamata a ogni pagina mostrata: se le tele sono troppe, si scende un po' sotto il massimo (così non succede a ogni pagina)
    func limitaTele() {
        let t = tetto
        guard canvases.count > t else { return }
        liberaTeleLontane(massimo: max(2, t - 3))
    }

    /// Risoluzione delle tele nuove: quella normale, più bassa solo se la memoria è già scarsa (le tele grandi pesano molto)
    var risoluzioneConsentita: CGFloat {
        let libera = GuardiaMemoria.disponibile
        guard libera > 0 else { return risoluzioneMax }
        if libera < 250_000_000 { return min(risoluzioneMax, 2) }
        if libera < 450_000_000 { return min(risoluzioneMax, 3) }
        return risoluzioneMax
    }

    /// Controllo periodico (ogni pochi secondi, anche mentre si scorre): se la memoria scende troppo si butta ciò che si può
    /// e si scrive subito il diario di recupero, così chiudendosi l'app il lavoro non va perso.
    func controllaMemoria() {
        let libera = GuardiaMemoria.disponibile
        guard libera > 0, document != nil else { return }
        // Intervento solo con la memoria davvero scarsa, e non più di una volta ogni 10 secondi:
        // buttare e rifare le tele di continuo farebbe bloccare l'app più del problema stesso.
        let ora = Date()
        if let u = ultimoIntervento, ora.timeIntervalSince(u) < 10 { return }
        if libera < 400_000_000 {
            ultimoIntervento = ora
            limitaTele()
        }
        if libera < 250_000_000 {
            alleggerisciUndo()
            AptDocInfoLoader.cache.removeAllObjects()
            scriviRecupero()
        }
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
        var buttate = 0
        for c in candidate {
            if canvases.count <= massimo { break }
            if c.distanza <= 1 { continue }       // la pagina accanto a quella che si legge resta
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
