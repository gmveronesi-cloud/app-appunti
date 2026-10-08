// Griglia / lista di elementi
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Griglia / lista di elementi

struct AptItemsView: View {
    @EnvironmentObject var store: AptStore
    let model: AptScreenModel

    private var cartelle: [AptEntry] {
        model.subCollections.map { AptEntry(kind: .collection($0)) }
        + model.folders.map { AptEntry(kind: .folder($0)) }
    }
    private var documenti: [AptEntry] { model.docs.map { AptEntry(kind: .doc($0)) } }

    var body: some View {
        // i titoli delle sezioni compaiono solo quando ci sono sia cartelle sia documenti
        let titoli = !cartelle.isEmpty && !documenti.isEmpty
        VStack(alignment: .leading, spacing: 28) {
            if !cartelle.isEmpty { sezione("Cartelle", cartelle, titolo: titoli, cartelle: true) }
            if !documenti.isEmpty { sezione("Documenti", documenti, titolo: titoli, cartelle: false) }
        }
    }

    @ViewBuilder
    private func sezione(_ nome: String, _ lista: [AptEntry], titolo: Bool, cartelle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if titolo {
                HStack(spacing: 8) {
                    Text(nome).font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
                    Text("\(lista.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AptTema.testo2)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(AptTema.linea.opacity(0.7)))
                }
            }
            if store.libView == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cartelle ? 150 : 118), spacing: 16)], alignment: .leading, spacing: 20) {
                    ForEach(lista) { e in
                        AptEntryView(entry: e, grid: true, model: model)
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(lista) { e in
                        AptEntryView(entry: e, grid: false, model: model)
                    }
                }
                .aptScheda()
            }
        }
    }
}

struct AptThumbFrame<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            AptTema.carta
            content
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
        .shadow(color: AptTema.ombraColore, radius: 10, x: 0, y: 4)
    }
}

struct AptEntryView: View {
    @EnvironmentObject var store: AptStore
    let entry: AptEntry
    let grid: Bool
    let model: AptScreenModel
    @State private var info: AptDocInfo?
    @State private var size: CGSize = .zero

    // Chiave di selezione ("doc:<percorso>" / "folder:<percorso>"); nil = non selezionabile
    private var selKey: String? {
        switch entry.kind {
        case .doc(let d): return "doc:" + d.id
        case .folder(let f): return "folder:" + f.id
        case .collection: return nil
        }
    }
    private var dragKind: AptDragKind? {
        switch entry.kind {
        case .doc: return .doc
        case .folder: return .folder
        case .collection: return nil
        }
    }
    private var rawID: String {
        switch entry.kind {
        case .doc(let d): return d.id
        case .folder(let f): return f.id
        case .collection(let c): return c.id
        }
    }
    private var name: String {
        switch entry.kind {
        case .doc(let d): return d.name
        case .folder(let f): return f.name
        case .collection(let c): return c.name
        }
    }
    private var meta: String {
        switch entry.kind {
        case .doc(let d):
            var parts = ["PDF"]
            if let p = info?.pages { parts.append("\(p) pag") }
            parts.append(AptFormat.relative(d.modDate))
            return parts.joined(separator: " · ")
        case .folder(let f): return AptFormat.documents(f.docCount)
        case .collection: return "Raccolta"
        }
    }
    private var selectable: Bool { store.selectionMode && selKey != nil }
    private var isSelected: Bool { selKey.map { store.selected.contains($0) } ?? false }
    private var canReorder: Bool { store.sortMode == .manual && !store.selectionMode && dragKind != nil }

    var body: some View {
        Group {
            if canReorder, let kind = dragKind {
                content
                    .onDrag {
                        store.dragging = AptDrag(kind: kind, source: .grid, id: rawID)
                        return NSItemProvider(object: rawID as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: AptGridDropDelegate(
                        store: store, targetID: rawID, kind: kind, horizontal: grid, size: size,
                        onReorder: { drag, before in
                            store.reorderEntry(model: model, kind: kind, drag: drag, target: rawID, before: before)
                        }))
            } else {
                content
            }
        }
        .aptReadSize { size = $0 }
        .overlay(indicatorOverlay)
        .onTapGesture { tap() }
        .contextMenu { if !store.selectionMode { entryMenu } }
        .task(id: taskID) {
            if case .doc(let d) = entry.kind { info = await AptDocInfoLoader.load(d) }
        }
    }

    private var taskID: String {
        if case .doc(let d) = entry.kind { return d.id + "|\(d.modDate.timeIntervalSince1970)" }
        return ""
    }

    @ViewBuilder private var content: some View {
        if grid { gridCard } else { listRow }
    }

    private func tap() {
        if let k = selKey, store.selectionMode {
            store.toggleSelection(k)
            return
        }
        switch entry.kind {
        case .doc(let d): store.openDocument = d
        case .folder(let f): store.open(folder: f.id)
        case .collection(let c): store.selectCollection(c.id)
        }
    }

    // Icone / griglia
    private var gridCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if case .doc = entry.kind {
                    AptThumbFrame { thumbContent }
                } else {
                    AptFolderTile(icon: tileIcon)
                }
                if selectable { AptCheck(checked: isSelected).padding(6) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous)
                    .stroke(AptTema.accento, lineWidth: isSelected ? 2.5 : 0)
            )
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(AptTema.testo).lineLimit(1)
            Text(meta).font(AptTema.dettaglio).foregroundColor(AptTema.testo2).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var thumbContent: some View {
        switch entry.kind {
        case .doc:
            if let img = info?.image {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(AptTema.linea).frame(height: 4)
                            .frame(maxWidth: i == 2 ? 60 : .infinity, alignment: .leading)
                    }
                    Spacer()
                }
                .padding(8)
            }
        case .folder, .collection:
            EmptyView()
        }
    }

    private var tileIcon: String {
        if case .collection = entry.kind { return "square.stack.3d.up.fill" }
        return "folder.fill"
    }

    // Menu del tocco lungo: rinomina, sposta, elimina
    @ViewBuilder private var entryMenu: some View {
        switch entry.kind {
        case .doc(let d):
            Button { store.renaming = .doc(d.id) } label: { Label("Rinomina", systemImage: "pencil") }
            Button { store.selected = ["doc:" + d.id]; store.sheet = .movePicker } label: { Label("Sposta in…", systemImage: "folder") }
            Button(role: .destructive) { store.pendingDelete = AptPendingDelete(docs: [d.id], folders: []) } label: { Label("Elimina", systemImage: "trash") }
        case .folder(let f):
            Button { store.renaming = .folder(f.id) } label: { Label("Rinomina", systemImage: "pencil") }
            Button { store.addFolder(parent: f.id) } label: { Label("Nuova sottocartella", systemImage: "folder.badge.plus") }
            Button { store.selected = ["folder:" + f.id]; store.sheet = .movePicker } label: { Label("Sposta in…", systemImage: "folder") }
            if AptPath.parent(f.id).isEmpty {
                Button { store.sheet = .collectionPicker(folder: f.id) } label: { Label("Aggiungi a raccolta", systemImage: "square.stack.3d.up") }
            }
            Button(role: .destructive) { store.pendingDelete = AptPendingDelete(docs: [], folders: [f.id]) } label: { Label("Elimina", systemImage: "trash") }
        case .collection(let c):
            Button { store.renaming = .collection(c.id) } label: { Label("Rinomina", systemImage: "pencil") }
            Button(role: .destructive) { store.removeCollection(c.id) } label: { Label("Rimuovi raccolta", systemImage: "trash") }
        }
    }

    // Lista
    private var listRow: some View {
        HStack(spacing: 12) {
            if selectable { AptCheck(checked: isSelected) }
            listIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 15, weight: .semibold)).foregroundColor(AptTema.testo).lineLimit(1)
                Text(meta).font(AptTema.dettaglio).foregroundColor(AptTema.testo2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { AptLinea() }
    }

    @ViewBuilder private var listIcon: some View {
        switch entry.kind {
        case .doc:
            ZStack {
                AptTema.carta
                if let img = info?.image { Image(uiImage: img).resizable().scaledToFit() }
            }
            .frame(width: 30, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AptTema.linea, lineWidth: 1))
        case .folder:
            folderChip("folder")
        case .collection:
            folderChip("square.stack.3d.up")
        }
    }
    private func folderChip(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15))
            .foregroundColor(AptTema.accentoTesto)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).fill(AptTema.accentoTenue))
    }

    // Linea di inserimento durante il riordino manuale
    @ViewBuilder private var indicatorOverlay: some View {
        if let ind = store.dropIndicator, ind.id == "g:" + rawID {
            if grid {
                Rectangle().fill(AptTema.accento).frame(width: 3)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: ind.zone == .before ? .leading : .trailing)
                    .offset(x: ind.zone == .before ? -8 : 8)
            } else {
                Rectangle().fill(AptTema.accento).frame(height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: ind.zone == .before ? .top : .bottom)
            }
        }
    }
}

/// Riquadro di una cartella o raccolta nella griglia: tinta tenue dell'accento con icona piena.
struct AptFolderTile: View {
    let icon: String
    var body: some View {
        ZStack {
            AptTema.accentoTenue
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AptTema.accento)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
    }
}

struct AptCheck: View {
    let checked: Bool
    var body: some View {
        ZStack {
            Circle().fill(checked ? AptTema.accento : AptTema.carta.opacity(0.95))
            Circle().stroke(checked ? AptTema.accento : AptTema.linea, lineWidth: 1.5)
            if checked { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(AptTema.suAccento) }
        }
        .frame(width: 21, height: 21)
    }
}

struct AptGridDropDelegate: DropDelegate {
    let store: AptStore
    let targetID: String
    let kind: AptDragKind
    let horizontal: Bool
    let size: CGSize
    let onReorder: (String, Bool) -> Void

    private func isBefore(_ info: DropInfo) -> Bool {
        horizontal ? info.location.x < size.width / 2 : info.location.y < size.height / 2
    }
    private func accepts() -> Bool {
        guard let d = store.dragging else { return false }
        return d.source == .grid && d.kind == kind && d.id != targetID
    }
    func validateDrop(info: DropInfo) -> Bool { accepts() }
    func dropEntered(info: DropInfo) {
        if accepts() { store.dropIndicator = AptDropIndicator(id: "g:" + targetID, zone: isBefore(info) ? .before : .after) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard accepts() else { return DropProposal(operation: .cancel) }
        store.dropIndicator = AptDropIndicator(id: "g:" + targetID, zone: isBefore(info) ? .before : .after)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if store.dropIndicator?.id == "g:" + targetID { store.dropIndicator = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard accepts(), let d = store.dragging else { return false }
        let before = isBefore(info)
        store.dropIndicator = nil
        store.dragging = nil
        onReorder(d.id, before)
        return true
    }
}
