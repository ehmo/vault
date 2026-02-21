import SwiftUI

// MARK: - Toast Model

struct ToastMessage: Equatable {
    let icon: String
    let message: String

    static func fileEncrypted() -> Self { .init(icon: "lock.fill", message: "File encrypted and saved") }
    static func filesImported(_ count: Int) -> Self { .init(icon: "lock.fill", message: "\(count) file\(count == 1 ? "" : "s") imported") }
    static func importFailed(_ failed: Int, imported: Int, reason: String? = nil) -> Self {
        var msg: String
        if imported > 0 {
            msg = "\(imported) imported, \(failed) failed"
        } else {
            msg = "\(failed) file\(failed == 1 ? "" : "s") failed to import"
        }
        if let reason, !reason.isEmpty {
            msg += ": \(reason)"
        }
        return .init(icon: "exclamationmark.triangle", message: msg)
    }
    static func filesDeleted(_ count: Int) -> Self { .init(icon: "trash", message: "\(count) file\(count == 1 ? "" : "s") deleted") }
    static func error(_ message: String) -> Self { .init(icon: "exclamationmark.triangle.fill", message: message) }
    static func exported() -> Self { .init(icon: "square.and.arrow.up", message: "Exported to Photos") }
    static func milestone(_ text: String) -> Self { .init(icon: "sparkles", message: text) }
    static func importInProgress() -> Self { .init(icon: "arrow.down.circle", message: "Import in progress — please wait") }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.body.weight(.semibold))

            Text(toast.message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?
    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                ToastView(toast: toast)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        dismissAfterDelay()
                    }
                    .onDisappear {
                        workItem?.cancel()
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toast)
    }

    private func dismissAfterDelay() {
        workItem?.cancel()
        let item = DispatchWorkItem { toast = nil }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
