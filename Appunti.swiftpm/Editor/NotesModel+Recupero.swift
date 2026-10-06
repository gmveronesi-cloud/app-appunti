// Editor: «diario» di recupero, il salvataggio leggero e frequente.
//
// Riscrivere l'intero PDF a ogni tratto è lento sui file grandi (e iCloud rimanda tutto il file).
// Quindi i livelli sono due:
//  1. Diario (qui): ogni pochi secondi si scrivono SOLO le pagine cambiate, in file piccoli dentro
//     Application Support (sull'iPad, fuori da iCloud). Serve a non perdere nulla se l'app si chiude di colpo.
//  2. PDF (`save()` in NotesModel+Salvataggio): scrittura completa, solo dopo una pausa di lavoro,
//     cambiando scheda, uscendo, mandando l'app in secondo piano, o se cambia l'ordine delle pagine.
// Il PDF resta la fonte di verità: dopo ogni scrittura riuscita il diario viene cancellato.
// Il diario vale solo per il PDF com'era su disco (dimensione e data di modifica): se il file cambia, si ignora.
import SwiftUI
import PDFKit
import PencilKit
import CryptoKit

struct ManifestoRecupero: Codable {
    var dimensione: Int64
    var data: Double
    var pagine: Int
}

struct RecuperoImmagine: Codable {
    var dati: Data
    var ritaglio: [Double]       // x, y, larghezza, altezza (pixel dell'immagine intera)
    var centro: [Double]         // x, y (coordinate pagina)
    var larghezza: Double
    var angolo: Double
    var creazione: Double
}

struct RecuperoTesto: Codable {
    var testo: String
    var punto: [Double]
    var corpo: Double
    var colore: [Double]         // r, g, b, a
    var larghezza: Double?
    var creazione: Double
}

struct RecuperoPagina: Codable {
    var tratti: Data             // PKDrawing in punti della pagina
    var immagini: [RecuperoImmagine]
    var testi: [RecuperoTesto]
}

extension NotesModel {
    /// Tutte le scritture e le cancellazioni del diario passano da qui, una alla volta
    static let codaRecupero = DispatchQueue(label: "appunti.recupero", qos: .utility)

    static func cartellaRecupero(per url: URL) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recupero", isDirectory: true)
        let impronta = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).prefix(10)
            .map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent(impronta, isDirectory: true)
    }

    /// Dimensione e data di modifica (al secondo) del PDF su disco
    static func firma(_ url: URL) -> (dimensione: Int64, data: Double)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let s = (a[.size] as? NSNumber)?.int64Value,
              let m = a[.modificationDate] as? Date else { return nil }
        return (s, m.timeIntervalSince1970.rounded())
    }

    // MARK: Scrittura (ogni pochi secondi, solo pagine cambiate)

    func scriviRecupero() {
        timerRecupero?.invalidate()
        timerRecupero = nil
        guard salvataggioAutomatico, modificato, !caricando, !pagineSporche.isEmpty,
              let document, let url = fileURL, let firma = Self.firma(url) else { return }
        var lavori: [(String, Data)] = []
        for page in pagineSporche {
            let i = document.index(for: page)
            guard i != NSNotFound, let dati = datiRecupero(page) else { continue }
            lavori.append(("p\(i).rec", dati))
        }
        pagineSporche.removeAll()
        guard !lavori.isEmpty else { return }
        let manifesto = ManifestoRecupero(dimensione: firma.dimensione, data: firma.data, pagine: document.pageCount)
        let cartella = Self.cartellaRecupero(per: url)
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        guard let datiManifesto = try? enc.encode(manifesto) else { return }
        Self.codaRecupero.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: cartella, withIntermediateDirectories: true)
            try? datiManifesto.write(to: cartella.appendingPathComponent("base.rec"), options: .atomic)
            for (nome, dati) in lavori {
                try? dati.write(to: cartella.appendingPathComponent(nome), options: .atomic)
            }
        }
    }

    private func datiRecupero(_ page: PDFPage) -> Data? {
        let box = page.bounds(for: .cropBox)
        var disegno = PKDrawing()
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = box.width / canvas.bounds.width
            disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
        } else if let ancora = trattiSalvati[page] {
            disegno = ancora
        }
        // Espressioni spezzate in passaggi semplici: il compilatore di Swift Playgrounds non regge quelle lunghe
        var imm: [RecuperoImmagine] = []
        for e in immagini[page] ?? [] {
            let rit: CGRect = e.ritaglio
            let ritaglio: [Double] = [Double(rit.minX), Double(rit.minY), Double(rit.width), Double(rit.height)]
            let centro: [Double] = [Double(e.centro.x), Double(e.centro.y)]
            let larghezza: Double = Double(e.larghezza)
            let angolo: Double = Double(e.angolo)
            let creazione: Double = e.creazione.timeIntervalSince1970
            imm.append(RecuperoImmagine(dati: e.dati, ritaglio: ritaglio, centro: centro,
                                        larghezza: larghezza, angolo: angolo, creazione: creazione))
        }
        var tes: [RecuperoTesto] = []
        for e in testi[page] ?? [] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            e.colore.getRed(&r, green: &g, blue: &b, alpha: &a)
            let punto: [Double] = [Double(e.punto.x), Double(e.punto.y)]
            let colore: [Double] = [Double(r), Double(g), Double(b), Double(a)]
            var larghezza: Double? = nil
            if let l = e.larghezza { larghezza = Double(l) }
            let creazione: Double = e.creazione.timeIntervalSince1970
            tes.append(RecuperoTesto(testo: e.testo, punto: punto, corpo: Double(e.corpo), colore: colore,
                                     larghezza: larghezza, creazione: creazione))
        }
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        return try? enc.encode(RecuperoPagina(tratti: disegno.dataRepresentation(), immagini: imm, testi: tes))
    }

    // MARK: Cancellazione (dopo un salvataggio riuscito, o se si scartano le modifiche)

    func cancellaRecupero() {
        guard let url = fileURL else { return }
        let cartella = Self.cartellaRecupero(per: url)
        Self.codaRecupero.async { try? FileManager.default.removeItem(at: cartella) }
    }

    // MARK: Lettura all'apertura

    /// Rimette nel documento appena aperto le modifiche del diario (se il PDF è lo stesso di quando furono scritte).
    /// Ritorna quante pagine sono state recuperate.
    func ripristinaRecupero(in doc: PDFDocument, url: URL) -> Int {
        let cartella = Self.cartellaRecupero(per: url)
        var trovate: [Int: RecuperoPagina] = [:]
        Self.codaRecupero.sync {
            let fm = FileManager.default
            guard fm.fileExists(atPath: cartella.path) else { return }
            let dec = PropertyListDecoder()
            guard let dm = try? Data(contentsOf: cartella.appendingPathComponent("base.rec")),
                  let man = try? dec.decode(ManifestoRecupero.self, from: dm),
                  let f = Self.firma(url),
                  man.dimensione == f.dimensione, man.data == f.data, man.pagine == doc.pageCount else {
                try? fm.removeItem(at: cartella)      // il PDF è cambiato: il diario non vale più
                return
            }
            for i in 0..<doc.pageCount {
                if let d = try? Data(contentsOf: cartella.appendingPathComponent("p\(i).rec")),
                   let r = try? dec.decode(RecuperoPagina.self, from: d) {
                    trovate[i] = r
                }
            }
        }
        var n = 0
        for (i, r) in trovate {
            guard let page = doc.page(at: i), let disegno = try? PKDrawing(data: r.tratti) else { continue }
            trattiSalvati[page] = disegno.strokes.isEmpty ? nil : disegno
            var imm: [ElementoImmagine] = []
            for e in r.immagini {
                guard e.ritaglio.count == 4, e.centro.count == 2, let img = UIImage(data: e.dati) else { continue }
                let rit = CGRect(x: e.ritaglio[0], y: e.ritaglio[1], width: e.ritaglio[2], height: e.ritaglio[3])
                let centro = CGPoint(x: e.centro[0], y: e.centro[1])
                let data = Date(timeIntervalSince1970: e.creazione)
                let nuova = ElementoImmagine(dati: e.dati, base: img, ritaglio: rit, centro: centro,
                                             larghezza: CGFloat(e.larghezza), angolo: CGFloat(e.angolo), creazione: data)
                imm.append(nuova)
            }
            immagini[page] = imm.isEmpty ? nil : imm
            var tes: [ElementoTesto] = []
            for e in r.testi {
                guard e.punto.count == 2, e.colore.count == 4 else { continue }
                let punto = CGPoint(x: e.punto[0], y: e.punto[1])
                let colore = UIColor(red: CGFloat(e.colore[0]), green: CGFloat(e.colore[1]),
                                     blue: CGFloat(e.colore[2]), alpha: CGFloat(e.colore[3]))
                var t = ElementoTesto(testo: e.testo, punto: punto, corpo: CGFloat(e.corpo), colore: colore)
                if let l = e.larghezza { t.larghezza = CGFloat(l) }
                t.creazione = Date(timeIntervalSince1970: e.creazione)
                tes.append(t)
            }
            testi[page] = tes.isEmpty ? nil : tes
            n += 1
        }
        return n
    }
}
