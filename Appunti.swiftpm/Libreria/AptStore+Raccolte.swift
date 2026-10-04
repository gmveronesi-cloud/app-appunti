// Store: raccolte (metadati) e drag & drop nella barra laterale
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension AptStore {
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
