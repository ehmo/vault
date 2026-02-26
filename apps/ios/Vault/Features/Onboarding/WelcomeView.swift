import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    @State private var animateIcon = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let isCompact = h < 700 // iPhone SE, mini

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Reduced top spacing to move logo/text higher
                        Spacer().frame(height: h * 0.04)

                        // App Logo
                        Image("VaultLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: min(h * 0.15, 140), height: min(h * 0.15, 140))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            .scaleEffect(animateIcon ? 1.05 : 1.0)
                            .accessibilityHidden(true)
                            .onAppear {
                                guard !reduceMotion else { return }
                                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                    animateIcon = true
                                }
                            }

                        Spacer().frame(height: h * 0.02)

                        // Welcome Text
                        VStack(spacing: 8) {
                            Text("Welcome to Vaultaire")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Secure storage with plausible deniability")
                                .font(isCompact ? .subheadline : .body)
                                .foregroundStyle(.vaultSecondaryText)
                        }
                        .multilineTextAlignment(.center)

                        // Increased spacing to push feature rows lower
                        Spacer().frame(height: h * 0.08)

                        // Feature Rows
                        VStack(alignment: .leading, spacing: h * 0.02) {
                            FeatureRow(
                                icon: "hand.draw",
                                title: "Pattern-Based Encryption",
                                description: isCompact ? "Different patterns = different vaults" : "Each pattern creates a unique encrypted vault"
                            )
                            FeatureRow(
                                icon: "eye.slash",
                                title: "True Plausible Deniability",
                                description: isCompact ? "No one can tell how many vaults you have" : "Nobody can tell how many vaults you have"
                            )
                            FeatureRow(
                                icon: "lock.shield",
                                title: "Hardware Security",
                                description: isCompact ? "Keys protected by Secure Enclave" : "Your encryption keys are protected by your device's Secure Enclave"
                            )
                            FeatureRow(
                                icon: "icloud",
                                title: "Encrypted Backup",
                                description: isCompact ? "Back up to iCloud, only you can decrypt" : "Back up to your iCloud. Only you can decrypt it with your pattern"
                            )
                            FeatureRow(
                                icon: "shield.slash",
                                title: "Duress Vault",
                                description: isCompact ? "Duress pattern silently wipes real vaults" : "If forced to unlock, the duress pattern silently wipes your real vaults"
                            )
                        }
                        .padding(.horizontal)

                        Spacer().frame(height: h * 0.04)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                // Continue Button — pinned at bottom
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .vaultProminentButtonStyle()
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .accessibilityIdentifier("welcome_continue")
            }
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }
}

#Preview("iPhone 16 Pro") {
    WelcomeView(onContinue: {
        // No-op: preview stub
    })
}

#Preview("iPhone SE") {
    WelcomeView(onContinue: {
        // No-op: preview stub
    })
}

#Preview("iPhone 16 mini") {
    WelcomeView(onContinue: {
        // No-op: preview stub
    })
}
