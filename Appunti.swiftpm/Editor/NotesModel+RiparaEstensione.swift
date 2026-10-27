// Riparazione dei file salvati prima del 27/10/2026 con «Estendi pagina» a sinistra.
// PDFKit, scrivendo, porta l'angolo del foglio a (0,0): la misura originale e le immagini restavano nelle coordinate di prima.
// Qui, all'apertura, si stima da che lato era stata allargata la pagina guardando dove il contenuto è vuoto, e si riallinea tutto.
import SwiftUI
import PDFKit

extension NotesModel {
    /// Margini bianchi (in punti di pagina) a sinistra e a destra del contenuto della pagina; nil se la pagina è vuota
    private func margini(_ page: PDFPage) -> (sinistra: CGFloat, destra: CGFloat)? {
        let box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let w = 400
        let h = max(1, Int((CGFloat(w) * box.height / box.width).rounded()))
        guard let cg = page.thumbnail(of: CGSize(width: w, height: h), for: .cropBox).cgImage else { return nil }
        var px = [UInt8](repeating: 255, count: w * h)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var primo = -1, ultimo = -1
        for x in 0..<w {
            var scuri = 0
            for y in 0..<h where px[y * w + x] < 200 {
                scuri += 1
                if scuri >= 2 { break }
            }
            if scuri >= 2 { if primo < 0 { primo = x }; ultimo = x }
        }
        guard primo >= 0 else { return nil }
        let k = box.width / CGFloat(w)
        return (CGFloat(primo) * k, CGFloat(w - 1 - ultimo) * k)
    }

    /// Per i documenti allargati e salvati dalla versione precedente: ricostruisce la misura originale delle pagine
    /// (da che lato è stato aggiunto lo spazio). Restituisce le pagine corrette (vuoto se non c'era niente da riparare).
    /// Le immagini NON si spostano da sole: dopo i salvataggi vecchi alcune sono giuste e altre no, e non si può sapere quali
    /// (per quelle sbagliate c'è «Sposta le foto di questa pagina» nei tre puntini).
    func riparaEstensioniVecchie(in doc: PDFDocument) -> [PDFPage] {
        defer { estensioniVecchie = [:] }
        // Solo le pagine che sembrano allargate a destra (come le legge il vecchio formato): lì può nascondersi un errore
        var pagine: [PDFPage] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i), estensioniVecchie[p] != nil, let o = originali[p] else { continue }
            let box = p.bounds(for: .cropBox)
            if abs(o.minX - box.minX) <= 1, box.maxX - o.maxX > 1 { pagine.append(p) }
        }
        guard let esempio = pagine.first, let o0 = originali[esempio] else { return [] }

        // Stima da miniature, usata solo per le pagine di cui il riquadro dell'annotazione non dice niente
        var stimato: CGFloat?
        if pagine.contains(where: { (estensioniVecchie[$0] ?? 0) <= 1 }) {
            let extra = esempio.bounds(for: .cropBox).maxX - o0.maxX      // spazio aggiunto in tutto (a sinistra + a destra)
            let passo = max(1, pagine.count / 12)
            var minSx = CGFloat.greatestFiniteMagnitude, minDx = CGFloat.greatestFiniteMagnitude
            var contate = 0
            for (i, p) in pagine.enumerated() where i % passo == 0 {
                if let m = margini(p) { minSx = min(minSx, m.sinistra); minDx = min(minDx, m.destra); contate += 1 }
            }
            if contate > 0 {
                // Margini bianchi = spazio aggiunto + margine originale (si suppone simile a sinistra e a destra)
                let stima = max(0, min(extra, (extra + minSx - minDx) / 2))
                stimato = [0, extra / 2, extra].min { abs($0 - stima) < abs($1 - stima) }
            }
        }

        var corrette: [PDFPage] = []
        for p in pagine {
            guard let o = originali[p] else { continue }
            let noto = estensioniVecchie[p] ?? 0
            let sx = noto > 1 ? noto : (stimato ?? 0)
            guard sx > 1 else { continue }
            originali[p] = CGRect(x: o.minX + sx, y: o.minY, width: o.width, height: o.height)
            corrette.append(p)
        }
        return corrette
    }

    /// Sposta tutte le immagini di una pagina della larghezza dello spazio aggiunto a sinistra (verso destra o verso sinistra).
    /// Serve per i file salvati dalla versione precedente, dove alcune immagini sono rimaste «indietro» di quella distanza.
    func spostaFoto(di pagina: PDFPage, versoDestra: Bool) {
        guard let c = controlloImmagini, let o = originali[pagina] else { return }
        let sx = o.minX - pagina.bounds(for: .cropBox).minX
        guard sx > 1, let lista = immagini[pagina], !lista.isEmpty else {
            message = "In questa pagina non ci sono foto da spostare."
            return
        }
        lazo?.deseleziona()
        c.resetta()
        let d = versoDestra ? sx : -sx
        for e in lista {
            var n = e
            n.centro.x += d
            c.cambia(pagina, togli: e, metti: n)
        }
        segnaModificato(pagina)
    }
}
