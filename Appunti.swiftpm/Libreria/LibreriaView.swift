// Radice e schermata Libreria
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Radice

struct LibreriaAppuntiView: View {
    @StateObject private var store = AptStore()

    var body: some View {
        Group {
            if store.rootURL == nil {
                AptWelcomeView()
            } else {
                AptLibraryView()
            }
        }
        .environmentObject(store)
        .tint(AptTema.accento)
        .overlay { OrologioRiquadro() }
        .onOpenURL { url in store.riceviEsterno([url]) }
        .overlay(alignment: .top) {
            if let m = store.messaggio {
                Text(m)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AptTema.testo)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(AptTema.carta))
                    .overlay(Capsule().strokeBorder(AptTema.linea, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.messaggio)
        .fileImporter(
            isPresented: $store.showImporter,
            allowedContentTypes: store.importerForRoot ? [UTType.folder] : [UTType.pdf],
            allowsMultipleSelection: !store.importerForRoot
        ) { result in
            switch result {
            case .success(let urls):
                if store.importerForRoot {
                    if let u = urls.first { store.setRoot(u) }
                } else {
                    store.importPDFs(urls, into: store.importTarget)
                }
            case .failure(let error):
                store.fail(error)
            }
        }
        .alert("Attenzione", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct AptWelcomeView: View {
    @EnvironmentObject var store: AptStore
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(AptTema.accento)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: AptTema.raggioL, style: .continuous).fill(AptTema.accentoTenue))
                .padding(.bottom, 8)
            Text("Scegli la cartella della libreria")
                .font(AptTema.titoloGrande)
                .foregroundColor(AptTema.testo)
            Button {
                store.importerForRoot = true
                store.showImporter = true
            } label: {
                Label("Scegli cartella", systemImage: "folder")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .aptProminentButton()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AptTema.sfondo)
    }
}

// MARK: - Schermata Libreria (barra laterale + contenuto)

struct AptLibraryView: View {
    @EnvironmentObject var store: AptStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AptSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
                .aptHideSidebarToggle()
        } detail: {
            AptMainView(toggleSidebar: {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            })
            .aptHideSidebarToggle()
        }
        .navigationSplitViewStyle(.balanced)
        .background(AptTema.sfondo)
        .sheet(item: $store.sheet, onDismiss: {
            if !store.selectionMode { store.selected = [] }
        }) { sheet in
            AptSheetView(sheet: sheet).environmentObject(store)
        }
        .sheet(item: $store.renaming) { target in
            AptRenameSheet(target: target).environmentObject(store)
        }
        .fullScreenCover(item: $store.openDocument) { doc in
            EditorView(doc: doc).environmentObject(store)
        }
        .confirmationDialog(
            store.pendingDelete.map { $0.count == 1 ? "Eliminare 1 elemento?" : "Eliminare \($0.count) elementi?" } ?? "",
            isPresented: Binding(
                get: { store.pendingDelete != nil },
                set: { if !$0 { store.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                if let p = store.pendingDelete { store.delete(docs: p.docs, folders: p.folders) }
                store.pendingDelete = nil
            }
            Button("Annulla", role: .cancel) { store.pendingDelete = nil }
        } message: {
            Text("I file vengono eliminati anche da iCloud Drive / File. Le cartelle vengono eliminate con tutto il loro contenuto.")
        }
    }
}
