import SwiftUI
import UIKit

// Stile grafico dell'app: vedi docs/stile-grafico.md e docs/stile-grafico.html.
// Regola: nelle viste nuove si usano SOLO questi valori (AptTema.*), mai colori o misure scritte a mano.

enum AptTema {

    // MARK: Colori (chiaro / scuro)
    private static func dinamico(_ chiaro: UInt32, _ scuro: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: scuro) : UIColor(hex: chiaro) })
    }

    static let sfondo        = dinamico(0xFAF6F0, 0x211A16)   // fondo schermate
    static let scrivania     = dinamico(0xF0E7DD, 0x1A1512)   // dietro i fogli
    static let carta         = dinamico(0xFFFDFA, 0x2B231F)   // barre, schede, finestre
    static let testo         = dinamico(0x3A2D26, 0xF3EAE2)
    static let testo2        = dinamico(0x7C6A5F, 0xB8A79A)
    static let linea         = dinamico(0xE7DBCE, 0x42352D)
    static let accento       = dinamico(0xAE6B4B, 0xDDA27F)   // marrone terracotta pastello, unico accento
    static let suAccento     = dinamico(0xFFFFFF, 0x2A1A10)   // testo sopra l'accento
    static let accentoTenue  = dinamico(0xF2E1D4, 0x4A3226)   // selezione, strumento attivo
    static let accentoTesto  = dinamico(0xA5603F, 0xE8B08D)
    static let accentoScuro  = dinamico(0x7F4528, 0xF0C9AF)   // testo sopra accentoTenue
    static let pericolo      = dinamico(0x9E3B33, 0xF0908A)   // elimina, errori

    // Colori dei tratti: NON fanno parte del tema. Restano quelli normali, scelti da Cristina
    // con i pallini e il selettore colori. Il tema vale solo per l'interfaccia dell'app.

    // MARK: Raggi
    static let raggioS: CGFloat = 10
    static let raggioM: CGFloat = 14
    static let raggioL: CGFloat = 20

    // MARK: Spazi
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32

    // MARK: Caratteri (San Francisco di sistema)
    static let titoloGrande = Font.system(size: 28, weight: .bold)
    static let titolo       = Font.system(size: 20, weight: .semibold)
    static let titoloMedio  = Font.system(size: 17, weight: .semibold)
    static let corpo        = Font.system(size: 15, weight: .regular)
    static let corpoForte   = Font.system(size: 15, weight: .semibold)
    static let dettaglio    = Font.system(size: 13, weight: .regular)

    // MARK: Ombra morbida (solo barra strumenti, elementi flottanti, finestre)
    static let ombraColore = Color(red: 0.35, green: 0.2, blue: 0.16).opacity(0.14)
    static let ombraRaggio: CGFloat = 18
    static let ombraY: CGFloat = 6
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

// MARK: Componenti base

/// Pulsante principale: pillola piena marrone pastello.
struct AptStilePrimario: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AptTema.corpoForte)
            .foregroundStyle(AptTema.suAccento)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(AptTema.accento.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
    }
}

/// Pulsante secondario: pillola tenue.
struct AptStileSecondario: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AptTema.corpoForte)
            .foregroundStyle(AptTema.accentoScuro)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(AptTema.accentoTenue.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Pulsante neutro con bordo sottile (Annulla). Con `pericolo` diventa Elimina.
struct AptStileContorno: ButtonStyle {
    var pericolo = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AptTema.corpoForte)
            .foregroundStyle(pericolo ? AptTema.pericolo : AptTema.testo)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(Capsule().stroke(AptTema.linea, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// Superficie a scheda (barre, finestre): carta, bordo sottile, raggio medio.
    func aptScheda(raggio: CGFloat = AptTema.raggioM, ombra: Bool = false) -> some View {
        self.background(AptTema.carta, in: RoundedRectangle(cornerRadius: raggio, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: raggio, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
            .shadow(color: ombra ? AptTema.ombraColore : .clear, radius: AptTema.ombraRaggio, y: AptTema.ombraY)
    }
}

// MARK: Componenti condivisi (barre, icone, separatori)

/// Icona tonda-quadrata delle barre (34 pt, raggio 10). `attiva` = sfondo marrone tenue.
struct AptIcona: View {
    let nome: String
    var attiva = false
    var colore: Color? = nil
    var lato: CGFloat = 34
    var corpo: CGFloat = 17
    var body: some View {
        Image(systemName: nome)
            .font(.system(size: corpo, weight: .regular))
            .foregroundStyle(colore ?? (attiva ? AptTema.accentoTesto : AptTema.testo2))
            .frame(width: lato, height: lato)
            .background(attiva ? AptTema.accentoTenue : Color.clear,
                        in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Linea sottile calda al posto dei Divider di sistema.
struct AptLinea: View {
    var verticale = false
    var body: some View {
        Rectangle().fill(AptTema.linea)
            .frame(width: verticale ? 1 : nil, height: verticale ? nil : 1)
    }
}

extension View {
    /// Barra in alto: scheda carta con bordo sottile, distanziata dai bordi.
    func aptBarra() -> some View {
        self.padding(.horizontal, AptTema.s3).padding(.vertical, AptTema.s2)
            .aptScheda()
            .padding(.horizontal, AptTema.s3).padding(.top, AptTema.s2)
    }
    /// Pannello dentro popover e fogli.
    func aptPannello() -> some View {
        self.presentationBackground(AptTema.carta)
    }
}

/// Aspetto globale dei controlli UIKit (selettori a segmenti).
func aptAspettoGlobale() {
    let seg = UISegmentedControl.appearance()
    seg.selectedSegmentTintColor = UIColor(AptTema.accentoTenue)
    seg.backgroundColor = UIColor(AptTema.scrivania)
    seg.setTitleTextAttributes([.foregroundColor: UIColor(AptTema.accentoScuro)], for: .selected)
    seg.setTitleTextAttributes([.foregroundColor: UIColor(AptTema.testo2)], for: .normal)
}

// MARK: Aspetto dell'app: segue l'iPad (predefinito), oppure sempre chiaro o sempre scuro

enum AspettoApp: String, CaseIterable, Identifiable {
    case sistema, chiaro, scuro
    var id: String { rawValue }
    static let chiave = "aspettoApp"

    var nome: String {
        switch self {
        case .sistema: return "Come l'iPad"
        case .chiaro: return "Chiaro"
        case .scuro: return "Scuro"
        }
    }
    var icona: String {
        switch self {
        case .sistema: return "circle.lefthalf.filled"
        case .chiaro: return "sun.max"
        case .scuro: return "moon"
        }
    }
    /// nil = segue l'iPad
    var schema: ColorScheme? {
        switch self {
        case .sistema: return nil
        case .chiaro: return .light
        case .scuro: return .dark
        }
    }
    var stileUIKit: UIUserInterfaceStyle {
        switch self {
        case .sistema: return .unspecified
        case .chiaro: return .light
        case .scuro: return .dark
        }
    }

    /// Vale per tutte le finestre dell'app, anche fogli, popover e schermate a tutto schermo
    func applica() {
        for scena in UIApplication.shared.connectedScenes {
            guard let s = scena as? UIWindowScene else { continue }
            for finestra in s.windows { finestra.overrideUserInterfaceStyle = stileUIKit }
        }
    }
}

/// Selettore del tema (segmenti), per le impostazioni
struct SelettoreAspetto: View {
    @AppStorage(AspettoApp.chiave) private var scelto = AspettoApp.sistema.rawValue
    var body: some View {
        Picker("Tema", selection: $scelto) {
            ForEach(AspettoApp.allCases) { Text($0.nome).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
    }
}

/// Pulsante della Libreria: menu con le tre scelte
struct MenuAspetto: View {
    @AppStorage(AspettoApp.chiave) private var scelto = AspettoApp.sistema.rawValue
    var body: some View {
        Menu {
            Picker("Tema", selection: $scelto) {
                ForEach(AspettoApp.allCases) { Label($0.nome, systemImage: $0.icona).tag($0.rawValue) }
            }
        } label: {
            AptIcona(nome: (AspettoApp(rawValue: scelto) ?? .sistema).icona)
        }
        .accessibilityLabel("Tema")
    }
}
