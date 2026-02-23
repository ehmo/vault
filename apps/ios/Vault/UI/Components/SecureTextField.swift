import SwiftUI
import UIKit
import os.log

// MARK: - Screenshot Shield

/// Applies screenshot protection at the window level using the secure UITextField layer technique.
/// When active, iOS screenshots and screen recordings capture a blank screen.
///
/// How it works: A `UITextField` with `isSecureTextEntry = true` creates an internal secure
/// container sublayer. By reparenting the window's layer into this container, iOS treats all
/// window content as "secure" and blanks it during screenshots and recordings.
@MainActor
final class ScreenshotShield {
    static let shared = ScreenshotShield()

    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "ScreenshotShield")

    private(set) var secureField: UITextField?
    private(set) var isActive = false

    init() {}

    /// Activates screenshot protection on the key window.
    /// Safe to call multiple times — only activates once.
    func activate() {
        guard !isActive else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            Self.logger.warning("No key window found, screenshot shield not activated")
            return
        }

        activate(on: window)
    }

    /// Activates screenshot protection on the given window.
    /// Exposed as internal for testing; production code should use `activate()`.
    func activate(on window: UIWindow) {
        guard !isActive else { return }

        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        window.addSubview(field)
        // Keep field at frame .zero (origin) — do NOT add centering constraints.
        // After layer reparenting, field.layer becomes the rendering root in
        // windowSuperlayer. Any offset on field.layer shifts ALL window content.

        // Reparent: move the window's layer inside the text field's secure container.
        // The secure container is a sublayer of the text field's layer.
        // iOS 17+ changed the sublayer order, so we use .last instead of .first.
        let secureContainer: CALayer?
        if #available(iOS 17.0, *) {
            secureContainer = field.layer.sublayers?.last
        } else {
            secureContainer = field.layer.sublayers?.first
        }
        guard let container = secureContainer,
              let windowSuperlayer = window.layer.superlayer else {
            Self.logger.error("Could not find secure container or window superlayer — screenshot protection unavailable")
            field.removeFromSuperview()
            return
        }

        // Prevent clipping — the zero-sized field/container must not clip the full-screen window layer.
        field.layer.masksToBounds = false
        container.masksToBounds = false

        windowSuperlayer.addSublayer(field.layer)
        container.addSublayer(window.layer)

        secureField = field
        isActive = true
        Self.logger.info("Screenshot shield activated")
    }
}

// MARK: - Screenshot Prevention Modifier

/// View modifier that activates the window-level screenshot shield.
/// Uses the secure UITextField layer technique to make screenshots capture a blank screen.
struct ScreenshotPreventionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ScreenshotShieldActivator())
    }
}

/// Activates the screenshot shield once the view enters the window hierarchy.
private struct ScreenshotShieldActivator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ShieldTriggerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// UIView that activates the shield when it enters a window.
private class ShieldTriggerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        ScreenshotShield.shared.activate()
    }
}

extension View {
    /// Prevents screenshots by activating the window-level screenshot shield.
    /// The shield uses the secure UITextField layer technique so that iOS renders
    /// a blank screen in screenshots and screen recordings.
    func preventScreenshots() -> some View {
        modifier(ScreenshotPreventionModifier())
    }
}
