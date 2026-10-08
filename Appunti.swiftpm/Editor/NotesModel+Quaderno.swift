// Quaderni di sola scrittura: PDF creati dall'app fatti solo di fogli bianchi (modello a scelta, formato verticale,
// orizzontale o gigante), pagine nuove con il modello del quaderno, pagine unite («papiro»),
// nuova pagina scorrendo oltre l'ultima.
import SwiftUI
import PDFKit
import PencilKit

/// Un quaderno: il modello proposto per le pagine nuove, e se le pagine stanno unite o distinte
struct Quaderno: Equatable {
    var modello = ModelloPagina.bianca
    var unite = false

    init(modello: ModelloPagina = .bianca, unite: Bool = false) {
        self.modello = modello
        self.unite = unite
    }

    /// Testo salvato nel PDF: il modello, poi «#» e 1 se le pagine sono unite
    var codice: String { modello.codice + "#" + (unite ? "1" : "0") }

    init?(codice: String) {
        let parti = codice.components(separatedBy: "#")
        guard parti.count == 2, let m = ModelloPagina(codice: parti[0]) else { return nil }
        self.modello = m
        self.unite = parti[1] == "1"
    }

    /// Il PDF di un quaderno nuovo: una pagina del formato scelto, con lo sfondo scelto, segnata come foglio di sola scrittura
    static func creaPDF(_ q: Quaderno, formato: FormatoPagina) -> Data? {
        let box = CGRect(origin: .zero, size: formato.misura)
        guard let p = ModelloPagina.creaPagina(q.modello, box: box) else { return nil }
        p.addAnnotation(NotesModel.annotazioneNascosta(nome: NotesModel.nomeModello, chiave: NotesModel.chiaveModello,
                                                      valore: q.modello.codice, box: box))
        p.addAnnotation(NotesModel.annotazioneNascosta(nome: NotesModel.nomeQuaderno, chiave: NotesModel.chiaveQuaderno,
                                                      valore: q.codice, box: box))
        let doc = PDFDocument()
        doc.insert(p, at: 0)
        return doc.dataRepresentation()
    }
}

extension NotesModel {
    static let nomeQuaderno = "AptQuaderno"                         // annotazione nascosta sulla prima pagina: il documento è un quaderno
    static let chiaveQuaderno = PDFAnnotationKey(rawValue: "/AptQuaderno")

    /// Sfondo proposto per una pagina nuova: quello del quaderno; altrimenti quello della pagina vicina se è un foglio bianco; altrimenti l'ultimo usato
    func modelloProposto(perPagina i: Int) -> ModelloPagina {
        if let q = quaderno { return q.modello }
        if let m = modello(della: i) { return m }
        return ModelliArchivio.recenti().first { $0.tipo != .personale } ?? .bianca
    }

    // MARK: Pagine unite («papiro»)

    func impostaUnite(_ unite: Bool) {
        guard var q = quaderno, q.unite != unite else { return }
        q.unite = unite
        quaderno = q
        modificato = true
        applicaVista()
    }

    // MARK: Pagina bianca nuova (annullabile)

    /// Una pagina con lo sfondo scelto, della misura di quella dopo cui va messa
    func aggiungiPagina(_ modello: ModelloPagina, dopo indice: Int) {
        guard let document, document.pageCount > 0 else { message = "Nessun PDF aperto."; return }
        let i = min(max(indice, 0), document.pageCount - 1)
        let riferimento = document.page(at: i)
        let box = riferimento?.bounds(for: .cropBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        lazo?.deseleziona()
        controlloImmagini?.annullaSelezione()
        controlloTesto?.resetta()
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
        document.insert(nuova, at: i + 1)
        let dati = [DatiPagina(pagina: nuova, tratti: nil, immagini: [], testi: [])]
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        pdfView?.go(to: nuova)
        avviso("Aggiunta una pagina.")
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
    }

    /// Dopo l'ultima pagina, con il modello del quaderno
    func aggiungiPaginaInFondo() {
        guard let document, document.pageCount > 0 else { return }
        let ultima = document.pageCount - 1
        aggiungiPagina(modelloProposto(perPagina: ultima), dopo: ultima)
    }

    // MARK: Nuova pagina scorrendo oltre l'ultima

    /// Collega l'osservazione dello scorrimento della vista PDF (da richiamare quando cambiano documento o modo di vista)
    func collegaSuperaFine() {
        guard let v = pdfView, !v.isUsingPageViewController else { return }
        let sf = superaFine ?? SuperaFine()
        superaFine = sf
        sf.orizzontale = scorrimentoOrizzontale
        sf.suggerisci = { [weak self] on in self?.suggerisciPagina = on }
        sf.scatta = { [weak self] in self?.aggiungiPaginaInFondo() }
        if let s = Self.scorrimentoDi(v) { sf.collega(s) }
    }

    /// Lo scorrimento della vista PDF stessa (non quelli delle tele Pencil, che stanno più in profondità)
    private static func scorrimentoDi(_ v: UIView) -> UIScrollView? {
        var coda = v.subviews
        while !coda.isEmpty {
            let x = coda.removeFirst()
            if let s = x as? UIScrollView, !(s is PKCanvasView) { return s }
            coda.append(contentsOf: x.subviews)
        }
        return nil
    }
}

/// Osserva lo scorrimento: se si tira oltre la fine del documento e si rilascia, scatta
final class SuperaFine: NSObject {
    weak var scroll: UIScrollView?
    var orizzontale = false
    var suggerisci: ((Bool) -> Void)?
    var scatta: (() -> Void)?
    private var osservazione: NSKeyValueObservation?
    private var pronto = false

    func collega(_ s: UIScrollView) {
        guard scroll !== s else { return }
        scroll = s
        osservazione = s.observe(\.contentOffset, options: [.new]) { [weak self] s, _ in self?.valuta(s) }
    }

    private func valuta(_ s: UIScrollView) {
        let oltre: CGFloat
        if orizzontale {
            oltre = s.contentOffset.x - max(s.contentSize.width + s.adjustedContentInset.right - s.bounds.width, 0)
        } else {
            oltre = s.contentOffset.y - max(s.contentSize.height + s.adjustedContentInset.bottom - s.bounds.height, 0)
        }
        if s.isDragging {
            let attivo = oltre > 70
            if attivo != pronto {
                pronto = attivo
                suggerisci?(attivo)
            }
        } else if pronto {
            pronto = false
            suggerisci?(false)
            scatta?()
        }
    }
}

/// «Rilascia per aggiungere una pagina»: compare mentre si tira oltre l'ultima pagina
struct SuggerimentoPagina: View {
    @ObservedObject var model: NotesModel

    var body: some View {
        ZStack {
            Color.clear
            if model.suggerisciPagina {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                    Text("Rilascia per aggiungere una pagina")
                }
                .font(AptTema.corpoForte)
                .foregroundColor(AptTema.accentoScuro)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(AptTema.accentoTenue))
                .overlay(Capsule().stroke(AptTema.linea, lineWidth: 1))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.scorrimentoOrizzontale ? .trailing : .bottom)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pagina Modelli dentro l'Editor

/// Presenta la pagina Modelli a tutto schermo quando il modello lo richiede (cambio sfondo, pagina bianca)
struct PresentaModelli: ViewModifier {
    @ObservedObject var model: NotesModel

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $model.modelliRichiesti) { r in copertina(r) }
    }

    private func formatoDi(_ i: Int) -> FormatoPagina {
        guard let p = model.document?.page(at: i) else { return .verticale }
        return FormatoPagina.simile(a: NotesModel.misuraVista(p))
    }

    @ViewBuilder
    private func copertina(_ r: RichiestaModelli) -> some View {
        switch r.modo {
        case .modifica(let i):
            PaginaModelli(
                modo: .modifica,
                formatoFisso: formatoDi(i),
                modelloIniziale: model.modello(della: i),
                possibileATutte: model.numeroPagineDiScrittura > 1,
                nomeATutte: model.quaderno != nil ? "Applica a tutte le pagine del quaderno" : "Applica a tutti i fogli bianchi",
                scegli: { m, _, tutte in
                    if tutte { model.applicaModelloATutte(m) } else { model.applicaModello(m, allaPagina: i) }
                },
                chiudi: { model.modelliRichiesti = nil }
            )
        case .inserisci(let dopo):
            PaginaModelli(
                modo: .inserisci,
                formatoFisso: formatoDi(dopo),
                scegli: { m, _, _ in model.aggiungiPagina(m, dopo: dopo) },
                chiudi: { model.modelliRichiesti = nil }
            )
        }
    }
}
