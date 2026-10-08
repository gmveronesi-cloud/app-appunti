// Ritaglio di un modello personale: il riquadro ha la forma del foglio ed è fisso; si sposta e si ingrandisce la foto sotto di esso.
import SwiftUI

struct RichiestaRitaglio: Identifiable {
    let id = UUID()
    let immagine: UIImage
    let formato: FormatoPagina
}

/// Preparazione delle immagini che diventano sfondi
enum ElaboraImmagine {
    /// Immagine dritta (senza rotazioni nascoste) e non più grande di 2800 punti per lato
    static func normalizza(_ i: UIImage) -> UIImage {
        let s = min(1, 2800 / max(i.size.width, i.size.height, 1))
        let nuova = CGSize(width: max((i.size.width * s).rounded(), 1), height: max((i.size.height * s).rounded(), 1))
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: nuova, format: f).image { _ in
            i.draw(in: CGRect(origin: .zero, size: nuova))
        }
    }

    /// La parte centrale che riempie un foglio di quel formato
    static func centrato(_ i: UIImage, formato: FormatoPagina) -> CGRect {
        let w = i.size.width, h = i.size.height
        if w / h > formato.rapporto {
            let nw = h * formato.rapporto
            return CGRect(x: (w - nw) / 2, y: 0, width: nw, height: h)
        }
        let nh = w / formato.rapporto
        return CGRect(x: 0, y: (h - nh) / 2, width: w, height: nh)
    }

    /// L'immagine finale: la parte `ritaglio` (in punti dell'immagine) portata alla misura del foglio
    static func finale(_ i: UIImage, ritaglio: CGRect, formato: FormatoPagina) -> UIImage {
        let larghezza: CGFloat = formato == .orizzontale ? 1754 : (formato == .gigante ? 2400 : 1240)
        let altezza = (larghezza / formato.rapporto).rounded()
        let k = larghezza / max(ritaglio.width, 1)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: larghezza, height: altezza), format: f).image { _ in
            i.draw(in: CGRect(x: -ritaglio.minX * k, y: -ritaglio.minY * k, width: i.size.width * k, height: i.size.height * k))
        }
    }
}

struct RitagliaModello: View {
    let richiesta: RichiestaRitaglio
    let usa: (UIImage) -> Void
    let annulla: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var spost: CGSize = .zero
    @State private var spostBase: CGSize = .zero
    @State private var area: CGSize = .zero

    private var img: UIImage { richiesta.immagine }

    /// Il riquadro fisso: grande quanto ci sta nell'area, con la forma del foglio
    private func cornice(_ a: CGSize) -> CGSize {
        let r = richiesta.formato.rapporto
        var w = a.width - 48
        var h = w / r
        if h > a.height - 48 {
            h = a.height - 48
            w = h * r
        }
        return CGSize(width: max(w, 10), height: max(h, 10))
    }

    /// Ingrandimento con cui la foto copre appena il riquadro
    private func copertura(_ c: CGSize) -> CGFloat {
        max(c.width / max(img.size.width, 1), c.height / max(img.size.height, 1))
    }

    /// Lo spostamento non lascia mai vuoti dentro il riquadro
    private func limita(_ s: CGSize, _ c: CGSize) -> CGSize {
        let k = copertura(c) * zoom
        let mx = max((img.size.width * k - c.width) / 2, 0)
        let my = max((img.size.height * k - c.height) / 2, 0)
        return CGSize(width: min(max(s.width, -mx), mx), height: min(max(s.height, -my), my))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Annulla", action: annulla).buttonStyle(AptStileSecondario())
                Spacer()
                Text("Scegli la parte da usare").font(AptTema.titoloMedio).foregroundColor(.white)
                Spacer()
                Button("Usa", action: conferma).buttonStyle(AptStilePrimario())
            }
            .padding(16)
            GeometryReader { geo in
                let c = cornice(geo.size)
                let k = copertura(c) * zoom
                let centro = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Color.black
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: img.size.width * k, height: img.size.height * k)
                        .position(x: centro.x + spost.width, y: centro.y + spost.height)
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geo.size))
                        p.addRect(CGRect(x: centro.x - c.width / 2, y: centro.y - c.height / 2, width: c.width, height: c.height))
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: c.width, height: c.height)
                        .position(centro)
                    Color.clear.onAppear { area = geo.size }
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            spost = limita(CGSize(width: spostBase.width + v.translation.width,
                                                  height: spostBase.height + v.translation.height), c)
                        }
                        .onEnded { _ in spostBase = spost }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in
                            zoom = min(max(zoomBase * v.magnification, 1), 6)
                            spost = limita(spost, c)
                        }
                        .onEnded { _ in
                            zoomBase = zoom
                            spostBase = spost
                        }
                )
                .onChange(of: geo.size) { _, nuova in area = nuova }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func conferma() {
        let c = cornice(area)
        let k = copertura(c) * zoom
        let w = img.size.width * k
        let h = img.size.height * k
        // Il riquadro, in coordinate della foto
        let x = (w / 2 - spost.width - c.width / 2) / k
        let y = (h / 2 - spost.height - c.height / 2) / k
        let rettangolo = CGRect(x: x, y: y, width: c.width / k, height: c.height / k)
        usa(ElaboraImmagine.finale(img, ritaglio: rettangolo, formato: richiesta.formato))
    }
}
