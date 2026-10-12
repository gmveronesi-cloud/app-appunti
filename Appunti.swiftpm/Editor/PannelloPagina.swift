// Barra alta dell'Editor, parte destra: «Estendi pagina» e finestra dei tre puntini
// (pagina singola o doppia, aggiungi pagina, direzione di scorrimento, vai a pagina).
import SwiftUI
import PDFKit

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
                ForEach(1...totale, id: \.self) { n in Text("\(n)").tag(n) }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            Text("di \(totale)")
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

/// Indicatore «5 di 60» sul PDF: piccolo, semitrasparente, sul bordo destro; un tocco apre «Vai a pagina»
struct IndicatorePagina: View {
    @ObservedObject var model: NotesModel
    @State private var corrente = 1
    @State private var totale = 1
    @State private var aperto = false
    @State private var scelta = 1

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.clear.allowsHitTesting(false)
            if totale > 1 {
                Button {
                    scelta = corrente
                    aperto = true
                } label: {
                    Text("\(corrente) di \(totale)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(AptTema.testo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AptTema.carta.opacity(0.7)))
                        .overlay(Capsule().stroke(AptTema.linea.opacity(0.8), lineWidth: 0.5))
                        .opacity(0.8)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .popover(isPresented: $aperto) {
                    VaiAPaginaView(model: model, scelta: $scelta, chiudi: { aperto = false })
                        .padding(20)
                        .frame(width: 280)
                        .aptPannello()
                }
                .accessibilityLabel("Pagina \(corrente) di \(totale). Tocca per andare a una pagina")
            }
        }
        .onAppear { aggiorna() }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { n in
            if let v = n.object as? PDFView, v === model.pdfView { aggiorna() }
        }
        .onChange(of: model.versionePagine) { _ in aggiorna() }
        .onChange(of: model.document) { _ in aggiorna() }
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
