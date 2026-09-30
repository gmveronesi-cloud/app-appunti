import SwiftUI
import UIKit

// Stile grafico dell'app: vedi docs/stile-grafico.md e docs/stile-grafico.html.
// Regola: nelle viste nuove si usano SOLO questi valori (AptTema.*), mai colori o misure scritte a mano.

enum AptTema {

    // MARK: Colori (chiaro / scuro)
    private static func dinamico(_ chiaro: UInt32, _ scuro: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: scuro) : UIColor(hex: chiaro) })
    }

    static let sfondo        = dinamico(0xFBF6F2, 0x221A19)   // fondo schermate
    static let scrivania     = dinamico(0xF1E6DF, 0x1A1413)   // dietro i fogli
    static let carta         = dinamico(0xFFFDFB, 0x2C2220)   // barre, schede, finestre
    static let testo         = dinamico(0x3B2B29, 0xF4E8E3)
    static let testo2        = dinamico(0x7D6763, 0xB8A19C)
    static let linea         = dinamico(0xE8D9D1, 0x443432)
    static let accento       = dinamico(0xBF5A54, 0xE89A92)   // rosso pastello, unico accento
    static let suAccento     = dinamico(0xFFFFFF, 0x2A1513)   // testo sopra l'accento
    static let accentoTenue  = dinamico(0xF6DDD9, 0x4A2E2B)   // selezione, strumento attivo
    static let accentoTesto  = dinamico(0xB5534D, 0xEFA9A2)
    static let accentoScuro  = dinamico(0x8E3A35, 0xF3C2BC)   // testo sopra accentoTenue
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

/// Pulsante principale: pillola piena rosso pastello.
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

/// Icona tonda-quadrata delle barre (34 pt, raggio 10). `attiva` = sfondo rosso tenue.
struct AptIcona: View {
    let nome: String
    var attiva = false
    var colore: Color? = nil
    var lato: CGFloat = 34
    var body: some View {
        Image(systemName: nome)
            .font(.system(size: 17, weight: .regular))
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
