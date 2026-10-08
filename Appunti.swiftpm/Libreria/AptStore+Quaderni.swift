// Store: nuovo quaderno (PDF di sola scrittura con il modello scelto)
import SwiftUI
import PDFKit

extension AptStore {
    @discardableResult
    func createNotebook(in parent: String, modello: ModelloPagina, formato: FormatoPagina) -> AptDoc? {
        guard let pURL = url(for: parent) else { return nil }
        guard let data = Quaderno.creaPDF(Quaderno(modello: modello, formato: formato), formato: formato) else {
            errorMessage = "Non riesco a creare il quaderno."
            return nil
        }
        let dest = AptFS.uniqueURL(in: pURL, base: "Quaderno " + AptFormat.stamp(), ext: "pdf")
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            fail(error)
            return nil
        }
        reload()
        return folder(parent)?.docs.first { $0.url.lastPathComponent == dest.lastPathComponent }
    }
}

