// Barra laterale
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Barra laterale

struct AptSectionLabel: View {
    let title: String
    let onAdd: () -> Void
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundColor(AptTema.testo2)
                .lineLimit(1)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundColor(AptTema.testo2)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct AptSidebar: View {
    @EnvironmentObject var store: AptStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    AptSectionLabel(title: "Raccolte") { store.addCollection(parent: nil) }
                    AptSideRow(
                        item: AptSideItem(id: AptStore.allID, name: "Tutti i documenti", count: store.allDocs.count, depth: 0, hasChildren: false),
                        tree: .collections, isAll: true
                    )
                    ForEach(store.flatCollections(store.meta.collections, depth: 0)) { item in
                        AptSideRow(item: item, tree: .collections, isAll: false)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    AptSectionLabel(title: store.activeCollection.map { "Cartelle · " + $0.name } ?? "Cartelle") {
                        store.addFolder(parent: "")
                    }
                    let items = store.sidebarFolderItems()
                    if items.isEmpty && store.activeCollection != nil {
                        Text("Nessuna cartella in questa raccolta.")
                            .font(AptTema.dettaglio)
                            .foregroundColor(AptTema.testo2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    ForEach(items) { item in
                        AptSideRow(item: item, tree: .folders, isAll: false)
                    }
                }
                Button {
                    store.importerForRoot = true
                    store.showImporter = true
                } label: {
                    Label(store.rootURL?.lastPathComponent ?? "Libreria", systemImage: "externaldrive")
                        .font(AptTema.dettaglio)
                        .foregroundColor(AptTema.testo2)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            .padding(10)
        }
        .background(AptTema.sfondo)
    }
}

struct AptSideRow: View {
    @EnvironmentObject var store: AptStore
    let item: AptSideItem
    let tree: AptTree
    let isAll: Bool
    @State private var hover = false

    private var isActive: Bool { tree == .collections && store.selectedCollection == item.id }
    private var isEditing: Bool { store.editingID == item.id && store.editingTree == tree }
    private var icon: String { tree == .collections ? "square.stack.3d.up" : "folder" }

    var body: some View {
        Group {
            if isEditing {
                rowContent
            } else if isAll {
                rowContent
            } else {
                rowContent
                    .onDrag {
                        store.dragging = AptDrag(kind: tree == .collections ? .collection : .folder, source: .sidebar, id: item.id)
                        return NSItemProvider(object: item.id as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: AptSidebarDropDelegate(store: store, targetID: item.id, tree: tree))
            }
        }
        .frame(height: 34)
        .overlay(indicator)
        .padding(.leading, CGFloat(item.depth) * 16)
        .onHover { hover = $0 }
        .contextMenu { if !isAll { menu } }
        .sheet(isPresented: Binding(
            get: { isEditing },
            set: { if !$0 && store.editingID == item.id { store.editingID = nil } }
        )) {
            AptRinomina(
                titolo: "Rinomina",
                nome: item.name,
                salva: { store.commitEdit(item.id, tree: tree, text: $0) },
                annulla: { store.editingID = nil }
            )
            .presentationDetents([.height(470)])
            .aptPannello()
        }
    }

    private var rowContent: some View {
        HStack(spacing: 2) {
            if hover && !isAll && !isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(AptTema.testo2)
                    .frame(width: 14)
            }
            do {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .frame(width: 17)
                        .foregroundStyle(isActive ? AptTema.accentoTesto : AptTema.testo2)
                    Text(item.name)
                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(item.count)")
                        .font(AptTema.dettaglio)
                        .foregroundStyle(isActive ? AptTema.accentoScuro.opacity(0.8) : AptTema.testo2)
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .foregroundStyle(isActive ? AptTema.accentoScuro : AptTema.testo)
                .background(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).fill(isActive ? AptTema.accentoTenue : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { tap() }
            }
            if (hover || isActive || tree == .folders) && !isAll && !isEditing {
                Button { addChild() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundColor(AptTema.testo2)
            }
        }
    }

    @ViewBuilder private var indicator: some View {
        if let ind = store.dropIndicator, ind.id == "s:" + item.id {
            switch ind.zone {
            case .before:
                Rectangle().fill(AptTema.accento).frame(height: 2).padding(.horizontal, 8).frame(maxHeight: .infinity, alignment: .top)
            case .after:
                Rectangle().fill(AptTema.accento).frame(height: 2).padding(.horizontal, 8).frame(maxHeight: .infinity, alignment: .bottom)
            case .inside:
                RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous)
                    .strokeBorder(AptTema.accento, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }

    @ViewBuilder private var menu: some View {
        Button { store.editingTree = tree; store.editingID = item.id } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        Button { addChild() } label: {
            Label(tree == .collections ? "Nuova sotto-raccolta" : "Nuova sottocartella", systemImage: "plus")
        }
        if tree == .folders && AptPath.parent(item.id).isEmpty {
            Button { store.sheet = .collectionPicker(folder: item.id) } label: {
                Label("Aggiungi a raccolta", systemImage: "folder")
            }
        }
        AptLinea()
        Button(role: .destructive) {
            if tree == .collections {
                store.removeCollection(item.id)
            } else {
                store.pendingDelete = AptPendingDelete(docs: [], folders: [item.id])
            }
        } label: {
            Label("Rimuovi", systemImage: "trash")
        }
    }

    private func tap() {
        if item.hasChildren { store.toggleExpanded(item.id) }
        if tree == .collections {
            store.selectCollection(item.id)
        } else {
            store.open(folder: item.id)
        }
    }
    private func addChild() {
        if tree == .collections { store.addCollection(parent: item.id) } else { store.addFolder(parent: item.id) }
    }
}

struct AptSidebarDropDelegate: DropDelegate {
    let store: AptStore
    let targetID: String
    let tree: AptTree
    static let rowHeight: CGFloat = 34

    private func zone(_ info: DropInfo) -> AptDropZone {
        guard let d = store.dragging else { return .inside }
        // una cartella trascinata su una raccolta si assegna: sempre "dentro"
        if d.kind == .folder && tree == .collections { return .inside }
        let y = info.location.y
        if y < AptSidebarDropDelegate.rowHeight * 0.28 { return .before }
        if y > AptSidebarDropDelegate.rowHeight * 0.72 { return .after }
        return .inside
    }
    private func accepts() -> Bool {
        guard let d = store.dragging, d.source == .sidebar, d.id != targetID else { return false }
        switch (d.kind, tree) {
        case (.folder, .collections): return AptPath.parent(d.id).isEmpty
        case (.folder, .folders): return !AptPath.isInside(targetID, of: d.id)
        case (.collection, .collections): return true
        default: return false
        }
    }
    func validateDrop(info: DropInfo) -> Bool { accepts() }
    func dropEntered(info: DropInfo) {
        if accepts() { store.dropIndicator = AptDropIndicator(id: "s:" + targetID, zone: zone(info)) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard accepts() else { return DropProposal(operation: .cancel) }
        store.dropIndicator = AptDropIndicator(id: "s:" + targetID, zone: zone(info))
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if store.dropIndicator?.id == "s:" + targetID { store.dropIndicator = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard accepts(), let d = store.dragging else { return false }
        let z = zone(info)
        store.dropIndicator = nil
        store.dragging = nil
        store.sidebarDrop(drag: d, targetID: targetID, tree: tree, zone: z)
        return true
    }
}
