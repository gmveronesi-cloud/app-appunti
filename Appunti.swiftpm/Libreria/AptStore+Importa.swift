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
        let data = renderer.pdfData { ctx in ctx.beginPage() }
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
            // Ogni foto sta su un foglio A4 standard (verticale o orizzontale, come la maggioranza delle foto):
            // niente pagine enormi (esaurirebbero la memoria della tela Pencil) e tutte uguali.
            let valide = imgs.filter { $0.size.width > 0 && $0.size.height > 0 }
            guard !valide.isEmpty else { return }
            let orizzontali = valide.filter { $0.size.width > $0.size.height }.count
            let foglio = NotesModel.foglioStandard(orizzontale: orizzontali * 2 > valide.count)
            let area = CGRect(origin: .zero, size: foglio)
            let dati = UIGraphicsPDFRenderer(bounds: area).pdfData { ctx in
                for img in valide {
                    ctx.beginPage(withBounds: area, pageInfo: [:])
                    UIColor.white.setFill()
                    UIRectFill(area)
                    let r = min(foglio.width / img.size.width, foglio.height / img.size.height)
                    let w = img.size.width * r, h = img.size.height * r
                    img.draw(in: CGRect(x: (foglio.width - w) / 2, y: (foglio.height - h) / 2, width: w, height: h))
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
