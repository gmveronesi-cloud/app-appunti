// Condividi / esporta: prima una finestra con due rulli (pagina di inizio e di fine) e due pulsanti
// («tutte le pagine» scelte, oppure solo questa); poi il foglio di condivisione di iPadOS
// (Mail, Messaggi, AirDrop, «Salva su File»…).
import SwiftUI
import PDFKit

struct PulsanteCondividi: View {
    @ObservedObject var model: NotesModel
    @State private var mostraFinestra = false
    @State private var condivisione: CondivisionePagine?

    var body: some View {
        Button { mostraFinestra = true } label: {
            AptIcona(nome: "square.and.arrow.up", lato: 40, corpo: 21)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Condividi o esporta")
        .sheet(isPresented: $mostraFinestra) {
            FinestraEsporta(
                model: model,
                esporta: { indici, conAnnotazioni, tutte in
                    mostraFinestra = false
                    let url = model.esportaPagine(indici, conAnnotazioni: conAnnotazioni,
                                                  suffisso: tutte ? nil : (indici.count == 1 ? "pagina \(indici[0] + 1)" : "pagine \(indici.first! + 1)-\(indici.last! + 1)"))
                    guard let url else { model.message = "Non riesco a preparare il PDF."; return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { condivisione = CondivisionePagine(url: url) }
                },
                chiudi: { mostraFinestra = false }
            )
            .presentationDetents([.height(560)])
            .aptPannello()
        }
        .sheet(item: $condivisione) { c in AptShareSheet(items: [c.url]) }
    }
}

struct FinestraEsporta: View {
    @ObservedObject var model: NotesModel
    let esporta: (_ indici: [Int], _ conAnnotazioni: Bool, _ tutte: Bool) -> Void
    let chiudi: () -> Void

    @State private var da = 1
    @State private var a = 1
    @State private var conAnnotazioni = true
    @State private var corrente = 0
    @State private var iniziato = false

    private var totale: Int { max(model.document?.pageCount ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Condividi o esporta").font(AptTema.titoloMedio).foregroundColor(AptTema.testo)
                Spacer()
                Button("Annulla", action: chiudi).buttonStyle(AptStileSecondario())
            }
            Picker("Annotazioni", selection: $conAnnotazioni) {
                Text("Con le mie annotazioni").tag(true)
                Text("Senza annotazioni").tag(false)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 0) {
                rullo("Da pagina", $da)
                rullo("A pagina", $a)
            }
            Text("Il documento ha \(totale) pagine")
                .font(AptTema.dettaglio)
                .foregroundStyle(AptTema.testo2)
                .frame(maxWidth: .infinity)
            Button {
                esporta(Array((da - 1)..<a), conAnnotazioni, da == 1 && a == totale)
            } label: {
                Text(da == 1 && a == totale ? "Tutte le pagine" : (da == a ? "Pagina \(da)" : "Pagine \(da)–\(a)"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AptStilePrimario())
            Button {
                esporta([corrente], conAnnotazioni, totale == 1)
            } label: {
                Text("Solo questa pagina (\(corrente + 1))").frame(maxWidth: .infinity)
            }
            .buttonStyle(AptStileSecondario())
        }
        .padding(20)
        .onAppear {
            guard !iniziato else { return }
            iniziato = true
            corrente = min(max(model.paginaCorrente, 0), totale - 1)
            da = 1
            a = totale
        }
        .onChange(of: da) { _, n in if a < n { a = n } }
        .onChange(of: a) { _, n in if da > n { da = n } }
    }

    private func rullo(_ titolo: String, _ valore: Binding<Int>) -> some View {
        VStack(spacing: 2) {
            Text(titolo).font(AptTema.dettaglio).foregroundStyle(AptTema.testo2)
            Picker(titolo, selection: valore) {
                ForEach(1...totale, id: \.self) { n in Text("\(n)").tag(n) }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
        }
        .frame(maxWidth: .infinity)
    }
}
