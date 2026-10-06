// Immagine: menu, livelli, annulla/ripeti, da e verso il PDF
import SwiftUI
import PDFKit
import PencilKit

extension ImmagineControllo {
    // MARK: Menu

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        switch modoMenu {
        case .vuoto:
            var voci: [UIMenuElement] = []
            if Self.appunti != nil {
                voci.append(UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incolla() })
            }
            voci.append(UIAction(title: "Nuova immagine", image: UIImage(systemName: "photo.badge.plus")) { [weak self] _ in
                guard let (p, pt) = self?.puntoVuoto else { return }
                self?.model?.richiediImmagine(pagina: p, punto: pt)
            })
            return UIMenu(options: .displayInline, children: voci)
        case .immagine:
            guard elementoScelto != nil else { return nil }
            if ritagliando {
                let fine = UIAction(title: "Fine ritaglio", image: UIImage(systemName: "checkmark")) { [weak self] _ in
                    self?.ritagliando = false
                    self?.mostraSelezione()
                }
                let ripristina = UIAction(title: "Ripristina", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in self?.ripristinaRitaglio() }
                return UIMenu(options: .displayInline, children: [fine, ripristina])
            }
            let taglia = UIAction(title: "Taglia", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.taglia() }
            let copia = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copia() }
            let ritaglia = UIAction(title: "Ritaglia", image: UIImage(systemName: "crop")) { [weak self] _ in
                self?.ritagliando = true
                self?.mostraSelezione()
            }
            let su = UIAction(title: "Porta sopra", image: UIImage(systemName: "square.2.layers.3d.top.filled")) { [weak self] _ in self?.livello(su: true) }
            let giu = UIAction(title: "Porta sotto", image: UIImage(systemName: "square.2.layers.3d.bottom.filled")) { [weak self] _ in self?.livello(su: false) }
            let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
            return UIMenu(options: .displayInline, children: [elimina, taglia, copia, ritaglia, su, giu])
        }
    }

    func copia() {
        Self.appunti = elementoScelto
        mettiNelVassoio()
    }

    /// Copia e taglia mandano nel vassoio anche l'immagine così com'è vista (con il ritaglio, senza rotazione)
    func mettiNelVassoio() {
        if let e = elementoScelto { mettiNelVassoio(e) }
    }

    func mettiNelVassoio(_ e: ElementoImmagine) {
        let scala = model?.pdfView?.scaleFactor ?? 1
        Vassoio.condiviso.aggiungi(immagine: e.ritagliata, larghezza: e.larghezza * scala)
    }

    func taglia() {
        Self.appunti = elementoScelto
        mettiNelVassoio()
        elimina()
    }

    func incolla() {
        guard let originale = Self.appunti, let (p, pt) = puntoVuoto else { return }
        var e = originale
        e.id = UUID()
        e.creazione = Date()
        e.centro = Self.dentro(pt, mezzaLarghezza: e.larghezza / 2, mezzaAltezza: e.altezza / 2, p)
        scelta = (p, e.id)
        ritagliando = false
        cambia(p, togli: nil, metti: e)
    }

    func elimina() {
        guard let s = scelta, let e = elementoScelto else { return }
        scelta = nil
        ritagliando = false
        cambia(s.pagina, togli: e, metti: nil)
    }

    func ripristinaRitaglio() {
        guard let s = scelta, let e = elementoScelto else { return }
        var n = e
        let scalaAttuale = e.scala
        let intera = CGRect(origin: .zero, size: e.base.size)
        // il contenuto già visibile resta fermo: si riaggiungono i bordi
        let vecchio = CGPoint(x: (intera.minX - e.ritaglio.minX) * scalaAttuale - e.larghezza / 2,
                              y: e.altezza / 2 - (intera.minY - e.ritaglio.minY) * scalaAttuale)
        n.impostaRitaglio(intera)
        n.larghezza = intera.width * scalaAttuale
        let nuovo = CGPoint(x: -n.larghezza / 2, y: n.altezza / 2)
        n.centro = e.mondo(CGPoint(x: vecchio.x - nuovo.x, y: vecchio.y - nuovo.y))
        cambia(s.pagina, togli: e, metti: n)
    }

    // MARK: Livelli: un passo sopra o sotto

    /// Un livello = il gruppo di tratti adiacente o l'immagine adiacente. Si cambia la data dell'immagine
    /// perché stia subito dopo (sopra) o subito prima (sotto) di quel gruppo.
    func livello(su: Bool) {
        guard let s = scelta, let e = elementoScelto, let model else { return }
        var voci: [(Date, Bool)] = model.tuttiITratti(s.pagina).map { ($0.path.creationDate, false) }
        voci += (model.immagini[s.pagina] ?? []).filter { $0.id != e.id }.map { ($0.creazione, true) }
        voci += (model.testi[s.pagina] ?? []).map { ($0.creazione, true) }
        voci.sort { $0.0 < $1.0 }
        let i = voci.firstIndex { $0.0 > e.creazione } ?? voci.count        // posizione dell'immagine tra le altre voci
        var nuova: Date?
        if su {
            if i < voci.count {
                var j = i
                if !voci[i].1 { while j + 1 < voci.count && !voci[j + 1].1 { j += 1 } }
                nuova = voci[j].0.addingTimeInterval(0.001)
            }
        } else if i > 0 {
            var j = i - 1
            if !voci[j].1 { while j > 0 && !voci[j - 1].1 { j -= 1 } }
            nuova = voci[j].0.addingTimeInterval(-0.001)
        }
        guard let d = nuova else { return }
        var n = e
        n.creazione = d
        cambia(s.pagina, togli: e, metti: n)
    }

    // MARK: Aggiunta/rimozione con annulla e ripeti

    func cambia(_ p: PDFPage, togli: ElementoImmagine?, metti: ElementoImmagine?) {
        guard let model else { return }
        var lista = model.immagini[p] ?? []
        if let t = togli { lista.removeAll { $0.id == t.id } }
        if let m = metti { lista.append(m) }
        model.immagini[p] = lista
        if let s = scelta, s.pagina === p, !lista.contains(where: { $0.id == s.id }) {
            scelta = nil
            ritagliando = false
        }
        model.ripartisci(p, pulisciUndo: false)
        model.segnaModificato(p)
        model.pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.cambia(p, togli: metti, metti: togli) }
    }

    // MARK: Da e verso il PDF

    /// Annotazione da scrivere nel PDF al salvataggio (immagine visibile + dati originali nascosti nella stessa annotazione)
    static func annotazione(da e: ElementoImmagine) -> PDFAnnotation {
        let a = AnnotazioneImmagine(bounds: e.riquadro, forType: .stamp, withProperties: nil)
        a.immagine = e.ritagliata
        a.centro = e.centro
        a.larghezza = e.larghezza
        a.altezza = e.altezza
        a.angolo = e.angolo
        a.userName = nome
        _ = a.setValue(e.dati.base64EncodedString(), forAnnotationKey: chiaveDati)
        let r = e.ritaglio
        let info = [e.centro.x, e.centro.y, e.larghezza, e.angolo, e.creazione.timeIntervalSince1970, r.minX, r.minY, r.width, r.height]
            .map { String(Double($0)) }.joined(separator: ",")
        _ = a.setValue(info, forAnnotationKey: chiaveInfo)
        return a
    }

    /// Immagine modificabile letta da un'annotazione dell'app
    static func elemento(da a: PDFAnnotation) -> ElementoImmagine? {
        guard let testo = a.value(forAnnotationKey: chiaveDati) as? String,
              let dati = Data(base64Encoded: testo),
              let img = UIImage(data: dati) else { return nil }
        if let info = a.value(forAnnotationKey: chiaveInfo) as? String {
            let v = info.split(separator: ",").compactMap { Double($0) }
            if v.count == 9 {
                return ElementoImmagine(dati: dati, base: img, ritaglio: CGRect(x: v[5], y: v[6], width: v[7], height: v[8]),
                                        centro: CGPoint(x: v[0], y: v[1]), larghezza: CGFloat(v[2]), angolo: CGFloat(v[3]),
                                        creazione: Date(timeIntervalSince1970: v[4]))
            }
        }
        // salvata dalla versione precedente: senza rotazione né ritaglio
        return ElementoImmagine(dati: dati, base: img, centro: CGPoint(x: a.bounds.midX, y: a.bounds.midY),
                                larghezza: a.bounds.width, creazione: Date())
    }
}
