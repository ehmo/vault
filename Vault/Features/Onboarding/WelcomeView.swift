import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    @State private var animateIcon = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 20)

                    // App Logo
                    Image("VaultLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .scaleEffect(animateIcon ? 1.05 : 1.0)
                        .accessibilityHidden(true)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                animateIcon = true
                            }
                        }

                    // Welcome Text
                    VStack(spacing: 12) {
                        Text("Welcome to Vaultaire")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Secure storage with plausible deniability")
                            .font(.title3)
                            .foregroundStyle(.vaultSecondaryText)
                    }

                    // Feature Rows
                    VStack(alignment: .leading, spacing: 24) {
                        FeatureRow(
                            icon: "hand.draw",
                            title: "Pattern-Based Encryption",
                            description: "Each pattern creates a unique encrypted vault. Different patterns = different vaults."
                        )

                        FeatureRow(
                            icon: "eye.slash",
                            title: "True Plausible Deniability",
                            description: "Nobody can tell how many vaults you have. Every pattern shows a vault."
                        )

                        FeatureRow(
                            icon: "lock.shield",
                            title: "Hardware Security",
                            description: "Your encryption keys are protected by your device's Secure Enclave."
                        )

                        FeatureRow(
                            icon: "icloud",
                            title: "Encrypted Backup",
                            description: "Back up to your iCloud. Only you can decrypt it with your pattern."
                        )
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 20)

                    // Continue Button
                    Button(action: onContinue) {
                        Text("Protect Your First Vault")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .vaultProminentButtonStyle()
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
