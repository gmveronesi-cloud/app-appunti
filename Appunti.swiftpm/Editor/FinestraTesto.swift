// Finestra di scrittura del testo: nostra tastiera + selettore della dimensione del carattere
import SwiftUI

struct FinestraTesto: View {
    let salva: (String, CGFloat) -> Void
    let annulla: () -> Void
    @State private var testo: String
    @State private var corpo: Double
    @State private var tutto = true

    init(testo: String, corpo: CGFloat, salva: @escaping (String, CGFloat) -> Void, annulla: @escaping () -> Void) {
        _testo = State(initialValue: testo)
        _corpo = State(initialValue: Double(min(max(corpo, 8), 96)))
        self.salva = salva
        self.annulla = annulla
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Testo").font(.headline)
                HStack {
                    Button("Annulla") { annulla() }
                    Spacer()
                    Button("Salva") { salva(testo, CGFloat(corpo)) }.fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            AptCampo(testo: testo, tutto: tutto, multiriga: true)
                .font(.system(size: min(max(corpo, 12), 30)))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(height: 118, alignment: .top)
                .background(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).fill(AptTema.scrivania))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            HStack(spacing: 12) {
                Image(systemName: "textformat.size").foregroundColor(.secondary)
                Button { corpo = max(8, corpo.rounded() - 1) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                Slider(value: $corpo, in: 8...96, step: 1)
                Button { corpo = min(96, corpo.rounded() + 1) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                Text("\(Int(corpo.rounded()))")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            AptTastiera(testo: $testo, tutto: $tutto, titoloInvio: "A capo", autoMaiuscola: true,
                        multiriga: true, onInvio: { salva(testo, CGFloat(corpo)) })
        }
        .background(AptTema.carta)
    }
}
