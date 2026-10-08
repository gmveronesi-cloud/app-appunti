// Fogli (Sposta, Aggiungi cartelle, Aggiungi a raccolta)
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Fogli (Sposta, Aggiungi cartelle, Aggiungi a raccolta, Condividi)

struct AptSheetView: View {
    @EnvironmentObject var store: AptStore
    let sheet: AptSheet
    var body: some View {
        switch sheet {
        case .movePicker:
            AptMovePicker()
        case .folderPicker(let collection):
            AptFolderPicker(collectionID: collection)
        case .collectionPicker(let folder):
            AptCollectionPicker(folderPath: folder)
        case .share(let urls, _):
            AptShareSheet(items: urls)
        }
    }
}

struct AptMovePicker: View {
    @EnvironmentObject var store: AptStore
    var body: some View {
        NavigationStack {
            List {
                Button { store.moveSelection(to: "") } label: {
                    Label("Nessuna cartella (Tutti i documenti)", systemImage: "square.stack.3d.up")
                }
                .foregroundColor(AptTema.testo)
                ForEach(store.flatFolderItems(store.root.children, depth: 0, orderParent: "", ignoreExpanded: true)) { item in
                    Button { store.moveSelection(to: item.id) } label: {
                        Label(item.name, systemImage: "folder")
                    }
                    .foregroundColor(AptTema.testo)
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AptTema.sfondo)
            .navigationTitle("Sposta in…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Annulla") { store.sheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .aptPannello()
    }
}

struct AptFolderPicker: View {
    @EnvironmentObject var store: AptStore
    let collectionID: String
    var body: some View {
        let coll = AptColl.find(store.meta.collections, collectionID)
        NavigationStack {
            List {
                Section {
                    if store.root.children.isEmpty {
                        Text("Non hai ancora nessuna cartella.").foregroundColor(AptTema.testo2)
                    }
                    ForEach(store.orderedFolders(store.root.children, parent: "")) { f in
                        Button { store.toggleFolder(f.id, inCollection: collectionID) } label: {
                            HStack {
                                Label(f.name, systemImage: "folder")
                                Spacer()
                                if coll?.folderPaths.contains(f.id) == true {
                                    Image(systemName: "checkmark").foregroundColor(AptTema.accento)
                                }
                            }
                        }
                        .foregroundColor(AptTema.testo)
                    }
                }
                Section {
                    Button { store.createFolderForCollection(collectionID) } label: {
                        Label("Crea nuova cartella", systemImage: "plus")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AptTema.sfondo)
            .navigationTitle("Aggiungi cartelle a \"\(coll?.name ?? "")\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Fine") { store.sheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .aptPannello()
    }
}

struct AptCollRow: Identifiable {
    let coll: AptCollection
    let depth: Int
    var id: String { coll.id }
}

struct AptCollectionPicker: View {
    @EnvironmentObject var store: AptStore
    let folderPath: String
    var body: some View {
        let flat = AptColl.flatten(store.meta.collections, depth: 0).map { AptCollRow(coll: $0.0, depth: $0.1) }
        NavigationStack {
            List {
                if flat.isEmpty {
                    Text("Non hai ancora nessuna raccolta oltre a \"Tutti i documenti\".")
                        .foregroundColor(AptTema.testo2)
                }
                ForEach(flat) { row in
                    Button { store.toggleFolder(folderPath, inCollection: row.coll.id) } label: {
                        HStack {
                            Label(row.coll.name, systemImage: "square.stack.3d.up")
                            Spacer()
                            if row.coll.folderPaths.contains(folderPath) {
                                Image(systemName: "checkmark").foregroundColor(AptTema.accento)
                            }
                        }
                    }
                    .foregroundColor(AptTema.testo)
                    .padding(.leading, CGFloat(row.depth) * 16)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AptTema.sfondo)
            .navigationTitle("Aggiungi \"\(AptPath.name(folderPath))\" a una raccolta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Fine") { store.sheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .aptPannello()
    }
}

// MARK: - Finestra del nome (rinomina e creazione di cartelle, raccolte, documenti)

struct AptRenameSheet: View {
    @EnvironmentObject var store: AptStore
    let target: AptRenameTarget
    @State private var fatto = false
    var body: some View {
        AptRinomina(
            titolo: target.titolo,
            nome: store.initialName(for: target),
            salva: { testo in
                guard !fatto else { return }
                fatto = true
                store.commitRename(target, text: testo)
            },
            annulla: { store.renaming = nil }
        )
        .presentationDetents([.height(470)])
        .aptPannello()
    }
}
