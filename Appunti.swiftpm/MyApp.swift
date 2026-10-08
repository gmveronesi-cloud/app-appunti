import SwiftUI

@main
struct MyApp: App {
    @AppStorage(AspettoApp.chiave) private var aspetto = AspettoApp.sistema.rawValue
    @AppStorage(AccentoApp.chiave) private var accentoApp = ""
    init() {
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
            .id(accentoApp)           // cambiando il colore dell'app l'interfaccia si ridisegna
            .preferredColorScheme((AspettoApp(rawValue: aspetto) ?? .sistema).schema)
            .onAppear { (AspettoApp(rawValue: aspetto) ?? .sistema).applica() }
            .onChange(of: aspetto) { _, nuovo in (AspettoApp(rawValue: nuovo) ?? .sistema).applica() }
        }
    }
}
