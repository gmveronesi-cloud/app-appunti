// Foglio «Sposta in cartella» del file aperto (menu del titolo): elenco di tutte le cartelle, come nella Libreria
import SwiftUI

struct SelettoreCartella: View {
    @ObservedObject var store: AptStore
    /// Cartella in cui il file sta adesso (non si può scegliere: non cambierebbe niente)
    let corrente: String
    let scelta: (String) -> Void
    let annulla: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button { scelta("") } label: {
                    Label("Nessuna cartella (Tutti i documenti)", systemImage: "square.stack.3d.up")
                }
                .foregroundColor(AptTema.testo)
                .disabled(corrente.isEmpty)
                ForEach(store.flatFolderItems(store.root.children, depth: 0, orderParent: "", ignoreExpanded: true)) { item in
                    Button { scelta(item.id) } label: {
                        Label(item.name, systemImage: "folder")
                    }
                    .foregroundColor(AptTema.testo)
                    .padding(.leading, CGFloat(item.depth) * 16)
                    .disabled(item.id == corrente)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AptTema.sfondo)
            .navigationTitle("Sposta in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Annulla", action: annulla) }
            }
        }
        .presentationDetents([.medium, .large])
        .aptPannello()
    }
}
