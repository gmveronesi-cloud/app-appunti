// Schermata Editor: apre il documento scelto in Libreria (interfaccia ancora minima)
import SwiftUI

struct EditorView: View {
    let doc: AptDoc
    @StateObject private var model = NotesModel()
    @Environment(\.dismiss) private var dismiss

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
                PDFKitView(model: model)
                    .ignoresSafeArea(edges: .bottom)
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
                    Toggle("Evidenziatore", isOn: $model.pencilMode).fixedSize()
                    Button("Scarta tratti") { model.discardUnsaved() }
                    Button("Salva") { model.save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { model.open(url: doc.url) }
    }
}
