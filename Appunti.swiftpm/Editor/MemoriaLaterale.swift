// Memoria del file aperto a lato (vista doppia): quale documento e a che pagina.
// Resta anche chiudendo la vista doppia, l'Editor o l'app: riaccendendo la vista doppia il file torna dov'era.
import Foundation

enum MemoriaLaterale {
    private static let d = UserDefaults.standard
    private static let chiaveDocumento = "ed.laterale.doc"
    private static let chiavePagina = "ed.laterale.pagina"

    /// Percorso (nella Libreria) del documento che stava a lato; nil se non c'è niente da ricordare
    static var documento: String? { d.string(forKey: chiaveDocumento) }

    /// Pagina (da 0) a cui il file laterale era arrivato
    static var pagina: Int { max(d.integer(forKey: chiavePagina), 0) }

    static func ricorda(documento: String, pagina: Int) {
        d.set(documento, forKey: chiaveDocumento)
        d.set(max(pagina, 0), forKey: chiavePagina)
    }

    /// Dimentica il file laterale (per esempio perché è stato eliminato)
    static func dimentica() {
        d.removeObject(forKey: chiaveDocumento)
        d.removeObject(forKey: chiavePagina)
    }
}
