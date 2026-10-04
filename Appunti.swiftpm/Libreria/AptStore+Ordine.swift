// Store: ordinamento, barra laterale, selezione
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension AptStore {
    // MARK: Ordinamento

    func ordered<T>(_ list: [T], order: [String], id: (T) -> String, name: (T) -> String) -> [T] {
        var rank: [String: Int] = [:]
        for (i, o) in order.enumerated() where rank[o] == nil { rank[o] = i }
        return list.sorted { a, b in
            let ra = rank[id(a)]
            let rb = rank[id(b)]
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return name(a).localizedStandardCompare(name(b)) == .orderedAscending
            }
        }
    }

    /// Ordine "salvato" delle sottocartelle (usato dalla barra laterale e dall'ordine manuale)
    func orderedFolders(_ list: [AptFolder], parent: String) -> [AptFolder] {
        ordered(list, order: meta.orders["folders:" + parent] ?? [], id: { $0.id }, name: { $0.name })
    }

    func byName(_ a: String, _ b: String) -> Bool {
        let r = a.localizedStandardCompare(b)
        return sortDir == .asc ? r == .orderedAscending : r == .orderedDescending
    }
    func byDate(_ a: Date, _ b: Date) -> Bool {
        sortDir == .asc ? a < b : a > b
    }

    func sortedFolders(_ list: [AptFolder], parent: String) -> [AptFolder] {
        switch sortMode {
        case .manual: return orderedFolders(list, parent: parent)
        case .name: return list.sorted { byName($0.name, $1.name) }
        case .date: return list.sorted { byDate($0.modDate, $1.modDate) }
        }
    }
    func sortedDocs(_ list: [AptDoc], key: String) -> [AptDoc] {
        switch sortMode {
        case .manual: return ordered(list, order: meta.orders[key] ?? [], id: { $0.id }, name: { $0.name })
        case .name: return list.sorted { byName($0.name, $1.name) }
        case .date: return list.sorted { byDate($0.modDate, $1.modDate) }
        }
    }

    func reorder(key: String, ids: [String], drag: String, target: String, before: Bool) {
        guard ids.contains(drag) else { return }
        var list = ids.filter { $0 != drag }
        guard let ti = list.firstIndex(of: target) else { return }
        list.insert(drag, at: before ? ti : ti + 1)
        meta.orders[key] = list
        saveMeta()
    }

    func reorderEntry(model: AptScreenModel, kind: AptDragKind, drag: String, target: String, before: Bool) {
        switch kind {
        case .doc:
            reorder(key: model.docOrderKey, ids: model.docs.map { $0.id }, drag: drag, target: target, before: before)
        case .folder:
            if let k = model.folderOrderKey {
                reorder(key: k, ids: model.folders.map { $0.id }, drag: drag, target: target, before: before)
            } else if let c = model.collection {
                let ids = model.folders.map { $0.id }
                guard ids.contains(drag) else { return }
                var list = ids.filter { $0 != drag }
                guard let ti = list.firstIndex(of: target) else { return }
                list.insert(drag, at: before ? ti : ti + 1)
                AptColl.mutate(&meta.collections, id: c.id) { col in
                    let extra = col.folderPaths.filter { !list.contains($0) }
                    col.folderPaths = list + extra
                }
                saveMeta()
            }
        case .collection:
            break
        }
    }

    func makeScreenModel() -> AptScreenModel {
        var m = AptScreenModel()
        if let p = openFolder, let f = folder(p) {
            m.title = f.name
            m.isFolder = true
            m.folders = sortedFolders(f.children, parent: f.id)
            m.docs = sortedDocs(f.docs, key: "docs:" + f.id)
            m.docOrderKey = "docs:" + f.id
            m.folderOrderKey = "folders:" + f.id
        } else if let c = activeCollection {
            m.title = c.name
            m.collection = c
            m.subCollections = c.children
            let assigned = c.folderPaths.compactMap { p -> AptFolder? in
                guard AptPath.parent(p).isEmpty else { return nil }   // solo cartelle di primo livello
                return folderIndex[p]
            }
            m.folders = sortMode == .manual ? assigned : sortedFolders(assigned, parent: "")
            m.folderOrderKey = nil
        } else {
            m.title = "Tutti i documenti"
            m.docs = sortedDocs(allDocs, key: "docs:*")
            m.docOrderKey = "docs:*"
        }
        return m
    }

    // MARK: Barra laterale

    func flatCollections(_ list: [AptCollection], depth: Int) -> [AptSideItem] {
        var out: [AptSideItem] = []
        for c in list {
            out.append(AptSideItem(id: c.id, name: c.name, count: docIDs(in: c).count, depth: depth, hasChildren: !c.children.isEmpty))
            if expanded.contains(c.id) { out += flatCollections(c.children, depth: depth + 1) }
        }
        return out
    }

    func flatFolderItems(_ list: [AptFolder], depth: Int, orderParent: String?, ignoreExpanded: Bool = false) -> [AptSideItem] {
        let ordered = orderParent == nil ? list : orderedFolders(list, parent: orderParent ?? "")
        var out: [AptSideItem] = []
        for f in ordered {
            out.append(AptSideItem(id: f.id, name: f.name, count: f.docCount, depth: depth, hasChildren: !f.children.isEmpty))
            if ignoreExpanded || expanded.contains(f.id) {
                out += flatFolderItems(f.children, depth: depth + 1, orderParent: f.id, ignoreExpanded: ignoreExpanded)
            }
        }
        return out
    }

    /// Cartelle mostrate nella barra laterale: tutte, oppure quelle assegnate alla raccolta attiva.
    func sidebarFolderItems() -> [AptSideItem] {
        if let c = activeCollection {
            let paths = c.folderPaths
            let roots = paths.filter { p in
                !paths.contains { $0 != p && p.hasPrefix($0 + "/") }
            }.compactMap { folderIndex[$0] }
            return flatFolderItems(roots, depth: 0, orderParent: nil)
        }
        return flatFolderItems(root.children, depth: 0, orderParent: "")
    }

    // MARK: Selezione

    func clearSelection() {
        selectionMode = false
        selected = []
    }
    func toggleSelection(_ key: String) {
        if let i = selected.firstIndex(of: key) { selected.remove(at: i) } else { selected.append(key) }
    }
    func currentSelectableKeys() -> [String] {
        if let p = openFolder, let f = folder(p) {
            return f.children.map { "folder:" + $0.id } + f.docs.map { "doc:" + $0.id }
        }
        if let c = activeCollection {
            return c.folderPaths.filter { AptPath.parent($0).isEmpty && folderIndex[$0] != nil }.map { "folder:" + $0 }
        }
        return allDocs.map { "doc:" + $0.id }
    }
    func selectedPaths(_ prefix: String) -> [String] {
        selected.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
