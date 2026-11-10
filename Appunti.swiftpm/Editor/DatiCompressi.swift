// Dati nascosti dei tratti (`/AptDati`): se comprimendoli si guadagna, si salvano compressi (zlib) prima del base64.
// Formato: testo che comincia con «~z» + base64 dei dati compressi. Il testo senza prefisso è il base64 semplice di prima:
// i file vecchi si leggono come sempre. Il carattere «~» non esiste nel base64, quindi i due formati non si confondono.
import Foundation

enum DatiCompressi {
    private static let prefisso = "~z"

    /// Testo da scrivere nel PDF: compresso solo se conviene (almeno 8% in meno), altrimenti base64 semplice come prima.
    static func codifica(_ dati: Data) -> String {
        if dati.count > 256,
           let c = try? (dati as NSData).compressed(using: .zlib) as Data,
           Double(c.count) < Double(dati.count) * 0.92,
           // controllo: decompresso deve tornare identico, altrimenti si scrive il formato vecchio
           let indietro = try? (c as NSData).decompressed(using: .zlib) as Data,
           indietro == dati {
            return prefisso + c.base64EncodedString()
        }
        return dati.base64EncodedString()
    }

    /// Dati originali da un testo scritto con `codifica` (o dal vecchio base64 semplice)
    static func decodifica(_ testo: String) -> Data? {
        if testo.hasPrefix(prefisso) {
            guard let c = Data(base64Encoded: String(testo.dropFirst(prefisso.count)), options: .ignoreUnknownCharacters) else { return nil }
            return try? (c as NSData).decompressed(using: .zlib) as Data
        }
        return Data(base64Encoded: testo)
    }
}
