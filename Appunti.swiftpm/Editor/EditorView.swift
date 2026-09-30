// Schermata Editor: apre il documento scelto in Libreria, con barra strumenti fissa o flottante
import SwiftUI

struct EditorView: View {
    let doc: AptDoc
    @StateObject private var model = NotesModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("posizioneBarra") private var posizioneBarra: String = "fissa"
    @State private var mostraImpostazioni = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.message.isEmpty {
                    Text(model.message)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    Divider()
                }
                if posizioneBarra == "fissa" {
                    BarraStrumenti(model: model)
                        .frame(maxWidth: .infinity)
                    Divider()
                }
                PDFKitView(model: model)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .bottom) {
                if posizioneBarra == "flottante" {
                    BarraFlottante(model: model)
                }
            }
            .navigationTitle(doc.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        model.close()
                        dismiss()
                    } label: { Label("Libreria", systemImage: "chevron.left") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { mostraImpostazioni = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Impostazioni")
                    .popover(isPresented: $mostraImpostazioni) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Barra strumenti").font(.headline)
                            Picker("Barra strumenti", selection: $posizioneBarra) {
                                Text("Fissa in alto").tag("fissa")
                                Text("Flottante").tag("flottante")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(20)
                        .frame(width: 320)
                    }
                    Button("Scarta tratti") { model.discardUnsaved() }
                    Button("Salva") { model.save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { model.open(url: doc.url) }
    }
}
