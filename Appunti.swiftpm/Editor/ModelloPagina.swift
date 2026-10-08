// Colore e modello delle pagine «di sola scrittura» (create dall'app): liscia, a righe, a quadretti, a puntini.
// Lo sfondo è disegnato nel PDF stesso (vettoriale), quindi si vede in ogni lettore.
import SwiftUI
import PDFKit

enum ColorePagina: String, CaseIterable, Identifiable {
    case bianco, crema, giallo, grigio, azzurro, verde
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .bianco: return "Bianco"
        case .crema: return "Crema"
        case .giallo: return "Giallo"
        case .grigio: return "Grigio"
        case .azzurro: return "Azzurro"
        case .verde: return "Verde"
        }
    }
    var uiColor: UIColor {
        switch self {
        case .bianco: return UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .crema: return UIColor(red: 0.99, green: 0.96, blue: 0.88, alpha: 1)
        case .giallo: return UIColor(red: 1, green: 0.97, blue: 0.74, alpha: 1)
        case .grigio: return UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)
        case .azzurro: return UIColor(red: 0.88, green: 0.94, blue: 1, alpha: 1)
        case .verde: return UIColor(red: 0.89, green: 0.97, blue: 0.90, alpha: 1)
        }
    }
}

enum TipoModello: String, CaseIterable, Identifiable {
    case liscio, righe, quadretti, puntini
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .liscio: return "Liscia"
        case .righe: return "Righe"
        case .quadretti: return "Quadretti"
        case .puntini: return "Puntini"
        }
    }
}

struct ModelloPagina: Equatable {
    var colore: ColorePagina = .bianco
    var tipo: TipoModello = .liscio

    static let bianca = ModelloPagina()

    /// Testo salvato nel PDF, per esempio «crema|righe»
    var codice: String { colore.rawValue + "|" + tipo.rawValue }

    init(colore: ColorePagina = .bianco, tipo: TipoModello = .liscio) {
        self.colore = colore
        self.tipo = tipo
    }

    init?(codice: String) {
        let parti = codice.split(separator: "|").map(String.init)
        guard parti.count == 2, let c = ColorePagina(rawValue: parti[0]), let t = TipoModello(rawValue: parti[1]) else { return nil }
        self.colore = c
        self.tipo = t
    }

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

    private func disegna(_ c: CGContext, area: CGRect) {
        c.setFillColor(colore.uiColor.cgColor)
        c.fill(area)
        let segno = UIColor(red: 0.35, green: 0.42, blue: 0.58, alpha: 0.45).cgColor
        let passo: CGFloat = 14.17          // 5 mm
        switch tipo {
        case .liscio:
            break
        case .righe:
            c.setStrokeColor(segno)
            c.setLineWidth(0.6)
            var y = area.minY + 64
            while y < area.maxY - 28 {
                c.move(to: CGPoint(x: area.minX + 28, y: y))
                c.addLine(to: CGPoint(x: area.maxX - 28, y: y))
                y += passo * 1.75
            }
            c.strokePath()
        case .quadretti:
            c.setStrokeColor(segno)
            c.setLineWidth(0.4)
            var x = area.minX + passo
            while x < area.maxX {
                c.move(to: CGPoint(x: x, y: area.minY))
                c.addLine(to: CGPoint(x: x, y: area.maxY))
                x += passo
            }
            var y = area.minY + passo
            while y < area.maxY {
                c.move(to: CGPoint(x: area.minX, y: y))
                c.addLine(to: CGPoint(x: area.maxX, y: y))
                y += passo
            }
            c.strokePath()
        case .puntini:
            c.setFillColor(segno)
            var y = area.minY + passo
            while y < area.maxY {
                var x = area.minX + passo
                while x < area.maxX {
                    c.fillEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += passo
                }
                y += passo
            }
        }
    }
}

/// Scelta di colore e modello (nella finestra dei tre puntini e dalle miniature)
struct SceltaModelloPagina: View {
    @ObservedObject var model: NotesModel
    let indice: Int
    let chiudi: () -> Void
    var margine: CGFloat = 20
    @State private var scelto = ModelloPagina.bianca

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colore e modello pagina")
                .font(AptTema.titoloMedio)
                .foregroundColor(AptTema.testo)
            Text("Colore").font(AptTema.dettaglio).foregroundStyle(AptTema.testo2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(ColorePagina.allCases) { c in
                    Button { scelto.colore = c } label: {
                        Circle()
                            .fill(Color(uiColor: c.uiColor))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(scelto.colore == c ? AptTema.accento : AptTema.linea, lineWidth: scelto.colore == c ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.nome)
                }
            }
            Text("Modello").font(AptTema.dettaglio).foregroundStyle(AptTema.testo2)
            Picker("Modello", selection: $scelto.tipo) {
                ForEach(TipoModello.allCases) { Text($0.nome).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 12) {
                Button("Annulla", action: chiudi).buttonStyle(AptStileSecondario())
                Button("Applica") {
                    model.applicaModello(scelto, allaPagina: indice)
                    chiudi()
                }
                .buttonStyle(AptStilePrimario())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(margine)
        .onAppear { scelto = model.modello(della: indice) ?? .bianca }
    }
}
