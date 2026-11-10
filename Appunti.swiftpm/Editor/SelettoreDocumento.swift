// Selettore dei file da aprire: usato da «+» (nuova scheda) e dalla vista doppia (documento di un riquadro).
// In alto la ricerca; sotto due sezioni: a sinistra i 7 file aperti, modificati o aggiunti da poco,
// a destra le raccolte e le cartelle di tutta l'app (si entra toccando, «‹» per tornare indietro).
// La tastiera è la nostra (AptTastiera), come nel resto dell'app.
import SwiftUI

struct SelettoreDocumento: View {
    @EnvironmentObject var store: AptStore

    let titolo: String
    /// File già aperti in una scheda (solo per segnarli nell'elenco)
    let aperti: Set<String>
    let scegli: (AptDoc) -> Void
    let annulla: () -> Void

    @State private var testo = ""
    @State private var tastiera = false
    @State private var posto: Posto?

    enum Posto: Equatable {
        case tutti
        case cartella(String)
        case raccolta(String)
    }

    private var cerca: String { testo.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            intestazione
            barraRicerca
            AptLinea()
            if cerca.isEmpty { duePannelli } else { risultati }
            if tastiera {
                AptTastiera(testo: $testo, tutto: .constant(false), titoloInvio: "Cerca",
                            onInvio: { tastiera = false },
                            onNascondi: { tastiera = false })
                    .padding(8)
            }
        }
        .background(AptTema.carta)
    }

    // MARK: Parte alta

    private var intestazione: some View {
        HStack {
            Text(titolo).font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
            Spacer()
            Button("Annulla", action: annulla).buttonStyle(AptStileSecondario())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var barraRicerca: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AptTema.testo2)
            AptCampo(testo: testo, segnaposto: "Cerca un file per nome", attivo: tastiera)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { tastiera = true }
            if !testo.isEmpty {
                Button { testo = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AptTema.testo2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancella il testo")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(AptTema.sfondo, in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous)
            .stroke(tastiera ? AptTema.accento : AptTema.linea, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Due sezioni

    private var duePannelli: some View {
        GeometryReader { geo in
            if geo.size.width >= 480 {
                HStack(spacing: 0) {
                    sezioneRecenti.frame(width: geo.size.width * 0.42)
                    AptLinea(verticale: true)
                    sezioneOrganizzazione.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    sezioneRecenti.frame(height: geo.size.height * 0.45)
                    AptLinea()
                    sezioneOrganizzazione.frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func etichetta(_ titolo: String, _ icona: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icona)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AptTema.accentoTesto)
            Text(titolo)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundColor(AptTema.testo2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    // MARK: Recenti (7)

    private var sezioneRecenti: some View {
        VStack(alignment: .leading, spacing: 0) {
            etichetta("Recenti", "clock")
            let docs = store.recentiSelettore(7)
            if docs.isEmpty {
                Text("Nessun file.").foregroundStyle(AptTema.testo2).padding(16)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(docs) { d in riga(d) }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    // MARK: Raccolte e cartelle

    @ViewBuilder private var sezioneOrganizzazione: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let p = posto {
                intestazioneDentro(p)
                dentro(p)
            } else {
                etichetta("Cartelle e raccolte", "folder")
                radice
            }
        }
    }

    private var radice: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                voce(icona: "tray.full", nome: "Tutti i documenti", conteggio: store.allDocs.count, profondita: 0) { posto = .tutti }
                let raccolte = AptColl.flatten(store.meta.collections, depth: 0)
                if !raccolte.isEmpty {
                    sottotitolo("Raccolte")
                    ForEach(raccolte, id: \.0.id) { (c, livello) in
                        voce(icona: "square.stack", nome: c.name, conteggio: store.docIDs(in: c).count, profondita: livello) { posto = .raccolta(c.id) }
                    }
                }
                let cartelle = store.flatFolderItems(store.root.children, depth: 0, orderParent: "", ignoreExpanded: true)
                if !cartelle.isEmpty {
                    sottotitolo("Cartelle")
                    ForEach(cartelle) { c in
                        voce(icona: "folder", nome: c.name, conteggio: c.count, profondita: c.depth) { posto = .cartella(c.id) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private func sottotitolo(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundColor(AptTema.testo2)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func voce(icona: String, nome: String, conteggio: Int, profondita: Int, _ vai: @escaping () -> Void) -> some View {
        Button(action: vai) {
            HStack(spacing: 10) {
                Image(systemName: icona)
                    .font(.system(size: 16))
                    .foregroundStyle(AptTema.accentoTesto)
                    .frame(width: 24)
                Text(nome).font(AptTema.corpo).foregroundColor(AptTema.testo).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(conteggio)").font(AptTema.dettaglio).foregroundStyle(AptTema.testo2).monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AptTema.testo2.opacity(0.7))
            }
            .padding(.leading, 10 + CGFloat(min(profondita, 4)) * 16)
            .padding(.trailing, 10)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Dentro una cartella o raccolta

    private func titoloPosto(_ p: Posto) -> String {
        switch p {
        case .tutti: return "Tutti i documenti"
        case .cartella(let id): return AptPath.name(id)
        case .raccolta(let id): return AptColl.find(store.meta.collections, id)?.name ?? "Raccolta"
        }
    }

    private func indietro(da p: Posto) {
        if case .cartella(let id) = p {
            let padre = AptPath.parent(id)
            posto = padre.isEmpty ? nil : .cartella(padre)
        } else {
            posto = nil
        }
    }

    private func intestazioneDentro(_ p: Posto) -> some View {
        Button { indietro(da: p) } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                Text(titoloPosto(p)).font(AptTema.corpoForte).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AptTema.accentoTesto)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Indietro")
    }

    private func dentro(_ p: Posto) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch p {
                case .tutti:
                    ForEach(store.allDocs.sorted { store.ultimoUso($0) > store.ultimoUso($1) }) { d in riga(d) }
                case .cartella(let id):
                    if let f = store.folder(id) {
                        ForEach(store.sortedFolders(f.children, parent: id)) { c in
                            voce(icona: "folder", nome: c.name, conteggio: c.docCount, profondita: 0) { posto = .cartella(c.id) }
                        }
                        ForEach(store.sortedDocs(f.docs, key: "docs:" + id)) { d in riga(d) }
                        if f.children.isEmpty && f.docs.isEmpty {
                            Text("Cartella vuota.").foregroundStyle(AptTema.testo2).padding(10)
                        }
                    }
                case .raccolta(let id):
                    if let c = AptColl.find(store.meta.collections, id) {
                        ForEach(c.children) { sc in
                            voce(icona: "square.stack", nome: sc.name, conteggio: store.docIDs(in: sc).count, profondita: 0) { posto = .raccolta(sc.id) }
                        }
                        let ids = store.docIDs(in: c)
                        let docs = store.allDocs.filter { ids.contains($0.id) }
                        ForEach(docs.sorted { store.ultimoUso($0) > store.ultimoUso($1) }) { d in riga(d) }
                        if c.children.isEmpty && docs.isEmpty {
                            Text("Raccolta vuota.").foregroundStyle(AptTema.testo2).padding(10)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    // MARK: Ricerca

    private var trovati: [AptDoc] {
        func norma(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
        let parole = norma(cerca).split(separator: " ").map(String.init)
        guard !parole.isEmpty else { return [] }
        return store.allDocs
            .filter { d in
                let tutto = norma(d.name + " " + d.folderPath)
                return parole.allSatisfy { tutto.contains($0) }
            }
            .sorted { store.ultimoUso($0) > store.ultimoUso($1) }
    }

    private var risultati: some View {
        let lista = trovati
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                etichetta(lista.isEmpty ? "Nessun risultato" : (lista.count == 1 ? "1 risultato" : "\(lista.count) risultati"), "magnifyingglass")
                ForEach(lista.prefix(80)) { d in riga(d, mostraCartella: true) }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    // MARK: Riga di un file

    private func riga(_ d: AptDoc, mostraCartella: Bool = false) -> some View {
        RigaSelettore(doc: d, aperto: aperti.contains(d.id), mostraCartella: mostraCartella) {
            tastiera = false
            scegli(d)
        }
    }
}

/// Un file nell'elenco: miniatura della prima pagina, nome, pagine e data
private struct RigaSelettore: View {
    let doc: AptDoc
    let aperto: Bool
    let mostraCartella: Bool
    let tocco: () -> Void
    @State private var info: AptDocInfo?

    var body: some View {
        Button(action: tocco) {
            HStack(spacing: 10) {
                ZStack {
                    AptTema.sfondo
                    if let img = info?.image { Image(uiImage: img).resizable().scaledToFit() }
                }
                .frame(width: 34, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AptTema.testo)
                        .lineLimit(1)
                    Text(dettaglio)
                        .font(AptTema.dettaglio)
                        .foregroundStyle(AptTema.testo2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: doc.id + "|\(doc.modDate.timeIntervalSince1970)") {
            info = await AptDocInfoLoader.load(doc)
        }
    }

    private var dettaglio: String {
        var parti: [String] = []
        if mostraCartella, !doc.folderPath.isEmpty { parti.append(doc.folderPath) }
        if let p = info?.pages { parti.append("\(p) pag") }
        parti.append(AptFormat.relative(doc.modDate))
        if aperto { parti.append("aperto") }
        return parti.joined(separator: " · ")
    }
}

extension View {
    /// Foglio alto e largo (come una pagina) per il selettore dei file
    @ViewBuilder func dimensioneSelettore() -> some View {
        if #available(iOS 18.0, *) {
            self.presentationSizing(.page).presentationDetents([.large])
        } else {
            self.presentationDetents([.large])
        }
    }
}
