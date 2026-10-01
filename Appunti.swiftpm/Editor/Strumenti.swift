// Modello degli strumenti della barra: ogni strumento ha il proprio colore, spessore e stile.
import SwiftUI
import PencilKit

enum TipoStrumento: String, Codable, CaseIterable, Identifiable {
    case penna, evidenziatore, matita, gomma, lazo, testo

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .penna: return "Penna"
        case .evidenziatore: return "Evidenziatore"
        case .matita: return "Matita"
        case .gomma: return "Gomma"
        case .lazo: return "Lazo"
        case .testo: return "Testo"
        }
    }

    var icona: String {
        switch self {
        case .penna: return "pencil.tip"
        case .evidenziatore: return "highlighter"
        case .matita: return "pencil"
        case .gomma: return "eraser"
        case .lazo: return "lasso"
        case .testo: return "textformat"
        }
    }

    var haColore: Bool { self != .gomma && self != .lazo }

    var haSpessore: Bool { self != .lazo }

    /// Intervallo dello spessore (la gomma: dimensione).
    var intervalloSpessore: ClosedRange<Double> {
        switch self {
        case .penna: return 0.5...12
        case .matita: return 0.5...14
        case .evidenziatore: return 4...34
        case .gomma: return 8...60
        case .lazo: return 1...1
        case .testo: return 10...48
        }
    }

    var passoSpessore: Double {
        switch self {
        case .penna, .matita: return 0.5
        default: return 1
        }
    }

    var stili: [StileStrumento] {
        switch self {
        case .penna: return [.normale, .stilografica, .monolinea]
        case .matita: return [.matita, .pastello]
        default: return []
        }
    }
}

enum StileStrumento: String, Codable {
    case normale, stilografica, monolinea, matita, pastello

    var nome: String {
        switch self {
        case .normale: return "Normale"
        case .stilografica: return "Stilografica"
        case .monolinea: return "Monolinea"
        case .matita: return "Matita"
        case .pastello: return "Pastello a cera"
        }
    }
}

/// Colore salvabile (UserDefaults): componenti sRGB.
struct ColoreSalvato: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ c: Color) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        UIColor(c).getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        self.init(r: Double(rr), g: Double(gg), b: Double(bb), a: Double(aa))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    /// Uguali a meno di piccole differenze (il selettore colori arrotonda).
    func simile(a altro: ColoreSalvato) -> Bool {
        abs(r - altro.r) < 0.02 && abs(g - altro.g) < 0.02 && abs(b - altro.b) < 0.02
    }

    static let nero = ColoreSalvato(r: 0.11, g: 0.12, b: 0.15)
    static let rosso = ColoreSalvato(r: 0.82, g: 0.23, b: 0.23)
    static let blu = ColoreSalvato(r: 0.29, g: 0.56, b: 0.94)
    static let verde = ColoreSalvato(r: 0.18, g: 0.64, b: 0.42)
    static let giallo = ColoreSalvato(r: 1.0, g: 0.90, b: 0.0)
    static let grigio = ColoreSalvato(r: 0.29, g: 0.31, b: 0.35)

    static let pallini: [ColoreSalvato] = [.nero, .rosso, .blu, .verde, .giallo]
}

struct Strumento: Identifiable, Codable, Equatable {
    var id = UUID()
    var tipo: TipoStrumento
    var colore: ColoreSalvato
    var spessore: Double
    var stile: StileStrumento
    /// Solo evidenziatore: 0 = come viene, fino a 0,85 = molto trasparente.
    var trasparenza: Double
    /// Solo gomma: true = cancella il tratto intero, false = solo i pixel toccati.
    var gommaIntera: Bool
    /// Solo lazo: true = riquadro, false = mano libera.
    var lazoRiquadro: Bool = false
    /// Solo lazo: tipi di tratto che il lazo può selezionare.
    var lazoFiltri: [TipoStrumento] = [.penna, .evidenziatore, .matita]

    enum CodingKeys: String, CodingKey {
        case id, tipo, colore, spessore, stile, trasparenza, gommaIntera, lazoRiquadro, lazoFiltri
    }

    static func nuovo(_ tipo: TipoStrumento) -> Strumento {
        switch tipo {
        case .penna:
            return Strumento(tipo: .penna, colore: .nero, spessore: 1.5, stile: .normale, trasparenza: 0, gommaIntera: false)
        case .evidenziatore:
            return Strumento(tipo: .evidenziatore, colore: .giallo, spessore: 16, stile: .normale, trasparenza: 0, gommaIntera: false)
        case .matita:
            return Strumento(tipo: .matita, colore: .grigio, spessore: 1.5, stile: .matita, trasparenza: 0, gommaIntera: false)
        case .gomma:
            return Strumento(tipo: .gomma, colore: .nero, spessore: 24, stile: .normale, trasparenza: 0, gommaIntera: false)
        case .lazo:
            return Strumento(tipo: .lazo, colore: .nero, spessore: 1, stile: .normale, trasparenza: 0, gommaIntera: false)
        case .testo:
            return Strumento(tipo: .testo, colore: .nero, spessore: 16, stile: .normale, trasparenza: 0, gommaIntera: false)
        }
    }

    static var predefiniti: [Strumento] {
        var rossa = Strumento.nuovo(.penna)
        rossa.colore = .rosso
        rossa.spessore = 1
        rossa.stile = .stilografica
        var azzurro = Strumento.nuovo(.evidenziatore)
        azzurro.colore = .blu
        return [.nuovo(.penna), rossa, .nuovo(.evidenziatore), azzurro, .nuovo(.matita), .nuovo(.gomma)]
    }

    /// Descrizione breve, per le etichette.
    var nome: String { tipo.nome }

    var inkType: PKInkingTool.InkType {
        switch tipo {
        case .penna:
            switch stile {
            case .stilografica: return .fountainPen
            case .monolinea: return .monoline
            default: return .pen
            }
        case .matita:
            return stile == .pastello ? .crayon : .pencil
        case .evidenziatore:
            return .monoline
        case .gomma, .lazo, .testo:
            return .marker
        }
    }

    /// `scala`: le tele sono più grandi della pagina (vedi `PaginaTela`), quindi spessori e gomma si moltiplicano.
    func pkTool(scala: CGFloat = 1) -> PKTool {
        switch tipo {
        case .lazo:
            return PKLassoTool()
        case .gomma:
            return gommaIntera ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: CGFloat(spessore) * scala)
        case .evidenziatore:
            // Linea di spessore costante, bordi netti e semitrasparente (il vecchio «marker» di PencilKit li aveva sfumati)
            let c = colore.ui.withAlphaComponent(0.45 * CGFloat(1 - trasparenza))
            return PKInkingTool(.monoline, color: c, width: CGFloat(spessore) * scala)
        default:
            return PKInkingTool(inkType, color: colore.ui, width: CGFloat(spessore) * scala)
        }
    }
}

enum DoppioTocco: String, CaseIterable, Identifiable {
    case gomma, precedente, niente

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .gomma: return "Gomma"
        case .precedente: return "Strumento prima"
        case .niente: return "Niente"
        }
    }
}

// Lettura tollerante: i dati salvati prima del lazo non hanno i campi nuovi.
extension Strumento {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tipo = try c.decode(TipoStrumento.self, forKey: .tipo)
        colore = try c.decode(ColoreSalvato.self, forKey: .colore)
        spessore = try c.decode(Double.self, forKey: .spessore)
        stile = try c.decode(StileStrumento.self, forKey: .stile)
        trasparenza = try c.decode(Double.self, forKey: .trasparenza)
        gommaIntera = try c.decode(Bool.self, forKey: .gommaIntera)
        lazoRiquadro = try c.decodeIfPresent(Bool.self, forKey: .lazoRiquadro) ?? false
        lazoFiltri = try c.decodeIfPresent([TipoStrumento].self, forKey: .lazoFiltri) ?? [.penna, .evidenziatore, .matita]
    }
}
