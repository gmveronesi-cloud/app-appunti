// Schermata Editor: barra in alto, striscia di schede (un PDF per scheda), barra strumenti e PDF.
// Il documento attivo sta nel modello; al cambio di scheda si salva (se ci sono modifiche) e si apre l'altro.
import SwiftUI
import PDFKit
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var store: AptStore
    @StateObject private var model = NotesModel()
    @StateObject private var ricerca = RicercaPDF()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var chiediUscita = false
    @State private var azioneSospesa: (() -> Void)?
    @State private var attivo: AptDoc
    @State private var mostraImpostazioni = false
    @State private var mostraMiniature = false
    @State private var mostraRecenti = false
    @State private var mostraFoto = false
    @State private var mostraFile = false
    @State private var fileDocumento = false          // false = immagine, true = PDF o documento di testo
    @State private var aggiungeAlDocumento = false    // true = le pagine vanno in fondo al documento aperto
    @State private var mostraScansione = false
    @State private var documentoScelto: DocumentoScelto?
    @State private var fotoScelta: PhotosPickerItem?

    @AppStorage("posizioneBarra") private var posizioneBarra: String = "fissa"
    @AppStorage("barraPos") private var posizioneFissa: String = "alto"
    @AppStorage("barraGrande") private var grande = false

    init(doc: AptDoc) {
        _attivo = State(initialValue: doc)
    }

    var body: some View {
        VStack(spacing: 0) {
            barraAlta
            strisciaSchede
            if ricerca.attiva {
                BarraRicerca(ricerca: ricerca)
            }
            corpo
            if ricerca.attiva && ricerca.tastiera {
                AptTastiera(testo: $ricerca.testo, tutto: .constant(false), titoloInvio: "Cerca",
                            onInvio: { ricerca.prossimo() },
                            onNascondi: { ricerca.tastiera = false })
            }
        }
        .background(AptTema.scrivania.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if posizioneBarra == "flottante" && !(ricerca.attiva && ricerca.tastiera) {
                GeometryReader { geo in
                    BarraFlottante(model: model, area: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !(ricerca.attiva && ricerca.tastiera) {
                VassoioView(aggiungi: { model.inserisciDaVassoio($0, larghezzaSchermo: $1) })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .overlay { OrologioRiquadro() }
        .onAppear {
            if !store.schede.contains(where: { $0.id == attivo.id }) { store.schede.append(attivo) }
            model.open(url: attivo.url)
        }
        .onChange(of: attivo.id) { _, _ in ricerca.azzera() }
        .onChange(of: scenePhase) { _, fase in
            if fase != .active { model.salvaSeModificato() }
        }
        .confirmationDialog("Ci sono modifiche non salvate", isPresented: $chiediUscita, titleVisibility: .visible) {
            Button("Salva") {
                model.save()
                guard !model.modificato else { return }   // scrittura riuscita
                let azione = azioneSospesa
                azioneSospesa = nil
                azione?()
            }
            Button("Non salvare", role: .destructive) {
                model.modificato = false
                let azione = azioneSospesa
                azioneSospesa = nil
                azione?()
            }
            Button("Annulla", role: .cancel) { azioneSospesa = nil }
        }
        .confirmationDialog("Immagine", isPresented: $model.chiediImmagine, titleVisibility: .hidden) {
            Button("Dalle Foto") { model.origine = .foto }
            Button("Da File") { model.origine = .file }
            Button("PDF o documento di testo") { model.origine = .documento }
            Button("Aggiungi PDF al documento") { model.origine = .aggiungiPDF }
            Button("Scansiona documento") { model.origine = .scansione }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: model.origine) { _, o in
            guard let o else { return }
            model.origine = nil
            switch o {
            case .foto: mostraFoto = true
            case .file: fileDocumento = false; aggiungeAlDocumento = false; mostraFile = true
            case .documento: fileDocumento = true; aggiungeAlDocumento = false; mostraFile = true
            case .aggiungiPDF: fileDocumento = true; aggiungeAlDocumento = true; mostraFile = true
            case .scansione:
                if VNDocumentCameraViewController.isSupported { mostraScansione = true }
                else { model.message = "La scansione con la fotocamera non è disponibile su questo dispositivo." }
            }
        }
        .fullScreenCover(isPresented: $mostraScansione) {
            ScannerDocumento { pagine in
                mostraScansione = false
                if !pagine.isEmpty { model.inserisciDocumento(pagine) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $documentoScelto) { d in
            SceltaPagine(
                scelto: d,
                aggiungi: { indici in
                    documentoScelto = nil
                    if d.aggiungeAlDocumento {
                        model.aggiungiPagine(da: d.documento, indici: indici)
                        return
                    }
                    let pagine = indici.compactMap { d.documento.page(at: $0) }.compactMap { ConvertitoreDocumento.immagine($0) }
                    model.inserisciDocumento(pagine)
                },
                annulla: { documentoScelto = nil }
            )
            .aptPannello()
        }
        .photosPicker(isPresented: $mostraFoto, selection: $fotoScelta, matching: .images)
        .onChange(of: fotoScelta) { _, scelta in
            guard let scelta else { return }
            Task {
                if let dati = try? await scelta.loadTransferable(type: Data.self) { model.inserisciImmagine(dati: dati) }
                fotoScelta = nil
            }
        }
        .fileImporter(isPresented: $mostraFile,
                      allowedContentTypes: fileDocumento ? [.pdf, .plainText, .rtf, .html] : [.image]) { esito in
            guard case .success(let url) = esito else { return }
            if fileDocumento {
                guard let doc = ConvertitoreDocumento.pdf(da: url), doc.pageCount > 0 else {
                    model.message = "Non riesco a leggere il file scelto."
                    return
                }
                if aggiungeAlDocumento {
                    if doc.pageCount == 1 {
                        model.aggiungiPagine(da: doc, indici: [0])
                    } else {
                        documentoScelto = DocumentoScelto(documento: doc, nome: url.lastPathComponent, aggiungeAlDocumento: true)
                    }
                } else if doc.pageCount == 1, let d = doc.page(at: 0).flatMap({ ConvertitoreDocumento.immagine($0) }) {
                    model.inserisciDocumento([d])
                } else {
                    documentoScelto = DocumentoScelto(documento: doc, nome: url.lastPathComponent)
                }
                return
            }
            let accesso = url.startAccessingSecurityScopedResource()
            defer { if accesso { url.stopAccessingSecurityScopedResource() } }
            if let dati = try? Data(contentsOf: url) { model.inserisciImmagine(dati: dati) }
        }
        .sheet(item: $model.bozzaTesto) { b in
            AptRinomina(
                titolo: "Testo",
                nome: b.testo,
                salva: { model.confermaTesto(b, $0) },
                annulla: { model.bozzaTesto = nil }
            )
            .presentationDetents([.height(470)])
            .aptPannello()
        }
    }

    // MARK: Barra in alto

    private var barraAlta: some View {
        ZStack {
            Text(attivo.name)
                .font(AptTema.corpoForte)
                .foregroundColor(AptTema.testo)
                .lineLimit(1)
                .padding(.horizontal, 250)
            HStack(spacing: 2) {
                Button { tornaInLibreria() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        Text("Libreria").font(AptTema.corpo)
                    }
                    .foregroundColor(AptTema.testo2)
                    .padding(.horizontal, 6).frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { mostraMiniature.toggle() } label: {
                    AptIcona(nome: "sidebar.left", attiva: mostraMiniature)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Miniature delle pagine")
                Spacer()
                Button {
                    ricerca.collega(model.pdfView)
                    ricerca.attiva.toggle()
                } label: {
                    AptIcona(nome: "magnifyingglass", attiva: ricerca.attiva)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerca nel testo")
                ShareLink(item: attivo.url) {
                    AptIcona(nome: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Condividi")
                Button { mostraImpostazioni = true } label: {
                    AptIcona(nome: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Impostazioni")
                .popover(isPresented: $mostraImpostazioni) { ImpostazioniEditor(model: model).aptPannello() }
                Button("Salva") { model.save() }
                    .buttonStyle(AptStilePrimario())
                Menu {
                    Button("Scarta tratti non salvati", role: .destructive) { model.discardUnsaved() }
                } label: {
                    AptIcona(nome: "ellipsis")
                }
                .accessibilityLabel("Altro")
            }
        }
        .frame(height: 38)
        .aptBarra()
    }

    // MARK: Schede

    private var strisciaSchede: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.schede) { d in scheda(d) }
                }
                .padding(.horizontal, 12)
            }
            Button { mostraRecenti = true } label: {
                AptIcona(nome: "plus")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel("Apri un altro file")
            .popover(isPresented: $mostraRecenti) { recenti.aptPannello() }
        }
        .frame(height: 44)
    }

    private func scheda(_ d: AptDoc) -> some View {
        let scelta = d.id == attivo.id
        return HStack(spacing: 2) {
            Button { chiudiScheda(d) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi \(d.name)")
            Button { vai(a: d) } label: {
                Text(d.name)
                    .font(.system(size: 13, weight: scelta ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                    .padding(.trailing, 10)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .foregroundStyle(scelta ? AptTema.testo : AptTema.testo2)
        .background(scelta ? AptTema.carta : Color.clear, in: Capsule())
        .overlay(Capsule().stroke(scelta ? AptTema.linea : Color.clear, lineWidth: 1))
    }

    // File da aprire con «+»: i più recenti (per data di modifica) non ancora aperti
    private var recenti: some View {
        let aperti = Set(store.schede.map { $0.id })
        let lista = store.allDocs
            .filter { !aperti.contains($0.id) }
            .sorted { $0.modDate > $1.modDate }
            .prefix(15)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("File recenti").font(AptTema.titoloMedio).foregroundColor(AptTema.testo).padding(16)
                if lista.isEmpty {
                    Text("Nessun altro file.").foregroundStyle(AptTema.testo2).padding(.horizontal, 16).padding(.bottom, 16)
                }
                ForEach(Array(lista)) { d in
                    Button {
                        mostraRecenti = false
                        apri(d)
                    } label: {
                        HStack {
                            Image(systemName: "doc.richtext")
                            Text(d.name).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    AptLinea()
                }
            }
        }
        .frame(width: 340, height: 420)
    }

    // MARK: Azioni sulle schede

    private func apri(_ d: AptDoc) {
        if !store.schede.contains(where: { $0.id == d.id }) { store.schede.append(d) }
        vai(a: d)
    }

    /// Salvataggio manuale con modifiche in sospeso: prima di lasciare il documento si chiede cosa fare.
    private func conConferma(_ azione: @escaping () -> Void) {
        if model.modificato && !model.salvataggioAutomatico {
            azioneSospesa = azione
            chiediUscita = true
        } else {
            azione()
        }
    }

    private func vai(a d: AptDoc) {
        guard d.id != attivo.id else { return }
        conConferma {
            model.salvaSeModificato()
            attivo = d
            model.open(url: d.url)
        }
    }

    private func chiudiScheda(_ d: AptDoc) {
        guard let i = store.schede.firstIndex(where: { $0.id == d.id }) else { return }
        let eraAttiva = d.id == attivo.id
        let esegui = {
            if eraAttiva { model.salvaSeModificato() }
            store.schede.remove(at: i)
            guard eraAttiva else { return }
            if store.schede.isEmpty {
                model.close()
                dismiss()
            } else {
                let prossima = store.schede[min(i, store.schede.count - 1)]
                attivo = prossima
                model.open(url: prossima.url)
            }
        }
        if eraAttiva { conConferma(esegui) } else { esegui() }
    }

    private func tornaInLibreria() {
        conConferma {
            model.salvaSeModificato()
            model.close()
            dismiss()
        }
    }

    // MARK: Corpo: barra strumenti e PDF

    private var fissaInAlto: Bool { posizioneBarra == "fissa" && posizioneFissa == "alto" }
    private var fissaInBasso: Bool { posizioneBarra == "fissa" && posizioneFissa == "basso" }
    private var fissaASinistra: Bool { posizioneBarra == "fissa" && posizioneFissa == "sinistra" }

    private var vistaPDF: some View {
        PDFKitView(model: model)
            .clipShape(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .ignoresSafeArea(edges: fissaInBasso ? Edge.Set() : Edge.Set.bottom)
    }

    private var areaPDF: some View {
        HStack(spacing: 0) {
            if mostraMiniature {
                MiniaturePagine(model: model)
                    .frame(width: 120)
                    .clipShape(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous))
                    .padding(.leading, 12)
            }
            vistaPDF
        }
    }

    private var corpo: some View {
        VStack(spacing: 0) {
            if !model.message.isEmpty {
                Text(model.message)
                    .font(AptTema.dettaglio)
                    .foregroundColor(AptTema.testo2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            if fissaInAlto {
                BarraStrumenti(model: model)
                    .aptCapsulaBarra()
            }
            if fissaASinistra {
                HStack(spacing: 0) {
                    BarraStrumenti(model: model, verticale: true)
                        .frame(width: grande ? 76 : 64)
                        .aptCapsulaBarra(verticale: true)
                    areaPDF
                }
            } else {
                areaPDF
            }
            if fissaInBasso {
                BarraStrumenti(model: model)
                    .aptCapsulaBarra()
            }
        }
    }
}

// Miniature delle pagine (PDFKit): un tocco porta alla pagina.
struct MiniaturePagine: UIViewRepresentable {
    @ObservedObject var model: NotesModel

    func makeUIView(context: Context) -> PDFThumbnailView {
        let t = PDFThumbnailView()
        t.pdfView = model.pdfView
        t.thumbnailSize = CGSize(width: 84, height: 112)
        t.backgroundColor = UIColor(AptTema.carta)
        return t
    }

    func updateUIView(_ t: PDFThumbnailView, context: Context) {
        if t.pdfView !== model.pdfView { t.pdfView = model.pdfView }
    }
}
