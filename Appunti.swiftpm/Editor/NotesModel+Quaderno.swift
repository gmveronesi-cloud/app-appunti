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

    /// Collega il gesto «tira oltre l'ultima pagina» alla vista PDF (da richiamare quando cambiano documento o modo di vista)
    func collegaSuperaFine() {
        guard let v = pdfView, !v.isUsingPageViewController else { return }
        let sf = superaFine ?? SuperaFine()
        superaFine = sf
        sf.orizzontale = scorrimentoOrizzontale
        sf.suggerisci = { [weak self] on in self?.suggerisciPagina = on }
        sf.scatta = { [weak self] in self?.aggiungiPaginaInFondo() }
        sf.collega(v)
    }

    /// Lo scorrimento della vista PDF stessa (non quelli delle tele Pencil, che stanno più in profondità)
    fileprivate static func scorrimentoDi(_ v: UIView) -> UIScrollView? {
        var coda = v.subviews
        while !coda.isEmpty {
            let x = coda.removeFirst()
            if let s = x as? UIScrollView, !(s is PKCanvasView) { return s }
            coda.append(contentsOf: x.subviews)
        }
        return nil
    }
}

/// Un dito che parte vicino alla fine del documento e continua a tirare oltre l'ultima pagina: al rilascio nasce una pagina nuova
final class SuperaFine: NSObject, UIGestureRecognizerDelegate {
    weak var vista: PDFView?
    var orizzontale = false
    var suggerisci: ((Bool) -> Void)?
    var scatta: (() -> Void)?
    private var gesto: UIPanGestureRecognizer?
    private var partitoInFondo = false
    private var pronto = false

    func collega(_ v: PDFView) {
        vista = v
        if gesto?.view === v { return }
        if let g = gesto { g.view?.removeGestureRecognizer(g) }
        let g = UIPanGestureRecognizer(target: self, action: #selector(tocco(_:)))
        g.delegate = self
        g.cancelsTouchesInView = false
        g.maximumNumberOfTouches = 1
        g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]    // solo il dito, mai la Pencil
        v.addGestureRecognizer(g)
        gesto = g
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// L'ultima pagina è visibile e lo scorrimento è arrivato (quasi) in fondo
    private func inFondo(tolleranza: CGFloat) -> Bool {
        guard let v = vista, !v.isUsingPageViewController, let doc = v.document, doc.pageCount > 0,
              let ultima = doc.page(at: doc.pageCount - 1), v.visiblePages.contains(ultima),
              let s = NotesModel.scorrimentoDi(v) else { return false }
        let fine: CGFloat
        let ora: CGFloat
        if orizzontale {
            fine = s.contentSize.width + s.adjustedContentInset.right - s.bounds.width
            ora = s.contentOffset.x
        } else {
            fine = s.contentSize.height + s.adjustedContentInset.bottom - s.bounds.height
            ora = s.contentOffset.y
        }
        return ora >= fine - tolleranza
    }

    @objc private func tocco(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            partitoInFondo = inFondo(tolleranza: 80)
        case .changed:
            guard partitoInFondo else { return }
            let t = g.translation(in: g.view)
            let tirata = orizzontale ? -t.x : -t.y
            let di_lato = orizzontale ? abs(t.y) : abs(t.x)
            let attivo = tirata > 60 && tirata > di_lato && inFondo(tolleranza: 2)
            if attivo != pronto {
                pronto = attivo
                suggerisci?(attivo)
            }
        case .ended:
            let scatto = pronto
            pronto = false
            partitoInFondo = false
            if scatto {
                suggerisci?(false)
                scatta?()
            }
        case .cancelled, .failed:
            if pronto { suggerisci?(false) }
            pronto = false
            partitoInFondo = false
        default:
            break
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
