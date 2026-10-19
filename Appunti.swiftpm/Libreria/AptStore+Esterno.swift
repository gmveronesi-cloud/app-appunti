// Store: file ricevuti da altre app (finestra di condivisione di iPadOS, «Apri con», «Copia in Appunti»)
//
// Arriva un PDF o una foto: compare una finestra SOPRA qualunque schermata (anche l'Editor) che chiede
// 1) in quale cartella salvarlo, 2) se aprirlo ora o restare dove si è.
import SwiftUI
import UIKit

extension AptStore {
    /// Un file arriva da un'altra app. Subito si fa una copia in una cartella temporanea (l'originale in «Inbox» si toglie).
    func riceviEsterno(_ urls: [URL]) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("Arrivo-" + UUID().uuidString)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        var ricevuti = 0
        var errore: String?
        for u in urls {
            guard u.isFileURL else { errore = "Ho ricevuto un collegamento, non un file."; continue }
            let acc = u.startAccessingSecurityScopedResource()
            defer { if acc { u.stopAccessingSecurityScopedResource() } }
            // Già ricevuto poco fa (iPadOS a volte consegna lo stesso file due volte)
            if inAttesa.contains(where: { $0.lastPathComponent == u.lastPathComponent }) { ricevuti += 1; continue }
            let dest = tmp.appendingPathComponent(u.lastPathComponent)
            var copiato = (try? fm.copyItem(at: u, to: dest)) != nil
            if !copiato, let d = try? Data(contentsOf: u, options: .mappedIfSafe) {      // ripiego: lettura diretta
                copiato = (try? d.write(to: dest)) != nil
            }
            if copiato {
                inAttesa.append(dest)
                ricevuti += 1
                if u.path.contains("/Inbox/") { try? fm.removeItem(at: u) }
            } else {
                errore = "Non riesco a leggere il file ricevuto."
            }
        }
        if ricevuti == 0 {
            mostraMessaggio(errore ?? "Nessun file ricevuto.")
            return
        }
        if rootURL == nil {
            mostraMessaggio("Scegli la cartella della libreria: poi potrai salvare il file ricevuto.")
        } else {
            mostraMessaggio(ricevuti == 1 ? "File ricevuto: scegli dove salvarlo." : "\(ricevuti) file ricevuti: scegli dove salvarli.")
            mostraArrivo()
        }
    }

    /// Apre la finestra di scelta (riprova qualche volta: all'avvio la schermata può non essere ancora pronta)
    func mostraArrivo(tentativo: Int = 0) {
        guard rootURL != nil, !inAttesa.isEmpty, PresentatoreArrivo.attivo == nil else { return }
        guard let cima = PresentatoreArrivo.cima(), !cima.isBeingPresented, !cima.isBeingDismissed else {
            if tentativo < 25 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.mostraArrivo(tentativo: tentativo + 1) }
            } else {
                mostraMessaggio("Non riesco ad aprire la finestra di salvataggio. Riprova dalla Libreria.")
            }
            return
        }
        let host = UIHostingController(rootView: SceltaArrivoView().environmentObject(self).tint(AptTema.accento))
        host.modalPresentationStyle = .formSheet
        host.preferredContentSize = CGSize(width: 540, height: 640)
        host.isModalInPresentation = true
        PresentatoreArrivo.attivo = host
        cima.present(host, animated: true)
    }

    /// Salva i file ricevuti nella cartella scelta; restituisce i documenti nati.
    func salvaArrivo(in parent: String) -> [AptDoc] {
        let urls = inAttesa
        inAttesa = []
        let prima = Set((folder(parent)?.docs ?? []).map { $0.id })
        var pdf: [URL] = []
        var foto: [UIImage] = []
        for u in urls {
            if u.pathExtension.lowercased() == "pdf" {
                pdf.append(u)
            } else if let d = try? Data(contentsOf: u), let img = UIImage(data: d) {
                foto.append(img)
            }
        }
        if !pdf.isEmpty { importPDFs(pdf, into: parent) }
        if !foto.isEmpty { addImages(foto, merge: false, into: parent) }
        for u in urls { try? FileManager.default.removeItem(at: u.deletingLastPathComponent()) }
        return (folder(parent)?.docs ?? []).filter { !prima.contains($0.id) }
    }

    func scartaArrivo() {
        for u in inAttesa { try? FileManager.default.removeItem(at: u.deletingLastPathComponent()) }
        inAttesa = []
    }

    /// Apre il documento: nell'Editor già aperto come nuova scheda, oppure aprendo l'Editor
    func apriDocumento(_ d: AptDoc) {
        if openDocument == nil { openDocument = d } else { richiestaApri = d }
    }

    func mostraMessaggio(_ testo: String) {
        messaggio = testo
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.messaggio == testo { self?.messaggio = nil }
        }
    }
}

enum PresentatoreArrivo {
    static weak var attivo: UIViewController?

    /// La schermata più in alto (anche sopra l'Editor, che è a tutto schermo)
    static func cima() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    static func chiudi(_ dopo: (() -> Void)? = nil) {
        guard let host = attivo else { dopo?(); return }
        host.dismiss(animated: true) { dopo?() }
        attivo = nil
    }
}

struct SceltaArrivoView: View {
    @EnvironmentObject var store: AptStore
    @State private var cartella = ""
    @State private var salvati: [AptDoc]?
    @State private var dove = ""
    @State private var iniziato = false

    private func righe(_ cartelle: [AptFolder], livello: Int, parent: String) -> [(AptFolder, Int)] {
        var out: [(AptFolder, Int)] = []
        for f in store.orderedFolders(cartelle, parent: parent) {
            out.append((f, livello))
            out += righe(f.children, livello: livello + 1, parent: f.id)
        }
        return out
    }

    private var descrizione: String {
        let n = store.inAttesa.count
        if n == 1, let u = store.inAttesa.first { return u.deletingPathExtension().lastPathComponent }
        return "\(n) file ricevuti"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let docs = salvati {
                fatto(docs)
            } else {
                scelta
            }
        }
        .background(AptTema.carta)
        .onAppear {
            guard !iniziato else { return }
            iniziato = true
            if let a = store.openFolder, store.folder(a) != nil { cartella = a }
        }
    }

    private var scelta: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Salva nella cartella…").font(AptTema.titolo).foregroundColor(AptTema.testo)
                Text(descrizione).font(.system(size: 14)).foregroundColor(AptTema.testo2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            AptLinea()
            ScrollView {
                VStack(spacing: 2) {
                    riga(nome: "Libreria (cartella principale)", icona: "tray.full", livello: 0, id: "")
                    ForEach(righe(store.root.children, livello: 0, parent: ""), id: \.0.id) { f, liv in
                        riga(nome: f.name, icona: "folder", livello: liv + 1, id: f.id)
                    }
                }
                .padding(12)
            }
            AptLinea()
            HStack(spacing: 12) {
                Button("Annulla") {
                    store.scartaArrivo()
                    PresentatoreArrivo.chiudi()
                }
                .foregroundColor(AptTema.testo2)
                Spacer()
                Button {
                    dove = store.folder(cartella)?.name ?? "Libreria"
                    let docs = store.salvaArrivo(in: cartella)
                    if docs.isEmpty {
                        store.mostraMessaggio("Non sono riuscito a salvare il file.")
                        PresentatoreArrivo.chiudi()
                    } else {
                        salvati = docs
                    }
                } label: {
                    Text("Salva qui").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10)
                }
                .aptProminentButton()
            }
            .padding(16)
        }
    }

    private func riga(nome: String, icona: String, livello: Int, id: String) -> some View {
        let scelta = cartella == id
        return Button { cartella = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icona).foregroundColor(scelta ? AptTema.accento : AptTema.testo2).frame(width: 24)
                Text(nome).font(.system(size: 16)).foregroundColor(AptTema.testo).lineLimit(1)
                Spacer()
                if scelta { Image(systemName: "checkmark").foregroundColor(AptTema.accento) }
            }
            .padding(.leading, CGFloat(livello) * 22 + 12).padding(.trailing, 12).padding(.vertical, 11)
            .background(scelta ? AptTema.accentoTenue : Color.clear,
                        in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fatto(_ docs: [AptDoc]) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(AptTema.accento)
            Text(docs.count == 1 ? "Salvato in «\(dove)»" : "\(docs.count) documenti salvati in «\(dove)»")
                .font(AptTema.titolo).foregroundColor(AptTema.testo)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button {
                    let d = docs[0]
                    PresentatoreArrivo.chiudi { store.apriDocumento(d) }
                } label: {
                    Text("Apri ora").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity)
                }
                .aptProminentButton()
                Button {
                    PresentatoreArrivo.chiudi()
                } label: {
                    Text("Rimani dove sei").font(.system(size: 16, weight: .medium))
                        .foregroundColor(AptTema.testo).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous).strokeBorder(AptTema.linea, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding(20)
    }
}
