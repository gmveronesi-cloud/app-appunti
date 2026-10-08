// Griglia di tutte le pagine: si apre pizzicando oltre lo zoom minimo.
// Un tocco su una pagina la apre; tenendo premuto e trascinando si riordinano; allargando le dita (o la «×») si chiude.
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

    private var numero: Int { model.document?.pageCount ?? 0 }

    var body: some View {
        let _ = model.versionePagine
        let inizio = model.indicePrima
        ZStack(alignment: .topTrailing) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 190), spacing: 16)], spacing: 18) {
                    ForEach(0..<numero, id: \.self) { i in
                        if let p = model.document?.page(at: i) { cella(i, p, inizio: inizio) }
                    }
                }
                .padding(20)
            }
            Button { chiudi() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AptTema.testo2)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AptTema.scrivania))
            }
            .padding(12)
            .accessibilityLabel("Chiudi la griglia delle pagine")
        }
        .background(AptTema.carta)
        .sheet(isPresented: $mostraModello) {
            SceltaModelloPagina(model: model, indice: modelloPer) { mostraModello = false }
                .presentationDetents([.height(380)])
        }
        .onAppear { aggiornaCorrente() }
        .gesture(
            MagnifyGesture().onEnded { v in if v.magnification > 1.25 { chiudi() } }
        )
    }

    private func cella(_ i: Int, _ p: PDFPage, inizio: Int?) -> some View {
        let scelta = i == corrente
        let id = ObjectIdentifier(p)
        return VStack(spacing: 6) {
            Group {
                if let img = immagini[id] {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Rectangle().fill(AptTema.scrivania).aspectRatio(0.75, contentMode: .fit)
                }
            }
            .overlay(Rectangle().stroke(bersaglio == i ? AptTema.accento : (scelta ? AptTema.accento.opacity(0.6) : AptTema.linea),
                                        lineWidth: bersaglio == i ? 3 : (scelta ? 2 : 1)))
            .overlay { MenuPaginaMiniatura(model: model, indice: i) { modelloPer = $0; mostraModello = true } }
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
            model.pdfView?.go(to: p)
            chiudi()
        }
        .onDrag {
            trascinata = i
            return NSItemProvider(object: String(i) as NSString)
        }
        .onDrop(of: [UTType.plainText], delegate: RiordinoPagina(
            indice: i, trascinata: $trascinata, bersaglio: $bersaglio,
            sposta: { da, a in model.muoviPagina(da: da, a: a) }
        ))
        .accessibilityLabel("Pagina \(i + 1)")
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
