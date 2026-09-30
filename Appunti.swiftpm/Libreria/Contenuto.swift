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
        .background(Color(.systemGroupedBackground))
        .refreshable { store.reload() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
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
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            Text(model.title)
                .font(.system(size: 26, weight: .bold))
                .lineLimit(1)
            Spacer()
            if let c = model.collection, !model.isEmpty {
                Button { store.sheet = .folderPicker(collection: c.id) } label: {
                    Label("Gestisci cartelle", systemImage: "plus").font(.system(size: 12.5, weight: .semibold))
                }
                .aptProminentButton()
                .controlSize(.small)
            }
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder private func emptyState(_ model: AptScreenModel) -> some View {
        if let c = model.collection {
            AptEmptyState(icon: "square.stack.3d.up", title: "Questa raccolta è vuota",
                          text: "Scegli le cartelle da includere qui, tra quelle che hai già o creandone di nuove.",
                          buttonTitle: "Aggiungi cartelle") { store.sheet = .folderPicker(collection: c.id) }
        } else if model.isFolder {
            AptEmptyState(icon: "folder", title: "Questa cartella è vuota",
                          text: "Aggiungi documenti o crea una sottocartella con il pulsante \"Nuovo\".",
                          buttonTitle: nil, action: nil)
        } else {
            AptEmptyState(icon: "doc", title: "Nessun documento",
                          text: "Importa un PDF o crea una nota con il pulsante \"Nuovo\".",
                          buttonTitle: nil, action: nil)
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            if store.selectionMode {
                Button { store.clearSelection() } label: { Image(systemName: "xmark") }
                Text(store.selected.isEmpty ? "Seleziona" : (store.selected.count == 1 ? "1 selezionato" : "\(store.selected.count) selezionati"))
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Button { showViewSort = true } label: { Image(systemName: "arrow.up.arrow.down") }
                    .popover(isPresented: $showViewSort) {
                        AptViewSortPopover().environmentObject(store).frame(width: 264)
                    }
                Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if store.selectionMode {
                let keys = store.currentSelectableKeys()
                if !keys.isEmpty {
                    let all = keys.allSatisfy { store.selected.contains($0) }
                    Button(all ? "Deseleziona tutto" : "Seleziona tutto") {
                        store.selected = all ? [] : keys
                    }
                }
            } else {
                if !store.currentSelectableKeys().isEmpty {
                    Button { store.selectionMode = true; store.selected = [] } label: { Image(systemName: "cursorarrow") }
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
                    Label("Nuovo", systemImage: "plus").font(.system(size: 14, weight: .semibold))
                }
                .aptProminentButton()
            }
        }
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
                .font(.system(size: 28))
                .foregroundColor(.secondary)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemFill)))
            Text(title).font(.system(size: 16, weight: .bold))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let bt = buttonTitle, let act = action {
                Button(action: act) {
                    Label(bt, systemImage: "plus").font(.system(size: 15, weight: .semibold))
                }
                .aptProminentButton()
                .controlSize(.large)
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
            Text("Visualizza come").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            AptSegmented(options: [
                AptSegOption(value: AptLibView.grid, label: "Icone", icon: "square.grid.2x2"),
                AptSegOption(value: AptLibView.list, label: "Lista", icon: "list.bullet")
            ], selection: $store.libView)
            Divider()
            Text("Ordina per").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            VStack(spacing: 1) {
                sortRow(.date, "Data di modifica")
                sortRow(.name, "Nome")
                sortRow(.manual, "Manuale")
            }
            Divider()
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
        .foregroundColor(.primary)
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
        .background(.bar)
        .opacity(1)
        .disabled(disabled)
        .overlay(alignment: .top) { Divider() }
    }
    private func barButton(_ icon: String, _ title: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(destructive ? .red : .accentColor)
            .opacity(store.selected.isEmpty ? 0.35 : 1)
        }
        .buttonStyle(.plain)
    }
}
