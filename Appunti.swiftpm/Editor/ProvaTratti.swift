// Prova automatica SOLO per il simulatore di GitHub (variabile d'ambiente APT_TRATTI): disegna tratti di prova con PencilKit,
// con punti modificati in modi diversi, per vedere come li rende. Non serve all'uso normale dell'app.
import SwiftUI
import PencilKit

enum ProvaTratti {
    static var attiva: Bool { ProcessInfo.processInfo.environment["APT_TRATTI"] != nil }

    enum Modo: String, CaseIterable {
        case originale = "originale"
        case sizeCampana = "size ×campana"
        case forzaCampana = "force ×campana"
        case sizeLarghezza = "size w=2h"
        case azimut = "azimuth 0"
        case altitudine = "altitude 90°"
    }

    /// Tratto a «S» lungo ~300 pt, punti ogni ~5 pt
    static func tratto(_ ink: PKInk, _ modo: Modo, base: CGFloat, y0: CGFloat) -> PKStroke {
        let n = 60
        var pts: [PKStrokePoint] = []
        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            let x = 20 + 300 * u
            let y = y0 + 14 * sin(u * 2 * .pi)
            let campana = pow(sin(u * .pi), 0.8)          // 0 agli estremi, 1 al centro
            let m = 0.25 + 1.5 * campana
            var size = CGSize(width: base, height: base)
            var forza: CGFloat = 0.5
            var az: CGFloat = .pi / 4
            var alt: CGFloat = .pi / 4
            switch modo {
            case .originale: break
            case .sizeCampana: size = CGSize(width: base * m, height: base * m)
            case .forzaCampana: forza = min(1, 0.5 * m)
            case .sizeLarghezza: size = CGSize(width: base * 2, height: base)
            case .azimut: az = 0
            case .altitudine: alt = .pi / 2
            }
            pts.append(PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: TimeInterval(i) * 0.012, size: size,
                                     opacity: 1, force: forza, azimuth: az, altitude: alt))
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()))
    }

    static func immagine() -> UIImage {
        var strokes: [PKStroke] = []
        let tipi: [(String, PKInk.InkType)] = [("fountain", .fountainPen), ("pen", .pen)]
        var y: CGFloat = 30
        for (_, t) in tipi {
            for m in Modo.allCases {
                strokes.append(tratto(PKInk(t, color: .black), m, base: 6, y0: y))
                y += 42
            }
            y += 14
        }
        let d = PKDrawing(strokes: strokes)
        let area = CGRect(x: 0, y: 0, width: 340, height: y)
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: area, scale: 2)
        }
        return img
    }
}

struct ProvaTrattiView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(uiImage: ProvaTratti.immagine())
                .background(Color.white)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<2, id: \.self) { b in
                    Text(b == 0 ? "fountainPen" : "pen").font(.system(size: 14, weight: .bold)).frame(height: 14)
                    ForEach(ProvaTratti.Modo.allCases, id: \.self) { m in
                        Text(m.rawValue).font(.system(size: 14)).frame(height: 42, alignment: .center)
                    }
                    Spacer().frame(height: 0)
                }
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// Prova automatica (APT_BARRA): la barra strumenti vera, in tema chiaro e scuro, verticale e orizzontale
enum ProvaBarra {
    static var attiva: Bool { ProcessInfo.processInfo.environment["APT_BARRA"] != nil }
}

struct ProvaBarraView: View {
    @StateObject private var model = NotesModel()

    private func pannello(_ scuro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                BarraStrumenti(model: model, verticale: true, scorrevole: false)
                    .background(AptTema.carta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AptTema.linea))
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(scuro ? 0.9 : 1)).frame(width: 220, height: 400)
                Spacer(minLength: 0)
            }
            BarraStrumenti(model: model, verticale: false, scorrevole: true)
                .background(AptTema.carta, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AptTema.linea))
                .frame(width: 440)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AptTema.sfondo)
        .environment(\.colorScheme, scuro ? .dark : .light)
    }

    var body: some View {
        HStack(spacing: 0) {
            pannello(false)
            pannello(true)
        }
        .onAppear {
            model.strumenti = [
                { var t = Strumento.nuovo(.penna); t.spessore = 1.5; return t }(),
                { var t = Strumento.nuovo(.penna); t.colore = .bianco; t.spessore = 4.5; t.stile = .stilografica; return t }(),
                { var t = Strumento.nuovo(.penna); t.colore = .rosso; t.spessore = 12; return t }(),
                Strumento.nuovo(.evidenziatore),
                { var t = Strumento.nuovo(.evidenziatore); t.colore = .blu; t.spessore = 24; return t }(),
                Strumento.nuovo(.matita),
                { var t = Strumento.nuovo(.matita); t.colore = .nero; t.spessore = 6; return t }(),
                Strumento.nuovo(.gomma), Strumento.nuovo(.lazo), Strumento.nuovo(.immagine)
            ]
            model.selezionato = model.strumenti[3].id
        }
    }
}

/// Prova automatica (APT_CALIBRA): righe dritte a angoli diversi, per misurare lo spessore che PencilKit dà in ogni direzione.
/// Scrive Documents/calibra.png (4 blocchi da 12 celle di 90 × 90 pt, scala 2).
enum ProvaCalibra {
    static var attiva: Bool { ProcessInfo.processInfo.environment["APT_CALIBRA"] != nil }

    static func linea(_ ink: PKInk, gradi: Double, centro: CGPoint, size: CGFloat, az: CGFloat, alt: CGFloat) -> PKStroke {
        let a = gradi * .pi / 180
        let n = 40
        var pts: [PKStrokePoint] = []
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1) - 0.5
            let loc = CGPoint(x: centro.x + CGFloat(cos(a)) * 70 * t, y: centro.y + CGFloat(sin(a)) * 70 * t)
            pts.append(PKStrokePoint(location: loc, timeOffset: TimeInterval(i) * 0.01,
                                     size: CGSize(width: size, height: size), opacity: 1, force: 0.5, azimuth: az, altitude: alt))
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()))
    }

    static func scrivi() {
        var strokes: [PKStroke] = []
        let fontana = PKInk(.fountainPen, color: .black)
        let penna = PKInk(.pen, color: .black)
        for b in 0..<4 {
            let y0 = CGFloat(b) * 190
            for i in 0..<12 {
                let c = CGPoint(x: 45 + CGFloat(i % 6) * 90, y: y0 + 45 + CGFloat(i / 6) * 90)
                switch b {
                case 0: strokes.append(linea(fontana, gradi: Double(i) * 15, centro: c, size: 6, az: .pi / 4, alt: .pi / 4))
                case 1: strokes.append(linea(fontana, gradi: Double(i) * 15, centro: c, size: 6, az: .pi / 4, alt: .pi / 2))
                case 2: strokes.append(linea(penna, gradi: Double(i) * 15, centro: c, size: 6, az: .pi / 4, alt: .pi / 4))
                default:
                    let sizes: [CGFloat] = [2, 4, 6, 8, 12, 2, 4, 6, 8, 12]
                    if i < 10 { strokes.append(linea(fontana, gradi: i < 5 ? 0 : 90, centro: c, size: sizes[i], az: .pi / 4, alt: .pi / 4)) }
                }
            }
        }
        let d = PKDrawing(strokes: strokes)
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: CGRect(x: 0, y: 0, width: 540, height: 760), scale: 2)
        }
        if let png = img.pngData(),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? png.write(to: dir.appendingPathComponent("calibra.png"))
        }
    }
}
