// Quaderni di sola scrittura: PDF creati dall'app fatti solo di fogli bianchi (colore e modello a scelta),
// pagine bianche inserite nei PDF, pagine unite («papiro»).
import SwiftUI
import PDFKit

/// Un quaderno: il colore e il modello proposti per le pagine nuove, e se le pagine stanno unite o distinte
struct Quaderno: Equatable {
    var modello = ModelloPagina.bianca
    var unite = false

    init(modello: ModelloPagina = .bianca, unite: Bool = false) {
        self.modello = modello
        self.unite = unite
    }

    /// Testo salvato nel PDF, per esempio «crema|righe|0»
    var codice: String { modello.codice + "|" + (unite ? "1" : "0") }

    init?(codice: String) {
        let parti = codice.split(separator: "|").map(String.init)
        guard parti.count == 3, let m = ModelloPagina(codice: parti[0] + "|" + parti[1]) else { return nil }
        self.modello = m
        self.unite = parti[2] == "1"
    }

    /// Il PDF di un quaderno nuovo: `pagine` fogli A4 (verticali od orizzontali) con lo sfondo scelto, ciascuno segnato come foglio di sola scrittura
    static func creaPDF(_ q: Quaderno, pagine: Int, orizzontale: Bool) -> Data? {
        let misura = orizzontale ? CGSize(width: 841.8, height: 595.2) : CGSize(width: 595.2, height: 841.8)
        let box = CGRect(origin: .zero, size: misura)
        let doc = PDFDocument()
        for n in 0..<max(pagine, 1) {
            guard let p = ModelloPagina.creaPagina(q.modello, box: box) else { return nil }
            p.addAnnotation(NotesModel.annotazioneNascosta(nome: NotesModel.nomeModello, chiave: NotesModel.chiaveModello,
                                                          valore: q.modello.codice, box: box))
            if n == 0 {
                p.addAnnotation(NotesModel.annotazioneNascosta(nome: NotesModel.nomeQuaderno, chiave: NotesModel.chiaveQuaderno,
                                                              valore: q.codice, box: box))
            }
            doc.insert(p, at: doc.pageCount)
        }
        return doc.dataRepresentation()
    }
}

/// Dove mettere le pagine bianche nuove
enum PosizionePagine: String, CaseIterable, Identifiable {
    case dopo, inizio, fine
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .dopo: return "Dopo questa"
        case .inizio: return "All'inizio"
        case .fine: return "In fondo"
        }
    }
}

extension NotesModel {
    static let nomeQuaderno = "AptQuaderno"                         // annotazione nascosta sulla prima pagina: il documento è un quaderno
    static let chiaveQuaderno = PDFAnnotationKey(rawValue: "/AptQuaderno")

    // MARK: Ultima scelta (si ricorda tra una sessione e l'altra)

    static var ultimoModello: ModelloPagina {
        d.string(forKey: "qd.ultimoModello").flatMap { ModelloPagina(codice: $0) } ?? .bianca
    }

    static func ricordaModello(_ m: ModelloPagina) { d.set(m.codice, forKey: "qd.ultimoModello") }

    /// Sfondo proposto per le pagine bianche nuove: quello del quaderno, o della pagina che si vede se è un foglio bianco, o l'ultimo scelto
    var modelloProposto: ModelloPagina {
        if let q = quaderno { return q.modello }
        return modello(della: paginaCorrente) ?? Self.ultimoModello
    }

    // MARK: Pagine unite («papiro»)

    func impostaUnite(_ unite: Bool) {
        guard var q = quaderno, q.unite != unite else { return }
        q.unite = unite
        quaderno = q
        modificato = true
        applicaVista()
    }

    // MARK: Pagine bianche nei documenti (annullabile)

    /// Aggiunge una o più pagine bianche con lo sfondo scelto, della misura della pagina vicina; un solo «Annulla» le toglie tutte
    func aggiungiPagineBianche(_ modello: ModelloPagina, quante: Int, posizione: PosizionePagine) {
        guard let document, document.pageCount > 0 else { message = "Nessun PDF aperto."; return }
        let n = min(max(quante, 1), 50)
        let corrente = min(paginaCorrente, document.pageCount - 1)
        let indiceRiferimento: Int
        let inizio: Int
        switch posizione {
        case .dopo: indiceRiferimento = corrente; inizio = corrente + 1
        case .inizio: indiceRiferimento = 0; inizio = 0
        case .fine: indiceRiferimento = document.pageCount - 1; inizio = document.pageCount
        }
        let riferimento = document.page(at: indiceRiferimento)
        let box = riferimento?.bounds(for: .cropBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        lazo?.deseleziona()
        controlloImmagini?.annullaSelezione()
        controlloTesto?.resetta()
        var dati: [DatiPagina] = []
        for k in 0..<n {
            let nuova: PDFPage
            if let generata = ModelloPagina.creaPagina(modello, box: box) {
                nuova = generata
            } else {
                nuova = PDFPage()
                nuova.setBounds(box, for: .mediaBox)
                nuova.setBounds(box, for: .cropBox)
            }
            modelli[nuova] = modello
            if let r = riferimento, let o = originali[r] { originali[nuova] = o }
            document.insert(nuova, at: min(inizio + k, document.pageCount))
            dati.append(DatiPagina(pagina: nuova, tratti: nil, immagini: [], testi: []))
        }
        Self.ricordaModello(modello)
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        if let p = dati.first?.pagina { pdfView?.go(to: p) }
        avviso(n == 1 ? "Aggiunta una pagina bianca." : "Aggiunte \(n) pagine bianche.")
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
    }
}

// MARK: - Pannello «Pagina bianca» (dentro la finestra dei tre puntini)

/// Scelta di sfondo, quantità e posizione delle pagine bianche da inserire
struct NuovePagineBianche: View {
    @ObservedObject var model: NotesModel
    let chiudi: () -> Void
    @State private var scelto = ModelloPagina.bianca
    @State private var quante = 1
    @State private var posizione = PosizionePagine.dopo

    private var orizzontale: Bool {
        guard let p = model.document?.page(at: model.paginaCorrente) else { return false }
        let s = NotesModel.misuraVista(p)
        return s.width > s.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SelettoreModello(scelto: $scelto, orizzontale: orizzontale)
            AptLinea()
            Picker("Posizione", selection: $posizione) {
                ForEach(PosizionePagine.allCases) { Text($0.nome).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper(value: $quante, in: 1...50) {
                Text(quante == 1 ? "1 pagina" : "\(quante) pagine")
                    .font(AptTema.corpo)
                    .foregroundColor(AptTema.testo)
            }
            Button("Aggiungi") {
                chiudi()
                model.aggiungiPagineBianche(scelto, quante: quante, posizione: posizione)
            }
            .buttonStyle(AptStilePrimario())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear { scelto = model.modelloProposto }
    }
}
