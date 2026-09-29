// Store: stato e azioni della libreria
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Store

final class AptStore: ObservableObject {
    static let allID = "all"
    static let metaFileName = "Appunti - impostazioni.json"
    private let bookmarkKey = "aptRootBookmark"

    // Radice e dati
    @Published var rootURL: URL?
    @Published var root: AptFolder = AptFolder.empty
    @Published var meta = AptMeta()
    private(set) var folderIndex: [String: AptFolder] = [:]
    private var metaReadFailed = false
    private var accessing = false

    // Messaggi e pannelli
    @Published var errorMessage: String?
    @Published var showImporter = false
    @Published var importerForRoot = true
    var importTarget: String = ""
    @Published var sheet: AptSheet?
    @Published var openDocument: AptDoc?
    @Published var pendingDelete: AptPendingDelete?

    // Preferenze di visualizzazione
    @Published var libView: AptLibView { didSet { UserDefaults.standard.set(libView.rawValue, forKey: "aptLibView") } }
    @Published var sortMode: AptSortMode { didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: "aptSortMode") } }
    @Published var sortDir: AptSortDir { didSet { UserDefaults.standard.set(sortDir.rawValue, forKey: "aptSortDir") } }

    // Navigazione
    @Published var selectedCollection: String = AptStore.allID
    @Published var openFolder: String?
    @Published var expanded: Set<String> = []

    // Selezione multipla (chiavi "doc:<percorso>" / "folder:<percorso>")
    @Published var selectionMode = false
    @Published var selected: [String] = []

    // Modifica nome in linea e drag & drop
    @Published var editingID: String?
    @Published var editingTree: AptTree = .folders
    @Published var dragging: AptDrag?
    @Published var dropIndicator: AptDropIndicator?

    init() {
        let d = UserDefaults.standard
        libView = AptLibView(rawValue: d.string(forKey: "aptLibView") ?? "") ?? .grid
        sortMode = AptSortMode(rawValue: d.string(forKey: "aptSortMode") ?? "") ?? .date
        sortDir = AptSortDir(rawValue: d.string(forKey: "aptSortDir") ?? "") ?? .desc
        restoreRoot()
    }

    // MARK: Cartella radice (bookmark di sicurezza)

    private func restoreRoot() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        accessing = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        rootURL = url
        loadMeta()
        reload()
    }

    func setRoot(_ url: URL) {
        if accessing, let old = rootURL { old.stopAccessingSecurityScopedResource() }
        accessing = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            fail(error)
        }
        rootURL = url
        selectedCollection = AptStore.allID
        openFolder = nil
        expanded = []
        clearSelection()
        loadMeta()
        reload()
    }

    private var metaURL: URL? { rootURL?.appendingPathComponent(AptStore.metaFileName) }

    private func loadMeta() {
        meta = AptMeta()
        metaReadFailed = false
        guard let u = metaURL, let root = rootURL else { return }
        let fm = FileManager.default
        let placeholder = root.appendingPathComponent("." + AptStore.metaFileName + ".icloud")
        if fm.fileExists(atPath: placeholder.path) {
            try? fm.startDownloadingUbiquitousItem(at: u)
            metaReadFailed = true
            errorMessage = "Le impostazioni (raccolte e ordine manuale) sono ancora in download da iCloud. Riprova tra poco: fino ad allora non vengono modificate."
            return
        }
        guard fm.fileExists(atPath: u.path) else { return }
        do {
            let data = try Data(contentsOf: u)
            meta = try JSONDecoder().decode(AptMeta.self, from: data)
        } catch {
            metaReadFailed = true
            errorMessage = "Non riesco a leggere il file «\(AptStore.metaFileName)». Raccolte e ordine manuale non verranno modificati per non perderli."
        }
    }

    func saveMeta() {
        guard let u = metaURL, !metaReadFailed else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(meta).write(to: u, options: .atomic)
        } catch {
            fail(error)
        }
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: Lettura dell'albero

    func reload() {
        guard let rootURL = rootURL else {
            root = AptFolder.empty
            folderIndex = [:]
            return
        }
        let modDate = (try? rootURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
        let tree = AptScanner.scan(dir: rootURL, relPath: "", name: rootURL.lastPathComponent, modDate: modDate)
        var idx: [String: AptFolder] = [:]
        indexFolders(tree, into: &idx)
        folderIndex = idx
        root = tree
        if let p = openFolder, idx[p] == nil { openFolder = nil }
    }

    private func indexFolders(_ f: AptFolder, into dict: inout [String: AptFolder]) {
        dict[f.id] = f
        for c in f.children { indexFolders(c, into: &dict) }
    }

    func folder(_ path: String) -> AptFolder? {
        path.isEmpty ? root : folderIndex[path]
    }
    var allDocs: [AptDoc] { root.allDocs }

    private func url(for path: String) -> URL? {
        guard let rootURL = rootURL else { return nil }
        return path.isEmpty ? rootURL : rootURL.appendingPathComponent(path)
    }

    // MARK: Contesto corrente

    var activeCollection: AptCollection? {
        selectedCollection == AptStore.allID ? nil : AptColl.find(meta.collections, selectedCollection)
    }

    func docIDs(in c: AptCollection) -> Set<String> {
        var set = Set<String>()
        for p in c.folderPaths {
            if let f = folderIndex[p] { for d in f.allDocs { set.insert(d.id) } }
        }
        for child in c.children { set.formUnion(docIDs(in: child)) }
        return set
    }

    func selectCollection(_ id: String) {
        selectedCollection = id
        openFolder = nil
        clearSelection()
    }
    func open(folder path: String) {
        openFolder = path
        clearSelection()
    }
    func folderBack() {
        guard let p = openFolder else { return }
        let parent = AptPath.parent(p)
        openFolder = parent.isEmpty ? nil : parent
        clearSelection()
    }
    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: Ordinamento

    private func ordered<T>(_ list: [T], order: [String], id: (T) -> String, name: (T) -> String) -> [T] {
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

    private func byName(_ a: String, _ b: String) -> Bool {
        let r = a.localizedStandardCompare(b)
        return sortDir == .asc ? r == .orderedAscending : r == .orderedDescending
    }
    private func byDate(_ a: Date, _ b: Date) -> Bool {
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
    private func selectedPaths(_ prefix: String) -> [String] {
        selected.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    // MARK: Cartelle (reali)

    @discardableResult
    func createFolder(parent: String, baseName: String = "Nuova cartella") -> String? {
        guard let pURL = url(for: parent) else { return nil }
        let dest = AptFS.uniqueURL(in: pURL, base: baseName, ext: nil)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            fail(error)
            return nil
        }
        reload()
        return AptPath.join(parent, dest.lastPathComponent)
    }

    /// "+" nella barra laterale: crea una cartella (e, se c'è una raccolta attiva, la assegna).
    func addFolder(parent: String) {
        guard let path = createFolder(parent: parent) else { return }
        if parent.isEmpty, let c = activeCollection {
            AptColl.mutate(&meta.collections, id: c.id) { $0.folderPaths.append(path) }
            saveMeta()
        }
        if !parent.isEmpty { expanded.insert(parent) }
        editingID = path
        editingTree = .folders
    }

    /// "Crea nuova cartella" dentro il selettore di una raccolta.
    func createFolderForCollection(_ collectionID: String) {
        guard let path = createFolder(parent: "") else { return }
        AptColl.mutate(&meta.collections, id: collectionID) { $0.folderPaths.append(path) }
        saveMeta()
        sheet = nil
        editingID = path
        editingTree = .folders
    }

    func renameFolder(_ path: String, to raw: String) {
        let clean = AptFS.sanitize(raw)
        let oldName = AptPath.name(path)
        guard !clean.isEmpty, clean != oldName, let src = url(for: path) else { return }
        let parent = AptPath.parent(path)
        guard let pURL = url(for: parent) else { return }
        let caseOnly = clean.lowercased() == oldName.lowercased()
        var dest = pURL.appendingPathComponent(clean)
        if !caseOnly { dest = AptFS.uniqueURL(in: pURL, base: clean, ext: nil) }
        do {
            if caseOnly {
                let tmp = pURL.appendingPathComponent(UUID().uuidString)
                try AptFS.move(src, to: tmp)
                try AptFS.move(tmp, to: dest)
            } else {
                try AptFS.move(src, to: dest)
            }
        } catch {
            fail(error)
            return
        }
        remap(from: path, to: AptPath.join(parent, dest.lastPathComponent))
        reload()
    }

    /// Aggiorna raccolte, ordini e cartelle espanse quando un percorso cambia.
    private func remap(from old: String, to new: String) {
        func fix(_ p: String) -> String { AptPath.rebase(p, from: old, to: new) }
        func fixColl(_ c: inout AptCollection) {
            c.folderPaths = c.folderPaths.map(fix)
            for i in c.children.indices { fixColl(&c.children[i]) }
        }
        for i in meta.collections.indices { fixColl(&meta.collections[i]) }
        var newOrders: [String: [String]] = [:]
        for (k, v) in meta.orders {
            var key = k
            if k.hasPrefix("folders:") {
                key = "folders:" + fix(String(k.dropFirst("folders:".count)))
            } else if k.hasPrefix("docs:") {
                let rest = String(k.dropFirst("docs:".count))
                if rest != "*" { key = "docs:" + fix(rest) }
            }
            newOrders[key] = v.map(fix)
        }
        meta.orders = newOrders
        expanded = Set(expanded.map(fix))
        saveMeta()
    }

    private func stripFromCollections(_ path: String) {
        func strip(_ c: inout AptCollection) {
            c.folderPaths = c.folderPaths.filter { $0 != path && !AptPath.isInside($0, of: path) }
            for i in c.children.indices { strip(&c.children[i]) }
        }
        for i in meta.collections.indices { strip(&meta.collections[i]) }
        saveMeta()
    }

    @discardableResult
    func moveFolder(_ path: String, into parent: String) -> String? {
        guard let src = url(for: path), let pURL = url(for: parent) else { return nil }
        guard path != parent, !AptPath.isInside(parent, of: path) else { return nil }
        if AptPath.parent(path) == parent { return path }
        let dest = AptFS.uniqueURL(in: pURL, base: AptPath.name(path), ext: nil)
        do {
            try AptFS.move(src, to: dest)
        } catch {
            fail(error)
            return nil
        }
        let newPath = AptPath.join(parent, dest.lastPathComponent)
        remap(from: path, to: newPath)
        reload()
        if !parent.isEmpty { expanded.insert(parent) }
        return newPath
    }

    private func moveDoc(_ path: String, into parent: String) {
        guard let src = url(for: path), let pURL = url(for: parent) else { return }
        if AptPath.parent(path) == parent { return }
        let base = String(AptPath.name(path).dropLast(4))
        let dest = AptFS.uniqueURL(in: pURL, base: base, ext: "pdf")
        do { try AptFS.move(src, to: dest) } catch { fail(error) }
    }

    func moveSelection(to target: String) {
        let docs = selectedPaths("doc:")
        let folders = selectedPaths("folder:")
        for d in docs { moveDoc(d, into: target) }
        reload()
        for f in folders { moveFolder(f, into: target) }   // cartella dentro se stessa o in una sua sottocartella: ignorata
        sheet = nil
        clearSelection()
        reload()
    }

    // MARK: Eliminazione

    func delete(docs: [String], folders: [String]) {
        let fm = FileManager.default
        for f in folders {
            if let u = url(for: f), fm.fileExists(atPath: u.path) {
                do { try AptFS.trash(u) } catch { fail(error) }
            }
            stripFromCollections(f)
        }
        for d in docs {
            if let u = url(for: d), fm.fileExists(atPath: u.path) {
                do { try AptFS.trash(u) } catch { fail(error) }
            }
        }
        clearSelection()
        reload()
    }

    func confirmDeleteSelection() {
        pendingDelete = AptPendingDelete(docs: selectedPaths("doc:"), folders: selectedPaths("folder:"))
    }

    // MARK: Nuovi documenti e importazioni

    @discardableResult
    func createNote(in parent: String) -> AptDoc? {
        guard let pURL = url(for: parent) else { return nil }
        let dest = AptFS.uniqueURL(in: pURL, base: "Nota " + AptFormat.stamp(), ext: "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595.2, height: 841.8))
        let data = renderer.pdfData { ctx in ctx.beginPage() }
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            fail(error)
            return nil
        }
        reload()
        return folder(parent)?.docs.first { $0.url.lastPathComponent == dest.lastPathComponent }
    }

    func importPDFs(_ urls: [URL], into parent: String) {
        guard let pURL = url(for: parent) else { return }
        for u in urls {
            let acc = u.startAccessingSecurityScopedResource()
            defer { if acc { u.stopAccessingSecurityScopedResource() } }
            let base = u.deletingPathExtension().lastPathComponent
            let dest = AptFS.uniqueURL(in: pURL, base: base, ext: "pdf")
            do { try AptFS.copy(u, to: dest) } catch { fail(error) }
        }
        reload()
    }

    /// Foto → PDF. merge = true: un unico PDF con una pagina per foto. merge = false: un PDF per foto.
    func addImages(_ images: [UIImage], merge: Bool, into parent: String) {
        guard let pURL = url(for: parent), !images.isEmpty else { return }
        let stamp = AptFormat.stamp()
        func write(_ imgs: [UIImage], base: String) {
            let pdf = PDFDocument()
            for img in imgs {
                if let page = PDFPage(image: img) { pdf.insert(page, at: pdf.pageCount) }
            }
            guard pdf.pageCount > 0 else { return }
            let dest = AptFS.uniqueURL(in: pURL, base: base, ext: "pdf")
            if !pdf.write(to: dest) { errorMessage = "Non sono riuscito a salvare «\(base)»." }
        }
        if merge {
            write(images, base: "Immagini " + stamp)
        } else {
            for (i, img) in images.enumerated() {
                write([img], base: images.count == 1 ? "Immagine " + stamp : "Immagine " + stamp + " (\(i + 1))")
            }
        }
        reload()
    }

    // MARK: Esportazione

    func exportURLs() -> [URL] {
        var docs: [AptDoc] = []
        for k in selected {
            if k.hasPrefix("doc:") {
                let p = String(k.dropFirst(4))
                if let d = allDocs.first(where: { $0.id == p }) { docs.append(d) }
            } else if k.hasPrefix("folder:") {
                if let f = folder(String(k.dropFirst(7))) { docs += f.allDocs }
            }
        }
        var seen = Set<String>()
        let unique = docs.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return [] }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AptExport-" + UUID().uuidString)
        var out: [URL] = []
        for (i, d) in unique.enumerated() {
            let dir = tmp.appendingPathComponent("\(i)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dst = dir.appendingPathComponent(d.url.lastPathComponent)
            do {
                try AptFS.copy(d.url, to: dst)
                out.append(dst)
            } catch {
                fail(error)
            }
        }
        return out
    }

    func exportSelection() {
        let urls = exportURLs()
        guard !urls.isEmpty else { return }
        clearSelection()
        sheet = .share(urls: urls, token: UUID())
    }

    // MARK: Raccolte (metadati)

    func addCollection(parent: String?) {
        let c = AptCollection(id: UUID().uuidString, name: "Nuova raccolta")
        if let p = parent {
            AptColl.mutate(&meta.collections, id: p) { $0.children.append(c) }
            expanded.insert(p)
        } else {
            meta.collections.append(c)
        }
        saveMeta()
        editingID = c.id
        editingTree = .collections
    }

    func removeCollection(_ id: String) {
        _ = AptColl.remove(&meta.collections, id: id)
        if selectedCollection == id || AptColl.find(meta.collections, selectedCollection) == nil {
            selectedCollection = AptStore.allID
        }
        saveMeta()
    }

    func toggleFolder(_ path: String, inCollection id: String) {
        AptColl.mutate(&meta.collections, id: id) { c in
            if let i = c.folderPaths.firstIndex(of: path) { c.folderPaths.remove(at: i) } else { c.folderPaths.append(path) }
        }
        saveMeta()
    }

    func commitEdit(_ id: String, tree: AptTree, text: String) {
        editingID = nil
        let clean = AptFS.sanitize(text)
        switch tree {
        case .collections:
            let final = clean.isEmpty ? "Nuova raccolta" : clean
            AptColl.mutate(&meta.collections, id: id) { $0.name = final }
            saveMeta()
        case .folders:
            renameFolder(id, to: clean)
        }
    }

    // MARK: Drag & drop nella barra laterale

    func sidebarDrop(drag: AptDrag, targetID: String, tree: AptTree, zone: AptDropZone) {
        switch (drag.kind, tree) {
        case (.folder, .collections):
            // trascinare una cartella di primo livello su una raccolta la assegna a quella raccolta
            guard AptPath.parent(drag.id).isEmpty else { return }
            AptColl.mutate(&meta.collections, id: targetID) { c in
                if !c.folderPaths.contains(drag.id) { c.folderPaths.append(drag.id) }
            }
            saveMeta()
        case (.folder, .folders):
            guard drag.id != targetID, !AptPath.isInside(targetID, of: drag.id) else { return }
            if zone == .inside {
                moveFolder(drag.id, into: targetID)
            } else {
                let parent = AptPath.parent(targetID)
                var newPath = drag.id
                if AptPath.parent(drag.id) != parent {
                    guard let np = moveFolder(drag.id, into: parent) else { return }
                    newPath = np
                }
                let siblings = orderedFolders(folder(parent)?.children ?? [], parent: parent).map { $0.id }
                reorder(key: "folders:" + parent, ids: siblings, drag: newPath, target: targetID, before: zone == .before)
            }
        case (.collection, .collections):
            guard drag.id != targetID,
                  let dragged = AptColl.find(meta.collections, drag.id),
                  !AptColl.contains(dragged, descendant: targetID),
                  let node = AptColl.remove(&meta.collections, id: drag.id) else { return }
            if zone == .inside {
                AptColl.mutate(&meta.collections, id: targetID) { $0.children.append(node) }
                expanded.insert(targetID)
            } else if !AptColl.insert(&meta.collections, node: node, relativeTo: targetID, after: zone == .after) {
                meta.collections.append(node)
            }
            saveMeta()
        default:
            return
        }
    }
}
