// Utilità di interfaccia
import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Utilità di interfaccia

struct AptSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
extension View {
    func aptReadSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: AptSizeKey.self, value: g.size) })
            .onPreferenceChange(AptSizeKey.self, perform: onChange)
    }
    @ViewBuilder func aptHideSidebarToggle() -> some View {
        if #available(iOS 17.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
    /// Pulsante "pillola" principale: vetro liquido di sistema su iPadOS 26+, standard prima.
    @ViewBuilder func aptProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

struct AptSegOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var icon: String? = nil
    var id: T { value }
}
struct AptSegmented<T: Hashable>: View {
    let options: [AptSegOption<T>]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                Button {
                    selection = o.value
                } label: {
                    HStack(spacing: 5) {
                        if let ic = o.icon { Image(systemName: ic).font(.system(size: 13)) }
                        Text(o.label).font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundColor(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selection == o.value ? Color(.secondarySystemGroupedBackground) : Color.clear)
                            .shadow(color: .black.opacity(selection == o.value ? 0.15 : 0), radius: 1.5, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(.systemFill)))
    }
}

struct AptShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
