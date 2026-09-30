// Operazioni sul filesystem (coordinate, per iCloud Drive)
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Operazioni sul filesystem (coordinate, per iCloud Drive)

enum AptFS {
    static func uniqueURL(in dir: URL, base: String, ext: String?) -> URL {
        let fm = FileManager.default
        func make(_ n: Int) -> URL {
            let nm = n == 1 ? base : "\(base) \(n)"
            if let e = ext { return dir.appendingPathComponent(nm + "." + e) }
            return dir.appendingPathComponent(nm)
        }
        var n = 1
        while fm.fileExists(atPath: make(n).path) { n += 1 }
        return make(n)
    }

    static func sanitize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix(".") { t.removeFirst() }
        return t
    }

    static func move(_ src: URL, to dst: URL) throws {
        var coordError: NSError?
        var opError: Error?
        NSFileCoordinator().coordinate(writingItemAt: src, options: .forMoving,
                                       writingItemAt: dst, options: .forReplacing,
                                       error: &coordError) { s, d in
            do { try FileManager.default.moveItem(at: s, to: d) } catch { opError = error }
        }
        if let e = coordError { throw e }
        if let e = opError { throw e }
    }

    static func copy(_ src: URL, to dst: URL) throws {
        var coordError: NSError?
        var opError: Error?
        NSFileCoordinator().coordinate(readingItemAt: src, options: [], error: &coordError) { s in
            do { try FileManager.default.copyItem(at: s, to: dst) } catch { opError = error }
        }
        if let e = coordError { throw e }
        if let e = opError { throw e }
    }

    /// Elimina il file o la cartella. Niente trashItem dentro la coordinazione: si bloccava
    /// (deadlock) sulle cartelle iCloud/File. Su iCloud Drive i file finiscono comunque in «Eliminati di recente».
    static func trash(_ url: URL) throws {
        var coordError: NSError?
        var opError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { u in
            do { try FileManager.default.removeItem(at: u) } catch { opError = error }
        }
        if let e = coordError { throw e }
        if let e = opError { throw e }
    }
}

enum AptScanner {
    /// Legge ricorsivamente una cartella reale: sottocartelle e PDF.
    static func scan(dir: URL, relPath: String, name: String, modDate: Date) -> AptFolder {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])) ?? []
        var folders: [AptFolder] = []
        var docs: [AptDoc] = []
        for url in entries {
            var fileName = url.lastPathComponent
            var isPlaceholder = false
            if fileName.hasPrefix(".") && fileName.hasSuffix(".icloud") {
                // file iCloud non ancora scaricato: ".nome.pdf.icloud"
                fileName = String(fileName.dropFirst().dropLast(".icloud".count))
                isPlaceholder = true
            } else if fileName.hasPrefix(".") {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let mod = values?.contentModificationDate ?? Date.distantPast
            let rel = AptPath.join(relPath, fileName)
            if isDir && !isPlaceholder {
                folders.append(scan(dir: url, relPath: rel, name: fileName, modDate: mod))
            } else if fileName.lowercased().hasSuffix(".pdf") {
                let realURL = dir.appendingPathComponent(fileName)
                if isPlaceholder { try? fm.startDownloadingUbiquitousItem(at: realURL) }
                docs.append(AptDoc(id: rel, url: realURL, name: String(fileName.dropLast(4)), modDate: mod, folderPath: relPath))
            }
        }
        return AptFolder(id: relPath, url: dir, name: name, modDate: modDate, children: folders, docs: docs)
    }
}
