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
    let bookmarkKey = "aptRootBookmark"

    // Radice e dati
    @Published var rootURL: URL?
    @Published var root: AptFolder = AptFolder.empty
    @Published var meta = AptMeta()
    private(set) var folderIndex: [String: AptFolder] = [:]
    var metaReadFailed = false
    var accessing = false

    // Messaggi e pannelli
    @Published var errorMessage: String?
    @Published var showImporter = false
    @Published var importerForRoot = true
    var importTarget: String = ""
    /// File arrivati dalla condivisione di iPadOS (altre app) mentre la libreria non era ancora scelta
    var inAttesa: [URL] = []
    /// Messaggio breve in alto nella Libreria (sparisce da solo)
    @Published var messaggio: String?
    @Published var sheet: AptSheet?
    @Published var openDocument: AptDoc?
    /// Documenti aperti nell'Editor (una scheda ciascuno)
    @Published var schede: [AptDoc] = []
    @Published var pendingDelete: AptPendingDelete?
    /// Pagina «Modelli» per un nuovo quaderno (aperta dal menu «Nuovo» e dal piede della barra laterale)
    @Published var showModelli = false

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

    // Finestra «Rinomina / Nuova cartella» (una sola, a livello di Libreria) e drag & drop
    @Published var renaming: AptRenameTarget?
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

    func restoreRoot() {
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
        importaInAttesa()
    }

    var metaURL: URL? { rootURL?.appendingPathComponent(AptStore.metaFileName) }

    func loadMeta() {
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
        // schede: si tengono solo i documenti ancora esistenti, con i dati aggiornati
        let esistenti = tree.allDocs
        schede = schede.compactMap { sc in esistenti.first { $0.id == sc.id } }
    }

    func indexFolders(_ f: AptFolder, into dict: inout [String: AptFolder]) {
        dict[f.id] = f
        for c in f.children { indexFolders(c, into: &dict) }
    }

    func folder(_ path: String) -> AptFolder? {
        path.isEmpty ? root : folderIndex[path]
    }
    var allDocs: [AptDoc] { root.allDocs }
    /// Numero di cartelle reali (la radice non conta)
    var folderCount: Int { max(folderIndex.count - 1, 0) }
    /// Gli ultimi documenti modificati
    func recentDocs(_ n: Int) -> [AptDoc] {
        Array(allDocs.sorted { $0.modDate > $1.modDate }.prefix(n))
    }

    func url(for path: String) -> URL? {
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

}
