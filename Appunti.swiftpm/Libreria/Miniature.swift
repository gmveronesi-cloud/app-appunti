// Miniature e numero pagine reali
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Miniature e numero pagine reali (PDFKit)

struct AptDocInfo {
    let image: UIImage?
    let pages: Int?
}
final class AptInfoBox {
    let info: AptDocInfo
    init(_ info: AptDocInfo) { self.info = info }
}
enum AptDocInfoLoader {
    static let cache = NSCache<NSString, AptInfoBox>()

    static func load(_ doc: AptDoc) async -> AptDocInfo {
        let key = "\(doc.id)|\(doc.modDate.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit.info }
        let url = doc.url
        let info: AptDocInfo = await Task.detached(priority: .utility) { () -> AptDocInfo in
            guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else {
                return AptDocInfo(image: nil, pages: nil)
            }
            let img = page.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
            return AptDocInfo(image: img, pages: pdf.pageCount)
        }.value
        if info.image != nil { cache.setObject(AptInfoBox(info), forKey: key) }
        return info
    }
}
