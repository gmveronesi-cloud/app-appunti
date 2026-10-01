import SwiftUI

@main
struct MyApp: App {
    init() { aptAspettoGlobale() }

    var body: some Scene {
        WindowGroup {
            if let m = ProvaNitidezza.modo {
                ProvaNitidezzaView(modo: m)
            } else {
                LibreriaAppuntiView()
                    .tint(AptTema.accento)
            }
        }
    }
}
