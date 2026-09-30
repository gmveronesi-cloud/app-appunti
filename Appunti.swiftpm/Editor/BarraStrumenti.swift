// Barra strumenti dell'Editor: strumenti multipli (ognuno con colore, spessore e stile propri),
// pallini colore, annulla/ripeti, modifica della barra. Fissa (alto/basso/sinistra) o flottante.
import SwiftUI

struct BarraStrumenti: View {
    @ObservedObject var model: NotesModel
    var verticale = false
    var scorrevole = true

    @AppStorage("barraGrande") private var grande = false
    @AppStorage("barraNomi") private var nomi = false
    @AppStorage("barraUndo") private var undoFissi = true

    @State private var pannello: UUID?
    @State private var pallinoAperto: Int?
    @State private var mostraModifica = false

    private var lato: CGFloat { grande ? 56 : 44 }

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
            ForEach(Array(model.pallini.enumerated()), id: \.offset) { i, c in pallino(i, c) }
            if undoFissi {
                separatore
                Button { model.annulla() } label: { icona("arrow.uturn.backward") }
                    .accessibilityLabel("Annulla")
                Button { model.ripeti() } label: { icona("arrow.uturn.forward") }
                    .accessibilityLabel("Ripeti")
            }
            separatore
            Button { mostraModifica = true } label: { icona("slider.horizontal.3") }
                .accessibilityLabel("Modifica la barra")
                .popover(isPresented: $mostraModifica) { ModificaBarra(model: model) }
        }
        .padding(.horizontal, verticale ? 4 : 10)
        .padding(.vertical, verticale ? 10 : 4)
    }

    private var separatore: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: verticale ? 26 : 1, height: verticale ? 1 : 26)
            .padding(verticale ? .vertical : .horizontal, 4)
    }

    private func icona(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(grande ? .title2 : .title3)
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
                    .font(grande ? .title2 : .title3)
                    .foregroundStyle(s.tipo.haColore ? s.colore.color : Color.primary)
                    .shadow(color: .black.opacity(0.3), radius: 0.6)
                    .frame(width: lato, height: nomi ? lato - 14 : lato)
                if nomi {
                    Text(s.nome).font(.caption2).foregroundStyle(.primary).lineLimit(1)
                }
            }
            .frame(minWidth: lato, minHeight: lato)
            .background(
                attivo ? Color.accentColor.opacity(0.2) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.nome)
        .popover(isPresented: Binding(
            get: { pannello == s.id },
            set: { if !$0 && pannello == s.id { pannello = nil } }
        )) {
            PannelloStrumento(model: model, id: s.id)
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
                        scelto ? Color.accentColor : Color.secondary.opacity(0.45),
                        lineWidth: scelto ? 3 : 1
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
                    get: { model.pallini.indices.contains(i) ? model.pallini[i].color : Color.gray },
                    set: { model.cambiaPallino(i, ColoreSalvato($0)) }
                ),
                supportsOpacity: false
            )
            .padding(20)
            .frame(width: 300)
        }
    }
}

// Impostazioni del singolo strumento: stile, spessore (parte dal minimo), trasparenza, gomma.
struct PannelloStrumento: View {
    @ObservedObject var model: NotesModel
    let id: UUID

    private var strumento: Strumento? { model.strumenti.first { $0.id == id } }

    var body: some View {
        if let s = strumento {
            VStack(alignment: .leading, spacing: 16) {
                Text(s.nome).font(.headline)

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

                if !(s.tipo == .gomma && s.gommaIntera) {
                    VStack(alignment: .leading) {
                        Text("\(s.tipo == .gomma ? "Dimensione" : "Spessore"): \(String(format: "%g", s.spessore))")
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

    private func lega<T>(_ percorso: WritableKeyPath<Strumento, T>) -> Binding<T> {
        Binding(
            get: { model.strumenti.first { $0.id == id }![keyPath: percorso] },
            set: { v in model.modifica(id) { $0[keyPath: percorso] = v } }
        )
    }
}

// Aggiungere, togliere e riordinare gli strumenti; numero dei pallini colore.
struct ModificaBarra: View {
    @ObservedObject var model: NotesModel

    private let inArrivo = ["Lazo", "Penna screenshot", "Immagine o PDF", "Testo", "Post-it"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Strumenti nella barra").font(.headline).padding([.horizontal, .top], 20)

            List {
                ForEach(model.strumenti) { s in
                    HStack {
                        Image(systemName: s.tipo.icona)
                            .foregroundStyle(s.tipo.haColore ? s.colore.color : Color.primary)
                            .frame(width: 28)
                        Text(dettaglio(s))
                    }
                }
                .onMove { model.sposta(from: $0, to: $1) }
                .onDelete { model.rimuovi(at: $0) }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(height: CGFloat(min(max(model.strumenti.count, 1), 7)) * 50 + 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aggiungi alla barra").font(.headline).padding(.bottom, 4)
                    ForEach(TipoStrumento.allCases) { t in
                        Button { model.aggiungi(t) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: t.icona).frame(width: 28)
                                Text(t.nome).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(inArrivo, id: \.self) { n in
                        HStack {
                            Text(n)
                            Spacer()
                            Text("in arrivo").font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    }
                    Divider().padding(.vertical, 8)
                    Stepper(
                        "Pallini colore: \(model.pallini.count)",
                        value: Binding(get: { model.pallini.count }, set: { model.impostaNumeroPallini($0) }),
                        in: 2...8
                    )
                }
                .padding(20)
            }
        }
        .frame(width: 360, height: 620)
    }

    private func dettaglio(_ s: Strumento) -> String {
        switch s.tipo {
        case .penna, .matita: return "\(s.nome) · \(s.stile.nome) · \(String(format: "%g", s.spessore))"
        case .evidenziatore: return "\(s.nome) · \(String(format: "%g", s.spessore))"
        case .gomma: return "\(s.nome) · \(s.gommaIntera ? "tratto intero" : "solo pixel")"
        }
    }
}

// Versione flottante: capsula con maniglia, si trascina dove serve, si riduce a un pulsante tondo.
// Posizione e stato ridotto sono ricordati.
struct BarraFlottante: View {
    @ObservedObject var model: NotesModel
    let area: CGSize

    @AppStorage("barraOri") private var ori = "h"
    @AppStorage("barraFlotX") private var x: Double = 0
    @AppStorage("barraFlotY") private var y: Double = 0
    @AppStorage("barraFlotRidotta") private var ridotta = false
    @GestureState private var trascinamento: CGSize = .zero

    private var verticale: Bool { ori == "v" }

    // La barra resta sempre dentro lo schermo
    private func limita(_ w: Double, _ h: Double) -> (Double, Double) {
        let mx = max(0, Double(area.width) / 2 - 30)
        let my = max(0, Double(area.height) - 100)
        return (min(max(w, -mx), mx), min(max(h, -my), 24))
    }

    private var spostamento: CGSize {
        let (a, b) = limita(x + Double(trascinamento.width), y + Double(trascinamento.height))
        return CGSize(width: a, height: b)
    }

    private var trascina: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($trascinamento) { valore, stato, _ in stato = valore.translation }
            .onEnded { valore in
                let (a, b) = limita(x + Double(valore.translation.width), y + Double(valore.translation.height))
                x = a
                y = b
            }
    }

    var body: some View {
        Group {
            if ridotta {
                Image(systemName: model.corrente?.tipo.icona ?? "pencil.tip")
                    .font(.title2)
                    .foregroundStyle(model.corrente.map { $0.tipo.haColore ? $0.colore.color : Color.primary } ?? Color.primary)
                    .frame(width: 56, height: 56)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 8, y: 3)
                    .contentShape(Circle())
                    .onTapGesture { ridotta = false }
                    .gesture(trascina)
                    .accessibilityLabel("Apri la barra strumenti")
                    .accessibilityAddTraits(.isButton)
            } else {
                let disposizione = verticale ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                disposizione {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .gesture(trascina)
                    BarraStrumenti(model: model, verticale: verticale, scorrevole: false)
                    Button { ridotta = true } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Riduci la barra")
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: verticale ? 28 : 40))
                .shadow(radius: 8, y: 3)
            }
        }
        .offset(spostamento)
        .padding(.bottom, 24)
    }
}
