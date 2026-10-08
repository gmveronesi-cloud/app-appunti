// Griglia di tutte le pagine: si apre pizzicando oltre lo zoom minimo.
// Un tocco su una pagina la apre; tenendo premuto e trascinando si riordinano; allargando le dita (o la «×») si chiude.
// «Seleziona»: si scelgono più pagine per esportarle in un PDF o eliminarle.
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct GrigliaPagine: View {
    @ObservedObject var model: NotesModel
    @State private var trascinata: Int?
    @State private var bersaglio: Int?
    @State private var corrente = 0
    @State private var immagini: [ObjectIdentifier: UIImage] = [:]
    @State private var modelloPer = 0
    @State private var mostraModello = false
    @State private var seleziona = false
    @State private var scelte = Set<Int>()
    @State private var condivisione: CondivisionePagine?
    @State private var chiediElimina = false

    private var numero: Int { model.document?.pageCount ?? 0 }

    var body: some View {
        let _ = model.versionePagine
        let inizio = model.indicePrima
        VStack(spacing: 0) {
            barraAlta
            AptLinea()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 190), spacing: 16)], spacing: 18) {
                    ForEach(0..<numero, id: \.self) { i in
                        if let p = model.document?.page(at: i) { cella(i, p, inizio: inizio) }
                    }
                }
                .padding(20)
            }
            if seleziona {
                AptLinea()
                barraBassa
            }
        }
        .background(AptTema.carta)
        .sheet(isPresented: $mostraModello) {
            SceltaModelloPagina(model: model, indice: modelloPer) { mostraModello = false }
                .presentationDetents([.height(500), .large])
        }
        .sheet(item: $condivisione) { c in AptShareSheet(items: [c.url]) }
        .confirmationDialog("Eliminare \(scelte.count == 1 ? "la pagina scelta" : "le \(scelte.count) pagine scelte")?",
                            isPresented: $chiediElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                model.eliminaPagine(Array(scelte))
                esciDallaSelezione()
            }
            Button("Annulla", role: .cancel) {}
        }
        .onAppear { aggiornaCorrente() }
        .onChange(of: numero) { _, nuovo in scelte = scelte.filter { $0 < nuovo } }
        .gesture(
            MagnifyGesture().onEnded { v in if v.magnification > 1.25 && !seleziona { chiudi() } }
        )
    }

    // MARK: Barre

    private var barraAlta: some View {
        HStack(spacing: 10) {
            if seleziona {
                Button("Annulla") { esciDallaSelezione() }
                    .buttonStyle(AptStileSecondario())
                Text(scelte.isEmpty ? "Seleziona pagine" : (scelte.count == 1 ? "1 selezionata" : "\(scelte.count) selezionate"))
                    .font(AptTema.corpoForte)
                    .foregroundColor(AptTema.testo)
                Spacer(minLength: 8)
                Button(scelte.count == numero && numero > 0 ? "Deseleziona tutte" : "Seleziona tutte") {
                    scelte = scelte.count == numero ? [] : Set(0..<numero)
                }
                .buttonStyle(AptStileSecondario())
            } else {
                Button("Seleziona") { seleziona = true }
                    .buttonStyle(AptStileSecondario())
                Spacer(minLength: 8)
                Button { chiudi() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AptTema.testo2)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AptTema.scrivania))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi la griglia delle pagine")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private var barraBassa: some View {
        HStack(spacing: 14) {
            Button {
                if let url = model.esportaPagine(Array(scelte)) { condivisione = CondivisionePagine(url: url) }
            } label: {
                Label("Esporta", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(AptStileSecondario())
            .disabled(scelte.isEmpty)
            Spacer()
            Button { chiediElimina = true } label: {
                Label("Elimina", systemImage: "trash")
                    .foregroundColor(AptTema.pericolo)
            }
            .buttonStyle(AptStileSecondario())
            .disabled(scelte.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    // MARK: Celle

    private func cella(_ i: Int, _ p: PDFPage, inizio: Int?) -> some View {
        let scelta = i == corrente
        let spuntata = scelte.contains(i)
        let id = ObjectIdentifier(p)
        return VStack(spacing: 6) {
            Group {
                if let img = immagini[id] {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Rectangle().fill(AptTema.scrivania).aspectRatio(0.75, contentMode: .fit)
                }
            }
            .overlay(Rectangle().stroke(bersaglio == i ? AptTema.accento : ((scelta || spuntata) ? AptTema.accento.opacity(spuntata ? 1 : 0.6) : AptTema.linea),
                                        lineWidth: bersaglio == i ? 3 : ((scelta || spuntata) ? 2 : 1)))
            .overlay {
                if !seleziona { MenuPaginaMiniatura(model: model, indice: i) { modelloPer = $0; mostraModello = true } }
            }
            .overlay(alignment: .topLeading) {
                if seleziona {
                    Image(systemName: spuntata ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26))
                        .foregroundStyle(spuntata ? AptTema.accento : AptTema.testo2)
                        .background(Circle().fill(AptTema.carta).padding(3))
                        .padding(6)
                }
            }
            Text(NotesModel.etichetta(i, inizio: inizio))
                .font(AptTema.dettaglio)
                .foregroundStyle(scelta ? AptTema.accentoTesto : AptTema.testo2)
        }
        .contentShape(Rectangle())
        .onAppear {
            if immagini[id] == nil {
                immagini[id] = p.thumbnail(of: CGSize(width: 300, height: 400), for: .cropBox)
            }
        }
        .onTapGesture {
            if seleziona {
                if spuntata { scelte.remove(i) } else { scelte.insert(i) }
            } else {
                model.pdfView?.go(to: p)
                chiudi()
            }
        }
        .onDrag {
            guard !seleziona else { return NSItemProvider() }
            trascinata = i
            return NSItemProvider(object: String(i) as NSString)
        }
        .onDrop(of: [UTType.plainText], delegate: RiordinoPagina(
            indice: i, trascinata: $trascinata, bersaglio: $bersaglio,
            sposta: { da, a in model.muoviPagina(da: da, a: a) }
        ))
        .accessibilityLabel("Pagina \(i + 1)")
    }

    private func esciDallaSelezione() {
        seleziona = false
        scelte = []
    }

    private func chiudi() {
        withAnimation(.easeOut(duration: 0.18)) { model.griglia = false }
    }

    private func aggiornaCorrente() {
        guard let d = model.document, let p = model.pdfView?.currentPage else { return }
        let i = d.index(for: p)
        if i != NSNotFound { corrente = i }
    }
}
