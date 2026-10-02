// Cronometro e timer: riquadro mobile sopra tutte le schermate (Libreria ed Editor).
// Lo stato sta in un oggetto condiviso (OrologioModello.condiviso): così il riquadro resta uguale
// anche aprendo o chiudendo l'Editor. Il riquadro si trascina, si ingrandisce dall'angolo e, spinto
// fuori dallo schermo, lascia una linguetta sul bordo. Niente tastiera di sistema: durata con
// pulsanti e contatori.
import SwiftUI
import UserNotifications
import UIKit

enum ModoOrologio: String {
    case cronometro, timer
}

enum LatoOrologio {
    case sinistra, destra, alto, basso
}

private let idNotificaOrologio = "orologio-timer"

@MainActor
final class OrologioModello: ObservableObject {
    static let condiviso = OrologioModello()

    // Scelte nel pannello, prima di avviare
    @Published var sceltaModo: ModoOrologio = .cronometro
    @Published var sceltaMinuti = 10
    @Published var sceltaSecondi = 0

    // Stato del conteggio
    @Published private(set) var attivo = false
    @Published private(set) var inCorso = false
    @Published private(set) var finito = false
    @Published private(set) var modo: ModoOrologio = .cronometro
    private(set) var totale: TimeInterval = 0
    private var base: TimeInterval = 0
    private var partenza: Date?

    // Aspetto e posizione (secondi e dimensione si ricordano; la posizione no)
    @Published var mostraSecondi: Bool {
        didSet { UserDefaults.standard.set(mostraSecondi, forKey: "orologioSecondi") }
    }
    @Published var scala: CGFloat {
        didSet { UserDefaults.standard.set(Double(scala), forKey: "orologioScala") }
    }
    @Published var origine: CGPoint?            // angolo in alto a sinistra del riquadro
    @Published var agganciato: LatoOrologio?    // se non nil: riquadro fuori schermo, resta la linguetta

    private init() {
        let d = UserDefaults.standard
        mostraSecondi = d.object(forKey: "orologioSecondi") as? Bool ?? true
        let s = d.double(forKey: "orologioScala")
        scala = s >= 0.7 && s <= 2.6 ? CGFloat(s) : 1
    }

    // MARK: Tempo

    func trascorso(_ adesso: Date = Date()) -> TimeInterval {
        base + (inCorso ? adesso.timeIntervalSince(partenza ?? adesso) : 0)
    }

    func rimanente(_ adesso: Date = Date()) -> TimeInterval {
        max(0, totale - trascorso(adesso))
    }

    /// Tempo da mostrare: il timer conta all'indietro (arrotondato per eccesso), il cronometro in avanti.
    func testo(_ adesso: Date = Date()) -> String {
        if modo == .timer { return formato(rimanente(adesso), perEccesso: true) }
        return formato(trascorso(adesso), perEccesso: false)
    }

    private func formato(_ t: TimeInterval, perEccesso: Bool) -> String {
        let t = max(0, t)
        if !mostraSecondi {
            let m = Int(perEccesso ? ceil(t / 60) : floor(t / 60))
            let h = m / 60
            return h > 0 ? "\(h) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
        }
        let s = Int(perEccesso ? ceil(t) : floor(t))
        let h = s / 3600
        let m = (s % 3600) / 60
        return (h > 0 ? "\(h):" : "") + String(format: "%02d:%02d", m, s % 60)
    }

    // MARK: Azioni

    /// Avvia con le scelte del pannello. Torna false se il timer non ha una durata.
    @discardableResult
    func avvia() -> Bool {
        let durata = TimeInterval(sceltaMinuti * 60 + sceltaSecondi)
        if sceltaModo == .timer && durata <= 0 { return false }
        modo = sceltaModo
        totale = sceltaModo == .timer ? durata : 0
        base = 0
        partenza = Date()
        inCorso = true
        finito = false
        attivo = true
        agganciato = nil
        programmaNotifica()
        return true
    }

    func pausaORiprendi() {
        guard attivo, !finito else { return }
        if inCorso {
            base += Date().timeIntervalSince(partenza ?? Date())
            partenza = nil
            inCorso = false
            cancellaNotifica()
        } else {
            partenza = Date()
            inCorso = true
            programmaNotifica()
        }
    }

    func chiudi() {
        cancellaNotifica()
        attivo = false
        inCorso = false
        finito = false
        partenza = nil
        base = 0
        agganciato = nil
    }

    /// Riporta il riquadro in vista nella posizione di partenza.
    func richiama() {
        agganciato = nil
        origine = nil
    }

    /// Chiamato di continuo dal riquadro: segna la fine del timer.
    func controlla() {
        guard attivo, modo == .timer, inCorso, !finito else { return }
        if trascorso() >= totale {
            base = totale
            partenza = nil
            inCorso = false
            finito = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Notifica (suona anche se l'app è in secondo piano)

    private func programmaNotifica() {
        guard modo == .timer else { return }
        let resto = rimanente()
        guard resto > 0 else { return }
        let centro = UNUserNotificationCenter.current()
        centro.requestAuthorization(options: [.alert, .sound]) { concesso, _ in
            guard concesso else { return }
            let contenuto = UNMutableNotificationContent()
            contenuto.title = "Timer scaduto"
            contenuto.sound = .default
            let richiesta = UNNotificationRequest(
                identifier: idNotificaOrologio,
                content: contenuto,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: resto, repeats: false)
            )
            centro.add(richiesta)
        }
    }

    private func cancellaNotifica() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [idNotificaOrologio])
    }
}

// MARK: - Riquadro mobile

private struct MisuraOrologio: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct OrologioRiquadro: View {
    @ObservedObject private var o = OrologioModello.condiviso
    @State private var misura = CGSize(width: 200, height: 56)
    @State private var inizioOrigine: CGPoint?
    @State private var inizioScala: CGFloat?
    private let controllo = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if o.attivo {
                    if let lato = o.agganciato {
                        linguetta(lato, geo.size)
                    } else {
                        riquadro(geo.size)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onReceive(controllo) { _ in o.controlla() }
    }

    // MARK: Riquadro

    private func posizione(_ area: CGSize) -> CGPoint {
        o.origine ?? CGPoint(x: max(6, area.width - misura.width - 14), y: 54)
    }

    private func limita(_ p: CGPoint, _ area: CGSize, libero: Bool) -> CGPoint {
        let w = misura.width, h = misura.height
        if libero {
            return CGPoint(x: min(max(p.x, -w * 0.85), area.width - w * 0.15),
                           y: min(max(p.y, -h * 0.85), area.height - h * 0.15))
        }
        return CGPoint(x: min(max(p.x, 6), max(6, area.width - w - 6)),
                       y: min(max(p.y, 6), max(6, area.height - h - 6)))
    }

    private func riquadro(_ area: CGSize) -> some View {
        let k = o.scala
        let p = posizione(area)
        return TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            contenuto(ctx.date, k)
        }
        .background(
            RoundedRectangle(cornerRadius: 18 * min(k, 1.4), style: .continuous)
                .fill(o.finito ? AptTema.accentoTenue : AptTema.carta)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18 * min(k, 1.4), style: .continuous)
                .stroke(o.finito ? AptTema.accento : AptTema.linea, lineWidth: 1)
        )
        .shadow(color: AptTema.ombraColore, radius: AptTema.ombraRaggio, y: AptTema.ombraY)
        .overlay(alignment: .bottomTrailing) { maniglia(area) }
        .background(
            GeometryReader { g in Color.clear.preference(key: MisuraOrologio.self, value: g.size) }
        )
        .onPreferenceChange(MisuraOrologio.self) { if $0 != .zero { misura = $0 } }
        .offset(x: p.x, y: p.y)
        .gesture(trascina(area))
    }

    private func contenuto(_ adesso: Date, _ k: CGFloat) -> some View {
        let lato = max(32, 30 * k)
        return VStack(spacing: 0) {
            HStack(spacing: 6 * k) {
                Text(o.testo(adesso))
                    .font(Font.system(size: 22 * k, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(o.finito ? AptTema.accentoScuro : AptTema.testo)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 4 * k)
                Button { o.pausaORiprendi() } label: {
                    Image(systemName: o.inCorso ? "pause.fill" : "play.fill")
                        .font(.system(size: 15 * k))
                        .frame(width: lato, height: lato)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(o.finito)
                .opacity(o.finito ? 0.35 : 1)
                .accessibilityLabel(o.inCorso ? "Pausa" : "Riprendi")
                Button { o.mostraSecondi.toggle() } label: {
                    Text("s")
                        .font(.system(size: 16 * k, weight: .heavy))
                        .strikethrough(!o.mostraSecondi)
                        .opacity(o.mostraSecondi ? 1 : 0.55)
                        .frame(width: lato, height: lato)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mostra o nascondi i secondi")
                Button { o.chiudi() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14 * k, weight: .semibold))
                        .frame(width: lato, height: lato)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi")
            }
            .foregroundStyle(o.finito ? AptTema.accentoScuro : AptTema.testo2)
        }
        .padding(.horizontal, 14 * k)
        .padding(.vertical, 8 * k)
        .overlay(alignment: .bottom) {
            // Avanzamento del timer: linea sottile sul bordo basso, non aggiunge altezza al riquadro
            if o.modo == .timer {
                GeometryReader { g in
                    let quota = o.totale > 0 ? CGFloat(o.rimanente(adesso) / o.totale) : 0
                    Capsule().fill(AptTema.accento)
                        .frame(width: max(0, (g.size.width - 28 * k) * quota), height: 3 * k)
                        .position(x: 14 * k + max(0, (g.size.width - 28 * k) * quota) / 2, y: g.size.height - 3 * k)
                }
            }
        }
    }

    // MARK: Trascinamento, ingrandimento, linguetta

    private func trascina(_ area: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                let i = inizioOrigine ?? posizione(area)
                inizioOrigine = i
                o.origine = limita(CGPoint(x: i.x + v.translation.width, y: i.y + v.translation.height),
                                   area, libero: true)
            }
            .onEnded { _ in
                inizioOrigine = nil
                finisciTrascinamento(area)
            }
    }

    private func finisciTrascinamento(_ area: CGSize) {
        let p = posizione(area)
        let cx = p.x + misura.width / 2
        let cy = p.y + misura.height / 2
        if cx < 0 { o.agganciato = .sinistra }
        else if cx > area.width { o.agganciato = .destra }
        else if cy < 0 { o.agganciato = .alto }
        else if cy > area.height { o.agganciato = .basso }
        else { o.origine = limita(p, area, libero: false) }
    }

    private func maniglia(_ area: CGSize) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AptTema.testo2.opacity(0.6))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let k0 = inizioScala ?? o.scala
                        inizioScala = k0
                        let d = (v.translation.width + v.translation.height) / 2
                        o.scala = min(2.6, max(0.7, k0 + d / 110))
                    }
                    .onEnded { _ in
                        inizioScala = nil
                        o.origine = limita(posizione(area), area, libero: false)
                    }
            )
            .accessibilityLabel("Ingrandisci o rimpicciolisci")
    }

    private func linguetta(_ lato: LatoOrologio, _ area: CGSize) -> some View {
        let largo: CGFloat = 30
        let lungo: CGFloat = 58
        let p = o.origine ?? .zero
        let orizzontale = lato == .alto || lato == .basso
        let w = orizzontale ? lungo : largo
        let h = orizzontale ? largo : lungo
        var x: CGFloat
        var y: CGFloat
        switch lato {
        case .sinistra:
            x = 0
            y = p.y + misura.height / 2 - lungo / 2
        case .destra:
            x = area.width - largo
            y = p.y + misura.height / 2 - lungo / 2
        case .alto:
            x = p.x + misura.width / 2 - lungo / 2
            y = 0
        case .basso:
            x = p.x + misura.width / 2 - lungo / 2
            y = area.height - largo
        }
        x = min(max(x, 6), max(6, area.width - w - (orizzontale ? 6 : 0)))
        y = min(max(y, 6), max(6, area.height - h - (orizzontale ? 0 : 6)))
        if lato == .sinistra { x = 0 }
        if lato == .alto { y = 0 }
        let r: CGFloat = 14
        let forma = UnevenRoundedRectangle(
            topLeadingRadius: lato == .destra || lato == .basso ? r : 0,
            bottomLeadingRadius: lato == .destra || lato == .alto ? r : 0,
            bottomTrailingRadius: lato == .sinistra || lato == .alto ? r : 0,
            topTrailingRadius: lato == .sinistra || lato == .basso ? r : 0,
            style: .continuous
        )
        return Button {
            var q = o.origine ?? posizione(area)
            switch lato {
            case .sinistra: q.x = 8
            case .destra: q.x = area.width - misura.width - 8
            case .alto: q.y = 8
            case .basso: q.y = area.height - misura.height - 8
            }
            o.agganciato = nil
            o.origine = limita(q, area, libero: false)
        } label: {
            Image(systemName: "clock")
                .font(.system(size: 15))
                .foregroundStyle(o.finito ? AptTema.suAccento : AptTema.accentoTesto)
                .frame(width: w, height: h)
                .background(o.finito ? AptTema.accento : AptTema.carta, in: forma)
                .overlay(forma.stroke(AptTema.linea, lineWidth: 1))
                .shadow(color: AptTema.ombraColore, radius: 8, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
        .accessibilityLabel("Mostra cronometro o timer")
    }
}

// MARK: - Pannello (pulsante «orologio» della barra strumenti)

struct PannelloOrologio: View {
    @ObservedObject private var o = OrologioModello.condiviso
    var chiudi: () -> Void

    private let durate = [5, 10, 15, 25, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if o.attivo { inCorso } else { impostazione }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var inCorso: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(o.modo == .timer ? "Timer" : "Cronometro")
                .font(AptTema.titoloMedio)
                .foregroundColor(AptTema.testo)
            if o.agganciato != nil {
                Button("Mostra il riquadro") { o.richiama(); chiudi() }
                    .buttonStyle(AptStileSecondario())
            }
            if !o.finito {
                Button(o.inCorso ? "Pausa" : "Riprendi") { o.pausaORiprendi(); chiudi() }
                    .buttonStyle(AptStileSecondario())
            }
            Button("Chiudi") { o.chiudi(); chiudi() }
                .buttonStyle(AptStileContorno())
        }
    }

    private var impostazione: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cronometro o timer")
                .font(AptTema.titoloMedio)
                .foregroundColor(AptTema.testo)
            Picker("Tipo", selection: $o.sceltaModo) {
                Text("Cronometro").tag(ModoOrologio.cronometro)
                Text("Timer").tag(ModoOrologio.timer)
            }
            .pickerStyle(.segmented)
            if o.sceltaModo == .timer {
                HStack(spacing: 6) {
                    ForEach(durate, id: \.self) { m in
                        let scelta = o.sceltaMinuti == m && o.sceltaSecondi == 0
                        Button {
                            o.sceltaMinuti = m
                            o.sceltaSecondi = 0
                        } label: {
                            Text("\(m)′")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(scelta ? AptTema.accentoScuro : AptTema.testo)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(scelta ? AptTema.accentoTenue : Color.clear, in: Capsule())
                                .overlay(Capsule().stroke(scelta ? Color.clear : AptTema.linea, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Stepper("Minuti: \(o.sceltaMinuti)", value: $o.sceltaMinuti, in: 0...999)
                    .foregroundColor(AptTema.testo)
                Stepper("Secondi: \(o.sceltaSecondi)", value: $o.sceltaSecondi, in: 0...55, step: 5)
                    .foregroundColor(AptTema.testo)
            }
            Toggle("Mostra i secondi", isOn: $o.mostraSecondi)
                .foregroundColor(AptTema.testo)
            Button("Avvia") {
                if o.avvia() { chiudi() }
            }
            .buttonStyle(AptStilePrimario())
            .frame(maxWidth: .infinity)
        }
    }
}
