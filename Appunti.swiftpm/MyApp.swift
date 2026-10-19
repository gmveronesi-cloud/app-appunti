import SwiftUI

@main
struct MyApp: App {
    @AppStorage(AspettoApp.chiave) private var aspetto = AspettoApp.sistema.rawValue
    @AppStorage(AccentoApp.chiave) private var accentoApp = ""
    init() {
        Diagnostica.avvia()
        PuliziaTemporanei.alAvvio()
        AccentoApp.aggiorna(UserDefaults.standard.string(forKey: AccentoApp.chiave) ?? "")
        aptAspettoGlobale()
    }

    var body: some Scene {
        let _ = AccentoApp.aggiorna(accentoApp)
        WindowGroup {
            Group {
                if ProvaPrestazioni.attiva, let d = ProvaPrestazioni.preparaPDF() {
                    ProvaRadice(doc: d)
                } else {
                    LibreriaAppuntiView()
                }
            }
            .tint(AptTema.accento)
            // I file ricevuti da altre app vanno alla finestra già aperta (l'ultima usata), senza aprirne una nuova
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .id(accentoApp)           // cambiando il colore dell'app l'interfaccia si ridisegna
            .preferredColorScheme((AspettoApp(rawValue: aspetto) ?? .sistema).schema)
            .onAppear { (AspettoApp(rawValue: aspetto) ?? .sistema).applica() }
            .onChange(of: aspetto) { _, nuovo in (AspettoApp(rawValue: nuovo) ?? .sistema).applica() }
        }
    }
}
