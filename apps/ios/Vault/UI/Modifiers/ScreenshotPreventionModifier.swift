import SwiftUI
import UIKit

/// A view modifier that prevents screenshots by using the secure text field technique.
/// When applied to a view, it makes that view "secure" in iOS's eyes, preventing screenshots.
struct ScreenshotPreventionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                SecureFieldOverlay()
                    .allowsHitTesting(false)
                    .opacity(0.01) // Nearly invisible but still effective
            )
    }
}

/// UIViewRepresentable that adds a secure text field to prevent screenshots
private struct SecureFieldOverlay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = false

        // Add a secure text field as a subview
        // This makes the parent view "secure" in the system's eyes
        let secureField = UITextField()
        secureField.isSecureTextEntry = true
        secureField.isUserInteractionEnabled = false
        secureField.alpha = 0.01 // Nearly invisible

        containerView.addSubview(secureField)

        // Pin secure field to edges
        secureField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            secureField.topAnchor.constraint(equalTo: containerView.topAnchor),
            secureField.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            secureField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // No updates needed
    }
}

extension View {
    /// Prevents screenshots by applying a secure overlay to this view.
    /// The overlay uses the secure text field technique to mark the view as sensitive.
    func preventScreenshots() -> some View {
        modifier(ScreenshotPreventionModifier())
    }
}
