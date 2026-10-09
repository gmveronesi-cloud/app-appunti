// Barra strumenti dell'Editor: strumenti multipli (ognuno con colore, spessore e stile propri),
// pallini colore, annulla/ripeti, modifica della barra. Fissa (alto/basso/sinistra) o flottante.
import SwiftUI

struct BarraStrumenti: View {
    @Environment(\.colorScheme) private var schema
    @ObservedObject var model: NotesModel
    var verticale = false
    var scorrevole = true

    @AppStorage("barraGrande") private var grande = false
    @AppStorage("barraNomi") private var nomi = false
    @AppStorage("barraUndo") private var undoFissi = true

    @State private var pannello: UUID?
    @State private var pallinoAperto: Int?
    @State private var mostraModifica = false
    @State private var mostraOrologio = false
    @ObservedObject private var orologio = OrologioModello.condiviso

    private var lato: CGFloat { grande ? 50 : 40 }

    private var layout: AnyLayout {
        verticale ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
    }

    var body: some View {
        if scorrevole {
            ScrollView(verticale ? .vertical : .horizontal, showsIndicators: false) { contenuto }
        } else {
            contenuto
        }
    }

    private var contenuto: some View {
        layout {
            ForEach(model.strumenti) { s in bottone(s) }
            separatore
            ForEach(Array(model.palliniAttivi.enumerated()), id: \.offset) { i, c in pallino(i, c) }
            if undoFissi {
                separatore
                Button { model.annulla() } label: { icona("arrow.uturn.backward") }
                    .disabled(!model.puoAnnullare)
                    .opacity(model.puoAnnullare ? 1 : 0.35)
                    .accessibilityLabel("Annulla")
                Button { model.ripeti() } label: { icona("arrow.uturn.forward") }
                    .disabled(!model.puoRipetere)
                    .opacity(model.puoRipetere ? 1 : 0.35)
                    .accessibilityLabel("Ripeti")
            }
            separatore
            Button { mostraOrologio = true } label: {
                Image(systemName: orologio.attivo ? "clock.fill" : "clock")
                    .font(.system(size: grande ? 20 : 18, weight: .regular))
                    .foregroundStyle(orologio.attivo ? AptTema.accentoTesto : AptTema.testo2)
                    .frame(width: lato, height: lato)
                    .background(
                        orologio.attivo ? AptTema.accentoTenue : Color.clear,
                        in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cronometro o timer")
            .popover(isPresented: $mostraOrologio) {
                PannelloOrologio(chiudi: { mostraOrologio = false }).aptPannello()
            }
            Button { mostraModifica = true } label: { icona("slider.horizontal.3") }
                .accessibilityLabel("Modifica la barra")
                .popover(isPresented: $mostraModifica) { ModificaBarra(model: model).aptPannello() }
        }
        .padding(.horizontal, verticale ? 4 : 10)
        .padding(.vertical, verticale ? 10 : 4)
    }

    private var separatore: some View {
        Rectangle()
            .fill(AptTema.linea)
            .frame(width: verticale ? 26 : 1, height: verticale ? 1 : 26)
            .padding(verticale ? .vertical : .horizontal, 4)
    }

    private func icona(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.system(size: grande ? 20 : 18, weight: .regular))
            .foregroundStyle(AptTema.testo2)
            .frame(width: lato, height: lato)
    }

    // Un tocco sullo strumento lo attiva; un secondo tocco apre le sue impostazioni.
    private func bottone(_ s: Strumento) -> some View {
        let attivo = model.corrente?.id == s.id
        return Button {
            if attivo { pannello = s.id } else { model.seleziona(s.id) }
        } label: {
            VStack(spacing: 0) {
                Image(systemName: s.tipo.icona)
                    .font(.system(size: grande ? 20 : 18, weight: .regular))
                    .foregroundStyle(s.tipo.haColore ? s.colore.perInterfaccia(schema) : (attivo ? AptTema.accentoTesto : AptTema.testo2))
                    .frame(width: lato, height: nomi ? lato - 14 : lato)
                if nomi {
                    Text(s.nome).font(.system(size: 11)).foregroundStyle(AptTema.testo2).lineLimit(1)
                }
            }
            .frame(minWidth: lato, minHeight: lato)
            .background(
                attivo ? AptTema.accentoTenue : Color.clear,
                in: RoundedRectangle(cornerRadius: AptTema.raggioS, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.nome)
        .popover(isPresented: Binding(
            get: { pannello == s.id },
            set: { if !$0 && pannello == s.id { pannello = nil } }
        )) {
            PannelloStrumento(model: model, id: s.id).aptPannello()
        }
    }

    // Pallino colore: un tocco applica il colore allo strumento attivo;
    // un tocco su quello già selezionato apre il selettore colori per cambiarlo.
    private func pallino(_ i: Int, _ c: ColoreSalvato) -> some View {
        let scelto = model.corrente.map { $0.tipo.haColore && $0.colore.simile(a: c) } ?? false
        return Button {
            if scelto { pallinoAperto = i } else { model.scegliColore(c) }
        } label: {
            Circle()
                .fill(c.color)
                .frame(width: lato * 0.5, height: lato * 0.5)
                .overlay(
                    Circle().strokeBorder(
                        scelto ? AptTema.accento : (schema == .dark && c.luminosita < 0.4 ? AptTema.testo2 : AptTema.linea),
                        lineWidth: scelto ? 2.5 : 1
                    )
                )
                .frame(width: lato * 0.8, height: lato * 0.8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colore \(i + 1)")
        .popover(isPresented: Binding(
            get: { pallinoAperto == i },
            set: { if !$0 && pallinoAperto == i { pallinoAperto = nil } }
        )) {
            ColorPicker(
                "Colore del pallino",
                selection: Binding(
                    get: { model.palliniAttivi.indices.contains(i) ? model.palliniAttivi[i].color : Color.gray },
                    set: { model.cambiaPallino(i, ColoreSalvato($0)) }
                ),
                supportsOpacity: false
            )
            .padding(20)
            .frame(width: 300)
            .aptPannello()
        }
    }
}

// Impostazioni del singolo strumento: stile, spessore (parte dal minimo), trasparenza, gomma.
struct PannelloStrumento: View {
    @ObservedObject var model: NotesModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    private var strumento: Strumento? { model.strumenti.first { $0.id == id } }

    var body: some View {
        if let s = strumento {
            VStack(alignment: .leading, spacing: 16) {
                Text(s.nome).font(AptTema.titoloMedio).foregroundColor(AptTema.testo)

                if s.tipo == .immagine {
                    VStack(alignment: .leading, spacing: 4) {
                        origine("Dalle Foto", "photo", .foto)
                        origine("Da File", "folder", .file)
                        origine("PDF o documento di testo", "doc.richtext", .documento)
                        origine("Scansiona documento", "doc.viewfinder", .scansione)
                        origine("Aggiungi PDF al documento", "doc.badge.plus", .aggiungiPDF)
                    }
                }

                if s.tipo == .gomma {
                    Picker("Cancella", selection: lega(\.gommaIntera)) {
                        Text("Tratto intero").tag(true)
                        Text("Solo pixel").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                if !s.tipo.stili.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Stile")
                        Picker("Stile", selection: lega(\.stile)) {
                            ForEach(s.tipo.stili, id: \.self) { Text($0.nome).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if s.tipo == .catturaSchermo {
                    Picker("Selezione", selection: lega(\.catturaRiquadro)) {
                        Text("Mano libera").tag(false)
                        Text("Riquadro").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if s.tipo == .lazo {
                    Picker("Selezione", selection: lega(\.lazoRiquadro)) {
                        Text("Mano libera").tag(false)
                        Text("Riquadro").tag(true)
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seleziona")
                        filtro("Penne", .penna, s)
                        filtro("Evidenziatori", .evidenziatore, s)
                        filtro("Matite", .matita, s)
                        Toggle("Immagini", isOn: lega(\.lazoImmagini))
                        Toggle("Testi", isOn: lega(\.lazoTesti))
                    }
                }

                if s.tipo.haSpessore && !(s.tipo == .gomma && s.gommaIntera) {
                    VStack(alignment: .leading) {
                        Text("\(s.tipo == .gomma || s.tipo == .testo ? "Dimensione" : "Spessore"): \(String(format: "%g", s.spessore))")
                        Slider(value: lega(\.spessore), in: s.tipo.intervalloSpessore, step: s.tipo.passoSpessore)
                    }
                }

                if s.tipo == .evidenziatore {
                    VStack(alignment: .leading) {
                        Text("Trasparenza: \(Int((s.trasparenza * 100).rounded()))%")
                        Slider(value: lega(\.trasparenza), in: 0...0.85, step: 0.05)
                    }
                }

            }
            .padding(20)
            .frame(width: 320)
        } else {
            Text("Strumento rimosso").padding(20)
        }
    }

    private func origine(_ titolo: String, _ icona: String, _ o: OrigineImmagine) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.avvia(o) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icona).frame(width: 26)
                Text(titolo)
                Spacer()
            }
            .foregroundStyle(AptTema.testo)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filtro(_ nome: String, _ tipo: TipoStrumento, _ s: Strumento) -> some View {
        Toggle(nome, isOn: Binding(
            get: { model.strumenti.first { $0.id == id }?.lazoFiltri.contains(tipo) ?? false },
            set: { acceso in
                model.modifica(id) {
                    $0.lazoFiltri.removeAll { $0 == tipo }
                    if acceso { $0.lazoFiltri.append(tipo) }
                }
            }
        ))
    }

    private func lega<T>(_ percorso: WritableKeyPath<Strumento, T>) -> Binding<T> {
        Binding(
            get: { model.strumenti.first { $0.id == id }![keyPath: percorso] },
            set: { v in model.modifica(id) { $0[keyPath: percorso] = v } }
        )
    }
}

// Aggiungere, togliere e riordinare gli strumenti; numero dei pallini colore.
struct ModificaBarra: View {
    @Environment(\.colorScheme) private var schema
    @ObservedObject var model: NotesModel

    private let altezzaRiga: CGFloat = 46

    private func titolo(_ t: String) -> some View {
        Text(t).font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metà alta: strumenti già nella barra (si riordinano e si tolgono)
            titolo("Nella barra")
            List {
                ForEach(model.strumenti) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.tipo.icona)
                            .foregroundStyle(s.tipo.haColore ? s.colore.perInterfaccia(schema) : AptTema.testo)
                            .frame(width: 28)
                        Text(dettaglio(s)).foregroundStyle(AptTema.testo).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: altezzaRiga)
                }
                .onMove { model.sposta(from: $0, to: $1) }
                .onDelete { model.rimuovi(at: $0) }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(maxHeight: .infinity)

            AptLinea()

            // Metà bassa: strumenti da aggiungere, stesse dimensioni di riga e di carattere
            titolo("Da aggiungere")
            List {
                ForEach(TipoStrumento.allCases) { t in
                    Button { model.aggiungi(t) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: t.icona).foregroundStyle(AptTema.testo).frame(width: 28)
                            Text(t.nome).foregroundStyle(AptTema.testo).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle").foregroundStyle(AptTema.accentoTesto)
                        }
                        .frame(height: altezzaRiga)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)

            AptLinea()

            Stepper(
                "Pallini colore: \(model.pallini.count)",
                value: Binding(get: { model.pallini.count }, set: { model.impostaNumeroPallini($0) }),
                in: 2...8
            )
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 360, height: 680)
    }

    private func dettaglio(_ s: Strumento) -> String {
        switch s.tipo {
        case .penna, .matita: return "\(s.nome) · \(s.stile.nome) · \(String(format: "%g", s.spessore))"
        case .evidenziatore: return "\(s.nome) · \(String(format: "%g", s.spessore))"
        case .gomma: return "\(s.nome) · \(s.gommaIntera ? "tratto intero" : "solo pixel")"
        case .lazo: return "\(s.nome) · \(s.lazoRiquadro ? "riquadro" : "mano libera")"
        case .immagine: return s.nome
        case .catturaSchermo: return "\(s.nome) · \(s.catturaRiquadro ? "riquadro" : "mano libera")"
        case .testo: return "\(s.nome) · \(String(format: "%g", s.spessore))"
        }
    }
}

// Versione flottante: capsula con maniglia, si trascina dove serve, si riduce a un pulsante tondo.
// Posizione (una per ogni orientamento) e stato ridotto sono ricordati; la posizione è una frazione dello spazio
// disponibile, quindi resta nello stesso punto anche ruotando l'iPad.
struct BarraFlottante: View {
    @Environment(\.colorScheme) private var schema
    @ObservedObject var model: NotesModel
    let area: CGSize

    @AppStorage("barraOri") private var ori = "h"
    @AppStorage("barraFlotFXh") private var fxh: Double = 0
    @AppStorage("barraFlotFYh") private var fyh: Double = 0
    @AppStorage("barraFlotFXv") private var fxv: Double = 0
    @AppStorage("barraFlotFYv") private var fyv: Double = 0
    @AppStorage("barraFlotRidotta") private var ridotta = false
    @GestureState private var trascinamento: CGSize = .zero

    private var verticale: Bool { ori == "v" }

    // Spazio in cui può stare il centro della barra (rispetto alla posizione di partenza, in basso al centro)
    private var meta: Double { max(1, Double(area.width) / 2 - 30) }
    private var altezzaUtile: Double { max(1, Double(area.height) - 100) }
    private let sopraMax: Double = 24

    private var fx: Double { verticale ? fxv : fxh }
    private var fy: Double { verticale ? fyv : fyh }

    private func limita(_ w: Double, _ h: Double) -> (Double, Double) {
        (min(max(w, -meta), meta), min(max(h, -altezzaUtile), sopraMax))
    }

    private var spostamento: CGSize {
        let (a, b) = limita(fx * meta + Double(trascinamento.width), fy * altezzaUtile + Double(trascinamento.height))
        return CGSize(width: a, height: b)
    }

    // Il trascinamento si misura nello spazio dello schermo: la barra si muove con il dito e, misurato nel suo spazio,
    // lo spostamento sbagliava e la posizione finale non era quella lasciata.
    private var trascina: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($trascinamento) { valore, stato, _ in stato = valore.translation }
            .onEnded { valore in
                let (a, b) = limita(fx * meta + Double(valore.translation.width), fy * altezzaUtile + Double(valore.translation.height))
                if verticale { fxv = a / meta; fyv = b / altezzaUtile } else { fxh = a / meta; fyh = b / altezzaUtile }
            }
    }

    var body: some View {
        Group {
            if ridotta {
                Image(systemName: model.corrente?.tipo.icona ?? "pencil.tip")
                    .font(.system(size: 22))
                    .foregroundStyle(model.corrente.map { $0.tipo.haColore ? $0.colore.perInterfaccia(schema) : AptTema.testo2 } ?? AptTema.testo2)
                    .frame(width: 56, height: 56)
                    .background(AptTema.carta, in: Circle())
                    .overlay(Circle().stroke(AptTema.linea, lineWidth: 1))
                    .shadow(color: AptTema.ombraColore, radius: AptTema.ombraRaggio, y: AptTema.ombraY)
                    .contentShape(Circle())
                    .onTapGesture { ridotta = false }
                    .gesture(trascina)
                    .accessibilityLabel("Apri la barra strumenti")
                    .accessibilityAddTraits(.isButton)
            } else {
                let disposizione = verticale ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                disposizione {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(AptTema.testo2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .gesture(trascina)
                    BarraStrumenti(model: model, verticale: verticale, scorrevole: false)
                    Button { ridotta = true } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(AptTema.testo2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Riduci la barra")
                }
                .background(AptTema.carta, in: RoundedRectangle(cornerRadius: verticale ? 28 : 40, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: verticale ? 28 : 40, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
                .shadow(color: AptTema.ombraColore, radius: AptTema.ombraRaggio, y: AptTema.ombraY)
            }
        }
        .offset(spostamento)
        .padding(.bottom, 24)
    }
}

extension View {
    /// Barra strumenti fissa: capsula carta con bordo sottile e ombra morbida, staccata dai bordi.
    func aptCapsulaBarra(verticale: Bool = false) -> some View {
        self
            .background(AptTema.carta, in: RoundedRectangle(cornerRadius: verticale ? 26 : 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: verticale ? 26 : 30, style: .continuous).stroke(AptTema.linea, lineWidth: 1))
            .shadow(color: AptTema.ombraColore, radius: AptTema.ombraRaggio, y: AptTema.ombraY)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }
}
