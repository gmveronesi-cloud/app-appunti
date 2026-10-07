import SwiftUI

@main
struct MyApp: App {
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
        }
    }
}
