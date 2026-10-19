// Pulizia dei file temporanei lasciati da salvataggi interrotti, esportazioni e importazioni
import Foundation

enum PuliziaTemporanei {
    /// All'avvio dell'app nessun salvataggio è in corso: tutto ciò che resta nella cartella temporanea è avanzo di
    /// un salvataggio interrotto (copie di PDF anche da centinaia di MB), di una condivisione o di un file ricevuto.
    static func alAvvio() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            guard let voci = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
            var liberati: Int64 = 0
            for u in voci where ["salva-", "AptExport-", "Arrivo-"].contains(where: { u.lastPathComponent.hasPrefix($0) }) {
                liberati += dimensione(u)
                try? fm.removeItem(at: u)
            }
            if liberati > 0 {
                Diagnostica.nota("pulizia", "file temporanei tolti all'avvio: \(liberati / 1_048_576) MB")
            }
        }
    }

    private static func dimensione(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var totale: Int64 = 0
        guard let it = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        for case let f as URL in it { totale += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        return totale
    }
}
