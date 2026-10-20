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
    /// Formato scelto alla nascita del quaderno: le pagine aggiunte in automatico lo seguono. Nil nei quaderni vecchi (si usa la prima pagina).
    var formato: FormatoPagina?

    init(modello: ModelloPagina = .bianca, unite: Bool = false, formato: FormatoPagina? = nil) {
        self.modello = modello
        self.unite = unite
        self.formato = formato
    }

    /// Testo salvato nel PDF: il modello, poi «#» e 1 se le pagine sono unite, poi «#» e il formato
    var codice: String { modello.codice + "#" + (unite ? "1" : "0") + (formato.map { "#" + $0.rawValue } ?? "") }

    init?(codice: String) {
        let parti = codice.components(separatedBy: "#")
        guard parti.count == 2 || parti.count == 3, let m = ModelloPagina(codice: parti[0]) else { return nil }
        self.modello = m
        self.unite = parti[1] == "1"
        self.formato = parti.count == 3 ? FormatoPagina(rawValue: parti[2]) : nil
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

    /// Una pagina con lo sfondo scelto. Senza `formato` ha la misura di quella dopo cui va messa;
    /// con `formato` (scelto a mano, o quello del quaderno) ha la misura di quel formato, anche diversa dalle vicine.
    func aggiungiPagina(_ modello: ModelloPagina, dopo indice: Int, formato: FormatoPagina? = nil) {
        guard let document, document.pageCount > 0 else { message = "Nessun PDF aperto."; return }
        let i = min(max(indice, 0), document.pageCount - 1)
        let riferimento = document.page(at: i)
        let box: CGRect
        if let formato {
            box = CGRect(origin: .zero, size: formato.misura)
        } else {
            box = riferimento?.bounds(for: .cropBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        }
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
        if formato == nil, let r = riferimento, let o = originali[r] { originali[nuova] = o }
        document.insert(nuova, at: i + 1)
        let dati = [DatiPagina(pagina: nuova, tratti: nil, immagini: [], testi: [])]
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        pdfView?.go(to: nuova)
        avviso("Aggiunta una pagina.")
        undoGenerale.registerUndo(withTarget: self) { s in s.togliPagine(dati) }
    }

    /// Il formato scelto alla nascita del quaderno (nei quaderni vecchi: quello della prima pagina)
    var formatoDelQuaderno: FormatoPagina? {
        guard let q = quaderno else { return nil }
        if let f = q.formato { return f }
        guard let p = document?.page(at: 0) else { return nil }
        return FormatoPagina.simile(a: NotesModel.misuraVista(p))
    }

    /// Dopo l'ultima pagina, in automatico: stesso modello e stesso formato (orientamento) del quaderno
    func aggiungiPaginaInFondo() {
        guard let document, document.pageCount > 0 else { return }
        let ultima = document.pageCount - 1
        aggiungiPagina(modelloProposto(perPagina: ultima), dopo: ultima, formato: formatoDelQuaderno)
    }

    // MARK: Nuova pagina scorrendo oltre l'ultima

    /// Collega il gesto «tira oltre l'ultima pagina» alla vista PDF (da richiamare quando cambiano documento o modo di vista)
    func collegaSuperaFine() {
        guard let v = pdfView, !v.isUsingPageViewController else { return }
        let sf = superaFine ?? SuperaFine()
        superaFine = sf
        sf.orizzontale = scorrimentoOrizzontale
        sf.avanzamento = avanzamentoPagina
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

/// Avanzamento del gesto «nuova pagina in fondo»: quanto si è tirato e se è pronta
final class AvanzamentoPagina: ObservableObject {
    @Published var tirata: CGFloat = 0     // 0...1: quanto si è tirato oltre l'ultima pagina
    @Published var pronta = false          // tirato abbastanza: rilasciando nasce la pagina
    @Published var visibile = false

    func azzera() {
        if visibile { visibile = false }
        if pronta { pronta = false }
        if tirata != 0 { tirata = 0 }
    }
}

/// Nuova pagina scorrendo oltre l'ultima, ma con calma: bisogna tirare molto (nessuna attesa dopo).
/// Appena il cerchio è pieno, rilasciando nasce la pagina; tornando indietro o rilasciando prima non succede niente.
/// (Così non nasce per sbaglio mentre si scorrono in fretta le pagine.)
final class SuperaFine: NSObject, UIGestureRecognizerDelegate {
    weak var vista: PDFView?
    var orizzontale = false
    var avanzamento: AvanzamentoPagina?
    var scatta: (() -> Void)?
    private var gesto: UIPanGestureRecognizer?
    private var partitoInFondo = false
    private let deciso = UIImpactFeedbackGenerator(style: .medium)

    private let tiro: CGFloat = 190             // quanto bisogna tirare (punti di movimento del dito)
    private let zonaMorta: CGFloat = 24         // i primi punti non contano

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

    private func ferma() {
        avanzamento?.azzera()
    }

    @objc private func tocco(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            partitoInFondo = inFondo(tolleranza: 40)
            deciso.prepare()
        case .changed:
            guard partitoInFondo, let av = avanzamento else { return }
            let t = g.translation(in: g.view)
            let tirata = orizzontale ? -t.x : -t.y
            let di_lato = orizzontale ? abs(t.y) : abs(t.x)
            guard tirata > zonaMorta, tirata > di_lato, inFondo(tolleranza: 4) else {
                if av.visibile { ferma() }          // tornato indietro o fuori strada: niente pagina
                return
            }
            let rapporto = min(1, (tirata - zonaMorta) / (tiro - zonaMorta))
            if !av.visibile { av.visibile = true }
            if abs(av.tirata - rapporto) > 0.01 { av.tirata = rapporto }
            if rapporto >= 1 {
                if !av.pronta {
                    av.pronta = true                   // pronta subito: nessuna attesa col dito fermo
                    deciso.impactOccurred()
                }
            } else if av.pronta && rapporto >= 0.6 {
                break                                  // già pronta: un piccolo ritorno non la annulla
            } else if av.pronta {
                av.pronta = false
            }
        case .ended:
            let fatta = avanzamento?.pronta == true
            ferma()
            partitoInFondo = false
            if fatta { scatta?() }
        case .cancelled, .failed:
            ferma()
            partitoInFondo = false
        default:
            break
        }
    }
}

/// Mentre si tira oltre l'ultima pagina: un foglio che sale dal bordo e un cerchio che si riempie (tirando);
/// quando è pieno: «Rilascia per aggiungere la pagina». Tornando indietro non succede niente.
struct SuggerimentoPagina: View {
    @ObservedObject var model: NotesModel

    var body: some View {
        SuggerimentoContenuto(avanzamento: model.avanzamentoPagina, orizzontale: model.scorrimentoOrizzontale)
            .allowsHitTesting(false)
    }
}

private struct SuggerimentoContenuto: View {
    @ObservedObject var avanzamento: AvanzamentoPagina
    let orizzontale: Bool

    private var progresso: CGFloat { avanzamento.tirata }

    private var frase: String {
        if avanzamento.pronta { return "Rilascia per aggiungere la pagina" }
        return "Continua a tirare per aggiungere una pagina"
    }

    private var cerchio: some View {
        ZStack {
            Circle().stroke(AptTema.linea, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(progresso, 0.001))
                .stroke(avanzamento.pronta ? AptTema.accento : AptTema.accentoScuro,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: avanzamento.pronta ? "checkmark" : "doc.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AptTema.accentoScuro)
        }
        .frame(width: 54, height: 54)
        .scaleEffect(avanzamento.pronta ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: avanzamento.pronta)
    }

    private var testo: some View {
        VStack(spacing: 2) {
            Text(frase)
                .font(AptTema.corpoForte)
                .foregroundColor(AptTema.accentoScuro)
            if avanzamento.pronta {
                Text("Per non farlo, trascina il dito indietro")
                    .font(AptTema.dettaglio)
                    .foregroundColor(AptTema.testo2)
            }
        }
    }

    var body: some View {
        ZStack {
            Color.clear
            if avanzamento.visibile {
                if orizzontale {
                    HStack(spacing: 12) {
                        cerchio
                        testo
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(AptTema.accentoTenue))
                    .overlay(Capsule().stroke(AptTema.linea, lineWidth: 1))
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.opacity)
                } else {
                    // Un foglio che sale dal bordo in basso man mano che si tira
                    VStack(spacing: 10) {
                        cerchio
                        testo
                    }
                    .padding(.top, 22)
                    .frame(width: 300, height: 190, alignment: .top)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AptTema.carta)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AptTema.accento, style: StrokeStyle(lineWidth: 2.5, dash: avanzamento.pronta ? [] : [9, 6]))
                    )
                    .shadow(color: .black.opacity(0.18), radius: 10, y: -2)
                    .offset(y: (1 - avanzamento.tirata) * 170 + 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: avanzamento.visibile)
        .animation(.easeOut(duration: 0.1), value: avanzamento.tirata)
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
            // a mano si può scegliere anche un orientamento diverso da quello delle altre pagine
            PaginaModelli(
                modo: .inserisci,
                formatoIniziale: model.formatoDelQuaderno ?? formatoDi(dopo),
                scegli: { m, f, _ in
                    // nei PDF normali, se il formato non è cambiato la pagina resta della misura esatta delle vicine
                    let invariato = model.quaderno == nil && f == formatoDi(dopo)
                    model.aggiungiPagina(m, dopo: dopo, formato: invariato ? nil : f)
                },
                chiudi: { model.modelliRichiesti = nil }
            )
        }
    }
}
