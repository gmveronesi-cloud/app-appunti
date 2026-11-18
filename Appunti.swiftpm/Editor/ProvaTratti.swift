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
