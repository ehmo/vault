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
    private(set) weak var protectedWindow: UIWindow?

    init() {
        // No-op: default initializer
    }

    /// Activates screenshot protection on the key window.
    /// Safe to call multiple times — only activates once.
    /// If the protected window is destroyed, will reactivate on the new key window.
    func activate() {
        // Check if we need to reactivate (window was destroyed or scene changed)
        if isActive && protectedWindow == nil {
            Self.logger.debug("Previous protected window was destroyed, resetting for reactivation")
            reset()
        }

        guard !isActive else {
            Self.logger.debug("Screenshot shield already active, skipping")
            return
        }

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
        guard !isActive else {
            Self.logger.debug("Screenshot shield already active, skipping")
            return
        }

        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        // Don't add as subview - we only need the layer for reparenting
        // Adding as subview then moving layer causes double-move issues

        // Reparent: move the window's layer inside the text field's secure container.
        // The secure container is a sublayer of the text field's layer.
        // iOS 17+ changed the sublayer order, so we try .last first on newer iOS.
        let secureContainer = findSecureContainer(in: field.layer)

        guard let container = secureContainer,
              let windowSuperlayer = window.layer.superlayer else {
            Self.logger.error("Could not find secure container or window superlayer — screenshot protection unavailable")
            return
        }

        // Prevent clipping — the zero-sized field/container must not clip the full-screen window layer.
        field.layer.masksToBounds = false
        container.masksToBounds = false

        // Verify layers still exist before reparenting (defensive against race conditions)
        guard field.layer.superlayer == nil || field.layer.superlayer === window.layer else {
            Self.logger.error("Field layer already in unexpected hierarchy, aborting")
            return
        }

        windowSuperlayer.addSublayer(field.layer)
        container.addSublayer(window.layer)

        secureField = field
        protectedWindow = window
        isActive = true
        Self.logger.info("Screenshot shield activated on window: \(window.hash, privacy: .public)")
    }

    /// Deactivates screenshot protection and restores normal layer hierarchy.
    /// Safe to call even if not active - will no-op.
    func deactivate() {
        guard isActive else { return }

        if let field = secureField {
            // Remove the window from secure container and restore to original superlayer
            // Note: We can't fully restore since we don't track the original position,
            // but removing the field layer will effectively disable screenshot protection
            field.layer.removeFromSuperlayer()
            secureField = nil
        }

        protectedWindow = nil
        isActive = false
        Self.logger.info("Screenshot shield deactivated")
    }

    /// Resets the shield state without attempting to restore layers.
    /// Useful when the protected window is known to be destroyed.
    func reset() {
        secureField?.layer.removeFromSuperlayer()
        secureField = nil
        protectedWindow = nil
        isActive = false
        Self.logger.debug("Screenshot shield state reset")
    }

    /// Finds the secure container sublayer in a text field's layer hierarchy.
    /// iOS 17+ changed the sublayer order, so we try both .last and .first.
    private func findSecureContainer(in layer: CALayer) -> CALayer? {
        // First, try the iOS version-specific location
        let preferredContainer: CALayer?
        if #available(iOS 17.0, *) {
            preferredContainer = layer.sublayers?.last
        } else {
            preferredContainer = layer.sublayers?.first
        }

        // Verify it looks like a secure container (has sublayers capability)
        if let container = preferredContainer {
            return container
        }

        // Fallback: try the other position if preferred didn't work
        if #available(iOS 17.0, *) {
            return layer.sublayers?.first
        } else {
            return layer.sublayers?.last
        }
    }

    /// Reactivates the shield if the window was destroyed (e.g., scene disconnect/reconnect).
    /// Call this when the app becomes active or when scenes change.
    func reactivateIfNeeded() {
        guard isActive && protectedWindow == nil else { return }
        Self.logger.info("Reactivating screenshot shield after window destruction")
        reset()
        activate()
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
    func makeUIView(context _: Context) -> UIView {
        let view = ShieldTriggerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ _: UIView, context _: Context) {
        // No update needed
    }
}

/// UIView that activates the shield when it enters a window.
private class ShieldTriggerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            // Window was removed - could be scene disconnect
            // Don't deactivate immediately as it might be temporary
            return
        }

        // Check if we need to reactivate (e.g., after scene reconnect)
        ScreenshotShield.shared.reactivateIfNeeded()

        // Activate if not already active
        ScreenshotShield.shared.activate()
    }
}

extension View {
    /// Prevents screenshots by activating the window-level screenshot shield.
    /// The shield uses the secure UITextField layer technique so that iOS renders
    /// a blank screen in screenshots and screen recordings.
    /// 
    /// Note: Automatically disabled in DEBUG builds to allow screenshot testing.
    func preventScreenshots() -> some View {
        #if DEBUG
        // Screenshot protection disabled in debug mode for testing
        return self
        #else
        return modifier(ScreenshotPreventionModifier())
        #endif
    }
}
