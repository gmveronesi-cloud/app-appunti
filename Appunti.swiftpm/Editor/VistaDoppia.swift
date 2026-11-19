// Vista doppia dei documenti: pezzi della schermata divisa a metà (segnaposto, comandi, divisore, scelta del documento).
import SwiftUI

/// Riquadro destro ancora vuoto: invita a scegliere il documento
struct SegnapostoSecondario: View {
    let scegli: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Vista doppia dei documenti")
                .font(AptTema.titolo)
                .foregroundColor(AptTema.testo)
            Button("Seleziona documento", action: scegli)
                .buttonStyle(AptStilePrimario())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AptTema.carta)
    }
}

/// Piccola pillola sul riquadro destro: «×» chiude la vista doppia, «⇄» scambia i lati, «⌄» apre la scelta del documento di destra
struct ComandiSecondario: View {
    let chiudi: () -> Void
    let scambia: () -> Void
    let scegli: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: chiudi) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 38, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi la vista doppia")
            AptLinea(verticale: true).frame(height: 18)
            Button(action: scambia) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 38, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scambia i lati")
            AptLinea(verticale: true).frame(height: 18)
            Button(action: scegli) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AptTema.testo2)
                    .frame(width: 17, height: 17)
                    .background(AptTema.testo2.opacity(0.22), in: Circle())
                    .frame(width: 38, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scegli il documento di destra")
        }
        .foregroundColor(AptTema.testo2)
        .aptScheda(raggio: 16, ombra: true)
    }
}

/// Maniglia tra i due riquadri (si trascina per ridistribuire lo spazio)
struct DivisoreDoppia: View {
    var trascinando = false

    var body: some View {
        Capsule()
            .fill(trascinando ? AptTema.accento : AptTema.testo2.opacity(0.45))
            .frame(width: 6, height: 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}
