// Evidenziatore disegnato DENTRO la pagina PDF, sotto le lettere
//
// Un evidenziatore sovrapposto alla pagina (una vista sopra il PDF) tinge le lettere. Per averlo SOTTO le lettere
// il colore va disegnato nello stesso disegno della pagina, con fusione «moltiplica»: il bianco lascia passare il colore,
// il nero resta nero, un fondo colorato si mescola al colore (come un vero evidenziatore).
// Lo fa `AnnotazioneEvidenziatore`: PDFKit, quando disegna la pagina, chiama il suo `draw(with:in:)` DOPO il contenuto della pagina
// e la fusione avviene tutta nello stesso contesto (non dipende da come iPadOS compone le viste).
// È un'annotazione di sola vista: si toglie sempre prima di scrivere o esportare il PDF (`senzaAnnotazioniEvid`).
// I tratti restano comunque PencilKit (`evid`, o nella tela con l'evidenziatore attivo) e si salvano come sempre.
import UIKit
import PDFKit
import PencilKit

final class AnnotazioneEvidenziatore: PDFAnnotation {
    var immagine: CGImage?
    var firma = 0
    /// Diventa vero quando PDFKit richiama davvero il disegno (serve alla verifica)
    var disegnata = false

    init(box: CGRect) {
        super.init(bounds: box, forType: .stamp, withProperties: nil)
        userName = NotesModel.nomeEvidVista
        shouldPrint = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let immagine else { return }
        disegnata = true
        context.saveGState()
        context.setBlendMode(.multiply)
        context.draw(immagine, in: bounds)
        context.restoreGState()
    }
}

extension NotesModel {
    /// Stessa regola del lazo: marker o linea semitrasparente
    static func eEvidenziatore(_ t: PKStroke) -> Bool {
        switch t.ink.inkType {
        case .marker: return true
        case .monoline: return t.ink.color.cgColor.alpha < 0.95
        default: return false
        }
    }

    /// Rifà il colore disegnato nella pagina: evidenziatori dello strato `evid` + quelli della tela se l'evidenziatore è attivo
    func aggiornaEvidenziatore(_ page: PDFPage) {
        guard let canvas = canvases[page] else { return }
        if Self.evidInPagina == false { rimuoviEvidenziatore(page); return }
        var tratti = evid[page] ?? []
        if corrente?.tipo == .evidenziatore && !unificato {
            tratti += canvas.drawing.strokes.filter(Self.eEvidenziatore)
        }
        guard !tratti.isEmpty, canvas.bounds.width > 0 else { rimuoviEvidenziatore(page); return }

        var h = Hasher()
        h.combine(tratti.count)
        for t in tratti {
            h.combine(t.path.creationDate)
            h.combine(Double(t.renderBounds.minX)); h.combine(Double(t.renderBounds.maxY))
            h.combine(Double(t.renderBounds.width)); h.combine(Double(t.renderBounds.height))
        }
        let firma = h.finalize()
        if let a = annotazioniEvid[page], a.firma == firma, a.immagine != nil { return }

        let box = page.bounds(for: .cropBox)
        let k = canvas.fattoreRisoluzione
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = PKDrawing(strokes: tratti).image(from: CGRect(x: 0, y: 0, width: box.width * k, height: box.height * k), scale: 1)
        }
        let a: AnnotazioneEvidenziatore
        if let esistente = annotazioniEvid[page] {
            a = esistente
        } else {
            a = AnnotazioneEvidenziatore(box: box)
            annotazioniEvid[page] = a
            page.addAnnotation(a)
        }
        a.bounds = box
        a.immagine = img?.cgImage
        a.firma = firma
        a.disegnata = false
        pdfView?.annotationsChanged(on: page)
        if Self.evidInPagina == nil { verificaEvidenziatore(page) }
    }

    /// Controlla che PDFKit richiami davvero il disegno nella pagina. Se dopo qualche tentativo non succede,
    /// si torna agli evidenziatori nella tela (visibili, ma sopra il testo) invece di perderli.
    func verificaEvidenziatore(_ page: PDFPage) {
        guard Self.evidInPagina == nil, !verificaInCorso else { return }
        verificaInCorso = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.verificaInCorso = false
            guard Self.evidInPagina == nil else { return }
            if self.annotazioniEvid.values.contains(where: { $0.disegnata }) {
                Self.evidInPagina = true
                for p in self.canvases.keys { self.aggiornaFusione(p) }
                return
            }
            // Una pagina non visibile non viene disegnata: non conta come fallimento
            let visibile = self.annotazioniEvid.keys.contains { self.pdfView?.visiblePages.contains($0) == true }
            self.tentativiVerifica += visibile ? 1 : 0
            if self.tentativiVerifica >= 3 || self.annotazioniEvid.isEmpty {
                if self.tentativiVerifica >= 3 {
                    Self.evidInPagina = false
                    for p in Array(self.canvases.keys) {
                        self.rimuoviEvidenziatore(p)
                        self.ripartisci(p, pulisciUndo: false)
                    }
                }
                return
            }
            for (p, _) in self.annotazioniEvid { self.pdfView?.annotationsChanged(on: p) }
            self.verificaEvidenziatore(page)
        }
    }

    func rimuoviEvidenziatore(_ page: PDFPage) {
        guard let a = annotazioniEvid.removeValue(forKey: page) else { return }
        page.removeAnnotation(a)
        pdfView?.annotationsChanged(on: page)
    }

    /// Esegue `corpo` senza le annotazioni di sola vista (scrittura del PDF)
    func senzaAnnotazioniEvid<T>(_ corpo: () -> T) -> T {
        let lista = annotazioniEvid
        for (p, a) in lista { p.removeAnnotation(a) }
        let r = corpo()
        for (p, a) in lista { p.addAnnotation(a) }
        return r
    }

    /// Con l'evidenziatore attivo la tela resta nascosta: il colore si vede nella pagina, la tela serve solo mentre si scrive
    func aggiornaFusione(_ page: PDFPage) {
        guard let canvas = canvases[page] else { return }
        if canvas.layer.compositingFilter != nil { canvas.layer.compositingFilter = nil }
        let nascosta = corrente?.tipo == .evidenziatore && !unificato && Self.evidInPagina == true
        // Mai 0: UIKit non passa i tocchi a una vista con opacità sotto 0,01 (la Pencil scorrerebbe la pagina invece di scrivere)
        let o: Float = nascosta ? 0.02 : 1
        if canvas.layer.opacity != o { canvas.layer.opacity = o }
    }
}
