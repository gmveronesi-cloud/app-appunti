// «Recenti» del selettore dei file: documenti aperti, modificati o aggiunti da poco
import SwiftUI

extension AptStore {
    private static let chiaveAperture = "aptAperture"

    /// Ultima apertura di ogni documento (percorso → secondi). Solo sul dispositivo, in UserDefaults.
    private var aperture: [String: Double] {
        UserDefaults.standard.dictionary(forKey: Self.chiaveAperture) as? [String: Double] ?? [:]
    }

    /// Da chiamare quando un documento si apre in un riquadro dell'Editor
    func segnaAperto(_ id: String) {
        var d = aperture
        d[id] = Date().timeIntervalSince1970
        if d.count > 300 {
            // si tengono solo le ultime 150 aperture
            let tenute = d.sorted { $0.value > $1.value }.prefix(150)
            d = Dictionary(uniqueKeysWithValues: tenute.map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(d, forKey: Self.chiaveAperture)
    }

    /// L'ultima volta che il documento è stato aperto, modificato o aggiunto
    func ultimoUso(_ doc: AptDoc) -> Date {
        let aperto = aperture[doc.id].map { Date(timeIntervalSince1970: $0) } ?? Date.distantPast
        return max(doc.modDate, doc.creazione, aperto)
    }

    /// I `n` documenti più recenti (aperti, modificati o aggiunti)
    func recentiSelettore(_ n: Int = 7) -> [AptDoc] {
        let a = aperture
        func quando(_ d: AptDoc) -> Date {
            max(d.modDate, d.creazione, a[d.id].map { Date(timeIntervalSince1970: $0) } ?? Date.distantPast)
        }
        return Array(allDocs.sorted { quando($0) > quando($1) }.prefix(n))
    }
}
