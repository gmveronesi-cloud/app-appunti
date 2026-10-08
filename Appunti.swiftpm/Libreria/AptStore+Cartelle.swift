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

    /// «Nuova cartella» (barra in alto, barra laterale, menu): apre la finestra del nome.
    /// La cartella viene creata solo quando si conferma, quindi non restano mai cartelle «provvisorie».
    func addFolder(parent: String) {
        renaming = .newFolder(parent: parent, collection: parent.isEmpty ? activeCollection?.id : nil)
    }

    /// «Crea nuova cartella» dentro il selettore di una raccolta.
    func createFolderForCollection(_ collectionID: String) {
        sheet = nil
        // un solo foglio alla volta: la finestra del nome si apre appena si è chiuso il selettore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.renaming = .newFolder(parent: "", collection: collectionID)
        }
    }

    func askNewCollection(parent: String?) {
        renaming = .newCollection(parent: parent)
    }

    // MARK: Finestra del nome (rinomina e creazione)

    func initialName(for t: AptRenameTarget) -> String {
        switch t {
        case .folder(let p): return AptPath.name(p)
        case .doc(let p): return String(AptPath.name(p).dropLast(4))
        case .collection(let id): return AptColl.find(meta.collections, id)?.name ?? ""
        case .newFolder: return "Nuova cartella"
        case .newCollection: return "Nuova raccolta"
        }
    }

    /// Conferma della finestra del nome.
    func commitRename(_ t: AptRenameTarget, text: String) {
        renaming = nil
        let clean = AptFS.sanitize(text)
        switch t {
        case .folder(let p):
            renameFolder(p, to: clean)
        case .doc(let p):
            renameDoc(p, to: clean)
        case .collection(let id):
            guard !clean.isEmpty else { return }
            AptColl.mutate(&meta.collections, id: id) { $0.name = clean }
            saveMeta()
        case .newFolder(let parent, let collection):
            guard let path = createFolder(parent: parent, baseName: clean.isEmpty ? "Nuova cartella" : clean) else { return }
            if let c = collection {
                AptColl.mutate(&meta.collections, id: c) { $0.folderPaths.append(path) }
                saveMeta()
            }
            if !parent.isEmpty { expanded.insert(parent) }
        case .newCollection(let parent):
            createCollection(parent: parent, name: clean)
        }
    }

    private func nameTakenMessage(_ name: String, folder: Bool) -> String {
        folder ? "Esiste già un elemento chiamato «\(name)» in questa posizione. Scegli un altro nome."
               : "Esiste già un file chiamato «\(name)» in questa posizione. Scegli un altro nome."
    }

    func renameFolder(_ path: String, to raw: String) {
        let clean = AptFS.sanitize(raw)
        let oldName = AptPath.name(path)
        guard !clean.isEmpty, clean != oldName, let src = url(for: path) else { return }
        let parent = AptPath.parent(path)
        guard let pURL = url(for: parent) else { return }
        let caseOnly = clean.lowercased() == oldName.lowercased()
        let dest = pURL.appendingPathComponent(clean)
        if !caseOnly && FileManager.default.fileExists(atPath: dest.path) {
            errorMessage = nameTakenMessage(clean, folder: true)
            return
        }
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
        remap(from: path, to: AptPath.join(parent, clean))
        reload()
    }

    func renameDoc(_ path: String, to raw: String) {
        let pulito = AptFS.sanitize(raw.lowercased().hasSuffix(".pdf") ? String(raw.dropLast(4)) : raw)
        let oldName = String(AptPath.name(path).dropLast(4))
        guard !pulito.isEmpty, pulito != oldName, let src = url(for: path) else { return }
        let parent = AptPath.parent(path)
        guard let pURL = url(for: parent) else { return }
        let caseOnly = pulito.lowercased() == oldName.lowercased()
        let dest = pURL.appendingPathComponent(pulito + ".pdf")
        if !caseOnly && FileManager.default.fileExists(atPath: dest.path) {
            errorMessage = nameTakenMessage(pulito, folder: false)
            return
        }
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
        remap(from: path, to: AptPath.join(parent, pulito + ".pdf"))
        reload()
    }

    /// Aggiorna raccolte, ordini, cartelle espanse, cartella aperta e schede quando un percorso cambia.
    func remap(from old: String, to new: String) {
        func fix(_ p: String) -> String { AptPath.rebase(p, from: old, to: new) }
        if let o = openFolder { openFolder = fix(o) }
        schede = schede.map { s in
            let nid = fix(s.id)
            guard nid != s.id, let u = url(for: nid) else { return s }
            return AptDoc(id: nid, url: u, name: String(AptPath.name(nid).dropLast(4)), modDate: s.modDate, folderPath: AptPath.parent(nid))
        }
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
