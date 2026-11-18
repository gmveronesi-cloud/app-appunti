// Penna stilografica con due regolazioni (18/11/2026): «Punta» (parte cicciotta del tratto, estremi sottili) e
// «Piattezza della punta» (da piatta = com'è PencilKit, ad arrotondata).
// PencilKit non le offre: a ogni tratto finito si rifanno le grandezze dei punti (`PKStrokePoint.size`) e il tratto è ricreato con
// lo stesso inchiostro (`.fountainPen`). Con entrambe a zero il tratto resta quello di PencilKit, senza modifiche.
import SwiftUI
import PencilKit

enum TrattoStilografico {
    /// Spessore relativo che la stilografica di PencilKit dà al tratto per direzione (0°, 15°, … 165°; 0° = orizzontale),
    /// con azimuth e altitudine fissi a 45°. Misurato con la prova `ProvaCalibra`.
    static let direzione: [Double] = [1.064, 0.806, 0.536, 0.396, 0.536, 0.804, 1.062, 1.271, 1.402, 1.448, 1.402, 1.273]

    /// Misurato: lo spessore dato da PencilKit è circa 1,575 × (grandezza del punto − 2), cioè con grandezze sotto 2 il tratto sparisce.
    /// Le modifiche si applicano quindi alla parte sopra 2.
    private static let soglia: CGFloat = 2

    private static func fattoreDirezione(_ gradi: Double) -> Double {
        let n = direzione.count
        let passo = 180.0 / Double(n)
        var g = gradi.truncatingRemainder(dividingBy: 180)
        if g < 0 { g += 180 }
        let i = Int(g / passo) % n
        let t = (g - Double(i) * passo) / passo
        return direzione[i] * (1 - t) + direzione[(i + 1) % n] * t
    }

    private static func liscia(_ x: CGFloat) -> CGFloat {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Nuovo tratto con grandezze modificate. `k` = fattore di risoluzione della tela (la tela è k volte la pagina).
    static func elabora(_ s: PKStroke, piattezza: Double, punta: Double, k: CGFloat) -> PKStroke? {
        let p = Array(s.path)
        let n = p.count
        guard n >= 3, piattezza > 0 || punta > 0 else { return nil }
        var cum = [CGFloat](repeating: 0, count: n)
        for i in 1..<n {
            cum[i] = cum[i - 1] + hypot(p[i].location.x - p[i - 1].location.x, p[i].location.y - p[i - 1].location.y)
        }
        let lunghezza = cum[n - 1]
        guard lunghezza > 0.5 else { return nil }
        let finestra = max(min(lunghezza * 0.45, 18 * k), 0.5)

        var nuovi: [PKStrokePoint] = []
        nuovi.reserveCapacity(n)
        for i in 0..<n {
            let a = p[max(0, i - 2)].location
            let b = p[min(n - 1, i + 2)].location
            let gradi = Double(atan2(b.y - a.y, b.x - a.x)) * 180 / .pi
            // Piattezza: si toglie in parte la dipendenza dalla direzione (1 = tratto di spessore uguale in ogni direzione)
            let fd = piattezza > 0 ? pow(max(fattoreDirezione(gradi), 0.05), -piattezza) : 1
            // Punta: 0 = tratto omogeneo; 1 = estremi sottili e parte centrale più grossa
            let campana = Double(liscia(cum[i] / finestra) * liscia((lunghezza - cum[i]) / finestra))
            let m = (1 - 0.7 * punta * (1 - campana)) * (1 + 0.8 * punta * campana)
            let f = CGFloat(fd * m)
            let q = p[i]
            func nuova(_ v: CGFloat) -> CGFloat { v <= soglia ? v : soglia + (v - soglia) * f }
            nuovi.append(PKStrokePoint(
                location: q.location, timeOffset: q.timeOffset,
                size: CGSize(width: nuova(q.size.width), height: nuova(q.size.height)),
                opacity: q.opacity, force: q.force,
                azimuth: piattezza > 0 ? .pi / 4 : q.azimuth,
                altitude: piattezza > 0 ? .pi / 4 : q.altitude))
        }
        let percorso = PKStrokePath(controlPoints: nuovi, creationDate: s.path.creationDate)
        return PKStroke(ink: s.ink, path: percorso, transform: s.transform, mask: s.mask)
    }

    /// Disegno di esempio (S allungata) per l'anteprima nel pannello: stesso percorso di un tratto vero.
    /// Si disegna come su una tela vera (4 volte la pagina) e poi si rimpicciolisce.
    static func campione(_ s: Strumento, larghezza: CGFloat, altezza: CGFloat) -> UIImage {
        let k: CGFloat = 4
        let n = 90
        var pts: [PKStrokePoint] = []
        let base = CGFloat(s.spessore) * k
        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            let x = (24 + (larghezza - 48) * u) * k
            let y = (altezza / 2 + (altezza * 0.30) * CGFloat(sin(Double(u) * 2 * .pi - 0.6)) * (1 - 0.3 * u)) * k
            pts.append(PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: TimeInterval(i) * 0.012,
                                     size: CGSize(width: base, height: base), opacity: 1, force: 0.5,
                                     azimuth: .pi / 4, altitude: .pi / 4))
        }
        let ink = PKInk(.fountainPen, color: s.colore.ui)
        var tratto = PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()))
        if let nuovo = elabora(tratto, piattezza: s.piattezza, punta: s.punta, k: k) { tratto = nuovo }
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = PKDrawing(strokes: [tratto]).image(from: CGRect(x: 0, y: 0, width: larghezza * k, height: altezza * k), scale: 0.5)
        }
        guard let cg = img.cgImage else { return img }
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }
}

/// Anteprima del tratto nel pannello della penna
struct AnteprimaTratto: View {
    let strumento: Strumento

    var body: some View {
        Image(uiImage: TrattoStilografico.campione(strumento, larghezza: 280, altezza: 84))
            .frame(width: 280, height: 84)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).stroke(AptTema.linea))
    }
}
