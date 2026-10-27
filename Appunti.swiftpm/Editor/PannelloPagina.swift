// Barra alta dell'Editor, parte destra: «Estendi pagina» e finestra dei tre puntini
// (pagina singola o doppia, aggiungi pagina, direzione di scorrimento, vai a pagina).
import SwiftUI
import PDFKit
import PencilKit

/// Icona «Estendi pagina»: menu con i lati (nessuno, sinistra, destra, entrambi) e la dimensione (piccolo, medio, grande)
struct MenuEstendi: View {
    @ObservedObject var model: NotesModel

    private var lati: Binding<LatiEstensione> {
        Binding(
            get: { model.estensione.lati },
            set: { nuovo in
                var e = model.estensione
                e.lati = nuovo
                model.impostaEstensione(e)
            }
        )
    }

    private var misura: Binding<MisuraEstensione> {
        Binding(
            get: { model.estensione.misura },
            set: { nuova in
                var e = model.estensione
                e.misura = nuova
                model.impostaEstensione(e)
            }
        )
    }

    var body: some View {
        Menu {
            Picker("Lati", selection: lati) {
                ForEach(LatiEstensione.allCases) { Text($0.nome).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Dimensione", selection: misura) {
                ForEach(MisuraEstensione.allCases) { Text($0.nome).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            AptIcona(nome: "arrow.left.and.right.square", attiva: model.estensione.lati != .nessuno, lato: 40, corpo: 21)
        }
        .accessibilityLabel("Estendi pagina")
    }
}

/// Finestra «Vai a pagina»: usata dai tre puntini e dall'indicatore di pagina sul PDF
struct VaiAPaginaView: View {
    @ObservedObject var model: NotesModel
    @Binding var scelta: Int
    let chiudi: () -> Void
    /// Se presente, in alto compare la freccia per tornare alla schermata precedente
    var indietro: (() -> Void)?

    var body: some View {
        let totale = max(model.document?.pageCount ?? 1, 1)
        let inizio = model.indicePrima
        VStack(alignment: .leading, spacing: 10) {
            if let indietro {
                Button(action: indietro) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        Text("Vai a pagina").font(AptTema.titoloMedio)
                        Spacer()
                    }
                    .foregroundColor(AptTema.testo)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("Vai a pagina").font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
            }
            Picker("Pagina", selection: $scelta) {
                ForEach(1...totale, id: \.self) { n in Text(NotesModel.etichetta(n - 1, inizio: inizio)).tag(n) }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            Text("di \(NotesModel.etichetta(totale - 1, inizio: inizio))")
                .font(AptTema.dettaglio)
                .foregroundStyle(AptTema.testo2)
                .frame(maxWidth: .infinity)
            Button("Vai") {
                chiudi()
                model.vaiAPagina(scelta - 1)
            }
            .buttonStyle(AptStilePrimario())
            .frame(maxWidth: .infinity)
        }
    }
}

/// Capisce quando si sta scorrendo il PDF: l'indicatore compare dopo mezza pagina di scorrimento e sparisce quando si è fermi
final class RilevaScorrimento: ObservableObject {
    @Published var visibile = false
    var orizzontale = false
    var soglia: () -> CGFloat = { 300 }
    var blocca = false                      // popover aperto o indicatore agganciato: resta visibile
    private weak var scroll: UIScrollView?
    private var osservatore: NSKeyValueObservation?
    private var inizio: CGFloat = 0
    private var ultimo: CGFloat = 0
    private var inCorso = false
    private var fermo: DispatchWorkItem?
    private var nascondi: DispatchWorkItem?

    func collega(_ v: PDFView?) {
        guard scroll == nil, let v, let s = Self.trova(in: v) else { return }
        scroll = s
        ultimo = valore(s)
        osservatore = s.observe(\.contentOffset, options: [.new]) { [weak self] s, _ in self?.cambiato(s) }
    }

    /// Lo scorrimento del documento: il più vicino a PDFView (le tele Pencil, più in profondità, sono escluse)
    private static func trova(in v: UIView) -> UIScrollView? {
        var coda = v.subviews
        while !coda.isEmpty {
            let x = coda.removeFirst()
            if let s = x as? UIScrollView, !(s is PKCanvasView) { return s }
            coda.append(contentsOf: x.subviews.filter { !($0 is PKCanvasView) })
        }
        return nil
    }

    private func valore(_ s: UIScrollView) -> CGFloat { orizzontale ? s.contentOffset.x : s.contentOffset.y }

    private func cambiato(_ s: UIScrollView) {
        let v = valore(s)
        if !inCorso { inCorso = true; inizio = ultimo }
        ultimo = v
        if abs(v - inizio) > soglia() { mostra() }
        fermo?.cancel()
        let f = DispatchWorkItem { [weak self] in self?.inCorso = false }
        fermo = f
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f)
        if visibile { programmaNascondi() }
    }

    /// Dopo un salto di pagina (per esempio «Vai a pagina») o in modalità a pagina singola
    func mostraBreve() { mostra(); programmaNascondi() }

    private func mostra() {
        if !visibile { visibile = true }
        programmaNascondi()
    }

    private func programmaNascondi() {
        nascondi?.cancel()
        let n = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.blocca { self.programmaNascondi(); return }
            self.visibile = false
        }
        nascondi = n
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: n)
    }
}

/// Indicatore «5 di 60» sul PDF: piccolo e semitrasparente, in alto a destra; un tocco apre «Vai a pagina»;
/// tenendolo premuto si «aggancia» (si ingrandisce, si accende il bordo) e si può trascinare dove si vuole.
/// La posizione scelta resta ricordata.
struct IndicatorePagina: View {
    @ObservedObject var model: NotesModel
    @State private var corrente = 1
    @State private var totale = 1
    @State private var aperto = false
    @State private var scelta = 1
    @State private var base: CGSize = IndicatorePagina.letta()      // spostamento dall'angolo in alto a destra (dx ≤ 0, dy ≥ 0)
    @State private var trascina: CGSize = .zero
    @State private var agganciato = false
    @State private var misura = CGSize(width: 84, height: 32)
    @StateObject private var rileva = RilevaScorrimento()

    private static let chiave = "ed.indicatorePagina"
    private static func letta() -> CGSize {
        let v = (UserDefaults.standard.string(forKey: chiave) ?? "").split(separator: ",").compactMap { Double($0) }
        return v.count == 2 ? CGSize(width: v[0], height: v[1]) : .zero
    }

    /// Tiene la pillola dentro l'area del PDF
    private func dentro(_ o: CGSize, _ area: CGSize) -> CGSize {
        let minX = -max(area.width - misura.width - 16, 0)
        let maxY = max(area.height - misura.height - 20, 0)
        return CGSize(width: min(0, max(minX, o.width)), height: min(maxY, max(0, o.height)))
    }

    private var area: CGSize { model.pdfView?.bounds.size ?? CGSize(width: 800, height: 1000) }

    private func somma(_ a: CGSize, _ b: CGSize) -> CGSize { CGSize(width: a.width + b.width, height: a.height + b.height) }

    var body: some View {
        // Niente contenitore a tutto schermo: l'overlay è grande quanto la pillola, così non intercetta la Pencil altrove
        Group {
            if totale > 1 {
                pillola
                    .opacity(rileva.visibile || aperto || agganciato ? 1 : 0)
                    .allowsHitTesting(rileva.visibile || aperto || agganciato)
                    .animation(.easeInOut(duration: 0.25), value: rileva.visibile)
                    .offset(dentro(somma(base, trascina), area))
                    .gesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                            .onChanged { v in
                                switch v {
                                case .second(true, let drag):
                                    if !agganciato {
                                        agganciato = true
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                    trascina = drag?.translation ?? .zero
                                default: break
                                }
                            }
                            .onEnded { v in
                                if case .second(true, let drag?) = v {
                                    base = dentro(somma(base, drag.translation), area)
                                    UserDefaults.standard.set("\(Double(base.width)),\(Double(base.height))", forKey: Self.chiave)
                                }
                                trascina = .zero
                                agganciato = false
                            }
                    )
                    .onTapGesture {
                        scelta = corrente
                        aperto = true
                    }
            }
        }
        .onAppear { aggiorna(); preparaRilevamento() }
        .onChange(of: aperto) { _, _ in rileva.blocca = aperto || agganciato }
        .onChange(of: agganciato) { _, _ in rileva.blocca = aperto || agganciato }
        .onChange(of: model.scorrimentoOrizzontale) { _, _ in rileva.orizzontale = model.scorrimentoOrizzontale }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { n in
            if let v = n.object as? PDFView, v === model.pdfView {
                aggiorna()
                preparaRilevamento()
                if !rileva.visibile { rileva.mostraBreve() }
            }
        }
        .onChange(of: model.versionePagine) { _, _ in aggiorna() }
        .onChange(of: model.document) { _, _ in aggiorna() }
    }

    /// Numero mostrato come nelle miniature: dalla pagina «uno» scelta in poi 1, 2, 3…, prima in numeri romani
    private var testoNumero: String {
        let inizio = model.indicePrima
        return "\(NotesModel.etichetta(corrente - 1, inizio: inizio)) di \(NotesModel.etichetta(max(totale - 1, 0), inizio: inizio))"
    }

    private var pillola: some View {
        Text(testoNumero)
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .foregroundColor(AptTema.testo)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(AptTema.carta.opacity(agganciato ? 0.95 : 0.7)))
            .overlay(Capsule().stroke(agganciato ? AptTema.accento : AptTema.linea.opacity(0.8), lineWidth: agganciato ? 2 : 0.5))
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { misura = g.size }
                    .onChange(of: g.size) { _, n in misura = n }
            })
            .opacity(agganciato ? 1 : 0.8)
            .scaleEffect(agganciato ? 1.18 : 1)
            .shadow(color: .black.opacity(agganciato ? 0.28 : 0), radius: agganciato ? 9 : 0, y: agganciato ? 4 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: agganciato)
            .padding(.top, 10)
            .padding(.trailing, 8)
            .popover(isPresented: $aperto) {
                VaiAPaginaView(model: model, scelta: $scelta, chiudi: { aperto = false })
                    .padding(20)
                    .frame(width: 280)
                    .aptPannello()
            }
            .accessibilityLabel("Pagina \(testoNumero). Tocca per andare a una pagina, tieni premuto per spostare")
    }

    private func preparaRilevamento() {
        rileva.orizzontale = model.scorrimentoOrizzontale
        rileva.soglia = { [weak model] in
            guard let v = model?.pdfView, let p = v.currentPage else { return 300 }
            let b = p.bounds(for: .cropBox)
            let lato = (model?.scorrimentoOrizzontale ?? false) ? b.width : b.height
            return max(lato * v.scaleFactor * 0.5, 80)
        }
        rileva.collega(model.pdfView)
    }

    private func aggiorna() {
        let t = model.document?.pageCount ?? 1
        let c = model.paginaCorrente + 1
        if t != totale { totale = t }
        if c != corrente { corrente = c }
    }
}

/// Finestra dei tre puntini
struct PannelloPagina: View {
    @ObservedObject var model: NotesModel
    let chiudi: () -> Void

    private enum Schermata { case principale, aggiungi, vai }
    @State private var schermata = Schermata.principale
    @State private var paginaScelta = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch schermata {
            case .principale: principale
            case .aggiungi: aggiungi
            case .vai: vai
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: Schermate

    private var principale: some View {
        VStack(alignment: .leading, spacing: 14) {
            etichettato("Pagine") {
                Picker("Pagine", selection: $model.paginaDoppia) {
                    Text("Singola").tag(false)
                    Text("Doppia").tag(true)
                }
                .pickerStyle(.segmented)
            }
            AptLinea()
            voce("doc.badge.plus", "Aggiungi pagina", freccia: true) { schermata = .aggiungi }
            voce("paintbrush", "Modello e colore pagina", freccia: true, attiva: model.eDiScrittura(model.paginaCorrente)) {
                guard model.eDiScrittura(model.paginaCorrente) else { return }
                let i = model.paginaCorrente
                chiudi()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.modelliRichiesti = RichiestaModelli(modo: .modifica(i)) }
            }
            if model.quaderno != nil {
                Toggle("Pagine unite", isOn: Binding(get: { model.quaderno?.unite ?? false }, set: { model.impostaUnite($0) }))
                    .font(AptTema.corpo)
                    .foregroundColor(AptTema.testo)
                    .frame(minHeight: 36)
            }
            AptLinea()
            etichettato("Direzione di scorrimento") {
                VStack(spacing: 10) {
                    Picker("Direzione", selection: $model.scorrimentoOrizzontale) {
                        Text("Orizzontale").tag(true)
                        Text("Verticale").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Picker("Scorrimento", selection: $model.scorrimentoContinuo) {
                        Text("Continuo").tag(true)
                        Text("Singolo").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            AptLinea()
            voce("arrow.right.to.line", "Vai a pagina…", freccia: true) {
                paginaScelta = model.paginaCorrente + 1
                schermata = .vai
            }
            if let p = model.document?.page(at: model.paginaCorrente), let o = model.originali[p], o.minX - p.bounds(for: .cropBox).minX > 1,
               !(model.immagini[p] ?? []).isEmpty {
                voce("arrow.right.square", "Sposta le foto di questa pagina a destra") {
                    chiudi()
                    model.spostaFoto(di: p, versoDestra: true)
                }
                voce("arrow.left.square", "Sposta le foto di questa pagina a sinistra") {
                    chiudi()
                    model.spostaFoto(di: p, versoDestra: false)
                }
            }
            voce("arrow.triangle.2.circlepath", "Ridisegna le pagine") {
                chiudi()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.riparaVista(forza: true) }
            }
        }
    }

    private var aggiungi: some View {
        VStack(alignment: .leading, spacing: 14) {
            intestazione("Aggiungi pagina")
            Text("Va dopo la pagina \(model.paginaCorrente + 1)")
                .font(AptTema.dettaglio)
                .foregroundStyle(AptTema.testo2)
            voce("doc", "Pagina di appunti…") {
                let i = model.paginaCorrente
                chiudi()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.modelliRichiesti = RichiestaModelli(modo: .inserisci(dopo: i)) }
            }
            voce("doc.on.doc", "File (PDF)…") {
                let i = model.paginaCorrente
                chiudi()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.inserisciDopo = i; model.origine = .aggiungiPDF }
            }
            voce("photo.on.rectangle", "Immagini…") {
                let i = model.paginaCorrente
                chiudi()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.inserisciDopo = i; model.origine = .immaginiPagine }
            }
        }
    }

    private var vai: some View {
        VaiAPaginaView(model: model, scelta: $paginaScelta, chiudi: chiudi, indietro: { schermata = .principale })
    }

    // MARK: Pezzi

    private func intestazione(_ titolo: String) -> some View {
        Button { schermata = .principale } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                Text(titolo).font(AptTema.titoloMedio)
                Spacer()
            }
            .foregroundColor(AptTema.testo)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func voce(_ icona: String, _ titolo: String, freccia: Bool = false, attiva: Bool = true,
                      azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            HStack(spacing: 12) {
                Image(systemName: icona).frame(width: 24)
                Text(titolo)
                Spacer()
                if freccia {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
            }
            .font(AptTema.corpo)
            .foregroundColor(attiva ? AptTema.testo : AptTema.testo2.opacity(0.5))
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!attiva)
    }

    private func etichettato<C: View>(_ titolo: String, @ViewBuilder _ contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titolo).font(AptTema.dettaglio).foregroundStyle(AptTema.testo2)
            contenuto()
        }
    }
}
