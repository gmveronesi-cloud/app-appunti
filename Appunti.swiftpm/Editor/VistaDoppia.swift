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

/// «×» chiude la vista doppia, «⇄» scambia i lati
struct ComandiSecondario: View {
    let chiudi: () -> Void
    let scambia: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: chiudi) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18))
                    .frame(width: 42, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi la vista doppia")
            AptLinea(verticale: true).frame(height: 22)
            Button(action: scambia) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 17))
                    .frame(width: 42, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scambia i lati")
        }
        .foregroundColor(AptTema.testo2)
        .aptScheda(raggio: 12, ombra: true)
    }
}

/// Maniglia tra i due riquadri (si trascina per ridistribuire lo spazio)
struct DivisoreDoppia: View {
    var trascinando = false

    var body: some View {
        Capsule()
            .fill(trascinando ? AptTema.accento : AptTema.testo2.opacity(0.45))
            .frame(width: 5, height: 48)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

/// Elenco dei documenti tra cui scegliere quello del secondo riquadro
struct SceltaDocumentoSecondario: View {
    let documenti: [AptDoc]
    let scegli: (AptDoc) -> Void
    let annulla: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Seleziona documento").font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
                Spacer()
                Button("Annulla", action: annulla).buttonStyle(AptStileSecondario())
            }
            .padding(16)
            AptLinea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if documenti.isEmpty {
                        Text("Nessun altro documento.")
                            .foregroundStyle(AptTema.testo2)
                            .padding(16)
                    }
                    ForEach(documenti) { d in
                        Button { scegli(d) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.richtext")
                                    .foregroundStyle(AptTema.testo2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).lineLimit(1).foregroundColor(AptTema.testo)
                                    if !d.folderPath.isEmpty {
                                        Text(d.folderPath)
                                            .font(AptTema.dettaglio)
                                            .foregroundStyle(AptTema.testo2)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        AptLinea()
                    }
                }
            }
        }
    }
}
