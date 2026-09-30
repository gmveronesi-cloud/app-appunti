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
        .tint(.red)
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
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text("Scegli la cartella della libreria")
                .font(.system(size: 22, weight: .bold))
            Button {
                store.importerForRoot = true
                store.showImporter = true
            } label: {
                Label("Scegli cartella", systemImage: "folder")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .aptProminentButton()
            .controlSize(.large)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
        .sheet(item: $store.sheet) { sheet in
            AptSheetView(sheet: sheet).environmentObject(store)
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
