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
    @State private var cache = CacheMiniature()
    @State private var chiusaDaPizzico = false
    @State private var seleziona = false
    @State private var scelte = Set<Int>()
    @State private var condivisione: CondivisionePagine?
    @State private var chiediElimina = false
    @State private var inVista = Set<ObjectIdentifier>()

    private var numero: Int { model.document?.pageCount ?? 0 }

    var body: some View {
        let _ = model.versionePagine
        let inizio = model.indicePrima
        VStack(spacing: 0) {
            barraAlta
            AptLinea()
            ScrollViewReader { lettore in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 190), spacing: 16)], spacing: 18) {
                        ForEach(0..<numero, id: \.self) { i in
                            if let p = model.document?.page(at: i) { cella(i, p, inizio: inizio).id(i) }
                        }
                    }
                    .padding(20)
                }
                // Si parte dalla pagina su cui si stava lavorando
                .onAppear {
                    aggiornaCorrente()
                    DispatchQueue.main.async { lettore.scrollTo(corrente, anchor: .center) }
                }
            }
            if seleziona {
                AptLinea()
                barraBassa
            }
        }
        .background(AptTema.carta)
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
        // Allargando le dita la griglia si chiude e si torna all'ultima pagina su cui si è scritto
        .simultaneousGesture(
            MagnifyGesture().onChanged { v in
                if v.magnification > 1.2 && !seleziona && !chiusaDaPizzico {
                    chiusaDaPizzico = true
                    tornaAllUltimaPagina()
                }
            }
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
                if !seleziona { MenuPaginaMiniatura(model: model, indice: i) }
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
            inVista.insert(id)
            if immagini[id] == nil {
                if let fatta = cache.immagine(p) {
                    immagini[id] = fatta
                } else {
                    // Fuori dal thread principale: la griglia compare subito e le miniature si riempiono man mano
                    let cacheLocale = cache
                    model.miniaturaInSottofondo(p, larghezza: 260) { nuova in
                        cacheLocale.salva(nuova, p)
                        if inVista.contains(id) { immagini[id] = nuova }
                    }
                }
            }
        }
        .onDisappear {
            inVista.remove(id)
            immagini[id] = nil       // fuori vista non restano in memoria
        }
        .onTapGesture {
            if seleziona {
                if spuntata { scelte.remove(i) } else { scelte.insert(i) }
            } else {
                model.vaiAPaginaDallaGriglia(p)
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

    /// Il pizzico verso l'esterno: si torna alla pagina su cui si stava scrivendo (se non si è scritto niente, dov'eravamo)
    private func tornaAllUltimaPagina() {
        if let p = model.ultimaPaginaModificata, let d = model.document, d.index(for: p) != NSNotFound {
            model.vaiAPaginaDallaGriglia(p)
        }
        chiudi()
    }

    /// La pagina evidenziata: l'ultima su cui si è scritto, altrimenti quella che si vedeva
    private func aggiornaCorrente() {
        guard let d = model.document else { return }
        let p = model.ultimaPaginaModificata.flatMap { d.index(for: $0) != NSNotFound ? $0 : nil } ?? model.pdfView?.currentPage
        guard let p else { return }
        let i = d.index(for: p)
        if i != NSNotFound { corrente = i }
    }
}
