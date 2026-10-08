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
                voci += creaAnnotazioni(from: d, canvasSize: box.size, page: page)
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

    func creaAnnotazioni(from drawing: PKDrawing, canvasSize: CGSize, page: PDFPage) -> [(Date, PDFAnnotation)] {
        let pageBounds = page.bounds(for: .cropBox)
        let size = canvasSize.width > 0 ? canvasSize : pageBounds.size
        let scale = pageBounds.width / size.width
        var create: [(Date, PDFAnnotation)] = []

        for stroke in drawing.strokes {
            let points = Array(stroke.path.interpolatedPoints(by: .distance(3)))
            guard points.count > 1 else { continue }

            let avgWidth = points.map { $0.size.width }.reduce(0, +) / CGFloat(points.count)
            let lineWidth = max(avgWidth * scale, 1)

            let path = UIBezierPath()
            for (i, p) in points.enumerated() {
                let loc = p.location.applying(stroke.transform)
                // Canvas: origine in alto a sinistra. PDF: origine in basso a sinistra.
                let pt = CGPoint(
                    x: pageBounds.minX + loc.x * scale,
                    y: pageBounds.maxY - loc.y * scale
                )
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }

            let bounds = path.bounds.insetBy(dx: -lineWidth, dy: -lineWidth)
            // Il percorso di un'annotazione ink è relativo all'origine dei suoi bounds
            path.apply(CGAffineTransform(translationX: -bounds.origin.x, y: -bounds.origin.y))

            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            // Evidenziatore: semitrasparente. Penna: colore pieno.
            // Il vecchio evidenziatore (marker) va reso più trasparente; quello nuovo (linea semitrasparente) ha già il suo valore
            let vecchioMarker = stroke.ink.inkType == .marker
            annotation.color = vecchioMarker ? stroke.ink.color.withAlphaComponent(0.4 * stroke.ink.color.cgColor.alpha) : stroke.ink.color
            let border = PDFBorder()
            border.lineWidth = lineWidth
            annotation.border = border
            annotation.add(path)

            annotation.userName = Self.nomeTratto
            create.append((stroke.path.creationDate, annotation))
        }
        return create
    }
}
