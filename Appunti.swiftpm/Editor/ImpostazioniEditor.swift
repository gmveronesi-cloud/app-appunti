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
    @State private var chiediScarto = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Aspetto").font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
                etichettato("Tema") { SelettoreAspetto() }

                AptLinea()
                Text("Barra strumenti").font(AptTema.titoloMedio).foregroundColor(AptTema.testo)

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

                AptLinea()
                Text("Comportamento").font(AptTema.titoloMedio).foregroundColor(AptTema.testo)

                etichettato("Dito sul foglio") {
                    Picker("Dito sul foglio", selection: $model.ditoDisegna) {
                        Text("Scorre").tag(false)
                        Text("Disegna").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                etichettato("Salvataggio") {
                    Picker("Salvataggio", selection: $model.salvataggioAutomatico) {
                        Text("Automatico").tag(true)
                        Text("Manuale").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                Button("Scarta i tratti non salvati") { chiediScarto = true }
                    .buttonStyle(AptStileContorno(pericolo: true))
                Toggle("Tocco con due dita = annulla", isOn: $model.dueDitaAnnulla)
                Toggle("Rette e forme con la Pencil ferma", isOn: $model.formeFerma)
                HStack {
                    Text("Penna screenshot: dove va")
                    Spacer()
                    Picker("Penna screenshot", selection: $model.destinazioneCattura) {
                        ForEach(DestinazioneCattura.allCases) { Text($0.nome).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
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
        .frame(width: 360, height: 560)
        .confirmationDialog("Scartare i tratti non salvati?", isPresented: $chiediScarto, titleVisibility: .visible) {
            Button("Scarta", role: .destructive) { model.discardUnsaved() }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func etichettato<C: View>(_ titolo: String, @ViewBuilder _ contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titolo).font(AptTema.dettaglio).foregroundStyle(AptTema.testo2)
            contenuto()
        }
    }
}
