// Tastiera nostra, tutta in SwiftUI. In Swift Playgrounds la tastiera di sistema non compare,
// quindi i campi di testo dell'app non usano TextField: mostrano il testo con AptCampo
// e si scrive con AptTastiera. Il testo si aggiunge e si cancella sempre in fondo (niente cursore mobile).
import SwiftUI

private enum PaginaTastiera { case lettere, simboli }

// MARK: Aspetto dei tasti

private struct AspettoTasto: ViewModifier {
    var scuro = false
    var acceso = false
    var accento = false
    var premuto = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 22))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(primo)
            .background(RoundedRectangle(cornerRadius: 8).fill(sfondo))
            .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 1)
            .contentShape(Rectangle())
    }

    private var primo: Color {
        if accento { return Color.white }
        if acceso { return Color(.systemBackground) }
        return Color.primary
    }

    private var sfondo: Color {
        if accento { return premuto ? Color.accentColor.opacity(0.7) : Color.accentColor }
        if acceso { return Color.primary }
        if premuto { return Color(.systemGray2) }
        return scuro ? Color(.systemGray3) : Color(.systemBackground)
    }
}

private struct StileTasto: ButtonStyle {
    var scuro = false
    var accento = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(AspettoTasto(scuro: scuro, accento: accento, premuto: configuration.isPressed))
    }
}

// Cancella: tenendo premuto ripete
private struct TastoCancella: View {
    let azione: () -> Void
    @State private var ripeti: Task<Void, Never>?
    @State private var premuto = false

    var body: some View {
        Image(systemName: "delete.left")
            .modifier(AspettoTasto(scuro: true, premuto: premuto))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard ripeti == nil else { return }
                        premuto = true
                        azione()
                        ripeti = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            while !Task.isCancelled {
                                azione()
                                try? await Task.sleep(nanoseconds: 70_000_000)
                            }
                        }
                    }
                    .onEnded { _ in
                        ripeti?.cancel()
                        ripeti = nil
                        premuto = false
                    }
            )
            .onDisappear {
                ripeti?.cancel()
                ripeti = nil
            }
            .accessibilityLabel("Cancella")
    }
}

// MARK: Tastiera

struct AptTastiera: View {
    @Binding var testo: String
    /// true = il testo è «selezionato»: il primo tasto lo sostituisce tutto.
    @Binding var tutto: Bool
    var titoloInvio = "Fine"
    var autoMaiuscola = false
    let onInvio: () -> Void
    var onNascondi: (() -> Void)? = nil

    @State private var pagina: PaginaTastiera = .lettere
    @State private var maiuscolo = false
    @State private var bloccato = false

    private let cifre = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let riga1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let riga2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l", "'"]
    private let riga3 = ["z", "x", "c", "v", "b", "n", "m", ",", ".", "-"]
    private let accenti = ["à", "è", "é", "ì", "ò", "ù"]
    private let sim1 = ["!", "?", ".", ",", ";", ":", "'", "\"", "(", ")"]
    private let sim2 = ["-", "_", "/", "\\", "@", "#", "&", "%", "+", "="]
    private let sim3 = ["*", "~", "€", "$", "<", ">", "[", "]", "{", "}"]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                riga(cifre)
                TastoCancella(azione: cancella).frame(width: 84)
            }
            if pagina == .lettere {
                riga(riga1).padding(.trailing, 90)
                riga(riga2).padding(.trailing, 90)
                HStack(spacing: 6) {
                    tastoMaiuscolo.frame(width: 84)
                    riga(riga3)
                }
                fondoLettere
            } else {
                riga(sim1).padding(.trailing, 90)
                riga(sim2).padding(.trailing, 90)
                riga(sim3).padding(.trailing, 90)
                fondoSimboli
            }
        }
        .padding(8)
        .background(Color(.systemGray5).ignoresSafeArea(edges: .bottom))
        .onAppear {
            if autoMaiuscola && (testo.isEmpty || tutto) { maiuscolo = true }
        }
    }

    // MARK: Righe

    private func riga(_ t: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(t, id: \.self) { k in tasto(k) }
        }
    }

    private func tasto(_ k: String) -> some View {
        Button { scrivi(aspetto(k)) } label: { Text(aspetto(k)) }
            .buttonStyle(StileTasto())
    }

    private var tastoMaiuscolo: some View {
        Image(systemName: bloccato ? "capslock.fill" : (maiuscolo ? "shift.fill" : "shift"))
            .modifier(AspettoTasto(scuro: true, acceso: maiuscolo || bloccato))
            .onTapGesture(count: 2) {
                bloccato = true
                maiuscolo = true
            }
            .onTapGesture {
                if bloccato {
                    bloccato = false
                    maiuscolo = false
                } else {
                    maiuscolo.toggle()
                }
            }
            .accessibilityLabel("Maiuscolo")
    }

    private var fondoLettere: some View {
        HStack(spacing: 6) {
            Button("#+=") { pagina = .simboli }
                .buttonStyle(StileTasto(scuro: true))
                .frame(width: 84)
            HStack(spacing: 6) {
                ForEach(accenti, id: \.self) { k in tasto(k) }
            }
            spazio
            invio
            nascondi
        }
    }

    private var fondoSimboli: some View {
        HStack(spacing: 6) {
            Button("abc") { pagina = .lettere }
                .buttonStyle(StileTasto(scuro: true))
                .frame(width: 84)
            spazio
            invio
            nascondi
        }
    }

    private var spazio: some View {
        Button { scrivi(" ") } label: {
            Text("spazio").font(.system(size: 16)).foregroundStyle(.secondary)
        }
        .buttonStyle(StileTasto())
    }

    private var invio: some View {
        Button(titoloInvio) { onInvio() }
            .buttonStyle(StileTasto(accento: true))
            .frame(width: 130)
    }

    @ViewBuilder private var nascondi: some View {
        if let chiudi = onNascondi {
            Button { chiudi() } label: { Image(systemName: "keyboard.chevron.compact.down") }
                .buttonStyle(StileTasto(scuro: true))
                .frame(width: 70)
                .accessibilityLabel("Nascondi la tastiera")
        }
    }

    // MARK: Logica

    private func aspetto(_ k: String) -> String {
        pagina == .lettere && (maiuscolo || bloccato) ? k.uppercased() : k
    }

    private func scrivi(_ s: String) {
        if tutto {
            testo = ""
            tutto = false
        }
        testo += s
        if maiuscolo && !bloccato { maiuscolo = false }
    }

    private func cancella() {
        if tutto {
            testo = ""
            tutto = false
        } else if !testo.isEmpty {
            testo.removeLast()
        }
        if autoMaiuscola && testo.isEmpty { maiuscolo = true }
    }
}

// MARK: Campo di testo finto (si scrive con AptTastiera)

struct AptCampo: View {
    let testo: String
    var segnaposto = "Nome"
    var tutto = false
    var attivo = true

    var body: some View {
        HStack(spacing: 0) {
            if testo.isEmpty {
                if attivo { AptCursore() }
                Text(segnaposto).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(testo)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, tutto ? 3 : 0)
                    .background(tutto ? Color.accentColor.opacity(0.3) : Color.clear)
                if attivo && !tutto { AptCursore() }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct AptCursore: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 22)
                .opacity(Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
        .frame(width: 2, height: 22)
    }
}

// MARK: Finestra «Rinomina» con la nostra tastiera

struct AptRinomina: View {
    let titolo: String
    let salva: (String) -> Void
    let annulla: () -> Void
    @State private var testo: String
    @State private var tutto = true

    init(titolo: String, nome: String, salva: @escaping (String) -> Void, annulla: @escaping () -> Void) {
        self.titolo = titolo
        self.salva = salva
        self.annulla = annulla
        _testo = State(initialValue: nome)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(titolo).font(.headline)
                HStack {
                    Button("Annulla") { annulla() }
                    Spacer()
                    Button("Salva") { salva(testo) }.fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            AptCampo(testo: testo, tutto: tutto)
                .font(.system(size: 20))
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            AptTastiera(testo: $testo, tutto: $tutto, titoloInvio: "Salva", autoMaiuscola: true,
                        onInvio: { salva(testo) })
        }
        .background(Color(.systemBackground))
    }
}
