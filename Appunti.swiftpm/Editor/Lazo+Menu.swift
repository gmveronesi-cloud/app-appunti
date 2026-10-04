// Lazo: menu sulla selezione, annulla e ripeti
import SwiftUI
import PDFKit
import PencilKit

extension LazoSelezione {
    // MARK: Menu (taglia, elimina, ridimensiona, copia, colore; incolla su un punto vuoto)

    func mostraMenu() {
        guard let vista, let tela = canvas, haSelezione else { return }
        let r = riquadroSelezione(in: tela)
        let punto = vista.convert(CGPoint(x: r.midX, y: r.minY), from: tela)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: punto))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if !haSelezione {
            guard !Self.appunti.isEmpty else { return nil }
            return UIMenu(children: [UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incolla() }])
        }
        let taglia = UIAction(title: "Taglia", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.taglia() }
        let elimina = UIAction(title: "Elimina", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.elimina() }
        let ridim = UIAction(title: "Ridimensiona e ruota", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")) { [weak self] _ in self?.ridimensiona() }
        let copia = UIAction(title: "Copia", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copia() }
        let colore = UIAction(title: "Colore", image: UIImage(systemName: "paintpalette")) { [weak self] _ in self?.cambiaColore() }
        var voci: [UIMenuElement] = [elimina, taglia, ridim, copia]
        if !selezione.isEmpty { voci.append(colore) }
        if !selezione.isEmpty, immaginiSel.isEmpty, let tela = canvas, let p = model?.pagina(di: tela), !(model?.immagini[p]?.isEmpty ?? true) {
            voci.append(UIAction(title: "Porta sopra", image: UIImage(systemName: "square.2.layers.3d.top.filled")) { [weak self] _ in self?.livello(su: true) })
            voci.append(UIAction(title: "Porta sotto", image: UIImage(systemName: "square.2.layers.3d.bottom.filled")) { [weak self] _ in self?.livello(su: false) })
        }
        return UIMenu(options: .displayInline, children: voci)
    }

    /// Un livello sopra o sotto l'immagine più vicina: si cambia la data di creazione dei tratti scelti.
    func livello(su: Bool) {
        guard let tela = canvas, let model, let pagina = model.pagina(di: tela), !selezione.isEmpty else { return }
        let immagini = (model.immagini[pagina] ?? []).map { $0.creazione }.sorted()
        let prima = tela.drawing
        let date = selezione.compactMap { prima.strokes.indices.contains($0) ? prima.strokes[$0].path.creationDate : nil }
        guard let minimo = date.min(), let massimo = date.max() else { return }
        let base: Date
        if su {
            guard let t = immagini.first(where: { $0 > massimo }) else { return }
            base = t.addingTimeInterval(0.001)
        } else {
            guard let t = immagini.last(where: { $0 < minimo }) else { return }
            base = t.addingTimeInterval(-0.001 - Double(selezione.count) * 0.00001)
        }
        var tutti = prima.strokes
        for (n, i) in selezione.sorted().enumerated() where tutti.indices.contains(i) {
            tutti[i] = Self.spostato(prima.strokes[i], .identity, data: base.addingTimeInterval(Double(n) * 0.00001))
        }
        let dopo = PKDrawing(strokes: tutti)
        tela.drawing = dopo
        registra(tela, da: prima, a: dopo)
        model.segnaModificato()
        model.message = "Livello cambiato: lo vedi tornando alla penna."
    }

    func trattiSelezionati() -> [PKStroke] {
        guard let tela = canvas else { return [] }
        let t = tela.drawing.strokes
        return selezione.compactMap { t.indices.contains($0) ? t[$0] : nil }
    }

    func copia() {
        Self.appunti = trattiSelezionati()
        model?.controlloImmagini?.copiaInAppunti(immaginiScelte())
    }

    func taglia() {
        copia()
        elimina()
    }

    func ridimensiona() {
        guard let tela = canvas else { return }
        modoRidimensiona = true
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    func incolla() {
        guard let tela = canvas, !Self.appunti.isEmpty else { return }
        var r = CGRect.null
        for t in Self.appunti { r = r.union(t.renderBounds) }
        let m = CGAffineTransform(translationX: puntoIncolla.x - r.midX, y: puntoIncolla.y - r.midY)
        let prima = tela.drawing
        var d = prima
        let primoNuovo = d.strokes.count
        let adesso = Date()
        d.strokes.append(contentsOf: Self.appunti.enumerated().map { Self.spostato($1, m, data: adesso.addingTimeInterval(Double($0) * 0.00001)) })
        tela.drawing = d
        registra(tela, da: prima, a: d)
        model?.segnaModificato()
        selezione = Array(primoNuovo..<d.strokes.count)
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    // Colore: selettore di sistema, applicato in diretta ai tratti scelti
    func cambiaColore() {
        guard let tela = canvas, let primo = trattiSelezionati().first else { return }
        coloreBase = tela.drawing
        coloreCambiato = false
        let picker = UIColorPickerViewController()
        picker.selectedColor = primo.ink.color
        picker.supportsAlpha = false
        picker.delegate = self
        var alto = vista?.window?.rootViewController
        while let p = alto?.presentedViewController { alto = p }
        alto?.present(picker, animated: true)
    }

    func colorPickerViewController(_ vc: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        guard let tela = canvas, let base = coloreBase else { return }
        var tutti = base.strokes
        for i in selezione where tutti.indices.contains(i) {
            let t = tutti[i]
            let alpha = t.ink.color.cgColor.alpha
            tutti[i] = PKStroke(ink: PKInk(t.ink.inkType, color: color.withAlphaComponent(alpha)), path: t.path, transform: t.transform, mask: t.mask)
        }
        tela.drawing = PKDrawing(strokes: tutti)
        coloreCambiato = true
        model?.segnaModificato()
    }

    func colorPickerViewControllerDidFinish(_ vc: UIColorPickerViewController) {
        guard let tela = canvas, let base = coloreBase, coloreCambiato else { return }
        registra(tela, da: base, a: tela.drawing)
        mostraRiquadro(riquadroSelezione(in: tela))
    }

    func elimina() {
        guard let tela = canvas, haSelezione else { return }
        let imm = immaginiScelte()
        let pagina = paginaTela
        if !selezione.isEmpty {
            let prima = tela.drawing
            var d = prima
            let fuori = Set(selezione)
            d.strokes = prima.strokes.enumerated().filter { !fuori.contains($0.offset) }.map { $0.element }
            tela.drawing = d
            registra(tela, da: prima, a: d)
        } else {
            registraSoloImmagini()
        }
        if let pagina, let c = model?.controlloImmagini {
            for e in imm { c.cambia(pagina, togli: e, metti: nil) }
        }
        model?.segnaModificato()
        deseleziona()
    }

    // MARK: Annulla e ripeti

    func registra(_ tela: PKCanvasView, da prima: PKDrawing, a dopo: PKDrawing) {
        let um = vista?.undoManager ?? tela.undoManager
        um?.registerUndo(withTarget: self) { [weak tela] s in
            guard let tela else { return }
            tela.drawing = prima
            s.deseleziona()
            s.registra(tela, da: dopo, a: prima)
            s.model?.segnaModificato()
        }
    }
}
