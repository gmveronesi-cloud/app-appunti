// Annulla e ripeti dei TRATTI, indipendente dallo strumento.
//
// Prima l'annulla dei tratti era quello di PencilKit: ricorda «come era la tela». Cambiando strumento i tratti vengono spostati
// fra la tela e gli strati sopra/sotto (vedi `ripartisci`), la tela non è più quella di prima e la cronologia andava azzerata.
//
// Ora ogni passo dice «questi tratti sono stati tolti, questi sono stati aggiunti», e ogni tratto è riconosciuto dalla sua
// «etichetta» (`ChiaveTratto`: data, forma, colore, posizione). Annullare = togliere i tratti aggiunti e rimettere quelli tolti,
// ovunque si trovino in quel momento. Il passo sta nella cronologia della pagina, insieme a quelli di immagini e testi,
// quindi l'ordine resta giusto. Il limite è solo numerico: `livelliPagina` passi per pagina, per qualsiasi strumento.
import UIKit
import PDFKit
import PencilKit

/// Etichetta di un tratto: due tratti uguali in tutto hanno la stessa etichetta
struct ChiaveTratto: Hashable {
    let data: Double
    let punti: Int
    let x0: Float, y0: Float, x1: Float, y1: Float
    let inchiostro: String
    let r: Float, g: Float, b: Float, a: Float
    let t: [Float]

    init(_ s: PKStroke) {
        data = s.path.creationDate.timeIntervalSinceReferenceDate
        punti = s.path.count
        if s.path.count > 0 {
            let p = s.path[0].location, q = s.path[s.path.count - 1].location
            x0 = Float(p.x); y0 = Float(p.y); x1 = Float(q.x); y1 = Float(q.y)
        } else { x0 = 0; y0 = 0; x1 = 0; y1 = 0 }
        inchiostro = s.ink.inkType.rawValue
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        s.ink.color.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r = Float(rr); g = Float(gg); b = Float(bb); a = Float(aa)
        let m = s.transform
        t = [Float(m.a), Float(m.b), Float(m.c), Float(m.d), Float(m.tx), Float(m.ty)]
    }
}

/// Un passo di annulla dei tratti
final class VoceTratti {
    var rimossi: [PKStroke]
    var aggiunti: [PKStroke]
    init(rimossi: [PKStroke], aggiunti: [PKStroke]) { self.rimossi = rimossi; self.aggiunti = aggiunti }
}

extension NotesModel {
    /// Cosa è stato tolto e cosa aggiunto passando da `prima` a `dopo`
    func differenza(_ prima: [PKStroke], _ dopo: [PKStroke]) -> (rimossi: [PKStroke], aggiunti: [PKStroke]) {
        var conta: [ChiaveTratto: Int] = [:]
        for s in prima { conta[ChiaveTratto(s), default: 0] += 1 }
        for s in dopo { conta[ChiaveTratto(s), default: 0] -= 1 }
        var rimossi: [PKStroke] = [], aggiunti: [PKStroke] = []
        for s in prima {
            let k = ChiaveTratto(s)
            if let n = conta[k], n > 0 { rimossi.append(s); conta[k] = n - 1 }
        }
        for s in dopo {
            let k = ChiaveTratto(s)
            if let n = conta[k], n < 0 { aggiunti.append(s); conta[k] = n + 1 }
        }
        return (rimossi, aggiunti)
    }

    private func registraVoce(_ v: VoceTratti, pagina: PDFPage) {
        gestoreUndo(per: pagina).registerUndo(withTarget: self) { s in s.applicaVoce(v, pagina: pagina, indietro: true) }
    }

    /// Inizia l'uso di uno strumento sulla tela (un tratto, un passaggio di gomma): si fotografano i tratti com'erano
    func inizioUsoStrumento(_ tela: PKCanvasView) {
        guard let p = pagina(di: tela) else { return }
        ultimiTratti[p] = tuttiITratti(p)
        voceInCorso[p] = nil
    }

    /// La tela è cambiata per mano dell'utente (tratto nuovo, gomma): si registra la differenza
    func registraCambioTratti(_ pagina: PDFPage) {
        guard !applicandoTratti else { return }
        let ora = tuttiITratti(pagina)
        guard let prima = ultimiTratti[pagina] else { ultimiTratti[pagina] = ora; return }
        ultimiTratti[pagina] = ora
        let (rim, agg) = differenza(prima, ora)
        if rim.isEmpty && agg.isEmpty { return }
        if let v = voceInCorso[pagina] {
            // Stesso passaggio di gomma che continua: un solo passo di annulla
            for s in rim {
                if let i = v.aggiunti.firstIndex(where: { ChiaveTratto($0) == ChiaveTratto(s) }) { v.aggiunti.remove(at: i) } else { v.rimossi.append(s) }
            }
            for s in agg {
                if let i = v.rimossi.firstIndex(where: { ChiaveTratto($0) == ChiaveTratto(s) }) { v.rimossi.remove(at: i) } else { v.aggiunti.append(s) }
            }
        } else {
            let v = VoceTratti(rimossi: rim, aggiunti: agg)
            voceInCorso[pagina] = v
            registraVoce(v, pagina: pagina)
        }
    }

    /// Modifica fatta dal lazo o dalle forme (la tela è già cambiata da `prima` a `dopo`)
    func registraTratti(_ tela: PKCanvasView, da prima: PKDrawing, a dopo: PKDrawing) {
        guard let p = pagina(di: tela) else { return }
        // Se PencilKit ha già avvisato del cambio (succede anche per le modifiche fatte dal codice), il passo è già registrato
        if voceInCorso[p] != nil, let foto = ultimiTratti[p] {
            let d = differenza(foto, tuttiITratti(p))
            if d.rimossi.isEmpty && d.aggiunti.isEmpty { voceInCorso[p] = nil; return }
        }
        let (rim, agg) = differenza(prima.strokes, dopo.strokes)
        voceInCorso[p] = nil
        if !(rim.isEmpty && agg.isEmpty) { registraVoce(VoceTratti(rimossi: rim, aggiunti: agg), pagina: p) }
        ultimiTratti[p] = tuttiITratti(p)
    }

    /// Annulla (`indietro`) o ripeti un passo: i tratti aggiunti si tolgono, quelli tolti si rimettono, in qualunque strato siano
    func applicaVoce(_ v: VoceTratti, pagina: PDFPage, indietro: Bool) {
        guard let tela = canvases[pagina] else { return }
        let togli = indietro ? v.aggiunti : v.rimossi
        let metti = indietro ? v.rimossi : v.aggiunti
        applicandoTratti = true
        defer { applicandoTratti = false }

        var conta: [ChiaveTratto: Int] = [:]
        for s in togli { conta[ChiaveTratto(s), default: 0] += 1 }
        func filtra(_ a: [PKStroke]) -> [PKStroke] {
            a.filter { s in
                let k = ChiaveTratto(s)
                if let n = conta[k], n > 0 { conta[k] = n - 1; return false }
                return true
            }
        }
        var inTela = filtra(tela.drawing.strokes)
        let bassi = filtra(sotto[pagina] ?? [])
        let alti = filtra(sopra[pagina] ?? [])
        // I tratti rimessi tornano al loro posto nell'ordine (per data di creazione)
        for s in metti {
            let d = s.path.creationDate
            let i = inTela.firstIndex { $0.path.creationDate > d } ?? inTela.count
            inTela.insert(s, at: i)
        }
        caricando = true
        tela.drawing = PKDrawing(strokes: inTela)
        caricando = false
        sotto[pagina] = bassi
        sopra[pagina] = alti
        ripartisci(pagina, pulisciUndo: false)
        lazo?.deseleziona()
        ultimiTratti[pagina] = tuttiITratti(pagina)
        voceInCorso[pagina] = nil
        segnaModificato(pagina)
        gestoreUndo(per: pagina).registerUndo(withTarget: self) { s in s.applicaVoce(v, pagina: pagina, indietro: !indietro) }
    }

    // MARK: Delegato della tela

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { inizioUsoStrumento(canvasView) }

    /// Finito il tratto o il passaggio di gomma: il passo di annulla è chiuso
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        if let p = pagina(di: canvasView) { voceInCorso[p] = nil }
    }
}
