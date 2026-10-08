// Pagina «Modelli»: formato, cinque colori a memoria, recenti, modelli del sistema (con cursore), modelli miei (PDF o foto).
// Si apre dopo «Nuovo quaderno», da «Pagina bianca…» e da «Modello e colore pagina».
import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

/// Richiesta di aprire la pagina Modelli dall'Editor
struct RichiestaModelli: Identifiable {
    enum Modo {
        case modifica(Int)              // cambia lo sfondo della pagina in questa posizione
        case inserisci(dopo: Int)       // aggiunge una pagina bianca dopo quella in questa posizione
    }
    let id = UUID()
    let modo: Modo
}

struct PaginaModelli: View {
    enum Modo { case nuovo, modifica, inserisci }

    let modo: Modo
    var formatoFisso: FormatoPagina?
    var modelloIniziale: ModelloPagina?
    var possibileATutte = false
    var nomeATutte = "Applica a tutte le pagine"
    /// Modello scelto, formato, e se vale per tutte le pagine
    let scegli: (ModelloPagina, FormatoPagina, Bool) -> Void
    let chiudi: () -> Void

    @State private var formato = ModelliArchivio.formato
    @State private var colori = ModelliArchivio.colori()
    @State private var indiceColore = ModelliArchivio.coloreScelto
    @State private var passi: [TipoModello: Double] = [:]
    @State private var recenti: [ModelloPagina] = []
    @State private var personali: [ModelloPersonale] = []
    @State private var selezionato: ModelloPagina?
    @State private var selSistema: TipoModello?
    @State private var atutte = false
    @State private var coloreInModifica: Int?
    @State private var mostraAlbum = false
    @State private var fotoScelta: PhotosPickerItem?
    @State private var mostraFile = false
    @State private var daRitagliare: RichiestaRitaglio?

    private var formatoCorrente: FormatoPagina { formatoFisso ?? formato }
    private var coloreAttuale: ColoreSalvato { colori[min(indiceColore, colori.count - 1)] }
    private var larghezzaScheda: CGFloat { formatoCorrente == .verticale ? 150 : 210 }

    private var titolo: String {
        switch modo {
        case .nuovo: return "Seleziona un Modello"
        case .modifica: return "Cambia Modello"
        case .inserisci: return "Pagina bianca"
        }
    }

    private func modelloSistema(_ t: TipoModello) -> ModelloPagina {
        ModelloPagina(colore: coloreAttuale, tipo: t, passo: t == .liscio ? 1 : (passi[t] ?? 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            barra
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(titolo).font(AptTema.titoloGrande).foregroundColor(AptTema.testo)
                    intestazione
                    if !recenti.isEmpty {
                        sezione("Recenti") {
                            riga {
                                ForEach(Array(recenti.enumerated()), id: \.offset) { _, m in
                                    scheda(m, nome: m.tipo.nome, evidenziata: selSistema == nil && selezionato == m) { tocca(m) }
                                }
                            }
                        }
                    }
                    sezione("Modelli del sistema") {
                        riga {
                            ForEach(TipoModello.disegnati) { t in
                                scheda(modelloSistema(t), nome: t.nome, evidenziata: selSistema == t,
                                       cursore: t == .liscio ? nil : cursore(t)) { tocca(modelloSistema(t), sistema: t) }
                            }
                        }
                    }
                    sezionePersonali
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            if modo == .modifica && possibileATutte { barraBassa }
        }
        .background(AptTema.sfondo.ignoresSafeArea())
        .photosPicker(isPresented: $mostraAlbum, selection: $fotoScelta, matching: .images)
        .onChange(of: fotoScelta) { _, voce in caricaFoto(voce) }
        .fileImporter(isPresented: $mostraFile, allowedContentTypes: [.pdf, .image]) { risultato in
            if case .success(let url) = risultato { importaFile(url) }
        }
        .fullScreenCover(item: $daRitagliare) { r in
            RitagliaModello(richiesta: r, usa: { img in
                salvaPersonale(img, r.formato)
                daRitagliare = nil
            }, annulla: { daRitagliare = nil })
        }
        .onChange(of: formato) { _, nuovo in ModelliArchivio.formato = nuovo }
        .onAppear(perform: iniziale)
    }

    // MARK: Parti

    private var barra: some View {
        HStack {
            Button("Annulla", action: chiudi).buttonStyle(AptStileSecondario())
            Spacer()
            if modo == .modifica {
                Button("Applica", action: applica)
                    .buttonStyle(AptStilePrimario())
                    .disabled(selezionato == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var intestazione: some View {
        HStack(alignment: .center, spacing: 20) {
            if formatoFisso == nil {
                Picker("Formato", selection: $formato) {
                    ForEach(FormatoPagina.allCases) { Text($0.nome).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
            }
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { i in pallino(i) }
            }
        }
    }

    private func pallino(_ i: Int) -> some View {
        Circle()
            .fill(colori[i].color)
            .frame(width: 38, height: 38)
            .overlay(Circle().stroke(i == indiceColore ? AptTema.accento : AptTema.linea, lineWidth: i == indiceColore ? 3 : 1))
            .contentShape(Circle())
            .onTapGesture {
                indiceColore = i
                ModelliArchivio.coloreScelto = i
                aggiornaSelezione()
            }
            .onLongPressGesture(minimumDuration: 0.4) { coloreInModifica = i }
            .accessibilityLabel("Colore \(i + 1)")
            .popover(isPresented: Binding(
                get: { coloreInModifica == i },
                set: { if !$0 && coloreInModifica == i { coloreInModifica = nil } }
            )) {
                ColorPicker(
                    "Colore",
                    selection: Binding(
                        get: { colori[i].color },
                        set: {
                            colori[i] = ColoreSalvato($0)
                            ModelliArchivio.salvaColori(colori)
                            aggiornaSelezione()
                        }
                    ),
                    supportsOpacity: false
                )
                .padding(20)
                .frame(width: 300)
                .aptPannello()
            }
    }

    private var sezionePersonali: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Modelli creati da me").font(AptTema.titolo).foregroundColor(AptTema.testo)
                Spacer()
                Button { mostraFile = true } label: { Label("File", systemImage: "folder") }
                    .buttonStyle(AptStileContorno())
                Button { mostraAlbum = true } label: { Label("Album", systemImage: "photo") }
                    .buttonStyle(AptStileContorno())
            }
            let miei = personali.filter { $0.formato == formatoCorrente }
            if !miei.isEmpty {
                riga {
                    ForEach(miei) { p in
                        let m = ModelloPagina(colore: .bianco, tipo: .personale, passo: 1, immagine: p.id)
                        scheda(m, nome: "Mio modello", evidenziata: selSistema == nil && selezionato == m) { tocca(m) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    ModelliArchivio.elimina(p)
                                    personali = ModelliArchivio.personali()
                                    recenti = ModelliArchivio.recenti()
                                } label: { Label("Elimina", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }

    private var barraBassa: some View {
        HStack {
            Text(nomeATutte).font(AptTema.corpo).foregroundColor(AptTema.testo)
            Spacer()
            Toggle("", isOn: $atutte).labelsHidden()
        }
        .padding(16)
        .aptScheda()
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private func sezione<C: View>(_ nome: String, @ViewBuilder _ contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(nome).font(AptTema.titolo).foregroundColor(AptTema.testo)
            contenuto()
        }
    }

    private func riga<C: View>(@ViewBuilder _ contenuto: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) { contenuto() }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
        }
    }

    /// Una scheda: anteprima, nome ed eventuale cursore di grandezza
    private func scheda(_ m: ModelloPagina, nome: String, evidenziata: Bool, cursore: Binding<Double>? = nil,
                        azione: @escaping () -> Void) -> some View {
        let misura = formatoCorrente.misura
        let altezza = larghezzaScheda * misura.height / misura.width
        return VStack(spacing: 8) {
            Button(action: azione) {
                Image(uiImage: ModelliArchivio.anteprima(m, misura: misura, larghezza: larghezzaScheda))
                    .resizable()
                    .frame(width: larghezzaScheda, height: altezza)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(evidenziata ? AptTema.accento : AptTema.linea, lineWidth: evidenziata ? 3 : 1))
                    .shadow(color: AptTema.ombraColore, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            Text(nome)
                .font(AptTema.corpo)
                .foregroundColor(evidenziata ? AptTema.accentoTesto : AptTema.testo)
            if let cursore {
                Slider(value: cursore, in: 0.6...2.0)
                    .tint(AptTema.accento)
                    .frame(width: larghezzaScheda)
            }
        }
        .frame(width: larghezzaScheda)
    }

    private func cursore(_ t: TipoModello) -> Binding<Double> {
        Binding(
            get: { passi[t] ?? 1 },
            set: { v in
                passi[t] = v
                ModelliArchivio.imposta(passo: v, per: t)
                if selSistema == t { selezionato = modelloSistema(t) }
            }
        )
    }

    // MARK: Azioni

    private func iniziale() {
        for t in TipoModello.disegnati where t != .liscio { passi[t] = ModelliArchivio.passo(t) }
        recenti = ModelliArchivio.recenti()
        personali = ModelliArchivio.personali()
        if modo == .modifica, let m = modelloIniziale {
            selezionato = m
            if m.tipo != .personale {
                selSistema = m.tipo
                if m.tipo != .liscio { passi[m.tipo] = m.passo }
            }
        }
    }

    private func aggiornaSelezione() {
        if let t = selSistema { selezionato = modelloSistema(t) }
    }

    private func tocca(_ m: ModelloPagina, sistema: TipoModello? = nil) {
        switch modo {
        case .modifica:
            selezionato = m
            selSistema = sistema
        case .nuovo, .inserisci:
            ModelliArchivio.ricorda(m)
            scegli(m, formatoCorrente, false)
            chiudi()
        }
    }

    private func applica() {
        guard let m = selezionato else { return }
        ModelliArchivio.ricorda(m)
        scegli(m, formatoCorrente, atutte && possibileATutte)
        chiudi()
    }

    // MARK: Modelli miei: foto e file

    private func caricaFoto(_ voce: PhotosPickerItem?) {
        guard let voce else { return }
        Task {
            if let dati = try? await voce.loadTransferable(type: Data.self), let img = UIImage(data: dati) {
                await MainActor.run { preparaImmagine(img) }
            }
            await MainActor.run { fotoScelta = nil }
        }
    }

    private func importaFile(_ url: URL) {
        let accesso = url.startAccessingSecurityScopedResource()
        defer { if accesso { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url), let p = doc.page(at: 0) else { return }
            let m = NotesModel.misuraVista(p)
            guard m.width > 1, m.height > 1 else { return }
            let larghezza: CGFloat = 1600
            preparaImmagine(p.thumbnail(of: CGSize(width: larghezza, height: larghezza * m.height / m.width), for: .cropBox))
        } else if let dati = try? Data(contentsOf: url), let img = UIImage(data: dati) {
            preparaImmagine(img)
        }
    }

    /// Se la proporzione è già quella del foglio si salva subito; altrimenti si sceglie la parte da usare
    private func preparaImmagine(_ originale: UIImage) {
        let img = ElaboraImmagine.normalizza(originale)
        guard img.size.width > 1, img.size.height > 1 else { return }
        let f = formatoCorrente
        if abs(img.size.width / img.size.height / f.rapporto - 1) < 0.03 {
            salvaPersonale(ElaboraImmagine.finale(img, ritaglio: ElaboraImmagine.centrato(img, formato: f), formato: f), f)
        } else {
            daRitagliare = RichiestaRitaglio(immagine: img, formato: f)
        }
    }

    private func salvaPersonale(_ img: UIImage, _ f: FormatoPagina) {
        _ = ModelliArchivio.aggiungiPersonale(img, formato: f)
        personali = ModelliArchivio.personali()
    }
}
