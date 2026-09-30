// Ricerca del testo digitato dentro il PDF aperto (PDFKit). Non cerca nella scrittura a mano.
import SwiftUI
import PDFKit

@MainActor
final class RicercaPDF: ObservableObject {
    @Published var testo = "" { didSet { if testo != oldValue { programma() } } }
    @Published private(set) var risultati: [PDFSelection] = []
    @Published private(set) var indice = 0
    @Published var attiva = false { didSet { if attiva { tastiera = true } else { pulisci() } } }
    /// Tastiera a schermo visibile (si può nascondere per vedere tutto il PDF).
    @Published var tastiera = true

    private weak var pdfView: PDFView?
    private var attesa: Task<Void, Never>?

    var conteggio: Int { risultati.count }
    var haCercato: Bool { testo.trimmingCharacters(in: .whitespaces).count >= 2 }

    func collega(_ v: PDFView?) { pdfView = v }

    /// Da chiamare quando cambia il documento (cambio scheda): azzera la ricerca.
    func azzera() {
        attesa?.cancel()
        testo = ""
        pulisci()
    }

    func prossimo() { muovi(+1) }
    func precedente() { muovi(-1) }

    private func programma() {
        attesa?.cancel()
        let q = testo.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { pulisci(); return }
        attesa = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.cerca(q)
        }
    }

    private func cerca(_ q: String) {
        guard let v = pdfView, let doc = v.document else { pulisci(); return }
        let trovati = doc.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
        for s in trovati { s.color = UIColor.systemYellow.withAlphaComponent(0.55) }
        risultati = trovati
        indice = 0
        v.highlightedSelections = trovati.isEmpty ? nil : trovati
        mostraCorrente()
    }

    private func muovi(_ passo: Int) {
        guard !risultati.isEmpty else { return }
        indice = (indice + passo + risultati.count) % risultati.count
        mostraCorrente()
    }

    private func mostraCorrente() {
        guard let v = pdfView, risultati.indices.contains(indice) else {
            pdfView?.setCurrentSelection(nil, animate: false)
            return
        }
        let s = risultati[indice]
        v.setCurrentSelection(s, animate: true)
        v.go(to: s)
    }

    private func pulisci() {
        attesa?.cancel()
        risultati = []
        indice = 0
        pdfView?.highlightedSelections = nil
        pdfView?.setCurrentSelection(nil, animate: false)
    }
}

// Striscia di ricerca sotto la barra in alto
struct BarraRicerca: View {
    @ObservedObject var ricerca: RicercaPDF

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AptTema.testo2)
            AptCampo(testo: ricerca.testo, segnaposto: "Cerca nel testo del PDF", attivo: ricerca.tastiera)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { ricerca.tastiera = true }
            if !ricerca.testo.isEmpty {
                Button { ricerca.testo = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AptTema.testo2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancella il testo")
            }
            if ricerca.haCercato {
                Text(ricerca.conteggio == 0 ? "Nessun risultato"
                     : "\(ricerca.indice + 1) di \(ricerca.conteggio)")
                    .font(AptTema.dettaglio)
                    .foregroundStyle(AptTema.testo2)
                    .monospacedDigit()
            }
            Button { ricerca.precedente() } label: {
                Image(systemName: "chevron.up").frame(width: 36, height: 34)
            }
            .disabled(ricerca.conteggio == 0)
            .accessibilityLabel("Risultato precedente")
            Button { ricerca.prossimo() } label: {
                Image(systemName: "chevron.down").frame(width: 36, height: 34)
            }
            .disabled(ricerca.conteggio == 0)
            .accessibilityLabel("Risultato successivo")
            Button("Chiudi") { ricerca.attiva = false }
                .foregroundColor(AptTema.accentoTesto)
        }
        .frame(height: 38)
        .aptBarra()
    }
}
