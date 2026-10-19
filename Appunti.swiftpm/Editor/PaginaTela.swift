// Contenitore della tela Pencil di una pagina.
//
// PDFView ingrandisce la vista di sovrapposizione insieme alla pagina, ma PencilKit disegna i tratti
// alla risoluzione della propria tela: ingrandita, restava sgranata (verificato nel simulatore:
// le tele misurano 595×842 punti, la pagina è mostrata a 1,7×). Qui la tela è `k` volte più grande
// della pagina e rimpicciolita di `1/k`: PencilKit disegna con `k` volte i dettagli e, a schermo,
// la tela occupa lo stesso spazio della pagina.
//
// Conseguenza: le coordinate dei tratti sono `k` volte i punti della pagina. Spessori, soglie e
// dimensioni dei segni di selezione nel codice si moltiplicano per `k` (= 1 / transform.a della tela).
import UIKit
import PencilKit

/// Tela che usa la cronologia di annulla della SUA pagina invece di quella condivisa della finestra:
/// PencilKit registra i tratti nell'`undoManager` della tela, quindi basta restituire quello della pagina (vedi NotesModel+Undo).
final class TelaPencil: PKCanvasView {
    var gestoreAnnulla: UndoManager?
    override var undoManager: UndoManager? { gestoreAnnulla ?? super.undoManager }

    // Con un tocco del dito PencilKit mostrava il suo menu «Select All / Insert Space»: qui non serve (selezione e spostamento
    // si fanno con il lazo). Si tolgono le sue interazioni di menu dalla tela e non si accettano azioni dal menu di sistema.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    override func didMoveToWindow() { super.didMoveToWindow(); togliMenuDiSistema() }
    override func layoutSubviews() { super.layoutSubviews(); togliMenuDiSistema() }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        togliMenuDiSistema()          // PencilKit può aggiungerlo con un attimo di ritardo
        super.touchesBegan(touches, with: event)
    }

    func togliMenuDiSistema() {
        func pulisci(_ v: UIView) {
            for i in v.interactions where i is UIEditMenuInteraction { v.removeInteraction(i) }
            v.subviews.forEach(pulisci)
        }
        pulisci(self)
    }
}

final class PaginaTela: UIView {
    let canvas = TelaPencil(frame: .zero)

    init(dimensione: CGSize, k: CGFloat) {
        super.init(frame: CGRect(origin: .zero, size: dimensione))
        backgroundColor = .clear
        isOpaque = false
        canvas.layer.anchorPoint = .zero
        canvas.bounds = CGRect(x: 0, y: 0, width: dimensione.width * k, height: dimensione.height * k)
        canvas.layer.position = .zero
        canvas.transform = CGAffineTransform(scaleX: 1 / k, y: 1 / k)
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }
}

extension PKCanvasView {
    /// Quante volte la tela è più grande della pagina (1 se non è dentro una `PaginaTela`)
    var fattoreRisoluzione: CGFloat { transform.a > 0 ? 1 / transform.a : 1 }
}
