// Store: nuovi documenti, importazioni, esportazione
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension AptStore {
    // MARK: Nuovi documenti e importazioni

    @discardableResult
    func createNote(in parent: String) -> AptDoc? {
        guard let pURL = url(for: parent) else { return nil }
        let dest = AptFS.uniqueURL(in: pURL, base: "Nota " + AptFormat.stamp(), ext: "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595.2, height: 841.8))
        var data = renderer.pdfData { ctx in ctx.beginPage() }
        // Pagina «di sola scrittura»: nel PDF resta segnata, così nell'Editor si può cambiare colore e modello
        if let doc = PDFDocument(data: data), let pagina = doc.page(at: 0) {
            pagina.addAnnotation(NotesModel.annotazioneNascosta(nome: NotesModel.nomeModello, chiave: NotesModel.chiaveModello,
                                                                 valore: ModelloPagina.bianca.codice, box: pagina.bounds(for: .cropBox)))
            if let nuovi = doc.dataRepresentation() { data = nuovi }
        }
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            fail(error)
            return nil
        }
        reload()
        return folder(parent)?.docs.first { $0.url.lastPathComponent == dest.lastPathComponent }
    }

    func importPDFs(_ urls: [URL], into parent: String) {
        guard let pURL = url(for: parent) else { return }
        for u in urls {
            let acc = u.startAccessingSecurityScopedResource()
            defer { if acc { u.stopAccessingSecurityScopedResource() } }
            let base = u.deletingPathExtension().lastPathComponent
            let dest = AptFS.uniqueURL(in: pURL, base: base, ext: "pdf")
            do { try AptFS.copy(u, to: dest) } catch { fail(error) }
        }
        reload()
    }

    /// Foto → PDF. merge = true: un unico PDF con una pagina per foto. merge = false: un PDF per foto.
    func addImages(_ images: [UIImage], merge: Bool, into parent: String) {
        guard let pURL = url(for: parent), !images.isEmpty else { return }
        let stamp = AptFormat.stamp()
        func write(_ imgs: [UIImage], base: String) {
            // Tutte le pagine hanno la stessa larghezza (quella di un A4, verticale o orizzontale come la maggioranza
            // delle foto); ogni foto tiene la propria proporzione e riempie la pagina, senza bordi bianchi.
            // Niente misure in pixel: esaurirebbero la memoria della tela Pencil.
            let valide = imgs.filter { $0.size.width > 0 && $0.size.height > 0 }
            guard !valide.isEmpty else { return }
            let orizzontali = valide.filter { $0.size.width > $0.size.height }.count
            let larghezza = NotesModel.larghezzaStandard(orizzontale: orizzontali * 2 > valide.count)
            let dati = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: larghezza, height: larghezza)).pdfData { ctx in
                for img in valide {
                    let altezza = (larghezza * img.size.height / img.size.width).rounded()
                    let area = CGRect(x: 0, y: 0, width: larghezza, height: max(altezza, 1))
                    ctx.beginPage(withBounds: area, pageInfo: [:])
                    UIColor.white.setFill()
                    UIRectFill(area)
                    img.draw(in: area)
                }
            }
            guard !dati.isEmpty else { return }
            let dest = AptFS.uniqueURL(in: pURL, base: base, ext: "pdf")
            do { try dati.write(to: dest, options: .atomic) } catch { errorMessage = "Non sono riuscito a salvare «\(base)»." }
        }
        if merge {
            write(images, base: "Immagini " + stamp)
        } else {
            for (i, img) in images.enumerated() {
                write([img], base: images.count == 1 ? "Immagine " + stamp : "Immagine " + stamp + " (\(i + 1))")
            }
        }
        reload()
    }

    // MARK: Esportazione

    func exportURLs() -> [URL] {
        var docs: [AptDoc] = []
        for k in selected {
            if k.hasPrefix("doc:") {
                let p = String(k.dropFirst(4))
                if let d = allDocs.first(where: { $0.id == p }) { docs.append(d) }
            } else if k.hasPrefix("folder:") {
                if let f = folder(String(k.dropFirst(7))) { docs += f.allDocs }
            }
        }
        var seen = Set<String>()
        let unique = docs.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return [] }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AptExport-" + UUID().uuidString)
        var out: [URL] = []
        for (i, d) in unique.enumerated() {
            let dir = tmp.appendingPathComponent("\(i)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dst = dir.appendingPathComponent(d.url.lastPathComponent)
            do {
                try AptFS.copy(d.url, to: dst)
                out.append(dst)
            } catch {
                fail(error)
            }
        }
        return out
    }

    func exportSelection() {
        let urls = exportURLs()
        guard !urls.isEmpty else { return }
        clearSelection()
        sheet = .share(urls: urls, token: UUID())
    }
}
