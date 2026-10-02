// Vassoio: anteprime in basso con le immagini «in sospeso» (screenshot, immagini tagliate o copiate).
// Vale per tutta l'app, non per il singolo foglio: resta tra un documento e l'altro e anche dopo aver
// chiuso l'app. Un tocco sull'anteprima mette l'immagine nel foglio attuale (e resta nel vassoio),
// la X la elimina, il pulsante a sinistra la condivide.
import SwiftUI
import UIKit
import ImageIO

struct VoceVassoio: Identifiable {
    let id: UUID
    let estensione: String
    let miniatura: UIImage

    var url: URL { Vassoio.cartella.appendingPathComponent("\(id.uuidString).\(estensione)") }
}

final class Vassoio: ObservableObject {
    static let condiviso = Vassoio()

    static let cartella: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Vassoio", isDirectory: true)
    }()

    private struct Registro: Codable {
        var id: UUID
        var estensione: String
    }

    /// Dalla più recente alla più vecchia
    @Published private(set) var voci: [VoceVassoio] = []

    private var indiceURL: URL { Self.cartella.appendingPathComponent("indice.json") }

    private init() {
        try? FileManager.default.createDirectory(at: Self.cartella, withIntermediateDirectories: true)
        guard let dati = try? Data(contentsOf: indiceURL),
              let registro = try? JSONDecoder().decode([Registro].self, from: dati) else { return }
        voci = registro.compactMap { r in
            let url = Self.cartella.appendingPathComponent("\(r.id.uuidString).\(r.estensione)")
            guard let mini = Self.miniatura(url: url) else { return nil }
            return VoceVassoio(id: r.id, estensione: r.estensione, miniatura: mini)
        }
    }

    // MARK: Aggiungere, togliere, leggere

    func aggiungi(dati: Data) {
        let id = UUID()
        let estensione = dati.starts(with: [0x89, 0x50]) ? "png" : "jpg"
        let url = Self.cartella.appendingPathComponent("\(id.uuidString).\(estensione)")
        guard (try? dati.write(to: url, options: .atomic)) != nil,
              let mini = Self.miniatura(url: url) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        voci.insert(VoceVassoio(id: id, estensione: estensione, miniatura: mini), at: 0)
        salva()
    }

    func aggiungi(immagine: UIImage) {
        if let d = immagine.pngData() { aggiungi(dati: d) }
    }

    func rimuovi(_ voce: VoceVassoio) {
        try? FileManager.default.removeItem(at: voce.url)
        voci.removeAll { $0.id == voce.id }
        salva()
    }

    func dati(_ voce: VoceVassoio) -> Data? {
        try? Data(contentsOf: voce.url)
    }

    private func salva() {
        let registro = voci.map { Registro(id: $0.id, estensione: $0.estensione) }
        if let d = try? JSONEncoder().encode(registro) { try? d.write(to: indiceURL, options: .atomic) }
    }

    private static func miniatura(url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opzioni: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opzioni as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Vista in basso

struct VassoioView: View {
    @ObservedObject private var v = Vassoio.condiviso
    @AppStorage("vassoioChiuso") private var chiuso = false
    /// Mette l'immagine nel foglio attuale
    var aggiungi: (Data) -> Void

    var body: some View {
        if !v.voci.isEmpty {
            if chiuso { pillola } else { striscia }
        }
    }

    private var pillola: some View {
        Button { chiuso = false } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                Text("\(v.voci.count)").font(AptTema.corpoForte)
            }
            .foregroundStyle(AptTema.accentoScuro)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(AptTema.accentoTenue, in: Capsule())
            .overlay(Capsule().stroke(AptTema.linea, lineWidth: 1))
            .shadow(color: AptTema.ombraColore, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mostra il vassoio")
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var striscia: some View {
        HStack(spacing: 6) {
            Button { chiuso = true } label: { AptIcona(nome: "chevron.down") }
                .buttonStyle(.plain)
                .accessibilityLabel("Nascondi il vassoio")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(v.voci) { scheda($0) }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(AptTema.carta.opacity(0.96), in: RoundedRectangle(cornerRadius: AptTema.raggioL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AptTema.raggioL, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
        .shadow(color: AptTema.ombraColore, radius: AptTema.ombraRaggio, y: AptTema.ombraY)
    }

    private func scheda(_ x: VoceVassoio) -> some View {
        Button {
            guard let d = v.dati(x) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            aggiungi(d)
        } label: {
            Image(uiImage: x.miniatura)
                .resizable()
                .scaledToFit()
                .padding(8)
                .frame(width: 124, height: 124)
                .background(Color.white, in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aggiungi al foglio")
        .overlay(alignment: .topLeading) {
            ShareLink(item: x.url) { pallino("square.and.arrow.up") }
                .buttonStyle(.plain)
                .padding(6)
        }
        .overlay(alignment: .topTrailing) {
            Button { v.rimuovi(x) } label: { pallino("xmark") }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Elimina")
        }
    }

    private func pallino(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AptTema.testo2)
            .frame(width: 26, height: 26)
            .background(AptTema.carta.opacity(0.92), in: Circle())
            .overlay(Circle().stroke(AptTema.linea, lineWidth: 1))
    }
}
