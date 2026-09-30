// Impostazioni dell'Editor (ingranaggio): aspetto della barra e comportamento di dito e Pencil.
import SwiftUI

struct ImpostazioniEditor: View {
    @ObservedObject var model: NotesModel

    @AppStorage("posizioneBarra") private var modo = "fissa"
    @AppStorage("barraPos") private var pos = "alto"
    @AppStorage("barraOri") private var ori = "h"
    @AppStorage("barraGrande") private var grande = false
    @AppStorage("barraNomi") private var nomi = false
    @AppStorage("barraUndo") private var undoFissi = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Barra strumenti").font(.headline)

                Picker("Modalità", selection: $modo) {
                    Text("Fissa").tag("fissa")
                    Text("Flottante").tag("flottante")
                }
                .pickerStyle(.segmented)

                if modo == "fissa" {
                    etichettato("Posizione") {
                        Picker("Posizione", selection: $pos) {
                            Text("Alto").tag("alto")
                            Text("Basso").tag("basso")
                            Text("Sinistra").tag("sinistra")
                        }
                        .pickerStyle(.segmented)
                    }
                } else {
                    etichettato("Orientamento") {
                        Picker("Orientamento", selection: $ori) {
                            Text("Orizzontale").tag("h")
                            Text("Verticale").tag("v")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                etichettato("Dimensione") {
                    Picker("Dimensione", selection: $grande) {
                        Text("Normale").tag(false)
                        Text("Grande").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Mostra i nomi sotto le icone", isOn: $nomi)
                Toggle("Annulla e Ripeti nella barra", isOn: $undoFissi)

                Divider()
                Text("Comportamento").font(.headline)

                etichettato("Dito sul foglio") {
                    Picker("Dito sul foglio", selection: $model.ditoDisegna) {
                        Text("Scorre").tag(false)
                        Text("Disegna").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Tocco con due dita = annulla", isOn: $model.dueDitaAnnulla)
                HStack {
                    Text("Doppio tocco sulla Pencil")
                    Spacer()
                    Picker("Doppio tocco sulla Pencil", selection: $model.doppioTocco) {
                        ForEach(DoppioTocco.allCases) { Text($0.nome).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            .padding(20)
        }
        .frame(width: 360, height: 520)
    }

    private func etichettato<C: View>(_ titolo: String, @ViewBuilder _ contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titolo).font(.subheadline).foregroundStyle(.secondary)
            contenuto()
        }
    }
}
