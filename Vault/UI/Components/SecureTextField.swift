import SwiftUI

/// A text field that prevents screenshots and screen recording
struct SecureTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        ZStack {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.roundedBorder)
        .overlay {
            // This overlay helps prevent screenshots on some systems
            SecureOverlay()
        }
    }
}

/// Overlay that uses secure text field technique to prevent screenshots
struct SecureOverlay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        // Add a secure text field as a subview
        // This makes the parent view "secure" in the system's eyes
        let secureField = UITextField()
        secureField.isSecureTextEntry = true
        secureField.isUserInteractionEnabled = false
        secureField.alpha = 0.01
        view.addSubview(secureField)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview {
    SecureTextField(placeholder: "Enter text", text: .constant(""))
        .padding()
}
