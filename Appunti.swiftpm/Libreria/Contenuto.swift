// Contenuto principale
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Contenuto principale

struct AptEntry: Identifiable {
    enum Kind {
        case doc(AptDoc)
        case folder(AptFolder)
        case collection(AptCollection)
    }
    let kind: Kind
    var id: String {
        switch kind {
        case .doc(let d): return "doc:" + d.id
        case .folder(let f): return "folder:" + f.id
        case .collection(let c): return "coll:" + c.id
        }
    }
}

struct AptMainView: View {
    @EnvironmentObject var store: AptStore
    let toggleSidebar: () -> Void
    @State private var showViewSort = false
    @State private var showPhotos = false
    @State private var photosMerge = true
    @State private var pickedPhotos: [PhotosPickerItem] = []

    private var currentFolderPath: String { store.openFolder ?? "" }

    var body: some View {
        let model = store.makeScreenModel()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(model)
                if model.isEmpty {
                    emptyState(model)
                } else {
                    AptItemsView(model: model)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(AptTema.scrivania)
        .refreshable { store.reload() }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { barraAlta }
        .safeAreaInset(edge: .bottom) {
            if store.selectionMode { AptSelectionBar() }
        }
        .photosPicker(isPresented: $showPhotos, selection: $pickedPhotos, matching: .images)
        .onChange(of: pickedPhotos) { items in
            handlePicked(items)
        }
    }

    // Intestazione: titolo grande, freccia indietro dentro una cartella, "Gestisci cartelle" nelle raccolte
    @ViewBuilder private func header(_ model: AptScreenModel) -> some View {
        HStack(spacing: 12) {
            if model.isFolder {
                Button { store.folderBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundColor(AptTema.accento)
            }
            Text(model.title)
                .font(AptTema.titoloGrande)
                .foregroundColor(AptTema.testo)
                .lineLimit(1)
            Spacer()
            if let c = model.collection, !model.isEmpty {
                Button { store.sheet = .folderPicker(collection: c.id) } label: {
                    Label("Gestisci cartelle", systemImage: "plus")
                }
                .buttonStyle(AptStileSecondario())
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder private func emptyState(_ model: AptScreenModel) -> some View {
        if let c = model.collection {
            AptEmptyState(icon: "square.stack.3d.up", title: "Questa raccolta è vuota",
                          text: "",
                          buttonTitle: "Aggiungi cartelle") { store.sheet = .folderPicker(collection: c.id) }
        } else if model.isFolder {
            AptEmptyState(icon: "folder", title: "Questa cartella è vuota",
                          text: "",
                          buttonTitle: nil, action: nil)
        } else {
            AptEmptyState(icon: "doc", title: "Nessun documento",
                          text: "",
                          buttonTitle: nil, action: nil)
        }
    }

    // Barra in alto nello stile dell'app (al posto della barra di sistema)
    private var barraAlta: some View {
        HStack(spacing: 4) {
            if store.selectionMode {
                Button { store.clearSelection() } label: { AptIcona(nome: "xmark") }
                    .buttonStyle(.plain)
                Text(store.selected.isEmpty ? "Seleziona" : (store.selected.count == 1 ? "1 selezionato" : "\(store.selected.count) selezionati"))
                    .font(AptTema.corpoForte)
                    .foregroundColor(AptTema.testo)
                    .padding(.leading, 4)
            } else {
                Button { showViewSort = true } label: { AptIcona(nome: "arrow.up.arrow.down", attiva: showViewSort) }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showViewSort) {
                        AptViewSortPopover().environmentObject(store).frame(width: 264).aptPannello()
                    }
                Button { toggleSidebar() } label: { AptIcona(nome: "sidebar.left") }
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if store.selectionMode {
                let keys = store.currentSelectableKeys()
                if !keys.isEmpty {
                    let all = keys.allSatisfy { store.selected.contains($0) }
                    Button(all ? "Deseleziona tutto" : "Seleziona tutto") {
                        store.selected = all ? [] : keys
                    }
                    .buttonStyle(AptStileContorno())
                }
            } else {
                if !store.currentSelectableKeys().isEmpty {
                    Button { store.selectionMode = true; store.selected = [] } label: { AptIcona(nome: "checkmark.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Seleziona")
                }
                Menu {
                    Section("Crea") {
                        Button { store.addFolder(parent: currentFolderPath) } label: { Label("Nuova cartella", systemImage: "folder.badge.plus") }
                        Button { createNote() } label: { Label("Nuova nota di appunti", systemImage: "note.text") }
                        Button { photosMerge = true; showPhotos = true } label: { Label("Da immagine a PDF", systemImage: "doc.richtext") }
                    }
                    Section("Importa") {
                        Button {
                            store.importTarget = currentFolderPath
                            store.importerForRoot = false
                            store.showImporter = true
                        } label: { Label("File", systemImage: "folder") }
                        Button { photosMerge = false; showPhotos = true } label: { Label("Foto o immagine", systemImage: "photo") }
                    }
                } label: {
                    Label("Nuovo", systemImage: "plus")
                        .font(AptTema.corpoForte)
                        .foregroundStyle(AptTema.suAccento)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(AptTema.accento, in: Capsule())
                }
            }
        }
        .aptBarra()
        .background(AptTema.scrivania)
    }

    private func createNote() {
        if let doc = store.createNote(in: currentFolderPath) { store.openDocument = doc }
    }

    private func handlePicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let merge = photosMerge
        let target = currentFolderPath
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    images.append(img)
                }
            }
            await MainActor.run {
                store.addImages(images, merge: merge, into: target)
                pickedPhotos = []
            }
        }
    }
}

struct AptEmptyState: View {
    let icon: String
    let title: String
    let text: String
    let buttonTitle: String?
    let action: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(AptTema.accentoTesto)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: AptTema.raggioL, style: .continuous).fill(AptTema.accentoTenue))
            Text(title).font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
            if let bt = buttonTitle, let act = action {
                Button(action: act) {
                    Label(bt, systemImage: "plus")
                }
                .buttonStyle(AptStilePrimario())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(.vertical, 40)
    }
}

struct AptViewSortPopover: View {
    @EnvironmentObject var store: AptStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visualizza come").font(AptTema.dettaglio).foregroundColor(AptTema.testo2)
            AptSegmented(options: [
                AptSegOption(value: AptLibView.grid, label: "Icone", icon: "square.grid.2x2"),
                AptSegOption(value: AptLibView.list, label: "Lista", icon: "list.bullet")
            ], selection: $store.libView)
            AptLinea()
            Text("Ordina per").font(AptTema.dettaglio).foregroundColor(AptTema.testo2)
            VStack(spacing: 1) {
                sortRow(.date, "Data di modifica")
                sortRow(.name, "Nome")
                sortRow(.manual, "Manuale")
            }
            AptLinea()
            if store.sortMode != .manual {
                AptSegmented(options: [
                    AptSegOption(value: AptSortDir.asc, label: "Crescente"),
                    AptSegOption(value: AptSortDir.desc, label: "Decrescente")
                ], selection: $store.sortDir)
            }
        }
        .padding(14)
    }
    private func sortRow(_ mode: AptSortMode, _ label: String) -> some View {
        Button { store.sortMode = mode } label: {
            HStack {
                Text(label).font(.system(size: 14))
                Spacer()
                if store.sortMode == mode { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)) }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(AptTema.testo)
    }
}

struct AptSelectionBar: View {
    @EnvironmentObject var store: AptStore
    var body: some View {
        let disabled = store.selected.isEmpty
        HStack {
            barButton("folder", "Sposta", destructive: false) { store.sheet = .movePicker }
            barButton("doc.text", "Esporta come PDF", destructive: false) { store.exportSelection() }
            barButton("trash", "Elimina", destructive: true) { store.confirmDeleteSelection() }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(AptTema.carta)
        .disabled(disabled)
        .overlay(alignment: .top) { AptLinea() }
    }
    private func barButton(_ icon: String, _ title: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(AptTema.dettaglio)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(destructive ? AptTema.pericolo : AptTema.accento)
            .opacity(store.selected.isEmpty ? 0.35 : 1)
        }
        .buttonStyle(.plain)
    }
}
