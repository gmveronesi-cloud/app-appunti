// Memoria della pagina Modelli: ultimi modelli usati, i cinque colori, la grandezza scelta per ogni modello,
// i modelli personali (immagini salvate nella cartella dell'app: i fogli già creati non ne dipendono, lo sfondo sta nel loro PDF).
import SwiftUI

/// Un modello personale: un'immagine già ritagliata per un certo formato di foglio
struct ModelloPersonale: Codable, Identifiable, Equatable {
    var id: String
    var formato: FormatoPagina
}

enum ModelliArchivio {
    private static let d = UserDefaults.standard

    // MARK: Recenti (gli ultimi sette)

    static let maxRecenti = 7

    static func recenti() -> [ModelloPagina] {
        guard let dati = d.data(forKey: "md.recenti"), let l = try? JSONDecoder().decode([ModelloPagina].self, from: dati) else { return [] }
        return l.filter { $0.tipo != .personale || ($0.immagine.map(esiste) ?? false) }
    }

    static func ricorda(_ m: ModelloPagina) {
        var l = recenti()
        l.removeAll { $0 == m }
        l.insert(m, at: 0)
        if let dati = try? JSONEncoder().encode(Array(l.prefix(maxRecenti))) { d.set(dati, forKey: "md.recenti") }
    }

    // MARK: I cinque colori

    static let coloriIniziali: [ColoreSalvato] = [
        .bianco,
        ColoreSalvato(r: 0.99, g: 0.96, b: 0.88),     // crema
        ColoreSalvato(r: 0.92, g: 0.92, b: 0.92),     // grigio chiaro
        ColoreSalvato(r: 0.88, g: 0.94, b: 1),        // azzurro
        ColoreSalvato(r: 0.89, g: 0.97, b: 0.90)      // verde
    ]

    static func colori() -> [ColoreSalvato] {
        guard let dati = d.data(forKey: "md.colori"), let l = try? JSONDecoder().decode([ColoreSalvato].self, from: dati), l.count == 5 else {
            return coloriIniziali
        }
        return l
    }

    static func salvaColori(_ l: [ColoreSalvato]) {
        if let dati = try? JSONEncoder().encode(l) { d.set(dati, forKey: "md.colori") }
    }

    static var coloreScelto: Int {
        get { min(max(d.integer(forKey: "md.coloreScelto"), 0), 4) }
        set { d.set(newValue, forKey: "md.coloreScelto") }
    }

    // MARK: Grandezza e formato

    static func passo(_ t: TipoModello) -> Double {
        (d.object(forKey: "md.passo." + t.rawValue) as? Double) ?? 1
    }

    static func imposta(passo: Double, per t: TipoModello) { d.set(passo, forKey: "md.passo." + t.rawValue) }

    static var formato: FormatoPagina {
        get { d.string(forKey: "md.formato").flatMap { FormatoPagina(rawValue: $0) } ?? .verticale }
        set { d.set(newValue.rawValue, forKey: "md.formato") }
    }

    // MARK: Modelli personali

    private static var cartella: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Modelli", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func url(_ id: String) -> URL { cartella.appendingPathComponent(id + ".jpg") }

    static func personali() -> [ModelloPersonale] {
        guard let dati = d.data(forKey: "md.personali"), let l = try? JSONDecoder().decode([ModelloPersonale].self, from: dati) else { return [] }
        return l.filter { esiste($0.id) }
    }

    private static func salvaPersonali(_ l: [ModelloPersonale]) {
        if let dati = try? JSONEncoder().encode(l) { d.set(dati, forKey: "md.personali") }
    }

    static func esiste(_ id: String) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }

    /// Salva un'immagine (già ritagliata sulla proporzione del formato) tra i miei modelli
    @discardableResult
    static func aggiungiPersonale(_ immagine: UIImage, formato: FormatoPagina) -> ModelloPersonale? {
        guard let dati = immagine.jpegData(compressionQuality: 0.85) else { return nil }
        let nuovo = ModelloPersonale(id: UUID().uuidString, formato: formato)
        do { try dati.write(to: url(nuovo.id), options: .atomic) } catch { return nil }
        salvaPersonali([nuovo] + personali())
        return nuovo
    }

    static func elimina(_ m: ModelloPersonale) {
        try? FileManager.default.removeItem(at: url(m.id))
        cacheImmagini.removeObject(forKey: m.id as NSString)
        salvaPersonali(personali().filter { $0.id != m.id })
    }

    private static let cacheImmagini = NSCache<NSString, UIImage>()

    static func immagine(_ id: String) -> UIImage? {
        if let g = cacheImmagini.object(forKey: id as NSString) { return g }
        guard let img = UIImage(contentsOfFile: url(id).path) else { return nil }
        cacheImmagini.setObject(img, forKey: id as NSString)
        return img
    }

    // MARK: Anteprime (in memoria)

    private static let cacheAnteprime = NSCache<NSString, UIImage>()

    static func anteprima(_ m: ModelloPagina, misura: CGSize, larghezza: CGFloat) -> UIImage {
        let chiave = "\(m.codice)#\(Int(misura.width))x\(Int(misura.height))#\(Int(larghezza))" as NSString
        if let g = cacheAnteprime.object(forKey: chiave) { return g }
        let img = m.anteprima(misura: misura, larghezza: larghezza)
        cacheAnteprime.setObject(img, forKey: chiave)
        return img
    }
}
