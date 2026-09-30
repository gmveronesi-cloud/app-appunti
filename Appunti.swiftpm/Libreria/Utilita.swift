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

struct AptNameField: UIViewRepresentable {
    let initial: String
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.text = initial
        tf.placeholder = "Nome"
        tf.font = .systemFont(ofSize: 13.5)
        tf.returnKeyType = .done
        tf.autocorrectionType = .no
        tf.clearButtonMode = .whileEditing
        tf.borderStyle = .roundedRect
        tf.delegate = context.coordinator
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.field = tf
        context.coordinator.requestFocus(attempt: 0)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {}

    final class Coordinator: NSObject, UITextFieldDelegate {
        let onCommit: (String) -> Void
        weak var field: UITextField?
        var done = false
        init(onCommit: @escaping (String) -> Void) { self.onCommit = onCommit }

        // Riprova più volte: subito dopo il menu contestuale la vista può non essere ancora pronta.
        func requestFocus(attempt: Int) {
            let delay = attempt == 0 ? 0.2 : 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.done, let tf = self.field else { return }
                if tf.window != nil, tf.becomeFirstResponder() {
                    tf.selectAll(nil)
                } else if attempt < 8 {
                    self.requestFocus(attempt: attempt + 1)
                }
            }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
        func textFieldDidEndEditing(_ textField: UITextField) { finish(textField.text ?? "") }
        private func finish(_ text: String) {
            if done { return }
            done = true
            onCommit(text)
        }
    }
}

struct AptShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
