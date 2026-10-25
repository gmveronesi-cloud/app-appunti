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
    @State private var latoScelta = Lato.secondario     // quale riquadro sta cambiando documento
    @State private var ponte = SincroDoppia()           // stesso file in due riquadri: le modifiche passano dall'uno all'altro
    @State private var frazione: CGFloat = 0.5          // quota di larghezza del riquadro a sinistra
    @State private var frazioneProvvisoria: CGFloat?    // posizione della maniglia mentre la si trascina
    @State private var invertiLati = false
    @State private var latoAttivo = Lato.principale
    @State private var ripristinaPrincipale = false     // vero mentre il documento principale si apre e torna all'ultima pagina vista
    @State private var ripristinaLaterale = false       // vero mentre il file laterale si apre e torna alla pagina ricordata
    @State private var modelloConferma: NotesModel?     // riquadro a cui si riferisce la domanda «Ci sono modifiche non salvate»
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
    @State private var mostraImmaginiPagine = false
    @State private var immaginiScelte: [PhotosPickerItem] = []

    @AppStorage("posizioneBarra") private var posizioneBarra: String = "fissa"
    @AppStorage("barraPos") private var posizioneFissa: String = "alto"
    @AppStorage("barraGrande") private var grande = false

    private enum Lato { case principale, secondario }

    /// Il riquadro dove si sta lavorando: barra strumenti, impostazioni e finestre fanno riferimento a lui
    private var modelloAttivo: NotesModel {
        if vistaDoppia && docSecondario != nil && latoAttivo == .secondario { return secondario }
        return model
    }

    /// Vero se il riquadro dove si lavora è quello di destra (il file a lato)
    private var secondarioAttivo: Bool { modelloAttivo === secondario }

    /// Il documento del riquadro attivo: titolo, peso, rinomina ed elimina fanno riferimento a lui
    private var docAttivo: AptDoc {
        if secondarioAttivo, let d = docSecondario { return d }
        return attivo
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
            if !store.schede.contains(where: { $0.chiave == attivo.chiave }) { store.schede.append(attivo) }
            apriPrincipale(attivo)
            ponte.collega(model, secondario)
            secondario.risoluzioneMax = 3          // il secondo documento ha tele più leggere (la memoria è una sola)
            secondario.teleMassime = 4
            // Solo se il lato cambia davvero: a ogni tocco normale non deve succedere nulla
            model.quandoToccato = { if latoAttivo != .principale { latoAttivo = .principale } }
            secondario.quandoToccato = { if latoAttivo != .secondario { latoAttivo = .secondario } }
        }
        .onChange(of: attivo.chiave) { _, _ in ricerca.azzera() }
        .onChange(of: latoAttivo) { _, _ in
            // La ricerca segue il file che si sta guardando
            if ricerca.attiva { ricerca.sposta(su: modelloAttivo.pdfView) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { n in
            guard let v = n.object as? PDFView else { return }
            // Ultima pagina vista di ogni documento (finché l'app resta aperta); non mentre si sta ancora tornando a quella ricordata
            if v === model.pdfView, !ripristinaPrincipale, model.document != nil {
                store.ultimaPagina[attivo.chiave] = model.paginaCorrente
            }
            // Il file a lato si ricorda anche dopo la chiusura dell'app
            if v === secondario.pdfView, !ripristinaLaterale, let d = docSecondario, secondario.document != nil {
                store.ultimaPagina[d.chiave] = secondario.paginaCorrente
                MemoriaLaterale.ricorda(documento: d.id, pagina: secondario.paginaCorrente)
            }
        }
        .onChange(of: store.richiestaApri) { _, d in
            guard let d else { return }
            store.richiestaApri = nil
            apri(d)
        }
        .onChange(of: scenePhase) { vecchia, fase in
            if fase == .inactive && vecchia == .active {            // la posizione si ricorda appena si esce, e si rimette al ritorno (la pagina non deve muoversi)
                model.ricordaPosizioneUscita()
                secondario.ricordaPosizioneUscita()
            } else if fase == .active {
                model.ripristinaPosizioneUscita()
                secondario.ripristinaPosizioneUscita()
            }
            if fase == .background {          // «inattiva» capita anche solo tirando giù il centro di controllo: lì non si scrive
                model.salvaSeModificato()
                secondario.salvaSeModificato()
                // Poi, a salvataggio finito, si libera memoria: iPadOS non deve chiudere l'app mentre si usa un'altra
                model.alleggerisciInSecondoPiano()
                secondario.alleggerisciInSecondoPiano()
            }
        }
    }

    private var conConferme: some View {
        conStato
        .confirmationDialog("Ci sono modifiche non salvate", isPresented: $chiediUscita, titleVisibility: .visible) {
            Button("Salva") {
                let m = modelloConferma ?? model
                let azione = azioneSospesa
                azioneSospesa = nil
                m.salva { riuscito in
                    if riuscito { azione?() }       // se la scrittura fallisce, si resta dove si è
                }
            }
            Button("Non salvare", role: .destructive) {
                (modelloConferma ?? model).modificato = false
                let azione = azioneSospesa
                azioneSospesa = nil
                azione?()
            }
            Button("Annulla", role: .cancel) { azioneSospesa = nil }
        }
        .confirmationDialog("Eliminare «\(docAttivo.name)»?", isPresented: $chiediElimina, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { eliminaAttivo() }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $mostraRinomina) {
            AptRinomina(
                titolo: "Rinomina",
                nome: docAttivo.name,
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
            Button("Aggiungi PDF al documento") { modelloAttivo.inserisciDopo = nil; modelloAttivo.origine = .aggiungiPDF }
            Button("Scansiona documento") { modelloAttivo.origine = .scansione }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: model.origine) { _, o in gestisciOrigine(o, in: model) }
        .onChange(of: secondario.origine) { _, o in gestisciOrigine(o, in: secondario) }
        .sheet(isPresented: $mostraScelta) {
            SceltaDocumentoSecondario(
                documenti: documentiPerScelta,
                scegli: { d in
                    mostraScelta = false
                    let lato = latoScelta
                    // Si aspetta che la finestra si chiuda: poi si cambia il documento del riquadro
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { cambiaDocumento(lato, d) }
                },
                annulla: { mostraScelta = false }
            )
            .presentationDetents([.medium, .large])
            .aptPannello()
        }
        .onChange(of: vistaDoppia) { _, acceso in
            model.teleMassime = acceso ? 4 : 7      // con due documenti si tengono meno tele ciascuno
            if acceso { secondario.allineaStrumenti(da: model) }
            model.limitaTele()
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
        .photosPicker(isPresented: $mostraImmaginiPagine, selection: $immaginiScelte, matching: .images)
        .onChange(of: immaginiScelte) { _, scelte in
            guard !scelte.isEmpty else { return }
            immaginiScelte = []
            Task {
                var tutte: [Data] = []
                for s in scelte {
                    if let dati = try? await s.loadTransferable(type: Data.self) { tutte.append(dati) }
                }
                modelloAttivo.aggiungiImmaginiComePagine(tutte)
            }
        }
        .onChange(of: fotoScelta) { _, scelta in
            guard let scelta else { return }
            Task {
                if let dati = try? await scelta.loadTransferable(type: Data.self) { modelloAttivo.inserisciImmagine(dati: dati) }
                fotoScelta = nil
            }
        }
        .fileImporter(isPresented: $mostraFile,
                      allowedContentTypes: fileDocumento ? [.pdf, .plainText, .rtf, .html] + TipoWord.tipi : [.image]) { esito in
            guard case .success(let url) = esito else { return }
            if fileDocumento {
                let modello = modelloAttivo
                let nome = url.lastPathComponent
                let aggiunge = aggiungeAlDocumento
                // Pagine del file scelto: come immagini sulla pagina o in fondo al documento
                func usa(_ doc: PDFDocument) {
                    if aggiunge {
                        if doc.pageCount == 1 {
                            modello.aggiungiPagine(da: doc, indici: [0])
                        } else {
                            documentoScelto = DocumentoScelto(documento: doc, nome: nome, aggiungeAlDocumento: true)
                        }
                    } else if doc.pageCount == 1, let d = doc.page(at: 0).flatMap({ ConvertitoreDocumento.immagine($0) }) {
                        modello.inserisciDocumento([d])
                    } else {
                        documentoScelto = DocumentoScelto(documento: doc, nome: nome)
                    }
                }
                if TipoWord.eWord(url) {
                    // Word: prima diventa PDF (ci vuole qualche secondo)
                    guard let copia = ConvertitoreWord.copiaTemporanea(url) else {
                        modello.message = "Non riesco a leggere il file scelto."
                        return
                    }
                    modello.message = "Converto il file Word in PDF…"
                    ConvertitoreWord.converti(copia) { dati in
                        guard let dati, let doc = PDFDocument(data: dati), doc.pageCount > 0 else {
                            modello.message = "Non sono riuscito a convertire il file Word."
                            return
                        }
                        modello.message = ""
                        usa(doc)
                    }
                    return
                }
                guard let doc = ConvertitoreDocumento.pdf(da: url), doc.pageCount > 0 else {
                    modello.message = "Non riesco a leggere il file scelto."
                    return
                }
                usa(doc)
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
            PulsanteCondividi(model: modelloAttivo)
            MenuEstendi(model: modelloAttivo)
            pulsanteVistaDoppia
            Button { mostraImpostazioni = true } label: {
                AptIcona(nome: "gearshape", lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Impostazioni")
            .popover(isPresented: $mostraImpostazioni) { ImpostazioniEditor(model: modelloAttivo).aptPannello() }
            if !modelloAttivo.salvataggioAutomatico {
                Button("Salva") { modelloAttivo.salva() }
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

    /// Vista doppia spenta: un tocco la accende. Accesa: un tocco la chiude; tenendo premuto si sceglie il documento di ciascun riquadro
    /// (anche lo stesso file in tutti e due: le modifiche passano subito dall'uno all'altro).
    @ViewBuilder private var pulsanteVistaDoppia: some View {
        if vistaDoppia {
            Menu {
                Button {
                    latoScelta = invertiLati ? .secondario : .principale
                    mostraScelta = true
                } label: { Label("Documento a sinistra…", systemImage: "rectangle.lefthalf.inset.filled") }
                Button {
                    latoScelta = invertiLati ? .principale : .secondario
                    mostraScelta = true
                } label: { Label("Documento a destra…", systemImage: "rectangle.righthalf.inset.filled") }
                Button { scambiaLati() } label: { Label("Scambia i lati", systemImage: "arrow.left.arrow.right") }
                Button(role: .destructive) { chiudiVistaDoppia() } label: { Label("Chiudi la vista doppia", systemImage: "xmark.circle") }
            } label: {
                AptIcona(nome: "rectangle.split.2x1", attiva: true, lato: 40, corpo: 21)
            } primaryAction: {
                alternaVistaDoppia()
            }
            .accessibilityLabel("Vista doppia dei documenti")
        } else {
            Button { alternaVistaDoppia() } label: {
                AptIcona(nome: "rectangle.split.2x1", attiva: false, lato: 40, corpo: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vista doppia dei documenti")
        }
    }

    /// Nome sulla scheda: le schede in più dello stesso file hanno un numero
    private func nomeScheda(_ d: AptDoc) -> String {
        d.copia == 0 ? d.name : "\(d.name) (\(d.copia + 1))"
    }

    /// Nome del PDF aperto (scheda attiva): un tocco apre il menu con peso del file, «Rinomina» ed «Elimina»
    private var menuTitolo: some View {
        Menu {
            Text("Peso: \(pesoFile)")
            Button { duplicaScheda(docAttivo) } label: {
                Label("Duplica scheda", systemImage: "plus.square.on.square")
            }
            Button { conConferma(per: modelloAttivo) { mostraRinomina = true } } label: {
                Label("Rinomina", systemImage: "pencil")
            }
            Button(role: .destructive) { chiediElimina = true } label: {
                Label("Elimina", systemImage: "trash")
            }
        } label: {
            HStack(spacing: 4) {
                Text(nomeScheda(docAttivo))
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
        .accessibilityLabel("Nome del file: \(docAttivo.name)")
    }

    private var pesoFile: String {
        let attributi = try? FileManager.default.attributesOfItem(atPath: docAttivo.url.path)
        guard let byte = (attributi?[.size] as? NSNumber)?.int64Value else { return "non disponibile" }
        return ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }

    /// Cambia il nome del file del riquadro attivo: il documento viene chiuso, spostato e riaperto (alla stessa pagina) con il nuovo nome.
    private func rinomina(_ testo: String) {
        let vecchio = docAttivo
        let m = modelloAttivo
        let laterale = secondarioAttivo
        let pulito = AptFS.sanitize(testo.hasSuffix(".pdf") ? String(testo.dropLast(4)) : testo)
        guard !pulito.isEmpty, pulito != vecchio.name else { return }
        let cartella = vecchio.url.deletingLastPathComponent()
        let soloMaiuscole = pulito.lowercased() == vecchio.name.lowercased()
        let pagina = m.paginaCorrente
        m.salvaSeModificato()
        // Lo stesso file può essere aperto anche nell'altro riquadro: si chiude prima di spostarlo (altrimenti lo ricreerebbe al salvataggio)
        let altroModello: NotesModel = (m === model) ? secondario : model
        let altroUguale = altroModello.document != nil
            && altroModello.fileURL?.standardizedFileURL == vecchio.url.standardizedFileURL
        let paginaAltro = altroModello.paginaCorrente
        if altroUguale { altroModello.salvaSeModificato(); altroModello.close() }
        m.close()
        // Il file si sposta solo a scrittura finita (il salvataggio parte in sottofondo, non si aspetta bloccando)
        func prosegui() {
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
            m.open(url: vecchio.url)
            m.vaiAPaginaQuandoPronto(pagina)
            if altroUguale {
                altroModello.open(url: vecchio.url)
                altroModello.vaiAPaginaQuandoPronto(paginaAltro)
            }
            return
        }
        let nuovo = AptDoc(id: AptPath.join(vecchio.folderPath, destinazione.lastPathComponent), url: destinazione,
                           name: String(destinazione.lastPathComponent.dropLast(4)), modDate: Date(), folderPath: vecchio.folderPath,
                           copia: vecchio.copia)
        // Il percorso cambia in tutte le schede di quel file (anche quelle con il numero)
        store.remap(from: vecchio.id, to: nuovo.id)
        store.ultimaPagina[nuovo.chiave] = pagina
        if let i = store.schede.firstIndex(where: { $0.chiave == vecchio.chiave }) { store.schede[i] = nuovo }
        if altroUguale {
            // L'altro riquadro mostra lo stesso file: nuovo nome anche per lui, poi si riapre alla pagina di prima
            if laterale {
                attivo = nuovo.conCopia(attivo.copia)
                ripristinaPrincipale = true
                altroModello.open(url: nuovo.url)
                altroModello.vaiAPaginaQuandoPronto(paginaAltro) { ripristinaPrincipale = false }
            } else if let ds = docSecondario {
                docSecondario = nuovo.conCopia(ds.copia)
                MemoriaLaterale.ricorda(documento: nuovo.id, pagina: paginaAltro)
                ripristinaLaterale = true
                altroModello.open(url: nuovo.url)
                altroModello.vaiAPaginaQuandoPronto(paginaAltro) { ripristinaLaterale = false }
            }
        }
        if laterale {
            docSecondario = nuovo
            MemoriaLaterale.ricorda(documento: nuovo.id, pagina: pagina)
            ripristinaLaterale = true
        } else {
            attivo = nuovo
        }
        m.open(url: nuovo.url)
        if !laterale { ripristinaPrincipale = true }
        m.vaiAPaginaQuandoPronto(pagina) {
            if laterale { ripristinaLaterale = false } else { ripristinaPrincipale = false }
        }
        store.reload()
        }
        NotesModel.dopoScrittura(di: vecchio.url, prosegui)
    }

    /// Elimina il file del riquadro attivo. Se era il file a lato si chiude quel riquadro; se era il principale si passa alla scheda vicina
    /// (o si torna in Libreria se era l'ultima).
    private func eliminaAttivo() {
        let d = docAttivo
        let m = modelloAttivo
        m.scritturaCorrente?.annulla()      // un salvataggio ancora in corso non deve ricreare il file
        m.cancellaRecupero()      // niente diario di recupero per un file che sparisce
        m.modificato = false      // e niente salvataggio automatico
        guard let i = store.schede.firstIndex(where: { $0.id == d.id }) else { return }
        // Il file sparisce da tutte le schede e da entrambi i riquadri in cui è aperto
        let primarioColpito = attivo.id == d.id
        let secondarioColpito = vistaDoppia && docSecondario?.id == d.id
        store.schede.removeAll { $0.id == d.id }
        store.ultimaPagina = store.ultimaPagina.filter { $0.key != d.id && !$0.key.hasPrefix(d.id + "#") }
        store.delete(docs: [d.id], folders: [])
        if secondarioColpito {
            secondario.cancellaRecupero()
            secondario.modificato = false
            chiudiSecondario()
            MemoriaLaterale.dimentica()
        }
        if !primarioColpito { return }
        model.cancellaRecupero()
        model.modificato = false
        if store.schede.isEmpty {
            model.close()
            chiudiSecondario()
            dismiss()
        } else {
            let prossima = store.schede[min(i, store.schede.count - 1)]
            liberaSeSecondario(prossima)
            attivo = prossima
            latoAttivo = .principale
            apriPrincipale(prossima)
        }
    }

    // MARK: Schede

    private var strisciaSchede: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.schede, id: \.chiave) { d in scheda(d) }
            }
        }
    }

    private func scheda(_ d: AptDoc) -> some View {
        let scelta = d.chiave == docAttivo.chiave
        // In vista doppia l'altro file che si vede ha un filo di bordo: si capisce quali due sono aperti
        let visibileAccanto = vistaDoppia && docSecondario != nil && !scelta && (d.chiave == attivo.chiave || d.chiave == docSecondario?.chiave)
        return HStack(spacing: 0) {
            Button { chiudiScheda(d) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi \(nomeScheda(d))")
            if scelta {
                menuTitolo
            } else {
                Button { tocca(d) } label: {
                    Text(nomeScheda(d))
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
        .overlay(Capsule().stroke(visibileAccanto ? AptTema.accento.opacity(0.55) : Color.clear, lineWidth: 1.5))
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
        let scheda = store.schede.first(where: { $0.id == d.id }) ?? d
        if !store.schede.contains(where: { $0.chiave == scheda.chiave }) { store.schede.append(scheda) }
        vai(a: scheda)
    }

    /// Salvataggio manuale con modifiche in sospeso: prima di lasciare il documento si chiede cosa fare.
    private func conConferma(per m: NotesModel? = nil, _ azione: @escaping () -> Void) {
        let m = m ?? model
        if m.modificato && !m.salvataggioAutomatico {
            modelloConferma = m
            azioneSospesa = azione
            chiediUscita = true
        } else {
            azione()
        }
    }

    private func vai(a d: AptDoc) {
        guard d.chiave != attivo.chiave else { return }
        conConferma {
            model.salvaSeModificato()
            ricordaPaginaPrincipale()
            if d.id == attivo.id {
                // Altra scheda dello stesso file: non si riapre nulla, si cambia solo il punto di lettura
                liberaSeSecondario(d)
                attivo = d
                latoAttivo = .principale
                let p = store.ultimaPagina[d.chiave] ?? model.paginaCorrente
                ripristinaPrincipale = true
                model.vaiAPaginaQuandoPronto(p) { ripristinaPrincipale = false }
                return
            }
            // Se il file è visibile nell'altro riquadro, deve essere salvato prima di aprirlo qui
            if docSecondario?.id == d.id { secondario.salvaSeModificato() }
            liberaSeSecondario(d)
            attivo = d
            latoAttivo = .principale
            apriPrincipale(d)
        }
    }

    /// Apre un documento nel riquadro principale e torna all'ultima pagina in cui era (ricordata finché l'app resta aperta)
    private func apriPrincipale(_ d: AptDoc) {
        ripristinaPrincipale = true
        model.open(url: d.url)
        model.vaiAPaginaQuandoPronto(store.ultimaPagina[d.chiave] ?? 0) { ripristinaPrincipale = false }
    }

    /// Prima di lasciare il documento principale si scrive a che pagina era
    private func ricordaPaginaPrincipale() {
        guard model.document != nil, !ripristinaPrincipale else { return }
        store.ultimaPagina[attivo.chiave] = model.paginaCorrente
    }

    /// Tocco su una scheda: se quel file è già visibile nell'altro riquadro si passa a lui (senza riaprire nulla), altrimenti si apre nel riquadro principale
    private func tocca(_ d: AptDoc) {
        if vistaDoppia, docSecondario != nil {
            if d.chiave == docSecondario?.chiave { latoAttivo = .secondario; return }
            if d.chiave == attivo.chiave { latoAttivo = .principale; return }
        }
        vai(a: d)
    }

    private func chiudiScheda(_ d: AptDoc) {
        // Scheda del file a lato: si chiude il riquadro destro (si salva da solo) e la scheda sparisce
        if vistaDoppia, d.chiave == docSecondario?.chiave, d.chiave != attivo.chiave {
            chiudiSecondario()
            store.schede.removeAll { $0.chiave == d.chiave }
            return
        }
        guard let i = store.schede.firstIndex(where: { $0.chiave == d.chiave }) else { return }
        let eraAttiva = d.chiave == attivo.chiave
        let esegui = {
            if eraAttiva { model.salvaSeModificato(); ricordaPaginaPrincipale() }
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
                apriPrincipale(prossima)
            }
        }
        if eraAttiva { conConferma(esegui) } else { esegui() }
    }

    private func tornaInLibreria() {
        conConferma {
            model.salvaSeModificato()
            ricordaPaginaPrincipale()
            model.close()
            chiudiSecondario()
            dismiss()
        }
    }

    // MARK: Vista doppia dei documenti

    /// Tutti i documenti, anche quello già visibile: lo stesso file può stare in tutti e due i riquadri
    private var documentiPerScelta: [AptDoc] {
        store.allDocs.sorted { $0.modDate > $1.modDate }
    }

    /// Una scheda del file `d` non ancora usata da nessuno dei due riquadri (se non c'è, ne nasce una nuova con il numero)
    private func schedaLibera(per d: AptDoc) -> AptDoc {
        let occupate = Set([attivo.chiave, docSecondario?.chiave].compactMap { $0 })
        if let t = store.schede.first(where: { $0.id == d.id && !occupate.contains($0.chiave) }) { return t }
        return nuovaCopia(di: d)
    }

    private func nuovaCopia(di d: AptDoc) -> AptDoc {
        let usate = Set(store.schede.filter { $0.id == d.id }.map { $0.copia })
        var n = 0
        while usate.contains(n) { n += 1 }
        let c = d.conCopia(n)
        store.schede.append(c)
        return c
    }

    /// «Duplica scheda»: lo stesso documento in un'altra scheda (stesso file, quindi le modifiche si vedono subito in entrambe)
    private func duplicaScheda(_ d: AptDoc) {
        if secondarioAttivo, docSecondario != nil {
            let c = nuovaCopia(di: d)
            store.ultimaPagina[c.chiave] = secondario.paginaCorrente
            docSecondario = c
            return
        }
        let c = nuovaCopia(di: d)
        store.ultimaPagina[c.chiave] = model.paginaCorrente
        vai(a: c)
    }

    /// Cambia il documento di un riquadro (anche con lo stesso file dell'altro riquadro)
    private func cambiaDocumento(_ lato: Lato, _ d: AptDoc) {
        switch lato {
        case .secondario:
            if docSecondario?.id == d.id { return }
            apriSecondario(schedaLibera(per: d))
        case .principale:
            if attivo.id == d.id { return }
            vai(a: schedaLibera(per: d))
        }
    }

    func alternaVistaDoppia() {
        if vistaDoppia {
            chiudiVistaDoppia()
        } else {
            vistaDoppia = true
            latoAttivo = .principale
            // Il file che stava a lato torna da solo, alla pagina a cui era arrivato (se esiste ancora e non è quello principale)
            if let id = MemoriaLaterale.documento, id != attivo.id, let d = store.allDocs.first(where: { $0.id == id }) {
                apriSecondario(store.schede.first(where: { $0.id == id }) ?? d, attivandolo: false)
            }
        }
    }

    /// Apre un documento nel riquadro destro. Se è quello che c'era a lato l'ultima volta, riparte dalla pagina ricordata.
    func apriSecondario(_ d: AptDoc, attivandolo: Bool = true) {
        if secondario.modificato { secondario.salva() }
        // Stesso file del riquadro principale: prima si salva lì, così il secondo lo legge aggiornato
        if d.id == attivo.id { model.salvaSeModificato() }
        let pagina = store.ultimaPagina[d.chiave]
            ?? (d.id == attivo.id ? model.paginaCorrente : (MemoriaLaterale.documento == d.id ? MemoriaLaterale.pagina : 0))
        MemoriaLaterale.ricorda(documento: d.id, pagina: pagina)
        ripristinaLaterale = true
        // Il file a lato sta tra le schede come gli altri: così si può selezionare, rinominare, eliminare
        if !store.schede.contains(where: { $0.chiave == d.chiave }) { store.schede.append(d) }
        docSecondario = d
        if attivandolo { latoAttivo = .secondario }
        // Il documento si apre dopo la chiusura dell'elenco: lettura e preparazione delle pagine non bloccano l'animazione
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard docSecondario?.chiave == d.chiave else { ripristinaLaterale = false; return }
            secondario.open(url: d.url)
            secondario.vaiAPaginaQuandoPronto(pagina) { ripristinaLaterale = false }
        }
    }

    /// Salva e chiude il documento del secondo riquadro (anche con il salvataggio manuale: niente va perso).
    /// La pagina a cui era arrivato resta in memoria.
    private func chiudiSecondario() {
        if let d = docSecondario, secondario.document != nil, !ripristinaLaterale {
            MemoriaLaterale.ricorda(documento: d.id, pagina: secondario.paginaCorrente)
        }
        if secondario.modificato { secondario.salva() }
        ripristinaLaterale = false
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

    /// La stessa scheda non può stare in due riquadri (lo stesso file sì, con schede diverse): in quel caso il secondo riquadro si chiude
    private func liberaSeSecondario(_ d: AptDoc) {
        if docSecondario?.chiave == d.chiave { chiudiSecondario() }
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
        case .immaginiPagine: mostraImmaginiPagine = true
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
            .overlay {
                if m.inAttesaScrittura {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Sto finendo di salvare questo file (è grande).\nIl documento riappare da solo appena ha finito.")
                            .font(AptTema.corpo)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AptTema.testo2)
                    }
                    .padding(24)
                }
            }
            .overlay { SuggerimentoPagina(model: m) }
            .overlay(alignment: .topTrailing) { IndicatorePagina(model: m) }
            .modifier(PresentaModelli(model: m))
            .overlay(forma.stroke(attivoOra ? AptTema.accento : Color.clear, lineWidth: 2).allowsHitTesting(false))
    }

    private func riquadroSecondario(larghezza: CGFloat, altezza: CGFloat) -> some View {
        let forma = RoundedRectangle(cornerRadius: AptTema.raggioM, style: .continuous)
        return ZStack(alignment: .topLeading) {
            if docSecondario != nil {
                riquadro(secondario, lato: .secondario)
            } else {
                SegnapostoSecondario { latoScelta = .secondario; mostraScelta = true }
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
                MiniaturePagine(model: modelloAttivo)
                    .id(ObjectIdentifier(modelloAttivo))      // cambiando riquadro si ricomincia da capo (pagina evidenziata, immagini)
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
        .onAppear { aggiornaCorrente() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            immagini.removeAll()       // poca memoria: le miniature si rifanno quando servono
            AptDocInfoLoader.cache.removeAllObjects()
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { n in
            // Con due riquadri la notifica arriva anche dall'altro: conta solo quella del nostro
            if let v = n.object as? PDFView, v !== model.pdfView { return }
            aggiornaCorrente()
        }
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
            .overlay { MenuPaginaMiniatura(model: model, indice: i) }
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
        .onDisappear { immagini[id] = nil }       // fuori vista non restano in memoria
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
