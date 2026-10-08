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
        .fullScreenCover(isPresented: $store.showModelli) {
            PaginaModelli(modo: .nuovo,
                          scegli: { modello, formato, _ in
                              if let doc = store.createNotebook(in: currentFolderPath, modello: modello, formato: formato) { store.openDocument = doc }
                          },
                          chiudi: { store.showModelli = false })
        }
        .onChange(of: pickedPhotos) { _, items in
            handlePicked(items)
        }
    }

    // Intestazione: percorso (dentro una cartella), titolo grande, riepilogo, "Gestisci cartelle" nelle raccolte
    @ViewBuilder private func header(_ model: AptScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isFolder { percorso }
            HStack(spacing: 10) {
                if model.isFolder {
                    Button { store.folderBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AptTema.accentoTesto)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AptTema.accentoTenue))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
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
            Text(riepilogo(model))
                .font(AptTema.dettaglio)
                .foregroundColor(AptTema.testo2)
        }
        .padding(.bottom, 20)
    }

    /// Briciole di pane: Raccolta › Cartella › Sottocartella (la cartella aperta è il titolo qui sotto)
    private var percorso: some View {
        let parti = (store.openFolder ?? "").split(separator: "/").map(String.init)
        let radice = store.activeCollection?.name ?? "Tutti i documenti"
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { store.selectCollection(store.selectedCollection) } label: {
                    Text(radice).font(AptTema.dettaglio).foregroundColor(AptTema.accentoTesto)
                }
                .buttonStyle(.plain)
                ForEach(Array(parti.dropLast().enumerated()), id: \.offset) { i, nome in
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(AptTema.testo2)
                    Button { store.open(folder: parti[0...i].joined(separator: "/")) } label: {
                        Text(nome).font(AptTema.dettaglio).foregroundColor(AptTema.accentoTesto)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func riepilogo(_ m: AptScreenModel) -> String {
        var parti: [String] = []
        let nCartelle = m.folders.count + m.subCollections.count
        if nCartelle > 0 { parti.append(nCartelle == 1 ? "1 cartella" : "\(nCartelle) cartelle") }
        let nDocumenti = m.collection.map { store.docIDs(in: $0).count } ?? m.docs.count
        parti.append(AptFormat.documents(nDocumenti))
        return parti.joined(separator: " · ")
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
                PulsanteColoreApp()
                Button {
                    store.importerForRoot = true
                    store.showImporter = true
                } label: { AptIcona(nome: "folder.badge.gearshape") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cambia cartella dell'app")
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
                MenuAspetto()
                Menu {
                    Section("Crea") {
                        Button { store.addFolder(parent: currentFolderPath) } label: { Label("Nuova cartella", systemImage: "folder.badge.plus") }
                        Button { store.showModelli = true } label: { Label("Nuovo quaderno", systemImage: "book.closed") }
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
