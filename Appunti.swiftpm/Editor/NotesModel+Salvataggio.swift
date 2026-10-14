// Editor: salvataggio e conversione tratti Pencil -> annotazioni PDF
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

extension NotesModel {
    // MARK: Salvataggio

    func save() {
        guard let document, let url = fileURL else {
            message = "Nessun PDF aperto."
            return
        }

        // Per ogni pagina: tratti visibili (ink) + disegno modificabile in un'annotazione nascosta
        var aggiunte: [(PDFPage, PDFAnnotation)] = []
        var tratti = 0
        for i in 0..<document.pageCount {
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
                tratti += voci.count
            }
            for e in immagini[page] ?? [] { voci.append((e.creazione, ImmagineControllo.annotazione(da: e))) }
            for e in testi[page] ?? [] { voci.append((e.creazione, TestoControllo.annotazione(da: e))) }
            voci.sort { $0.0 < $1.0 }
            for (_, a) in voci {
                page.addAnnotation(a)
                aggiunte.append((page, a))
            }

            if let ext = annotazioneEstensione(per: page, box: box) {
                page.addAnnotation(ext)
                aggiunte.append((page, ext))
            }

            if let m = modelli[page] {
                let a = Self.annotazioneNascosta(nome: Self.nomeModello, chiave: Self.chiaveModello, valore: m.codice, box: box)
                page.addAnnotation(a)
                aggiunte.append((page, a))
            }
            if i == 0, let q = quaderno {
                let a = Self.annotazioneNascosta(nome: Self.nomeQuaderno, chiave: Self.chiaveQuaderno, valore: q.codice, box: box)
                page.addAnnotation(a)
                aggiunte.append((page, a))
            }
            if paginaUno === page {
                let a = Self.annotazioneNascosta(nome: Self.nomePrima, chiave: Self.chiavePrima, valore: "1", box: box)
                page.addAnnotation(a)
                aggiunte.append((page, a))
            }

            guard let d = disegno, !d.strokes.isEmpty else { continue }
            let dati = PDFAnnotation(bounds: CGRect(x: box.minX, y: box.minY, width: 1, height: 1), forType: .square, withProperties: nil)
            dati.userName = Self.nomeDati
            dati.shouldDisplay = false
            dati.shouldPrint = false
            _ = dati.setValue(d.dataRepresentation().base64EncodedString(), forAnnotationKey: Self.chiaveDati)
            page.addAnnotation(dati)
            aggiunte.append((page, dati))
        }

        let data = document.dataRepresentation()
        // In memoria le annotazioni non servono: i tratti restano sulle tele
        for (page, a) in aggiunte { page.removeAnnotation(a) }
        guard let data else {
            message = "Impossibile generare il PDF."
            return
        }

        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do { try data.write(to: writeURL) } catch { writeError = error }
        }
        if let err = coordError ?? (writeError as NSError?) {
            message = "Errore di scrittura: \(err.localizedDescription)"
            return
        }
        modificato = false
        cancellaRecupero()          // il PDF è aggiornato: il diario non serve più
        primaModificaNonSalvata = nil
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
        let chiaro = UITraitCollection(userInterfaceStyle: .light)
        let paginaDisegno = CGRect(origin: .zero, size: size)
        for n in gruppi.keys.sorted() {
            let tratti = gruppi[n] ?? []
            let d = PKDrawing(strokes: tratti)
            let r = d.bounds.insetBy(dx: -4, dy: -4).intersection(paginaDisegno).integral
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            let px = min(pixelPerPunto / max(scale, 0.0001), sqrt(12_000_000 / (r.width * r.height)))
            var immagine: UIImage?
            chiaro.performAsCurrent { immagine = d.image(from: r, scale: px) }
            guard let cg = immagine?.cgImage else { continue }

            let bounds = CGRect(x: pageBounds.minX + r.minX * scale, y: pageBounds.maxY - r.maxY * scale,
                                width: r.width * scale, height: r.height * scale)
            let annotation = AnnotazioneTratti(bounds: bounds, forType: .stamp, withProperties: nil)
            annotation.immagine = cg
            annotation.fonde = (n % 2 == 1)
            annotation.userName = Self.nomeTratto
            create.append((tratti.map { $0.path.creationDate }.min() ?? Date(), annotation))
        }
        return create
    }
}

/// Annotazione Stamp che disegna l'immagine dei tratti nel suo riquadro: PDFKit la salva nel file con il suo aspetto.
final class AnnotazioneTratti: PDFAnnotation {
    var immagine: CGImage?
    var fonde = false          // evidenziatore: si mescola al colore della pagina (multiply)

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = immagine else { return }
        context.saveGState()
        if fonde { context.setBlendMode(.multiply) }
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}
