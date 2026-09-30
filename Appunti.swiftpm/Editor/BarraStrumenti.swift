// Barra strumenti dell'Editor: penna, evidenziatore, gomma, annulla/ripeti.
// Si mostra fissa in alto oppure flottante (trascinabile), a scelta nelle impostazioni.
import SwiftUI

struct BarraStrumenti: View {
    @ObservedObject var model: NotesModel
    @State private var pannello: NotesModel.Strumento?

    var body: some View {
        HStack(spacing: 6) {
            bottone(.penna, icona: "pencil.tip", nome: "Penna")
            bottone(.evidenziatore, icona: "highlighter", nome: "Evidenziatore")
            bottone(.gomma, icona: "eraser", nome: "Gomma")
            Divider().frame(height: 26).padding(.horizontal, 4)
            Button { model.annulla() } label: { icona("arrow.uturn.backward") }
                .accessibilityLabel("Annulla")
            Button { model.ripeti() } label: { icona("arrow.uturn.forward") }
                .accessibilityLabel("Ripeti")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func icona(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.title3)
            .frame(width: 44, height: 44)
    }

    // Un tocco sullo strumento lo attiva; un secondo tocco apre colore e spessore.
    private func bottone(_ s: NotesModel.Strumento, icona nome: String, nome accessibilita: String) -> some View {
        Button {
            if model.strumento == s { pannello = s } else { model.strumento = s }
        } label: {
            icona(nome)
                .background(
                    model.strumento == s ? Color.accentColor.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .accessibilityLabel(accessibilita)
        .popover(isPresented: Binding(
            get: { pannello == s },
            set: { if !$0 && pannello == s { pannello = nil } }
        )) {
            PannelloStrumento(model: model, strumento: s)
        }
    }
}

struct PannelloStrumento: View {
    @ObservedObject var model: NotesModel
    let strumento: NotesModel.Strumento

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch strumento {
            case .penna:
                ColorPicker("Colore", selection: $model.colorePenna, supportsOpacity: false)
                VStack(alignment: .leading) {
                    Text("Spessore: \(Int(model.spessorePenna))")
                    Slider(value: $model.spessorePenna, in: 1...12, step: 1)
                }
            case .evidenziatore:
                ColorPicker("Colore", selection: $model.coloreEvidenziatore, supportsOpacity: false)
                VStack(alignment: .leading) {
                    Text("Spessore: \(Int(model.spessoreEvidenziatore))")
                    Slider(value: $model.spessoreEvidenziatore, in: 8...40, step: 1)
                }
            case .gomma:
                Toggle("Cancella il tratto intero", isOn: $model.gommaTrattoIntero)
                Text("Spento: cancella solo dove passi con la Pencil.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// Versione flottante: capsula con maniglia, si trascina dove serve.
struct BarraFlottante: View {
    @ObservedObject var model: NotesModel
    @State private var posizione: CGSize = .zero
    @GestureState private var trascinamento: CGSize = .zero

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($trascinamento) { valore, stato, _ in stato = valore.translation }
                        .onEnded { valore in
                            posizione.width += valore.translation.width
                            posizione.height += valore.translation.height
                        }
                )
            BarraStrumenti(model: model)
        }
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 3)
        .offset(
            x: posizione.width + trascinamento.width,
            y: posizione.height + trascinamento.height
        )
        .padding(.bottom, 24)
    }
}
