// Sfondo dei fogli «di sola scrittura» (creati dall'app): bianco, quadretti, righe, puntini, oppure un modello personale
// (PDF o foto). Colore a scelta, grandezza regolabile. Lo sfondo è disegnato nel PDF stesso, quindi si vede in ogni lettore.
import SwiftUI
import PDFKit

extension ColoreSalvato {
    static let bianco = ColoreSalvato(r: 1, g: 1, b: 1)

    /// «RRGGBB»
    var esadecimale: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    init?(esadecimale t: String) {
        guard t.count == 6, let n = UInt32(t, radix: 16) else { return nil }
        self.init(r: Double((n >> 16) & 255) / 255, g: Double((n >> 8) & 255) / 255, b: Double(n & 255) / 255)
    }

    /// Chiarezza percepita, da 0 (nero) a 1 (bianco)
    var luminosita: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    /// Per le icone dell'interfaccia: nel tema scuro i colori molto scuri (nero) si schiariscono, per restare visibili
    func perInterfaccia(_ schema: ColorScheme) -> Color {
        guard schema == .dark, luminosita < 0.4 else { return color }
        let t = 0.75 - luminosita
        func m(_ v: Double) -> Double { v * (1 - t) + 0.95 * t }
        return Color(red: m(r), green: m(g), blue: m(b))
    }
}

/// Misura del foglio: A4 verticale, A4 orizzontale, oppure «gigante» (una lavagna da scorrere in lungo e in largo)
enum FormatoPagina: String, CaseIterable, Identifiable, Codable {
    case verticale, orizzontale, gigante
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .verticale: return "Verticale"
        case .orizzontale: return "Orizzontale"
        case .gigante: return "Gigante"
        }
    }
    /// In punti di pagina
    var misura: CGSize {
        switch self {
        case .verticale: return CGSize(width: 595.2, height: 841.8)
        case .orizzontale: return CGSize(width: 841.8, height: 595.2)
        case .gigante: return CGSize(width: 2400, height: 1800)
        }
    }
    var rapporto: CGFloat { misura.width / misura.height }

    /// Il formato che assomiglia di più a una pagina esistente
    static func simile(a misura: CGSize) -> FormatoPagina {
        if misura.width > 1500 || misura.height > 1500 { return .gigante }
        return misura.width > misura.height ? .orizzontale : .verticale
    }
}

enum TipoModello: String, CaseIterable, Identifiable, Codable {
    case liscio, righe, quadretti, puntini, personale
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .liscio: return "Bianco"
        case .righe: return "Righe"
        case .quadretti: return "Quadretti"
        case .puntini: return "Puntini"
        case .personale: return "Mio modello"
        }
    }
    /// I modelli di sistema, nell'ordine in cui si mostrano
    static let disegnati: [TipoModello] = [.liscio, .quadretti, .righe, .puntini]
}

struct ModelloPagina: Equatable, Codable {
    var colore: ColoreSalvato = .bianco
    var tipo: TipoModello = .liscio
    /// Grandezza di quadretti, distanza delle righe e dei puntini: 1 = come un quaderno normale
    var passo: Double = 1
    /// Solo per i modelli personali: identificativo dell'immagine salvata (vedi `ModelliArchivio`)
    var immagine: String?

    static let bianca = ModelloPagina()

    init(colore: ColoreSalvato = .bianco, tipo: TipoModello = .liscio, passo: Double = 1, immagine: String? = nil) {
        self.colore = colore
        self.tipo = tipo
        self.passo = passo
        self.immagine = immagine
    }

    // MARK: Testo salvato nel PDF, per esempio «FCF5E0|righe|1.00|»

    var codice: String {
        [colore.esadecimale, tipo.rawValue, String(format: "%.2f", passo), immagine ?? ""].joined(separator: "|")
    }

    /// Nomi dei colori usati dalle prime versioni (i vecchi fogli si leggono ancora)
    private static let coloriStorici: [String: ColoreSalvato] = [
        "bianco": ColoreSalvato(r: 1, g: 1, b: 1),
        "crema": ColoreSalvato(r: 0.99, g: 0.96, b: 0.88),
        "giallo": ColoreSalvato(r: 1, g: 0.97, b: 0.74),
        "grigio": ColoreSalvato(r: 0.92, g: 0.92, b: 0.92),
        "azzurro": ColoreSalvato(r: 0.88, g: 0.94, b: 1),
        "verde": ColoreSalvato(r: 0.89, g: 0.97, b: 0.90)
    ]

    init?(codice: String) {
        let p = codice.components(separatedBy: "|")
        guard p.count >= 2, let t = TipoModello(rawValue: p[1]) else { return nil }
        if let c = Self.coloriStorici[p[0]] {
            colore = c
        } else if let c = ColoreSalvato(esadecimale: p[0]) {
            colore = c
        } else {
            return nil
        }
        tipo = t
        passo = p.count > 2 ? (Double(p[2]) ?? 1) : 1
        immagine = (p.count > 3 && !p[3].isEmpty) ? p[3] : nil
    }

    // MARK: Pagina nuova

    /// Una pagina nuova con questo sfondo, grande come `box` (stesse coordinate della pagina che sostituisce)
    static func creaPagina(_ modello: ModelloPagina, box: CGRect) -> PDFPage? {
        guard box.width > 1, box.height > 1 else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: box.origin, size: box.size))
        let dati = renderer.pdfData { ctx in
            ctx.beginPage()
            modello.disegna(ctx.cgContext, area: ctx.pdfContextBounds)
        }
        guard let doc = PDFDocument(data: dati), let p = doc.page(at: 0), let copia = p.copy() as? PDFPage else { return nil }
        copia.setBounds(box, for: .mediaBox)
        copia.setBounds(box, for: .cropBox)
        return copia
    }

    /// Lo sfondo in piccolo (per la scelta): linee e puntini non scendono sotto una misura leggibile
    func anteprima(misura: CGSize, larghezza: CGFloat) -> UIImage {
        let k = larghezza / max(misura.width, 1)
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 2
        let r = UIGraphicsImageRenderer(size: CGSize(width: larghezza, height: misura.height * k), format: formato)
        return r.image { ctx in
            let c = ctx.cgContext
            c.scaleBy(x: k, y: k)
            disegna(c, area: CGRect(origin: .zero, size: misura), minimo: 0.5 / k)
        }
    }

    // MARK: Disegno

    /// `c` ha l'origine in alto a sinistra (come nei contesti di UIKit)
    private func disegna(_ c: CGContext, area: CGRect, minimo: CGFloat = 0) {
        c.setFillColor(colore.ui.cgColor)
        c.fill(area)
        let segno: CGColor = colore.luminosita < 0.45
            ? UIColor(white: 1, alpha: 0.30).cgColor
            : UIColor(red: 0.35, green: 0.42, blue: 0.58, alpha: 0.45).cgColor
        let scala = CGFloat(min(max(passo, 0.4), 3))
        let passoBase: CGFloat = 14.17 * scala          // 5 mm per un quaderno normale
        switch tipo {
        case .liscio:
            break
        case .personale:
            guard let id = immagine, let img = ModelliArchivio.immagine(id) else { break }
            // L'immagine riempie il foglio senza deformarsi (se la proporzione è diversa, si taglia ciò che sporge)
            let k = max(area.width / max(img.size.width, 1), area.height / max(img.size.height, 1))
            let misura = CGSize(width: img.size.width * k, height: img.size.height * k)
            c.saveGState()
            c.clip(to: area)
            UIGraphicsPushContext(c)
            img.draw(in: CGRect(x: area.midX - misura.width / 2, y: area.midY - misura.height / 2, width: misura.width, height: misura.height))
            UIGraphicsPopContext()
            c.restoreGState()
        case .righe:
            c.setStrokeColor(segno)
            c.setLineWidth(max(0.6, minimo))
            var y = area.minY + 64 * min(scala, 1.5)
            while y < area.maxY - 28 {
                c.move(to: CGPoint(x: area.minX + 28, y: y))
                c.addLine(to: CGPoint(x: area.maxX - 28, y: y))
                y += passoBase * 1.75
            }
            c.strokePath()
        case .quadretti:
            c.setStrokeColor(segno)
            c.setLineWidth(max(0.4, minimo))
            var x = area.minX + passoBase
            while x < area.maxX {
                c.move(to: CGPoint(x: x, y: area.minY))
                c.addLine(to: CGPoint(x: x, y: area.maxY))
                x += passoBase
            }
            var y = area.minY + passoBase
            while y < area.maxY {
                c.move(to: CGPoint(x: area.minX, y: y))
                c.addLine(to: CGPoint(x: area.maxX, y: y))
                y += passoBase
            }
            c.strokePath()
        case .puntini:
            // Una riga per volta, tratteggiata con punte tonde: pochi tratti, anche su fogli giganti
            c.setStrokeColor(segno)
            c.setLineCap(.round)
            c.setLineWidth(max(1.8, minimo * 1.8))
            c.setLineDash(phase: 0, lengths: [0.001, passoBase])
            var y = area.minY + passoBase
            while y < area.maxY {
                c.move(to: CGPoint(x: area.minX + passoBase, y: y))
                c.addLine(to: CGPoint(x: area.maxX, y: y))
                y += passoBase
            }
            c.strokePath()
            c.setLineDash(phase: 0, lengths: [])
        }
    }
}
