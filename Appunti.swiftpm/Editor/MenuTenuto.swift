// Tocco lungo (1 secondo) col dito, con QUALSIASI strumento in mano: compare il menu di sistema
// (Incolla, Seleziona, Testo, Immagine). Inoltre si possono trascinare sulla pagina foto, PDF, documenti e testo da altre app
// (Foto, File, Safari…): foto e testo vanno dove si lascia il dito, PDF e documenti si aggiungono al file.
import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

final class MenuTenuto: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate, UIDropInteractionDelegate {
    weak var model: NotesModel?
    let gesto: UILongPressGestureRecognizer
    private(set) var menu: UIEditMenuInteraction!
    private(set) var drop: UIDropInteraction!
    private var punto: (pagina: PDFPage, pp: CGPoint, pv: CGPoint)?

    init(model: NotesModel) {
        self.model = model
        gesto = UILongPressGestureRecognizer()
        super.init()
        gesto.addTarget(self, action: #selector(tenuto(_:)))
        gesto.minimumPressDuration = 1.0
        gesto.allowableMovement = 12
        gesto.numberOfTouchesRequired = 1
        gesto.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]     // solo il dito, non la Pencil
        gesto.cancelsTouchesInView = false
        gesto.delegate = self
        menu = UIEditMenuInteraction(delegate: self)
        drop = UIDropInteraction(delegate: self)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: Tocco lungo

    @objc private func tenuto(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let model, let v = model.pdfView else { return }
        let pv = g.location(in: v)
        guard let p = v.page(for: pv, nearest: false) else { return }
        let pp = v.convert(pv, to: p)
        // Sopra a una selezione, a un'immagine o a un testo lavorano già i loro menu
        if model.lazo?.haSelezione == true { return }
        if model.controlloImmagini?.sotto(pp, in: p) != nil { return }
        if model.controlloTesto?.elemento(in: p, at: pp) != nil { return }
        punto = (p, pp, pv)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: pv))
    }

    private var haAppuntiDiSistema: Bool {
        let pb = UIPasteboard.general
        return pb.hasImages || pb.hasStrings || pb.contains(pasteboardTypes: [UTType.pdf.identifier])
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard punto != nil, let model else { return nil }
        var voci: [UIMenuElement] = []
        let internoPieno = LazoSelezione.haAppunti || TestoControllo.appunti != nil || ImmagineControllo.appunti != nil
        let sistema = haAppuntiDiSistema
        if internoPieno {
            voci.append(UIAction(title: "Incolla", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.incollaInterno() })
        }
        if sistema {
            voci.append(UIAction(title: internoPieno ? "Incolla da iPad" : "Incolla", image: UIImage(systemName: "doc.on.clipboard.fill")) { [weak self] _ in
                self?.incollaDiSistema()
            })
        }
        voci.append(UIAction(title: "Seleziona", image: UIImage(systemName: "lasso")) { [weak self] _ in self?.passaAlLazo() })
        voci.append(UIAction(title: "Testo", image: UIImage(systemName: "textformat")) { [weak self] _ in
            guard let (p, pp, _) = self?.punto, let model = self?.model else { return }
            let s = model.corrente
            model.bozzaTesto = BozzaTesto(pagina: p, punto: pp, testo: "", corpo: s?.tipo == .testo ? CGFloat(s!.spessore) : 18,
                                          colore: s?.tipo == .testo ? s!.colore.ui : .black, esistente: nil)
        })
        voci.append(UIAction(title: "Immagine", image: UIImage(systemName: "photo.badge.plus")) { [weak self] _ in
            guard let (p, pp, _) = self?.punto else { return }
            self?.model?.richiediImmagine(pagina: p, punto: pp)
        })
        _ = model
        return UIMenu(options: .displayInline, children: voci)
    }

    private func passaAlLazo() {
        guard let model else { return }
        if let l = model.strumenti.first(where: { $0.tipo == .lazo }) { model.seleziona(l.id) } else { model.aggiungi(.lazo) }
        model.avviso("Lazo attivo: cerchia ciò che vuoi selezionare.")
    }

    /// Appunti interni dell'app (copiati col lazo, con il testo o con l'immagine)
    private func incollaInterno() {
        guard let (p, pp, pv) = punto, let model else { return }
        if LazoSelezione.haAppunti, let lazo = model.lazo, let tela = model.canvases[p] {
            lazo.canvas = tela
            lazo.puntoIncolla = tela.convert(pv, from: model.pdfView)
            lazo.incolla()
        } else if TestoControllo.appunti != nil, let t = model.controlloTesto {
            t.puntoVuoto = (p, pp)
            t.incolla()
        } else if ImmagineControllo.appunti != nil, let i = model.controlloImmagini {
            i.puntoVuoto = (p, pp)
            i.incolla()
        }
    }

    /// Appunti di sistema: PDF, immagine o testo copiati in un'altra app
    private func incollaDiSistema() {
        guard let (p, pp, _) = punto, let model else { return }
        let pb = UIPasteboard.general
        if let dati = pb.data(forPasteboardType: UTType.pdf.identifier), let doc = PDFDocument(data: dati), doc.pageCount > 0 {
            model.pdfTrascinato = DocumentoScelto(documento: doc, nome: "PDF incollato", aggiungeAlDocumento: true)
        } else if let img = pb.image, let dati = img.pngData() ?? img.jpegData(compressionQuality: 0.9) {
            if model.controlloImmagini?.inserisci(dati, pagina: p, punto: pp) != true { model.avviso("Immagine non leggibile.") }
        } else if let testo = pb.string, !testo.isEmpty {
            metti(testo: testo, pagina: p, punto: pp)
        }
    }

    fileprivate func metti(testo: String, pagina: PDFPage, punto pp: CGPoint) {
        guard let model, let c = model.controlloTesto else { return }
        let s = model.corrente
        let box = pagina.bounds(for: .cropBox)
        let corpo: CGFloat = s?.tipo == .testo ? CGFloat(s!.spessore) : 18
        let colore: UIColor = s?.tipo == .testo ? s!.colore.ui : .black
        let x = max(box.minX + 10, min(pp.x, box.maxX - 220))
        let y = max(box.minY + corpo * 2, min(pp.y, box.maxY - 10))
        var e = ElementoTesto(testo: testo.trimmingCharacters(in: .whitespacesAndNewlines), punto: CGPoint(x: x, y: y), corpo: corpo, colore: colore)
        e.larghezza = min(400, box.maxX - x - 10)
        c.cambia(pagina, togli: nil, metti: e)
        model.avviso("Testo aggiunto.")
    }

    // MARK: Trascinamento da altre app

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession == nil && model?.document != nil
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let model, let v = model.pdfView else { return }
        let pv = session.location(in: v)
        var passo: CGFloat = 0
        for item in session.items {
            let proveniente = item.itemProvider
            let spostamento = passo
            passo += 24
            gestisci(proveniente, pv: CGPoint(x: pv.x + spostamento, y: pv.y + spostamento), model: model)
        }
    }

    private func tipoDocumento(_ pr: NSItemProvider) -> String? {
        let ammessi: [UTType] = [.pdf, .rtf, .html] + TipoWord.tipi
        for id in pr.registeredTypeIdentifiers {
            guard let t = UTType(id) else { continue }
            if ammessi.contains(where: { t.conforms(to: $0) }) { return id }
            if t.conforms(to: .plainText), pr.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return id }   // file .txt, non testo selezionato
        }
        return nil
    }

    private func gestisci(_ pr: NSItemProvider, pv: CGPoint, model: NotesModel) {
        // 1. PDF e documenti: si aggiungono al file
        if let id = tipoDocumento(pr) {
            pr.loadFileRepresentation(forTypeIdentifier: id) { url, _ in
                guard let url else { DispatchQueue.main.async { model.avviso("Non riesco a leggere il file trascinato.") }; return }
                let ext = url.pathExtension.isEmpty ? (UTType(id)?.preferredFilenameExtension ?? "") : url.pathExtension
                let base = (pr.suggestedName.map { ($0 as NSString).deletingPathExtension } ?? url.deletingPathExtension().lastPathComponent)
                let cartella = FileManager.default.temporaryDirectory.appendingPathComponent("trascinato-" + UUID().uuidString, isDirectory: true)
                let copia = cartella.appendingPathComponent(base + (ext.isEmpty ? "" : "." + ext))
                do {
                    try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copia)
                } catch {
                    DispatchQueue.main.async { model.avviso("Non riesco a leggere il file trascinato.") }
                    return
                }
                DispatchQueue.main.async { model.fileTrascinato = copia }
            }
            return
        }
        // 2. Foto e immagini: vanno dove si lascia il dito
        if pr.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            pr.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { dati, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, let dati, let (p, pp) = self.paginaPunto(pv, model) else { model.avviso("Immagine non leggibile."); return }
                    if model.controlloImmagini?.inserisci(dati, pagina: p, punto: pp) == true { model.avviso("Immagine aggiunta.") }
                    else { model.avviso("Immagine non leggibile.") }
                }
            }
            return
        }
        // 3. Testo (anche un indirizzo web)
        if pr.canLoadObject(ofClass: NSString.self) {
            _ = pr.loadObject(ofClass: NSString.self) { oggetto, _ in
                let testo = (oggetto as? NSString).map { $0 as String } ?? ""
                DispatchQueue.main.async { [weak self] in
                    guard let self, !testo.isEmpty, let (p, pp) = self.paginaPunto(pv, model) else { return }
                    self.metti(testo: testo, pagina: p, punto: pp)
                }
            }
            return
        }
        model.avviso("Questo tipo di elemento non si può aggiungere.")
    }

    private func paginaPunto(_ pv: CGPoint, _ model: NotesModel) -> (PDFPage, CGPoint)? {
        guard let v = model.pdfView, let p = v.page(for: pv, nearest: true) else { return nil }
        return (p, v.convert(pv, to: p))
    }
}
