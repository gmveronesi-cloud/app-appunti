// Store: file ricevuti da altre app (finestra di condivisione di iPadOS, «Apri con», «Copia in Appunti»)
import SwiftUI
import UIKit

extension AptStore {
    /// Un PDF (o una foto) arriva da un'altra app: va nella cartella aperta in Libreria, o nella radice.
    /// Se la libreria non è ancora scelta, resta in attesa e si importa appena viene scelta.
    func riceviEsterno(_ urls: [URL]) {
        inAttesa += urls
        if rootURL == nil {
            mostraMessaggio("Scegli la cartella della libreria: poi aggiungo il file ricevuto.")
        } else {
            importaInAttesa()
        }
    }

    func importaInAttesa() {
        guard rootURL != nil, !inAttesa.isEmpty else { return }
        let urls = inAttesa
        inAttesa = []
        let parent = (openFolder.flatMap { folder($0) != nil ? $0 : nil }) ?? ""
        var pdf: [URL] = []
        var foto: [UIImage] = []
        for u in urls {
            if u.pathExtension.lowercased() == "pdf" {
                pdf.append(u)
            } else {
                let acc = u.startAccessingSecurityScopedResource()
                defer { if acc { u.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: u), let img = UIImage(data: d) { foto.append(img) }
            }
        }
        if !pdf.isEmpty { importPDFs(pdf, into: parent) }
        if !foto.isEmpty { addImages(foto, merge: false, into: parent) }
        // La copia nella cartella «Inbox» dell'app non serve più (quella originale resta dove era)
        for u in urls where u.path.hasPrefix(NSHomeDirectory()) { try? FileManager.default.removeItem(at: u) }
        let n = pdf.count + foto.count
        guard n > 0 else {
            mostraMessaggio("Il file ricevuto non è un PDF né un'immagine.")
            return
        }
        let dove = parent.isEmpty ? "nella libreria" : "in «\(folder(parent)?.name ?? parent)»"
        mostraMessaggio(n == 1 ? "Documento aggiunto \(dove)." : "\(n) documenti aggiunti \(dove).")
    }

    func mostraMessaggio(_ testo: String) {
        messaggio = testo
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.messaggio == testo { self?.messaggio = nil }
        }
    }
}
