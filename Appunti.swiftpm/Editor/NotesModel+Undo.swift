// Annulla e ripeti per pagina.
// Prima c'era una sola cronologia per tutto il documento: annullare su una pagina poteva toccare un'altra. Ora ogni pagina ha la sua
// (`undoPagine`): i tratti, le immagini e i testi di quella pagina. Finita la sua cronologia, annulla si spegne finché si resta su quella
// pagina; spostandosi su un'altra si può annullare ciò che si è fatto lì. Le operazioni sul documento (aggiungere, togliere, spostare pagine,
// cambiare sfondo) hanno una cronologia generale (`undoGenerale`) che si usa per prima e si azzera appena si scrive su una pagina.
//
// Memoria: al massimo `livelliPagina` passi per pagina; la cronologia di una pagina sparisce con la sua tela (le azioni puntano a quella tela:
// tenerle la terrebbe in memoria), quindi pesa al massimo quanto le tele tenute vive (vedi NotesModel+Memoria); su avviso di memoria
// restano solo le cronologie della pagina in uso. Chiudendo o cambiando documento tutto si azzera.
import UIKit
import PDFKit

extension NotesModel {
    static let livelliPagina = 20

    /// La cronologia di una pagina (si crea al bisogno). Senza pagina: quella generale.
    func gestoreUndo(per pagina: PDFPage?) -> UndoManager {
        guard let pagina else { return undoGenerale }
        if let u = undoPagine[pagina] { return u }
        let u = UndoManager()
        u.levelsOfUndo = Self.livelliPagina
        undoPagine[pagina] = u
        return u
    }

    /// La pagina a cui si riferiscono annulla e ripeti: l'ultima su cui si è scritto, finché non si cambia pagina; altrimenti quella corrente
    var paginaUndo: PDFPage? {
        if let p = paginaLavoro, let d = document, d.index(for: p) != NSNotFound { return p }
        return pdfView?.currentPage
    }

    /// La pagina non esiste più o la sua tela è stata buttata: la sua cronologia non serve più
    func scartaUndo(_ pagina: PDFPage) {
        undoPagine[pagina]?.removeAllActions()
        undoPagine[pagina] = nil
        if paginaLavoro === pagina { paginaLavoro = nil }
    }

    /// Poca memoria: si tengono solo le cronologie della pagina in uso
    func alleggerisciUndo() {
        let uso = paginaUndo
        for (p, u) in undoPagine where p !== uso { u.removeAllActions() }
        aggiornaUndo()
    }

    /// La pagina ha qualcosa da annullare o ripetere (serve a scegliere quali tele buttare per ultime)
    func haCronologia(_ pagina: PDFPage) -> Bool {
        guard let u = undoPagine[pagina] else { return false }
        return u.canUndo || u.canRedo
    }

    /// I pulsanti Annulla e Ripeti seguono la cronologia della pagina in uso.
    /// NIENTE `NSUndoManagerCheckpoint`: leggere canUndo/canRedo lo fa scattare, e quindi l'aggiornamento
    /// richiamava se stesso all'infinito (con due riquadri, raddoppiando a ogni giro: era la lentezza della vista doppia).
    func osservaUndo() {
        for o in osservatoriVista { NotificationCenter.default.removeObserver(o) }
        osservatoriVista = []
        let nomi: [Notification.Name] = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup,
                                         .NSUndoManagerDidOpenUndoGroup]
        for nome in nomi {
            let o = NotificationCenter.default.addObserver(forName: nome, object: nil, queue: .main) { [weak self] n in
                guard let self, let um = n.object as? UndoManager else { return }
                if um !== self.undoGenerale {
                    guard let pagina = self.undoPagine.first(where: { $0.value === um })?.key else { return }
                    // Un'azione nuova su una pagina: si lavora lì, e le operazioni generali precedenti non si possono più annullare
                    if n.name == .NSUndoManagerDidCloseUndoGroup && !um.isUndoing && !um.isRedoing {
                        self.paginaLavoro = pagina
                        self.undoGenerale.removeAllActions()
                    }
                }
                self.programmaAggiornaUndo()
            }
            osservatoriVista.append(o)
        }
        // Cambiando pagina cambia anche la cronologia a cui si riferiscono i pulsanti
        if let v = pdfView {
            let o = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [weak self] _ in
                self?.paginaLavoro = nil
                self?.programmaAggiornaUndo()
            }
            osservatoriVista.append(o)
        }
    }
}
