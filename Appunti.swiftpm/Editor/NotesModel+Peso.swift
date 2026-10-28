// Peso dei file: foto PNG più leggere (stessi pixel) e compattazione del PDF (vedi PNGOttimo.swift e PDFCompatta.swift).
import SwiftUI
import PDFKit

extension NotesModel {
    /// All'apertura: le foto PNG già nel file (scritte con il vecchio codificatore) si ricomprimono in sottofondo.
    /// I pixel restano identici; le pagine toccate si salvano alla prima occasione e il file diventa più leggero.
    func alleggerisciImmagini() {
        guard let doc = document else { return }
        var elenco: [(PDFPage, UUID, Data)] = []
        for (p, l) in immagini {
            for e in l where e.dati.count > 30_000 { elenco.append((p, e.id, e.dati)) }
        }
        guard !elenco.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var nuovi: [(PDFPage, UUID, Int, Data)] = []
            for (p, id, d) in elenco {
                let n = autoreleasepool { PNGOttimo.ottimizza(d) }
                if n.count < d.count { nuovi.append((p, id, d.count, n)) }
            }
            guard !nuovi.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.document === doc else { return }
                var pagine: [PDFPage] = []
                var risparmio = 0
                for (p, id, vecchia, n) in nuovi {
                    guard var l = self.immagini[p], let k = l.firstIndex(where: { $0.id == id }), l[k].dati.count == vecchia else { continue }
                    risparmio += vecchia - n.count
                    l[k].dati = n
                    self.immagini[p] = l
                    if !pagine.contains(p) { pagine.append(p) }
                }
                guard !pagine.isEmpty else { return }
                for p in pagine { self.segnaModificato(p) }
                Diagnostica.nota("immagini-alleggerite", "\(pagine.count) pagine, \(risparmio / 1024) KB in meno nei dati originali")
            }
        }
    }

    /// Compatta `file` in una copia dentro `lavoro` se conviene. Ritorna la copia (già controllata), nil se non serve o non è riuscita.
    static func compattato(_ file: URL, lavoro: URL, soglieAlte: Bool) -> URL? {
        do {
            let a = try PDFCompatta.analizza(url: file)
            let mb = { (x: Int) in x / 1_048_576 }
            guard PDFCompatta.conviene(a, soglieAlte: soglieAlte) else {
                Diagnostica.nota("compatta-salto", "file \(mb(a.totale)) MB, scarto \(mb(a.scarto)) MB, immagini ricomprimibili \(mb(a.daRicomprimere)) MB")
                return nil
            }
            let nuovo = lavoro.appendingPathComponent("compatto-" + UUID().uuidString + ".pdf")
            let inizio = Date()
            let e = try PDFCompatta.compatta(da: file, a: nuovo)
            guard e.dopo < e.prima else {
                try? FileManager.default.removeItem(at: nuovo)
                return nil
            }
            let pagine = autoreleasepool { PDFDocument(url: nuovo)?.pageCount ?? -1 }
            guard pagine > 0, PDFCompatta.verifica(originale: file, nuovo: nuovo) else {
                Diagnostica.nota("compatta-scartata", "il controllo di pagine e annotazioni non torna (\(pagine) pagine): si tiene il file com'è")
                try? FileManager.default.removeItem(at: nuovo)
                return nil
            }
            Diagnostica.nota("compatta", "da \(mb(e.prima)) MB a \(mb(e.dopo)) MB (scarto tolto \(mb(a.scarto)) MB, \(e.immagini) immagini ricompresse, \(e.scartati) oggetti eliminati) in \(Int(Date().timeIntervalSince(inizio))) s")
            return nuovo
        } catch {
            Diagnostica.nota("compatta-errore", "\(error)")
            return nil
        }
    }

    /// Dopo un salvataggio per aggiunta: se nel file si sono accumulati scarti, lo si compatta sul posto
    static func compattaSulPosto(_ url: URL, lavoro: URL, stato: StatoScrittura) {
        guard !stato.annullata else { return }
        let firmaPrima = firmaPrecisa(url)
        guard let nuovo = compattato(url, lavoro: lavoro, soglieAlte: true) else { return }
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { scrivibile in
            guard !stato.annullata, FileManager.default.fileExists(atPath: scrivibile.path),
                  let ora = firmaPrecisa(scrivibile), let prima = firmaPrima,
                  ora.dimensione == prima.dimensione, abs(ora.data - prima.data) < 0.002 else {
                Diagnostica.nota("compatta-scartata", "il file è cambiato nel frattempo")
                return
            }
            do { _ = try FileManager.default.replaceItemAt(scrivibile, withItemAt: nuovo) } catch {
                Diagnostica.nota("compatta-errore", "sostituzione: \(error.localizedDescription)")
            }
        }
    }
}
