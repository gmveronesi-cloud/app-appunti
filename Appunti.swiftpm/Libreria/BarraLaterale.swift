// Barra laterale: intestazione della libreria, raccolte, cartelle, recenti
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
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundColor(AptTema.testo2)
                .lineLimit(1)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AptTema.accentoTesto)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AptTema.accentoTenue))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

/// In alto: nome della cartella della libreria e quanti documenti e cartelle contiene.
struct AptSideHeader: View {
    @EnvironmentObject var store: AptStore
    var body: some View {
        let nCartelle = store.folderCount
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(AptTema.accentoTesto)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous).fill(AptTema.accentoTenue))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.rootURL?.lastPathComponent ?? "Libreria")
                    .font(AptTema.titoloMedio)
                    .foregroundStyle(AptTema.testo)
                    .lineLimit(1)
                Text(AptFormat.documents(store.allDocs.count) + " · " + (nCartelle == 1 ? "1 cartella" : "\(nCartelle) cartelle"))
                    .font(AptTema.dettaglio)
                    .foregroundStyle(AptTema.testo2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

struct AptSidebar: View {
    @EnvironmentObject var store: AptStore
    /// Altezza di raccolte + cartelle: serve a capire quanti «Recenti» entrano nello spazio rimasto
    @State private var altezzaNavigazione: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            AptSideHeader()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        navigazione.aptReadSize { altezzaNavigazione = $0.height }
                        AptRecenti(quanti: quantiRecenti(altezza: geo.size.height))
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
            AptSideFooter()
        }
        .background(AptTema.sfondo)
    }

    /// I «Recenti» riempiono lo spazio libero in basso: tanti quanti ne entrano (da 3 a 10)
    private func quantiRecenti(altezza: CGFloat) -> Int {
        guard altezzaNavigazione > 0 else { return 5 }
        let libero = altezza - altezzaNavigazione - 20 - 18
        let n = Int((libero - AptRecenti.altezzaTitolo - 12) / AptRecenteRow.altezza)
        return min(max(n, 3), 10)
    }

    private var navigazione: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                AptSectionLabel(title: "Raccolte") { store.askNewCollection(parent: nil) }
                AptSideRow(
                    item: AptSideItem(id: AptStore.allID, name: "Tutti i documenti", count: store.allDocs.count, depth: 0, hasChildren: false),
                    tree: .collections, isAll: true
                )
                ForEach(store.flatCollections(store.meta.collections, depth: 0)) { item in
                    AptSideRow(item: item, tree: .collections, isAll: false)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                AptSectionLabel(title: store.activeCollection.map { "Cartelle · " + $0.name } ?? "Cartelle") {
                    store.addFolder(parent: "")
                }
                let items = store.sidebarFolderItems()
                if items.isEmpty {
                    Text(store.activeCollection != nil ? "Nessuna cartella in questa raccolta." : "Nessuna cartella.")
                        .font(AptTema.dettaglio)
                        .foregroundColor(AptTema.testo2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                ForEach(items) { item in
                    AptSideRow(item: item, tree: .folders, isAll: false)
                }
            }
        }
    }
}

/// Scheda «Recenti»: gli ultimi documenti modificati, con miniatura. Occupa lo spazio libero della barra laterale.
struct AptRecenti: View {
    static let altezzaTitolo: CGFloat = 38

    @EnvironmentObject var store: AptStore
    let quanti: Int

    var body: some View {
        let docs = store.recentDocs(quanti)
        if !docs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AptTema.accentoTesto)
                    Text("Recenti")
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.6)
                        .textCase(.uppercase)
                        .foregroundColor(AptTema.testo2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: AptRecenti.altezzaTitolo)
                VStack(spacing: 0) {
                    ForEach(docs) { d in AptRecenteRow(doc: d) }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .aptScheda()
        }
    }
}

struct AptRecenteRow: View {
    static let altezza: CGFloat = 54

    @EnvironmentObject var store: AptStore
    let doc: AptDoc
    @State private var info: AptDocInfo?

    var body: some View {
        Button { store.openDocument = doc } label: {
            HStack(spacing: 10) {
                ZStack {
                    AptTema.sfondo
                    if let img = info?.image { Image(uiImage: img).resizable().scaledToFit() }
                }
                .frame(width: 34, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AptTema.testo)
                        .lineLimit(1)
                    Text(dettaglio)
                        .font(AptTema.dettaglio)
                        .foregroundStyle(AptTema.testo2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: AptRecenteRow.altezza)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: doc.id + "|\(doc.modDate.timeIntervalSince1970)") {
            info = await AptDocInfoLoader.load(doc)
        }
    }

    private var dettaglio: String {
        var parti: [String] = []
        if let p = info?.pages { parti.append("\(p) pag") }
        parti.append(AptFormat.relative(doc.modDate))
        return parti.joined(separator: " · ")
    }
}

/// Piede della barra laterale, sempre in basso: nuovo quaderno e importazione di PDF.
struct AptSideFooter: View {
    @EnvironmentObject var store: AptStore

    var body: some View {
        VStack(spacing: 0) {
            AptLinea()
            HStack(spacing: AptTema.s2) {
                azione("Quaderno", "square.and.pencil") { store.showModelli = true }
                azione("Importa", "square.and.arrow.down") {
                    store.importTarget = store.openFolder ?? ""
                    store.importerForRoot = false
                    store.showImporter = true
                }
            }
            .padding(.horizontal, AptTema.s3)
            .padding(.vertical, AptTema.s3)
        }
        .background(AptTema.sfondo)
    }

    private func azione(_ titolo: String, _ icona: String, _ fai: @escaping () -> Void) -> some View {
        Button(action: fai) {
            Label(titolo, systemImage: icona)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AptTema.accentoScuro)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AptTema.accentoTenue, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AptSideRow: View {
    static let altezza: CGFloat = 38

    @EnvironmentObject var store: AptStore
    let item: AptSideItem
    let tree: AptTree
    let isAll: Bool

    private var isActive: Bool {
        switch tree {
        case .collections: return store.selectedCollection == item.id && store.openFolder == nil
        case .folders: return store.openFolder == item.id
        }
    }
    private var icon: String {
        if tree == .collections { return isAll ? "tray.full" : "square.stack.3d.up" }
        return isActive ? "folder.fill" : "folder"
    }

    var body: some View {
        Group {
            if isAll {
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
        .frame(height: AptSideRow.altezza)
        .overlay(indicator)
        .padding(.leading, CGFloat(item.depth) * 14)
        .contextMenu { if !isAll { menu } }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            // freccia: apre e chiude i livelli sotto, senza cambiare pagina
            if item.hasChildren {
                Button { store.toggleExpanded(item.id) } label: {
                    Image(systemName: store.expanded.contains(item.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AptTema.testo2)
                        .frame(width: 22, height: AptSideRow.altezza)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 22, height: 1)
            }
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(isActive ? AptTema.accentoTesto : AptTema.testo2)
                Text(item.name)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(item.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? AptTema.accentoScuro.opacity(0.8) : AptTema.testo2)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .foregroundStyle(isActive ? AptTema.accentoScuro : AptTema.testo)
            .background(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).fill(isActive ? AptTema.accentoTenue : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            if isActive && !isAll {
                Button { addChild() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: AptSideRow.altezza)
                        .contentShape(Rectangle())
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
        Button { store.renaming = tree == .collections ? .collection(item.id) : .folder(item.id) } label: {
            Label("Rinomina", systemImage: "pencil")
        }
        Button { addChild() } label: {
            Label(tree == .collections ? "Nuova sotto-raccolta" : "Nuova sottocartella", systemImage: "plus")
        }
        if tree == .folders && AptPath.parent(item.id).isEmpty {
            Button { store.sheet = .collectionPicker(folder: item.id) } label: {
                Label("Aggiungi a raccolta", systemImage: "square.stack.3d.up")
            }
        }
        Button(role: .destructive) {
            if tree == .collections {
                store.removeCollection(item.id)
            } else {
                store.pendingDelete = AptPendingDelete(docs: [], folders: [item.id])
            }
        } label: {
            Label(tree == .collections ? "Rimuovi raccolta" : "Elimina", systemImage: "trash")
        }
    }

    private func tap() {
        if item.hasChildren && !store.expanded.contains(item.id) { store.toggleExpanded(item.id) }
        if tree == .collections {
            store.selectCollection(item.id)
        } else {
            store.open(folder: item.id)
        }
    }
    private func addChild() {
        if tree == .collections { store.askNewCollection(parent: item.id) } else { store.addFolder(parent: item.id) }
    }
}

struct AptSidebarDropDelegate: DropDelegate {
    let store: AptStore
    let targetID: String
    let tree: AptTree
    static let rowHeight: CGFloat = AptSideRow.altezza

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
