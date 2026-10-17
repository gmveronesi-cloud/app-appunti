// Piccoli strumenti per non far chiudere l'app per un numero «impossibile».
//
// In Swift `Int(x)` ferma l'app (crash) se `x` non è un numero (NaN), è infinito o è enorme. Con misure di pagine, tratti e forme
// può succedere (per esempio una divisione per zero). `Int(sicuro:)` in quei casi restituisce un valore di riserva e l'app va avanti.
import UIKit

extension Int {
    /// Come `Int(valore)`, ma senza fermare l'app con NaN, infinito o numeri troppo grandi: in quel caso dà `predefinito`.
    init(sicuro valore: Double, predefinito: Int = 0) {
        if valore.isFinite && abs(valore) < 4_000_000_000_000_000 {
            self = Int(valore)
        } else {
            self = predefinito
        }
    }

    init(sicuro valore: CGFloat, predefinito: Int = 0) {
        self.init(sicuro: Double(valore), predefinito: predefinito)
    }
}
