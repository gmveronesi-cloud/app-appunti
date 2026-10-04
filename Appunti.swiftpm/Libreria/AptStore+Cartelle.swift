// Store: cartelle reali, spostamento, eliminazione
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension AptStore {
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
    func remap(from old: String, to new: String) {
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

    func stripFromCollections(_ path: String) {
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

    func moveDoc(_ path: String, into parent: String) {
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
        var daEliminare: [URL] = []
        for f in folders {
            if let u = url(for: f), fm.fileExists(atPath: u.path) { daEliminare.append(u) }
            stripFromCollections(f)
        }
        for d in docs {
            if let u = url(for: d), fm.fileExists(atPath: u.path) { daEliminare.append(u) }
        }
        clearSelection()
        // Le operazioni sui file girano fuori dal thread principale: l'app non si congela.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var errore: Error?
            for u in daEliminare {
                do { try AptFS.trash(u) } catch { errore = error }
            }
            DispatchQueue.main.async {
                if let errore { self?.fail(errore) }
                self?.reload()
            }
        }
    }

    func confirmDeleteSelection() {
        pendingDelete = AptPendingDelete(docs: selectedPaths("doc:"), folders: selectedPaths("folder:"))
    }
}
