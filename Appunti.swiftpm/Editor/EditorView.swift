// Schermata Editor: barra in alto, striscia di schede (un PDF per scheda), barra strumenti e PDF.
// Il documento attivo sta nel modello; al cambio di scheda si salva (se ci sono modifiche) e si apre l'altro.
import SwiftUI
import PDFKit

struct EditorView: View {
    @EnvironmentObject private var store: AptStore
    @StateObject private var model = NotesModel()
    @StateObject private var ricerca = RicercaPDF()
    @Environment(\.dismiss) private var dismiss

    @State private var attivo: AptDoc
    @State private var mostraImpostazioni = false
    @State private var mostraMiniature = false
    @State private var mostraRecenti = false

    @AppStorage("posizioneBarra") private var posizioneBarra: String = "fissa"
    @AppStorage("barraPos") private var posizioneFissa: String = "alto"
    @AppStorage("barraGrande") private var grande = false

    init(doc: AptDoc) {
        _attivo = State(initialValue: doc)
    }

    var body: some View {
        VStack(spacing: 0) {
            barraAlta
            Divider()
            strisciaSchede
            Divider()
            if ricerca.attiva {
                BarraRicerca(ricerca: ricerca)
                Divider()
            }
            corpo
            if ricerca.attiva && ricerca.tastiera {
                Divider()
                AptTastiera(testo: $ricerca.testo, tutto: .constant(false), titoloInvio: "Cerca",
                            onInvio: { ricerca.prossimo() },
                            onNascondi: { ricerca.tastiera = false })
            }
        }
        .overlay(alignment: .bottom) {
            if posizioneBarra == "flottante" && !(ricerca.attiva && ricerca.tastiera) {
                GeometryReader { geo in
                    BarraFlottante(model: model, area: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .onAppear {
            if !store.schede.contains(where: { $0.id == attivo.id }) { store.schede.append(attivo) }
            model.open(url: attivo.url)
        }
        .onChange(of: attivo.id) { _, _ in ricerca.azzera() }
    }

    // MARK: Barra in alto

    private var barraAlta: some View {
        ZStack {
            Text(attivo.name)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 250)
            HStack(spacing: 2) {
                Button { tornaInLibreria() } label: {
                    Label("Libreria", systemImage: "chevron.left").padding(.horizontal, 6)
                }
                Button { mostraMiniature.toggle() } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 44, height: 44)
                        .background(mostraMiniature ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Miniature delle pagine")
                Spacer()
                Button {
                    ricerca.collega(model.pdfView)
                    ricerca.attiva.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 44, height: 44)
                        .background(ricerca.attiva ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Cerca nel testo")
                ShareLink(item: attivo.url) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Condividi")
                Button { mostraImpostazioni = true } label: {
                    Image(systemName: "gearshape").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Impostazioni")
                .popover(isPresented: $mostraImpostazioni) { ImpostazioniEditor(model: model) }
                Button("Salva") { model.save() }
                    .buttonStyle(.borderedProminent)
                Menu {
                    Button("Scarta tratti non salvati", role: .destructive) { model.discardUnsaved() }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Altro")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(.bar)
    }

    // MARK: Schede

    private var strisciaSchede: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.schede) { d in scheda(d) }
                }
                .padding(.horizontal, 8)
            }
            Button { mostraRecenti = true } label: {
                Image(systemName: "plus").frame(width: 44, height: 34)
            }
            .accessibilityLabel("Apri un altro file")
            .popover(isPresented: $mostraRecenti) { recenti }
        }
        .frame(height: 38)
        .background(Color(.secondarySystemBackground))
    }

    private func scheda(_ d: AptDoc) -> some View {
        let scelta = d.id == attivo.id
        return HStack(spacing: 2) {
            Button { chiudiScheda(d) } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi \(d.name)")
            Button { vai(a: d) } label: {
                Text(d.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                    .padding(.trailing, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 2)
        .foregroundStyle(scelta ? Color.primary : Color.secondary)
        .background(scelta ? Color(.systemBackground) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
                Text("File recenti").font(.headline).padding(16)
                if lista.isEmpty {
                    Text("Nessun altro file.").foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 16)
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
                    Divider()
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

    private func vai(a d: AptDoc) {
        guard d.id != attivo.id else { return }
        model.salvaSeModificato()
        attivo = d
        model.open(url: d.url)
    }

    private func chiudiScheda(_ d: AptDoc) {
        guard let i = store.schede.firstIndex(where: { $0.id == d.id }) else { return }
        let eraAttiva = d.id == attivo.id
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

    private func tornaInLibreria() {
        model.salvaSeModificato()
        model.close()
        dismiss()
    }

    // MARK: Corpo: barra strumenti e PDF

    private var fissaInAlto: Bool { posizioneBarra == "fissa" && posizioneFissa == "alto" }
    private var fissaInBasso: Bool { posizioneBarra == "fissa" && posizioneFissa == "basso" }
    private var fissaASinistra: Bool { posizioneBarra == "fissa" && posizioneFissa == "sinistra" }

    private var vistaPDF: some View {
        PDFKitView(model: model)
            .ignoresSafeArea(edges: fissaInBasso ? Edge.Set() : Edge.Set.bottom)
    }

    private var areaPDF: some View {
        HStack(spacing: 0) {
            if mostraMiniature {
                MiniaturePagine(model: model)
                    .frame(width: 120)
                Divider()
            }
            vistaPDF
        }
    }

    private var corpo: some View {
        VStack(spacing: 0) {
            if !model.message.isEmpty {
                Text(model.message)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }
            if fissaInAlto {
                BarraStrumenti(model: model)
                    .frame(maxWidth: .infinity)
                Divider()
            }
            if fissaASinistra {
                HStack(spacing: 0) {
                    BarraStrumenti(model: model, verticale: true)
                        .frame(width: grande ? 76 : 64)
                    Divider()
                    areaPDF
                }
            } else {
                areaPDF
            }
            if fissaInBasso {
                Divider()
                BarraStrumenti(model: model)
                    .frame(maxWidth: .infinity)
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
        t.backgroundColor = .secondarySystemBackground
        return t
    }

    func updateUIView(_ t: PDFThumbnailView, context: Context) {
        if t.pdfView !== model.pdfView { t.pdfView = model.pdfView }
    }
}
