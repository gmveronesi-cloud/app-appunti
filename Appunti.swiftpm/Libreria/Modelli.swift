// Percorsi, formattazione, modelli e metadati della libreria
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Percorsi relativi alla cartella radice

enum AptPath {
    static func parent(_ p: String) -> String {
        p.split(separator: "/").dropLast().joined(separator: "/")
    }
    static func name(_ p: String) -> String {
        String(p.split(separator: "/").last ?? "")
    }
    static func join(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : a + "/" + b
    }
    /// true se `p` sta dentro `ancestor` (a qualunque livello), escluso `ancestor` stesso
    static func isInside(_ p: String, of ancestor: String) -> Bool {
        if ancestor.isEmpty { return !p.isEmpty }
        return p.hasPrefix(ancestor + "/")
    }
    static func rebase(_ p: String, from old: String, to new: String) -> String {
        if p == old { return new }
        if p.hasPrefix(old + "/") { return new + String(p.dropFirst(old.count)) }
        return p
    }
}

// MARK: - Formattazione

enum AptFormat {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if date == Date.distantPast { return "—" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "oggi"
        case 1: return "ieri"
        case 2..<7: return "\(days) gg fa"
        case 7..<30: return "\(days / 7) sett fa"
        case 30..<365:
            let m = days / 30
            return m == 1 ? "1 mese fa" : "\(m) mesi fa"
        default:
            let y = days / 365
            return y == 1 ? "1 anno fa" : "\(y) anni fa"
        }
    }
    static func documents(_ n: Int) -> String {
        n == 1 ? "1 documento" : "\(n) documenti"
    }
    static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}

// MARK: - Modelli (letti dal filesystem)

struct AptDoc: Identifiable, Hashable {
    let id: String          // percorso relativo alla radice
    let url: URL
    let name: String        // nome file senza .pdf
    let modDate: Date       // data di modifica vera del file
    let folderPath: String
}

struct AptFolder: Identifiable {
    let id: String          // percorso relativo alla radice ("" = radice)
    let url: URL
    let name: String
    let modDate: Date       // data di modifica vera della cartella
    var children: [AptFolder]
    var docs: [AptDoc]

    var docCount: Int { docs.count + children.reduce(0) { $0 + $1.docCount } }
    var allDocs: [AptDoc] { docs + children.flatMap { $0.allDocs } }

    static let empty = AptFolder(id: "", url: URL(fileURLWithPath: "/"), name: "", modDate: Date.distantPast, children: [], docs: [])
}

// MARK: - Metadati salvati in un file JSON dentro la cartella radice

struct AptCollection: Codable, Identifiable {
    var id: String
    var name: String
    var children: [AptCollection] = []
    var folderPaths: [String] = []
}

struct AptMeta: Codable {
    var collections: [AptCollection] = []
    var orders: [String: [String]] = [:]   // "docs:<cartella|*>" e "folders:<cartella padre>"
}

enum AptColl {
    static func find(_ list: [AptCollection], _ id: String) -> AptCollection? {
        for c in list {
            if c.id == id { return c }
            if let f = find(c.children, id) { return f }
        }
        return nil
    }
    @discardableResult
    static func mutate(_ list: inout [AptCollection], id: String, _ body: (inout AptCollection) -> Void) -> Bool {
        for i in list.indices {
            if list[i].id == id { body(&list[i]); return true }
            if mutate(&list[i].children, id: id, body) { return true }
        }
        return false
    }
    static func remove(_ list: inout [AptCollection], id: String) -> AptCollection? {
        if let i = list.firstIndex(where: { $0.id == id }) { return list.remove(at: i) }
        for i in list.indices {
            if let r = remove(&list[i].children, id: id) { return r }
        }
        return nil
    }
    static func insert(_ list: inout [AptCollection], node: AptCollection, relativeTo targetID: String, after: Bool) -> Bool {
        if let i = list.firstIndex(where: { $0.id == targetID }) {
            list.insert(node, at: after ? i + 1 : i)
            return true
        }
        for i in list.indices {
            if insert(&list[i].children, node: node, relativeTo: targetID, after: after) { return true }
        }
        return false
    }
    static func contains(_ node: AptCollection, descendant id: String) -> Bool {
        node.children.contains { $0.id == id || contains($0, descendant: id) }
    }
    static func flatten(_ list: [AptCollection], depth: Int) -> [(AptCollection, Int)] {
        var out: [(AptCollection, Int)] = []
        for c in list {
            out.append((c, depth))
            out += flatten(c.children, depth: depth + 1)
        }
        return out
    }
}

// MARK: - Enumerazioni di supporto

enum AptLibView: String { case grid, list }
enum AptSortMode: String { case date, name, manual }
enum AptSortDir: String { case asc, desc }
enum AptTree { case collections, folders }
enum AptDragKind { case doc, folder, collection }
enum AptDragSource { case grid, sidebar }
enum AptDropZone { case before, inside, after }

struct AptDrag {
    let kind: AptDragKind
    let source: AptDragSource
    let id: String
}
struct AptDropIndicator: Equatable {
    let id: String
    let zone: AptDropZone
}
struct AptSideItem: Identifiable {
    let id: String
    let name: String
    let count: Int
    let depth: Int
    let hasChildren: Bool
}
/// Cosa si sta rinominando o creando con la finestra del nome.
enum AptRenameTarget: Identifiable {
    case folder(String)
    case doc(String)
    case collection(String)
    case newFolder(parent: String, collection: String?)
    case newCollection(parent: String?)

    var id: String {
        switch self {
        case .folder(let p): return "f:" + p
        case .doc(let p): return "d:" + p
        case .collection(let i): return "c:" + i
        case .newFolder(let p, let c): return "nf:" + p + "|" + (c ?? "")
        case .newCollection(let p): return "nc:" + (p ?? "")
        }
    }
    var titolo: String {
        switch self {
        case .newFolder: return "Nuova cartella"
        case .newCollection: return "Nuova raccolta"
        default: return "Rinomina"
        }
    }
}

struct AptPendingDelete {
    let docs: [String]
    let folders: [String]
    var count: Int { docs.count + folders.count }
}
enum AptSheet: Identifiable {
    case movePicker
    case folderPicker(collection: String)
    case collectionPicker(folder: String)
    case share(urls: [URL], token: UUID)
    var id: String {
        switch self {
        case .movePicker: return "move"
        case .folderPicker(let c): return "fp-" + c
        case .collectionPicker(let f): return "cp-" + f
        case .share(_, let t): return "share-" + t.uuidString
        }
    }
}

/// Tutto ciò che la schermata principale deve mostrare in questo momento.
struct AptScreenModel {
    var title: String = ""
    var isFolder: Bool = false
    var collection: AptCollection? = nil
    var subCollections: [AptCollection] = []
    var folders: [AptFolder] = []
    var docs: [AptDoc] = []
    var docOrderKey: String = "docs:*"
    var folderOrderKey: String? = nil     // nil = ordine delle cartelle della raccolta
    var isEmpty: Bool { subCollections.isEmpty && folders.isEmpty && docs.isEmpty }
}
