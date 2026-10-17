// Stesso file in due riquadri (vista doppia, anche con due schede dello stesso documento):
// ciò che si fa in un riquadro compare subito (dopo un attimo) nell'altro.
//
// Come funziona: ogni riquadro ha il suo PDF in memoria. Quando in uno cambia qualcosa, dopo una breve pausa le pagine cambiate
// (tratti, immagini, testi) passano all'altro, che le sostituisce. Se cambia la struttura (pagine aggiunte, tolte, spostate,
// sfondo, estensione) non si può copiare a pezzi: il riquadro che ha lavorato salva il PDF e l'altro lo rilegge, alla stessa pagina.
// Chi riceve non segna il documento come modificato: il salvataggio lo fa solo chi ha lavorato.
// Con due riquadri su file DIVERSI il ponte non fa niente.
import UIKit
import PDFKit
import PencilKit

final class SincroDoppia {
    weak var primo: NotesModel?
    weak var secondo: NotesModel?
    private var attese: [ObjectIdentifier: Timer] = [:]

    /// Pausa dopo l'ultima modifica prima di passarla all'altro riquadro
    static let pausa: TimeInterval = 0.35

    func collega(_ a: NotesModel, _ b: NotesModel) {
        primo = a
        secondo = b
        a.sincro = self
        b.sincro = self
    }

    /// L'altro riquadro, solo se mostra lo stesso file
    func altro(da m: NotesModel) -> NotesModel? {
        let o: NotesModel? = (m === primo) ? secondo : primo
        guard let o, o !== m,
              let u1 = m.fileURL?.standardizedFileURL, let u2 = o.fileURL?.standardizedFileURL, u1 == u2,
              m.document != nil, o.document != nil else { return nil }
        return o
    }

    /// Qualcosa è cambiato in `m`: dopo una pausa si passa all'altro riquadro
    func cambiato(da m: NotesModel) {
        guard altro(da: m) != nil else { return }
        let k = ObjectIdentifier(m)
        attese[k]?.invalidate()
        let t = Timer(timeInterval: Self.pausa, repeats: false) { [weak self, weak m] _ in
            guard let self, let m else { return }
            self.attese[k] = nil
            self.invia(da: m)
        }
        RunLoop.main.add(t, forMode: .common)
        attese[k] = t
    }

    private func invia(da m: NotesModel) {
        guard let o = altro(da: m), let doc = m.document, let docAltro = o.document else { return }
        var indici = Set<Int>()
        for p in m.pagineDaSincro {
            let i = doc.index(for: p)
            if i != NSNotFound { indici.insert(i) }
        }
        m.pagineDaSincro.removeAll()
        // Struttura cambiata: si copia dopo il salvataggio (vedi `struttura(salvataDa:)`)
        guard doc.pageCount == docAltro.pageCount, !m.strutturaCambiata else { return }
        for i in indici.sorted() { applica(da: m, a: o, indice: i) }
    }

    private func applica(da m: NotesModel, a o: NotesModel, indice i: Int) {
        guard let p = m.document?.page(at: i), let q = o.document?.page(at: i) else { return }
        var tratti: PKDrawing?
        if let c = m.canvases[p], c.bounds.width > 0 {
            let f = p.bounds(for: .cropBox).width / c.bounds.width
            tratti = PKDrawing(strokes: m.tuttiITratti(p)).transformed(using: CGAffineTransform(scaleX: f, y: f))
        } else {
            tratti = m.trattiSalvati[p]
        }
        o.ricevi(q, tratti: tratti, immagini: m.immagini[p] ?? [], testi: m.testi[p] ?? [])
    }

    /// `m` ha scritto il PDF dopo un cambio di struttura: l'altro riquadro lo rilegge, tornando alla pagina in cui era
    func struttura(salvataDa m: NotesModel) {
        guard let o = altro(da: m), let url = m.fileURL else { return }
        let pagina = o.paginaCorrente
        o.open(url: url)
        o.vaiAPaginaQuandoPronto(pagina)
    }
}

extension NotesModel {
    /// Una pagina arrivata dall'altro riquadro (stesso file): sostituisce tratti, immagini e testi.
    /// Il documento non risulta modificato qui: non si salva da questo lato.
    func ricevi(_ page: PDFPage, tratti: PKDrawing?, immagini imm: [ElementoImmagine], testi tes: [ElementoTesto]) {
        var cambiata = false
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = canvas.bounds.width / page.bounds(for: .cropBox).width
            let nuovo = (tratti ?? PKDrawing()).transformed(using: CGAffineTransform(scaleX: f, y: f))
            if Self.firmaTratti(nuovo.strokes) != Self.firmaTratti(tuttiITratti(page)) {
                lazo?.deseleziona()
                azzeraStrati(page)
                caricando = true
                canvas.drawing = nuovo
                caricando = false
                cambiata = true
            }
        } else {
            let vuoto = tratti?.strokes.isEmpty ?? true
            trattiSalvati[page] = vuoto ? nil : tratti
        }
        immagini[page] = imm.isEmpty ? nil : imm
        testi[page] = tes.isEmpty ? nil : tes
        if canvases[page] != nil {
            ripartisci(page, pulisciUndo: false)        // rifà gli strati e ridisegna anche immagini e testi
            controlloImmagini?.mostraSelezione()
            controlloTesto?.mostraSelezione()
        }
        // Le azioni di annulla di questa pagina riguardavano lo stato di prima
        if cambiata || undoPagine[page] != nil {
            undoPagine[page]?.removeAllActions()
            aggiornaUndo()
        }
    }

    /// Impronta leggera di un gruppo di tratti: serve solo a capire se due disegni sono già uguali
    static func firmaTratti(_ tratti: [PKStroke]) -> [Int] {
        var somma: CGFloat = 0
        var punti = 0
        var tempo: TimeInterval = 0
        for t in tratti {
            let r = t.renderBounds
            somma += r.minX + r.maxX * 3 + r.minY * 5 + r.maxY * 7
            punti += t.path.count
            tempo = max(tempo, t.path.creationDate.timeIntervalSinceReferenceDate)
        }
        return [tratti.count, punti, Int(sicuro: somma.rounded()), Int(sicuro: tempo.rounded())]
    }
}
