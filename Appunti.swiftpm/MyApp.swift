import SwiftUI

@main
struct MyApp: App {
    init() { aptAspettoGlobale() }

    var body: some Scene {
        WindowGroup {
            LibreriaAppuntiView()
                .tint(AptTema.accento)
        }
    }
}
