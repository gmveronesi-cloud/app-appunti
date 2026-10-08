import SwiftUI

@main
struct MyApp: App {
    @AppStorage(AspettoApp.chiave) private var aspetto = AspettoApp.sistema.rawValue
    init() { aptAspettoGlobale() }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProvaPrestazioni.attiva, let d = ProvaPrestazioni.preparaPDF() {
                    ProvaRadice(doc: d)
                } else {
                    LibreriaAppuntiView()
                }
            }
            .tint(AptTema.accento)
            .preferredColorScheme((AspettoApp(rawValue: aspetto) ?? .sistema).schema)
            .onAppear { (AspettoApp(rawValue: aspetto) ?? .sistema).applica() }
            .onChange(of: aspetto) { _, nuovo in (AspettoApp(rawValue: nuovo) ?? .sistema).applica() }
        }
    }
}
