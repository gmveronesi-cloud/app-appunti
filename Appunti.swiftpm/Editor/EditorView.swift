// Schermata Editor: apre il documento scelto in Libreria, con barra strumenti fissa o flottante
import SwiftUI

struct EditorView: View {
    let doc: AptDoc
    @StateObject private var model = NotesModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("posizioneBarra") private var posizioneBarra: String = "fissa"
    @AppStorage("barraPos") private var posizioneFissa: String = "alto"
    @AppStorage("barraGrande") private var grande = false
    @State private var mostraImpostazioni = false

    var body: some View {
        NavigationStack {
            corpo
            .overlay(alignment: .bottom) {
                if posizioneBarra == "flottante" {
                    GeometryReader { geo in
                        BarraFlottante(model: model, area: geo.size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
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
                        ImpostazioniEditor(model: model)
                    }
                    Button("Scarta tratti") { model.discardUnsaved() }
                    Button("Salva") { model.save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { model.open(url: doc.url) }
    }

    private var fissaInAlto: Bool { posizioneBarra == "fissa" && posizioneFissa == "alto" }
    private var fissaInBasso: Bool { posizioneBarra == "fissa" && posizioneFissa == "basso" }
    private var fissaASinistra: Bool { posizioneBarra == "fissa" && posizioneFissa == "sinistra" }

    private var vistaPDF: some View {
        PDFKitView(model: model)
            .ignoresSafeArea(edges: fissaInBasso ? Edge.Set() : Edge.Set.bottom)
    }

    private var corpo: some View {
        VStack(spacing: 0) {
            if !model.message.isEmpty {
                Text(model.message)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }
            if fissaInAlto {
                BarraStrumenti(model: model)
                    .frame(maxWidth: .infinity)
                Divider()
            }
            if fissaASinistra {
                HStack(spacing: 0) {
                    BarraStrumenti(model: model, verticale: true)
                        .frame(width: grande ? 76 : 64)
                    Divider()
                    vistaPDF
                }
            } else {
                vistaPDF
            }
            if fissaInBasso {
                Divider()
                BarraStrumenti(model: model)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
