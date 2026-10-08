// Schermata Editor: barra in alto, striscia di schede (un PDF per scheda), barra strumenti e PDF.
// Il documento attivo sta nel modello; al cambio di scheda si salva (se ci sono modifiche) e si apre l'altro.
import SwiftUI
import PDFKit
import PhotosUI
import VisionKit
import UniformTypeIdentifiers
import Combine

struct EditorView: View {
    @EnvironmentObject private var store: AptStore
    @StateObject var model = NotesModel()
    @StateObject var secondario = NotesModel()      // secondo riquadro della vista doppia
    @StateObject private var ricerca = RicercaPDF()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var chiediUscita = false
    @State private var azioneSospesa: (() -> Void)?
    @State private var attivo: AptDoc
    @State private var mostraImpostazioni = false
    @State private var mostraPagina = false
    @State private var vistaDoppia = false
    @State private var docSecondario: AptDoc?
    @State private var mostraScelta = false
    @State private var frazione: CGFloat = 0.5          // quota di larghezza del riquadro a sinistra
    @State private var frazioneProvvisoria: CGFloat?    // posizione della maniglia mentre la si trascina
    @State private var invertiLati = false
    @State private var latoAttivo = Lato.principale
    @State private var mostraMiniature = false
    @State private var mostraRecenti = false
    @State private var mostraRinomina = false
    @State private var chiediElimina = false
    @State private var mostraFoto = false
    @State private var mostraFile = false
    @State private var fileDocumento = false          // false = immagine, true = PDF o documento di testo
    @State private var aggiungeAlDocumento = false    // true = le pagine vanno in fondo al documento aperto
    @State private var mostraScansione = false
    @State private var documentoScelto: DocumentoScelto?
    @State private var fotoScelta: PhotosPickerItem?

    @AppStorage("posizioneBarra") private var posizioneBarra: String = "fissa"
    @AppStorage("barraPos") private var posizioneFissa: String = "alto"
    @AppStorage("barraGrande") private var grande = false

    private enum Lato { case principale, secondario }

    /// Il riquadro dove si sta lavorando: barra strumenti, impostazioni e finestre fanno riferimento a lui
    private var modelloAttivo: NotesModel {
        if vistaDoppia && docSecondario != nil && latoAttivo == .secondario { return secondario }
        return model
    }

    init(doc: AptDoc) {
        _attivo = State(initialValue: doc)
    }

    var body: some View {
        ProvaPrestazioni.corpi += 1
        return conImportazioni
            .onAppear {
                if ProvaPrestazioni.attiva { Task { await eseguiProva() } }
            }
    }

    private var scheletro: some View {
        VStack(spacing: 0) {
            barraAlta
            if ricerca.attiva {
                BarraRicerca(ricerca: ricerca)
            }
            corpo
            if ricerca.attiva && ricerca.tastiera {
                AptTastiera(testo: $ricerca.testo, tutto: .constant(false), titoloInvio: "Cerca",
                            onInvio: { ricerca.prossimo() },
                            onNascondi: { ricerca.tastiera = false })
            }
        }
        .background(AptTema.scrivania.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if posizioneBarra == "flottante" && !(ricerca.attiva && ricerca.tastiera) {
                GeometryReader { geo in
                    BarraFlottante(model: modelloAttivo, area: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !(ricerca.attiva && ricerca.tastiera) {
                VassoioView(aggiungi: { modelloAttivo.inserisciDaVassoio($0, larghezzaSchermo: $1) })
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .overlay { OrologioRiquadro() }
    }

    private var conStato: some View {
        scheletro
        .onAppear {
            if !store.schede.contains(where: { $0.id == attivo.id }) { store.schede.append(attivo) }
            model.open(url: attivo.url)
            // Solo se il lato cambia davvero: a ogni tocco normale non deve succedere nulla
            model.quandoToccato = { if latoAttivo != .principale { latoAttivo = .principale } }
            secondario.quandoToccato = { if latoAttivo != .secondario { latoAttivo = .secondario } }
        }
        .onChange(of: attivo.id) { _, _ in ricerca.azzera() }
        .onChange(of: scenePhase) { _, fase in
            if fase != .active {
                model.salvaSeModificato()
                secondario.salvaSeModificato()
            }
        }
    }

    private var conConferme: some View {
        conStato
        .confirmationDialog("Ci sono modifiche non salvate", isPresented: $chiediUscita, titleVisibility: .visible) {
            Button("Salva") {
                model.save()
                guard !model.modificato else { return }   // scrittura riuscita
                let azione = azioneSospesa
                azioneSospesa = nil
                azione?()
            }
            Button("Non salvare", role: .destructive) {
                model.modificato = false
                let azione = azioneSospesa
                azioneSospesa = nil
                azione?()
            }
            Button("Annulla", role: .cancel) { azioneSospesa = nil }
        }
        .confirmationDialog("Eliminare «\(attivo.name)»?", isPresented: $chiediElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { eliminaAttivo() }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $mostraRinomina) {
            AptRinomina(
                titolo: "Rinomina",
                nome: attivo.name,
                salva: { mostraRinomina = false; rinomina($0) },
                annulla: { mostraRinomina = false }
            )
            .presentationDetents([.height(470)])
            .aptPannello()
        }
    }

    private var conOrigini: some View {
        conConferme
        .confirmationDialog("Immagine", isPresented: chiediImmagineAttivo, titleVisibility: .hidden) {
            Button("Dalle Foto") { modelloAttivo.origine = .foto }
            Button("Da File") { modelloAttivo.origine = .file }
            Button("PDF o documento di testo") { modelloAttivo.origine = .documento }
            Button("Aggiungi PDF al documento") { modelloAttivo.origine = .aggiungiPDF }
            Button("Scansiona documento") { modelloAttivo.origine = .scansione }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: model.origine) { _, o in gestisciOrigine(o, in: model) }
        .onChange(of: secondario.origine) { _, o in gestisciOrigine(o, in: secondario) }
        .sheet(isPresented: $mostraScelta) {
            SceltaDocumentoSecondario(
                documenti: documentiPerSecondario,
                scegli: { d in mostraScelta = false; apriSecondario(d) },
                annulla: { mostraScelta = false }
            )
            .presentationDetents([.medium, .large])
            .aptPannello()
        }
        .onChange(of: vistaDoppia) { _, acceso in
            if acceso { secondario.allineaStrumenti(da: model) }
        }
        .onChange(of: latoAttivo) { vecchio, nuovo in
            guard vistaDoppia, docSecondario != nil else { return }
            let da = vecchio == .secondario ? secondario : model
            let a = nuovo == .secondario ? secondario : model
            a.allineaStrumenti(da: da)
        }
    }

    private var conImportazioni: some View {
        conOrigini
        .fullScreenCover(isPresented: $mostraScansione) {
            ScannerDocumento { pagine in
                mostraScansione = false
                if !pagine.isEmpty { modelloAttivo.inserisciDocumento(pagine) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $documentoScelto) { d in
            SceltaPagine(
                scelto: d,
                aggiungi: { indici in
                    documentoScelto = nil
                    if d.aggiungeAlDocumento {
                        modelloAttivo.aggiungiPagine(da: d.documento, indici: indici)
                        return
                    }
                    let pagine = indici.compactMap { d.documento.page(at: $0) }.compactMap { ConvertitoreDocumento.immagine($0) }
                    modelloAttivo.inserisciDocumento(pagine)
                },
                annulla: { documentoScelto = nil }
            )
            .aptPannello()
        }
        .photosPicker(isPresented: $mostraFoto, selection: $fotoScelta, matching: .images)
        .onChange(of: fotoScelta) { _, scelta in
            guard let scelta else { return }
            Task {
                if let dati = try? await scelta.loadTransferable(type: Data.self) { modelloAttivo.inserisciImmagine(dati: dati) }
                fotoScelta = nil
            }
        }
        .fileImporter(isPresented: $mostraFile,
                      allowedContentTypes: fileDocumento ? [.pdf, .plainText, .rtf, .html] : [.image]) { esito in
            guard case .success(let url) = esito else { return }
            if fileDocumento {
                guard let doc = ConvertitoreDocumento.pdf(da: url), doc.pageCount > 0 else {
                    modelloAttivo.message = "Non riesco a leggere il file scelto."
                    return
                }
                if aggiungeAlDocumento {
                    if doc.pageCount == 1 {
                        modelloAttivo.aggiungiPagine(da: doc, indici: [0])
                    } else {
                        documentoScelto = DocumentoScelto(documento: doc, nome: url.lastPathComponent, aggiungeAlDocumento: true)
                    }
                } else if doc.pageCount == 1, let d = doc.page(at: 0).flatMap({ ConvertitoreDocumento.immagine($0) }) {
                    modelloAttivo.inserisciDocumento([d])
                } else {
                    documentoScelto = DocumentoScelto(documento: doc, nome: url.lastPathComponent)
                }
                return
            }
            let accesso = url.startAccessingSecurityScopedResource()
            defer { if accesso { url.stopAccessingSecurityScopedResource() } }
            if let dati = try? Data(contentsOf: url) { modelloAttivo.inserisciImmagine(dati: dati) }
        }
        .sheet(item: bozzaTestoAttivo) { b in
            FinestraTesto(
                testo: b.testo,
                corpo: b.corpo,
                salva: { modelloAttivo.confermaTesto(b, $0, corpo: $1) },
                annulla: { modelloAttivo.bozzaTesto = nil }
            )
            .presentationDetents([.height(630)])
            .aptPannello()
        }
    }

    // MARK: Barra in alto (una sola riga: indietro, miniature, schede dei PDF aperti, icone)

    private var urlAttivo: URL {
        if modelloAttivo === secondario, let d = docSecondario { return d.url }
        return attivo.url
    }

    private var barraAlta: some View {
        HStack(spacing: 2) {
            Button { tornaInLibreria() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AptTema.testo2)
                    .frame(width: 38, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Torna alla libreria")
            Button { mostraMiniature.toggle() } label: {
                AptIcona(nome: "sidebar.left", attiva: mostraMiniature, lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Miniature delle pagine")
            AptLinea(verticale: true).frame(height: 24).padding(.horizontal, 3)
            strisciaSchede
            Button { mostraRecenti = true } label: {
                AptIcona(nome: "plus", lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apri un altro file")
            .popover(isPresented: $mostraRecenti) { recenti.aptPannello() }
            iconeDestra
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .aptScheda()
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var iconeDestra: some View {
        HStack(spacing: 2) {
            AptLinea(verticale: true).frame(height: 24).padding(.horizontal, 3)
            Button {
                ricerca.collega(modelloAttivo.pdfView)
                ricerca.attiva.toggle()
            } label: {
                AptIcona(nome: "magnifyingglass", attiva: ricerca.attiva, lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerca nel testo")
            ShareLink(item: urlAttivo) {
                AptIcona(nome: "square.and.arrow.up", lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Condividi")
            MenuEstendi(model: modelloAttivo)
            Button { alternaVistaDoppia() } label: {
                AptIcona(nome: "rectangle.split.2x1", attiva: vistaDoppia, lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vista doppia dei documenti")
            Button { mostraImpostazioni = true } label: {
                AptIcona(nome: "gearshape", lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Impostazioni")
            .popover(isPresented: $mostraImpostazioni) { ImpostazioniEditor(model: modelloAttivo).aptPannello() }
            if !modelloAttivo.salvataggioAutomatico {
                Button("Salva") { modelloAttivo.save() }
                    .buttonStyle(AptStilePrimario())
            }
            Button { mostraPagina = true } label: {
                AptIcona(nome: "ellipsis", lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Altro")
            .popover(isPresented: $mostraPagina) {
                PannelloPagina(model: modelloAttivo, chiudi: { mostraPagina = false }).aptPannello()
            }
        }
    }

    /// Nome del PDF aperto (scheda attiva): un tocco apre il menu con peso del file, «Rinomina» ed «Elimina»
    private var menuTitolo: some View {
        Menu {
            Text("Peso: \(pesoFile)")
            Button { conConferma { mostraRinomina = true } } label: {
                Label("Rinomina", systemImage: "pencil")
            }
            Button(role: .destructive) { chiediElimina = true } label: {
                Label("Elimina", systemImage: "trash")
            }
        } label: {
            HStack(spacing: 4) {
                Text(attivo.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AptTema.testo)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AptTema.testo2)
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Nome del file: \(attivo.name)")
    }

    private var pesoFile: String {
        let attributi = try? FileManager.default.attributesOfItem(atPath: attivo.url.path)
        guard let byte = (attributi?[.size] as? NSNumber)?.int64Value else { return "non disponibile" }
        return ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }

    /// Cambia il nome del file: il documento viene chiuso, spostato e riaperto con il nuovo nome.
    private func rinomina(_ testo: String) {
        let pulito = AptFS.sanitize(testo.hasSuffix(".pdf") ? String(testo.dropLast(4)) : testo)
        guard !pulito.isEmpty, pulito != attivo.name else { return }
        let vecchio = attivo
        let cartella = vecchio.url.deletingLastPathComponent()
        let soloMaiuscole = pulito.lowercased() == vecchio.name.lowercased()
        model.salvaSeModificato()
        model.close()
        let destinazione = soloMaiuscole
            ? cartella.appendingPathComponent(pulito + ".pdf")
            : AptFS.uniqueURL(in: cartella, base: pulito, ext: "pdf")
        do {
            if soloMaiuscole {
                let temp = cartella.appendingPathComponent(UUID().uuidString)
                try AptFS.move(vecchio.url, to: temp)
                try AptFS.move(temp, to: destinazione)
            } else {
                try AptFS.move(vecchio.url, to: destinazione)
            }
        } catch {
            store.fail(error)
            model.open(url: vecchio.url)
            return
        }
        let nuovo = AptDoc(id: AptPath.join(vecchio.folderPath, destinazione.lastPathComponent), url: destinazione,
                           name: String(destinazione.lastPathComponent.dropLast(4)), modDate: Date(), folderPath: vecchio.folderPath)
        store.remap(from: vecchio.id, to: nuovo.id)
        if let i = store.schede.firstIndex(where: { $0.id == vecchio.id }) { store.schede[i] = nuovo }
        attivo = nuovo
        model.open(url: nuovo.url)
        store.reload()
    }

    /// Elimina il file aperto e passa alla scheda vicina (o torna in Libreria se era l'ultima).
    private func eliminaAttivo() {
        let d = attivo
        model.cancellaRecupero()      // niente diario di recupero per un file che sparisce
        model.modificato = false      // e niente salvataggio automatico
        guard let i = store.schede.firstIndex(where: { $0.id == d.id }) else { return }
        store.schede.remove(at: i)
        store.delete(docs: [d.id], folders: [])
        if store.schede.isEmpty {
            model.close()
            chiudiSecondario()
            dismiss()
        } else {
            let prossima = store.schede[min(i, store.schede.count - 1)]
            liberaSeSecondario(prossima)
            attivo = prossima
            model.open(url: prossima.url)
        }
    }

    // MARK: Schede

    private var strisciaSchede: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.schede) { d in scheda(d) }
            }
        }
    }

    private func scheda(_ d: AptDoc) -> some View {
        let scelta = d.id == attivo.id
        return HStack(spacing: 0) {
            Button { chiudiScheda(d) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi \(d.name)")
            if scelta {
                menuTitolo
            } else {
                Button { vai(a: d) } label: {
                    Text(d.name)
                        .font(.system(size: 14, weight: .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 10)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
        .frame(width: 176)
        .foregroundStyle(scelta ? AptTema.testo : AptTema.testo2)
        .background(scelta ? AptTema.accentoTenue : Color.clear, in: Capsule())
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
                Text("File recenti").font(AptTema.titoloMedio).foregroundColor(AptTema.testo).padding(16)
                if lista.isEmpty {
                    Text("Nessun altro file.").foregroundStyle(AptTema.testo2).padding(.horizontal, 16).padding(.bottom, 16)
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
                    AptLinea()
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

    /// Salvataggio manuale con modifiche in sospeso: prima di lasciare il documento si chiede cosa fare.
    private func conConferma(_ azione: @escaping () -> Void) {
        if model.modificato && !model.salvataggioAutomatico {
            azioneSospesa = azione
            chiediUscita = true
        } else {
            azione()
        }
    }

    private func vai(a d: AptDoc) {
        guard d.id != attivo.id else { return }
        conConferma {
            model.salvaSeModificato()
            liberaSeSecondario(d)
            attivo = d
            model.open(url: d.url)
        }
    }

    private func chiudiScheda(_ d: AptDoc) {
        guard let i = store.schede.firstIndex(where: { $0.id == d.id }) else { return }
        let eraAttiva = d.id == attivo.id
        let esegui = {
            if eraAttiva { model.salvaSeModificato() }
            store.schede.remove(at: i)
            guard eraAttiva else { return }
            if store.schede.isEmpty {
                model.close()
                chiudiSecondario()
                dismiss()
            } else {
                let prossima = store.schede[min(i, store.schede.count - 1)]
                liberaSeSecondario(prossima)
                attivo = prossima
                model.open(url: prossima.url)
            }
        }
        if eraAttiva { conConferma(esegui) } else { esegui() }
    }

    private func tornaInLibreria() {
        conConferma {
            model.salvaSeModificato()
            model.close()
            chiudiSecondario()
            dismiss()
        }
    }

    // MARK: Vista doppia dei documenti

    private var documentiPerSecondario: [AptDoc] {
        let altri = store.allDocs.filter { $0.id != attivo.id }
        return altri.sorted { $0.modDate > $1.modDate }
    }

    func alternaVistaDoppia() {
        if vistaDoppia {
            chiudiVistaDoppia()
        } else {
            vistaDoppia = true
            latoAttivo = .principale
        }
    }

    func apriSecondario(_ d: AptDoc) {
        if secondario.modificato { secondario.save() }
        docSecondario = d
        latoAttivo = .secondario
        // Il documento si apre dopo la chiusura dell'elenco: lettura e preparazione delle pagine non bloccano l'animazione
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard docSecondario?.id == d.id else { return }
            secondario.open(url: d.url)
        }
    }

    /// Salva e chiude il documento del secondo riquadro (anche con il salvataggio manuale: niente va perso)
    private func chiudiSecondario() {
        if secondario.modificato { secondario.save() }
        secondario.close()
        docSecondario = nil
        latoAttivo = .principale
    }

    private func chiudiVistaDoppia() {
        chiudiSecondario()
        vistaDoppia = false
    }

    private func scambiaLati() {
        invertiLati.toggle()
        frazione = 1 - frazione
    }

    /// Un documento non può stare in due riquadri: se si apre come scheda, il secondo riquadro si chiude
    private func liberaSeSecondario(_ d: AptDoc) {
        if docSecondario?.id == d.id { chiudiSecondario() }
    }

    private var chiediImmagineAttivo: Binding<Bool> {
        Binding(get: { modelloAttivo.chiediImmagine }, set: { modelloAttivo.chiediImmagine = $0 })
    }

    private var bozzaTestoAttivo: Binding<BozzaTesto?> {
        Binding(get: { modelloAttivo.bozzaTesto }, set: { modelloAttivo.bozzaTesto = $0 })
    }

    private func gestisciOrigine(_ o: OrigineImmagine?, in m: NotesModel) {
        guard let o else { return }
        m.origine = nil
        switch o {
        case .foto: mostraFoto = true
        case .file: fileDocumento = false; aggiungeAlDocumento = false; mostraFile = true
        case .documento: fileDocumento = true; aggiungeAlDocumento = false; mostraFile = true
        case .aggiungiPDF: fileDocumento = true; aggiungeAlDocumento = true; mostraFile = true
        case .scansione:
            if VNDocumentCameraViewController.isSupported { mostraScansione = true }
            else { m.message = "La scansione con la fotocamera non è disponibile su questo dispositivo." }
        }
    }

    // MARK: Corpo: barra strumenti e PDF

    private var fissaInAlto: Bool { posizioneBarra == "fissa" && posizioneFissa == "alto" }
    private var fissaInBasso: Bool { posizioneBarra == "fissa" && posizioneFissa == "basso" }
    private var fissaASinistra: Bool { posizioneBarra == "fissa" && posizioneFissa == "sinistra" }

    /// Un foglio (riquadro) con la sua griglia di pagine; in vista doppia il riquadro attivo ha il bordo marrone
    private func riquadro(_ m: NotesModel, lato: Lato) -> some View {
        let attivoOra = vistaDoppia && latoAttivo == lato
        let forma = RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous)
        // Niente mascheratura (clipShape) sul PDF: con tele grandi rallenta scorrimento e tocchi
        return PDFKitView(model: m)
            .overlay {
                if m.griglia { GrigliaPagine(model: m).transition(.opacity) }
            }
            .overlay(forma.stroke(attivoOra ? AptTema.accento : Color.clear, lineWidth: 2).allowsHitTesting(false))
    }

    private func riquadroSecondario(larghezza: CGFloat, altezza: CGFloat) -> some View {
        let forma = RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous)
        return ZStack(alignment: .topLeading) {
            if docSecondario != nil {
                riquadro(secondario, lato: .secondario)
            } else {
                SegnapostoSecondario { mostraScelta = true }
                    .clipShape(forma)
                    .overlay(forma.stroke(AptTema.linea, lineWidth: 1))
            }
            ComandiSecondario(chiudi: { chiudiVistaDoppia() }, scambia: { scambiaLati() })
                .padding(8)
                .zIndex(10)
        }
        .frame(width: larghezza, height: altezza)
    }

    /// Mentre si trascina si muove solo la maniglia; i due PDF cambiano misura una volta sola, quando si lascia
    /// (ridimensionarli di continuo è ciò che li rallentava).
    private func trascinaDivisore(larghezza: CGFloat, spazio: CGFloat) -> some Gesture {
        func quota(_ v: DragGesture.Value) -> CGFloat {
            let x: CGFloat = v.location.x - 4 - spazio / 2
            let f: CGFloat = x / max(larghezza - spazio, 1)
            return min(0.75, max(0.25, f))
        }
        return DragGesture(minimumDistance: 1, coordinateSpace: .named("fogli"))
            .onChanged { v in frazioneProvvisoria = quota(v) }
            .onEnded { v in
                frazione = quota(v)
                frazioneProvvisoria = nil
            }
    }

    /// Area dei fogli: uno solo, o due affiancati con il divisore da trascinare.
    /// Il riquadro principale resta sempre lo stesso elemento (cambiano solo misura e posizione): niente si ricostruisce.
    private var areaFogli: some View {
        GeometryReader { geo in
            let larghezza: CGFloat = max(geo.size.width - 8, 100)
            let altezza: CGFloat = max(geo.size.height - 6, 100)
            let spazio: CGFloat = 28
            let sinistra: CGFloat = (larghezza - spazio) * frazione
            let destra: CGFloat = larghezza - spazio - sinistra
            let primarioASinistra = !invertiLati
            let lP: CGFloat = vistaDoppia ? (primarioASinistra ? sinistra : destra) : larghezza
            let xP: CGFloat = 4 + ((vistaDoppia && !primarioASinistra) ? sinistra + spazio : 0)
            let lS: CGFloat = primarioASinistra ? destra : sinistra
            let xS: CGFloat = 4 + (primarioASinistra ? sinistra + spazio : 0)
            ZStack(alignment: .topLeading) {
                riquadro(model, lato: .principale)
                    .frame(width: lP, height: altezza)
                    .offset(x: xP)
                if vistaDoppia {
                    riquadroSecondario(larghezza: lS, altezza: altezza)
                        .offset(x: xS)
                    DivisoreDoppia(trascinando: frazioneProvvisoria != nil)
                        .frame(width: spazio, height: altezza)
                        .offset(x: 4 + (larghezza - spazio) * (frazioneProvvisoria ?? frazione))
                        .highPriorityGesture(trascinaDivisore(larghezza: larghezza, spazio: spazio))
                        .zIndex(5)
                }
            }
            .coordinateSpace(name: "fogli")
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: fissaInBasso ? Edge.Set() : Edge.Set.bottom)
    }

    private var areaPDF: some View {
        HStack(spacing: 0) {
            if mostraMiniature {
                MiniaturePagine(model: model)
                    .frame(width: 124)
                    .clipShape(RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous))
                    .padding(.leading, 4)
            }
            areaFogli
        }
    }

    private var corpo: some View {
        VStack(spacing: 0) {
            if !modelloAttivo.message.isEmpty {
                Text(modelloAttivo.message)
                    .font(AptTema.dettaglio)
                    .foregroundColor(AptTema.testo2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            if fissaInAlto {
                BarraStrumenti(model: modelloAttivo)
                    .aptCapsulaBarra()
            }
            if fissaASinistra {
                HStack(spacing: 0) {
                    BarraStrumenti(model: modelloAttivo, verticale: true)
                        .frame(width: grande ? 76 : 64)
                        .aptCapsulaBarra(verticale: true)
                    areaPDF
                }
            } else {
                areaPDF
            }
            if fissaInBasso {
                BarraStrumenti(model: modelloAttivo)
                    .aptCapsulaBarra()
            }
        }
    }
}

// Miniature delle pagine: un tocco porta alla pagina; tenendo premuto e trascinando si riordinano.
struct MiniaturePagine: View {
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
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<numero, id: \.self) { i in
                    if let p = model.document?.page(at: i) { riga(i, p, inizio: inizio) }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .background(AptTema.carta)
        .sheet(isPresented: $mostraModello) {
            SceltaModelloPagina(model: model, indice: modelloPer) { mostraModello = false }
                .presentationDetents([.height(500), .large])
        }
        .onAppear { aggiornaCorrente() }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { _ in aggiornaCorrente() }
    }

    private func riga(_ i: Int, _ p: PDFPage, inizio: Int?) -> some View {
        let scelta = i == corrente
        let id = ObjectIdentifier(p)
        return VStack(spacing: 4) {
            Group {
                if let img = immagini[id] {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Rectangle().fill(AptTema.scrivania).aspectRatio(0.75, contentMode: .fit)
                }
            }
            .frame(width: 84)
            .overlay(Rectangle().stroke(bersaglio == i ? AptTema.accento : (scelta ? AptTema.accento.opacity(0.6) : AptTema.linea),
                                        lineWidth: bersaglio == i ? 3 : (scelta ? 2 : 1)))
            .overlay { MenuPaginaMiniatura(model: model, indice: i) { modelloPer = $0; mostraModello = true } }
            Text(NotesModel.etichetta(i, inizio: inizio))
                .font(AptTema.dettaglio)
                .foregroundStyle(scelta ? AptTema.accentoTesto : AptTema.testo2)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            if immagini[id] == nil {
                immagini[id] = p.thumbnail(of: CGSize(width: 168, height: 224), for: .cropBox)
            }
        }
        .onTapGesture { model.pdfView?.go(to: p) }
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

    private func aggiornaCorrente() {
        guard let d = model.document, let p = model.pdfView?.currentPage else { return }
        let i = d.index(for: p)
        if i != NSNotFound { corrente = i }
    }
}

/// Rilascio di una miniatura su un'altra: la pagina trascinata va in quella posizione
struct RiordinoPagina: DropDelegate {
    let indice: Int
    @Binding var trascinata: Int?
    @Binding var bersaglio: Int?
    let sposta: (Int, Int) -> Void

    func dropEntered(info: DropInfo) { bersaglio = indice }
    func dropExited(info: DropInfo) { if bersaglio == indice { bersaglio = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { trascinata = nil; bersaglio = nil }
        guard let da = trascinata, da != indice else { return false }
        sposta(da, indice)
        return true
    }
}
