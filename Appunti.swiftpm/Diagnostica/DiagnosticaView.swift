// Pagina «Diagnosi»: prepara il rapporto da mandare a Claude e permette di segnare un problema nel registro.
import SwiftUI
import UIKit

struct DiagnosticaView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inLavoro = false
    @State private var rapporto: URL?
    @State private var errore = false
    @State private var segnato = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Se l'app si è chiusa da sola, o sta andando male, qui prepari un file da mandare a Claude per capire cosa è successo.")
                        .font(AptTema.corpo).foregroundColor(AptTema.testo)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Com'è finita l'ultima volta").font(AptTema.corpoForte).foregroundColor(AptTema.testo)
                        Text(Diagnostica.esitoPrecedente)
                            .font(AptTema.corpo)
                            .foregroundColor(Diagnostica.chiusuraAnomala ? .red : AptTema.testo)
                    }

                    AptLinea()

                    Text("1. Mentre usi l'app")
                        .font(AptTema.corpoForte).foregroundColor(AptTema.testo)
                    Text("Se noti qualcosa di strano (scatti, tratti in ritardo, schermo che si blocca) tocca «Segna un problema adesso»: lascia un segno nel registro così Claude trova il punto esatto.")
                        .font(AptTema.corpo).foregroundColor(AptTema.testo)
                    Button {
                        Diagnostica.segnalaProblema()
                        segnato = true
                    } label: { Text(segnato ? "Segnato ✓" : "Segna un problema adesso") }
                        .buttonStyle(AptStileContorno())

                    AptLinea()

                    Text("2. Quando vuoi mandarlo")
                        .font(AptTema.corpoForte).foregroundColor(AptTema.testo)
                    Text("Tocca «Prepara rapporto», poi scegli «Salva su File» (o AirDrop) e allega il file alla chat con Claude. Dentro ci sono solo numeri e nomi di operazioni: nessun nome di file né contenuto dei tuoi documenti.")
                        .font(AptTema.corpo).foregroundColor(AptTema.testo)
                    Button {
                        inLavoro = true
                        Diagnostica.preparaRapporto(motivo: "richiesto dall'utente") { url in
                            inLavoro = false
                            if let url { rapporto = url } else { errore = true }
                        }
                    } label: { Text(inLavoro ? "Preparo…" : "Prepara rapporto") }
                        .buttonStyle(AptStilePrimario())
                        .disabled(inLavoro)
                }
                .padding(20)
            }
            .background(AptTema.carta)
            .navigationTitle("Diagnosi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
            }
            .sheet(item: Binding(get: { rapporto.map { RapportoPronto(url: $0) } },
                                 set: { if $0 == nil { rapporto = nil } })) { r in
                AptShareSheet(items: [r.url])
            }
            .alert("Non sono riuscita a preparare il rapporto", isPresented: $errore) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Controlla di avere spazio libero sull'iPad e riprova.")
            }
        }
    }
}

private struct RapportoPronto: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Pulsante «Diagnosi» per le barre dell'app
struct PulsanteDiagnosi: View {
    @State private var aperta = false

    var body: some View {
        Button { aperta = true } label: { AptIcona(nome: "stethoscope", attiva: aperta) }
            .buttonStyle(.plain)
            .accessibilityLabel("Diagnosi")
            .sheet(isPresented: $aperta) { DiagnosticaView() }
    }
}

/// Avviso mostrato in Libreria dopo una chiusura improvvisa
struct AvvisoChiusura: View {
    @State private var visibile = Diagnostica.chiusuraAnomala
    @State private var aperta = false

    var body: some View {
        if visibile {
            HStack(spacing: 10) {
                Text("L'app si è chiusa da sola l'ultima volta.")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(AptTema.testo)
                Button("Invia diagnosi") { aperta = true }
                    .buttonStyle(AptStilePrimario())
                Button { visibile = false } label: { AptIcona(nome: "xmark") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(AptTema.carta))
            .overlay(Capsule().strokeBorder(AptTema.linea, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.top, 12)
            .sheet(isPresented: $aperta) { DiagnosticaView() }
        }
    }
}
