// Menu delle miniature: taglia, copia, duplica, elimina, colore e modello, «conta come prima pagina»
import SwiftUI
import PDFKit
import PencilKit

/// Una pagina copiata, con tutto ciò che l'app ci aveva messo sopra
struct PaginaCopiata {
    let pagina: PDFPage
    let tratti: PKDrawing?
    let immagini: [ElementoImmagine]
    let testi: [ElementoTesto]
    let originale: CGRect?
    let modello: ModelloPagina?
}

/// Appunti delle pagine: valgono per tutti i documenti aperti (schede e vista doppia)
final class AppuntiPagine: ObservableObject {
    static let condivisi = AppuntiPagine()
    @Published var pagine: [PaginaCopiata] = []
}

extension NotesModel {
    static let nomeModello = "AptModello"                              // annotazione nascosta: colore e modello della pagina
    static let chiaveModello = PDFAnnotationKey(rawValue: "/AptModello")
    static let nomePrima = "AptPrima"                                  // annotazione nascosta: da qui si conta 1
    static let chiavePrima = PDFAnnotationKey(rawValue: "/AptPrima")

    static func annotazioneNascosta(nome: String, chiave: PDFAnnotationKey, valore: String, box: CGRect) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: box.minX, y: box.minY, width: 1, height: 1), forType: .square, withProperties: nil)
        a.userName = nome
        a.shouldDisplay = false
        a.shouldPrint = false
        _ = a.setValue(valore, forAnnotationKey: chiave)
        return a
    }

    // MARK: Numerazione

    /// Posizione (da 0) della pagina che conta come prima, se c'è e sta ancora nel documento
    var indicePrima: Int? {
        guard let document, let p = paginaUno else { return nil }
        let i = document.index(for: p)
        return i == NSNotFound ? nil : i
    }

    /// Numero mostrato per la pagina in posizione `i`: dalla pagina «uno» in poi 1, 2, 3…; prima di essa i, ii, iii…
    static func etichetta(_ i: Int, inizio: Int?) -> String {
        guard let inizio else { return "\(i + 1)" }
        return i >= inizio ? "\(i - inizio + 1)" : romano(i + 1)
    }

    static func romano(_ n: Int) -> String {
        let tabella: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                                        (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var resto = n
        var testo = ""
        for (valore, simbolo) in tabella {
            while resto >= valore { testo += simbolo; resto -= valore }
        }
        return testo
    }

    func eLaPrima(_ i: Int) -> Bool { indicePrima == i }

    func contaComePrima(_ i: Int) {
        guard let p = document?.page(at: i) else { return }
        if paginaUno === p {
            paginaUno = nil
            avviso("Si torna a contare dalla prima pagina del documento.")
        } else {
            paginaUno = p
            avviso(i == 0 ? "La pagina 1 è la prima." : "Da questa pagina si conta 1; le precedenti in numeri romani.")
        }
        strutturaCambiata = true
        modificato = true
        versionePagine += 1
    }

    // MARK: Pagine di sola scrittura

    func modello(della i: Int) -> ModelloPagina? {
        guard let p = document?.page(at: i) else { return nil }
        return modelli[p]
    }

    func eDiScrittura(_ i: Int) -> Bool { modello(della: i) != nil }

    /// Cambia colore e modello: la pagina si rifà con il nuovo sfondo, tratti, immagini e testi restano. Annullabile.
    func applicaModello(_ nuovo: ModelloPagina, allaPagina i: Int) {
        guard let document, let vecchia = document.page(at: i) else { return }
        applicaModello(nuovo, pagina: vecchia)
    }

    func applicaModello(_ nuovo: ModelloPagina, pagina vecchia: PDFPage) {
        guard let document else { return }
        let i = document.index(for: vecchia)
        guard i != NSNotFound else { return }
        let precedente = modelli[vecchia] ?? .bianca
        guard nuovo != precedente || modelli[vecchia] == nil else { return }
        let box = vecchia.bounds(for: .cropBox)
        guard let nuovaPagina = ModelloPagina.creaPagina(nuovo, box: box) else { message = "Non riesco a cambiare lo sfondo."; return }
        let dati = istantanea(vecchia)
        lazo?.deseleziona()
        controlloImmagini?.annullaSelezione()
        controlloTesto?.resetta()

        document.removePage(at: i)
        document.insert(nuovaPagina, at: i)
        trattiSalvati[vecchia] = nil
        immagini[vecchia] = nil
        testi[vecchia] = nil
        sotto[vecchia] = nil
        canvases[vecchia] = nil
        contenitori[vecchia] = nil
        trattiSalvati[nuovaPagina] = dati.tratti
        if !dati.immagini.isEmpty { immagini[nuovaPagina] = dati.immagini }
        if !dati.testi.isEmpty { testi[nuovaPagina] = dati.testi }
        if let o = originali[vecchia] { originali[nuovaPagina] = o }
        originali[vecchia] = nil
        modelli[vecchia] = nil
        modelli[nuovaPagina] = nuovo
        if paginaUno === vecchia { paginaUno = nuovaPagina }

        strutturaCambiata = true
        modificato = true
        versionePagine += 1
        pdfView?.layoutDocumentView()
        pdfView?.go(to: nuovaPagina)
        pdfView?.undoManager?.registerUndo(withTarget: self) { s in s.applicaModello(precedente, pagina: nuovaPagina) }
        avviso("Pagina cambiata.")
    }

    // MARK: Taglia, copia, duplica, elimina, incolla

    /// La pagina com'è adesso, con i tratti in punti di pagina (anche quelli ancora sulla tela)
    func istantanea(_ page: PDFPage) -> DatiPagina {
        var disegno: PKDrawing?
        if let canvas = canvases[page], canvas.bounds.width > 0 {
            let f = page.bounds(for: .cropBox).width / canvas.bounds.width
            disegno = PKDrawing(strokes: tuttiITratti(page)).transformed(using: CGAffineTransform(scaleX: f, y: f))
        } else {
            disegno = trattiSalvati[page]
        }
        if let d = disegno, d.strokes.isEmpty { disegno = nil }
        return DatiPagina(pagina: page, tratti: disegno, immagini: immagini[page] ?? [], testi: testi[page] ?? [])
    }

    private func copiaDi(_ i: Int) -> PaginaCopiata? {
        guard let document, let page = document.page(at: i), let copia = page.copy() as? PDFPage else { return nil }
        let d = istantanea(page)
        return PaginaCopiata(pagina: copia, tratti: d.tratti, immagini: d.immagini, testi: d.testi,
                             originale: originali[page], modello: modelli[page])
    }

    /// Una pagina nuova (copia indipendente) pronta per essere inserita nel documento
    private func nuovaDa(_ c: PaginaCopiata) -> DatiPagina? {
        guard let nuova = c.pagina.copy() as? PDFPage else { return nil }
        if let o = c.originale { originali[nuova] = o }
        if let m = c.modello { modelli[nuova] = m }
        let immagini = c.immagini.map { e -> ElementoImmagine in var x = e; x.id = UUID(); return x }
        let testi = c.testi.map { e -> ElementoTesto in var x = e; x.id = UUID(); return x }
        return DatiPagina(pagina: nuova, tratti: c.tratti, immagini: immagini, testi: testi)
    }

    func copia(_ i: Int) {
        guard let c = copiaDi(i) else { message = "Non riesco a copiare la pagina."; return }
        AppuntiPagine.condivisi.pagine = [c]
        avviso("Pagina copiata.")
    }

    func taglia(_ i: Int) {
        guard let document, document.pageCount > 1 else { avviso("Il documento deve avere almeno una pagina."); return }
        guard let c = copiaDi(i), let page = document.page(at: i) else { message = "Non riesco a tagliare la pagina."; return }
        AppuntiPagine.condivisi.pagine = [c]
        togliPagine([istantanea(page)])
        avviso("Pagina tagliata.")
    }

    func elimina(_ i: Int) {
        guard let document, document.pageCount > 1 else { avviso("Il documento deve avere almeno una pagina."); return }
        guard let page = document.page(at: i) else { return }
        togliPagine([istantanea(page)])
        avviso("Pagina eliminata.")
    }

    func duplica(_ i: Int) {
        guard let c = copiaDi(i), let d = nuovaDa(c) else { message = "Non riesco a duplicare la pagina."; return }
        rimettiPagine([d], da: i + 1)
        avviso("Pagina duplicata.")
    }

    func incolla(dopo i: Int) {
        guard let c = AppuntiPagine.condivisi.pagine.first, let d = nuovaDa(c) else { return }
        rimettiPagine([d], da: i + 1)
        avviso("Pagina incollata.")
    }
}

/// I tre pallini al centro di ogni miniatura
struct MenuPaginaMiniatura: View {
    @ObservedObject var model: NotesModel
    @ObservedObject private var appunti = AppuntiPagine.condivisi
    let indice: Int
    let scegliModello: (Int) -> Void

    var body: some View {
        Menu {
            Button { model.taglia(indice) } label: { Label("Taglia", systemImage: "scissors") }
            Button { model.copia(indice) } label: { Label("Copia", systemImage: "doc.on.doc") }
            Button { model.duplica(indice) } label: { Label("Duplica", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { model.elimina(indice) } label: { Label("Elimina", systemImage: "trash") }
            if model.eDiScrittura(indice) {
                Button { scegliModello(indice) } label: { Label("Colore e modello pagina", systemImage: "paintbrush") }
            }
            Button { model.contaComePrima(indice) } label: {
                Label(model.eLaPrima(indice) ? "Non contare come prima pagina" : "Conta come prima pagina", systemImage: "1.square")
            }
            if !appunti.pagine.isEmpty {
                Button { model.incolla(dopo: indice) } label: { Label("Incolla dopo", systemImage: "doc.on.clipboard") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AptTema.testo)
                .frame(width: 38, height: 38)
                .background(Circle().fill(AptTema.carta.opacity(0.88)))
                .overlay(Circle().stroke(AptTema.linea, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel("Azioni della pagina")
    }
}
