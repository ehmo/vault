import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    @State private var animateIcon = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = proxy.size.height
            let isCompact = availableHeight < 800 // iPhone 16 and smaller need compact layout
            let isVeryCompact = availableHeight < 700 // iPhone SE, mini
            
            VStack(spacing: isVeryCompact ? 16 : (isCompact ? 20 : 24)) {
                Spacer(minLength: 0)

                // App Logo - scales based on screen size
                Image("VaultLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: isVeryCompact ? 100 : (isCompact ? 110 : 120),
                        height: isVeryCompact ? 100 : (isCompact ? 110 : 120)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isVeryCompact ? 20 : 24, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .scaleEffect(animateIcon ? 1.05 : 1.0)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            animateIcon = true
                        }
                    }

                // Welcome Text
                VStack(spacing: isVeryCompact ? 6 : 8) {
                    Text("Welcome to Vaultaire")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Secure storage with plausible deniability")
                        .font(isVeryCompact ? .subheadline : .body)
                        .foregroundStyle(.vaultSecondaryText)
                }
                .multilineTextAlignment(.center)

                // Feature Rows - condensed on smaller screens
                VStack(alignment: .leading, spacing: isVeryCompact ? 12 : (isCompact ? 14 : 16)) {
                    FeatureRow(
                        icon: "hand.draw",
                        title: "Pattern-Based Encryption",
                        description: isVeryCompact ? "Different patterns = different vaults" : "Each pattern creates a unique encrypted vault"
                    )

                    FeatureRow(
                        icon: "eye.slash",
                        title: "True Plausible Deniability",
                        description: isVeryCompact ? "No one can tell how many vaults you have" : "Nobody can tell how many vaults you have"
                    )

                    FeatureRow(
                        icon: "lock.shield",
                        title: "Hardware Security",
                        description: isVeryCompact ? "Keys protected by Secure Enclave" : "Your encryption keys are protected by your device's Secure Enclave"
                    )

                    FeatureRow(
                        icon: "icloud",
                        title: "Encrypted Backup",
                        description: isVeryCompact ? "Back up to iCloud, only you can decrypt" : "Back up to your iCloud. Only you can decrypt it with your pattern"
                    )
                }
                .padding(.horizontal)

                Spacer(minLength: 0)

                // Continue Button
                Button(action: onContinue) {
                    Text("Protect Your First Vault")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .vaultProminentButtonStyle()
                .padding(.horizontal, isVeryCompact ? 24 : 32)
                .padding(.bottom, isVeryCompact ? 20 : 24)
                .accessibilityIdentifier("welcome_continue")
            }
            .frame(maxWidth: .infinity, maxHeight: availableHeight)
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }
}

#Preview("iPhone 16 Pro") {
    WelcomeView(onContinue: {})
}

#Preview("iPhone SE") {
    WelcomeView(onContinue: {})
        .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
}

#Preview("iPhone 16 mini") {
    WelcomeView(onContinue: {})
        .previewDevice(PreviewDevice(rawValue: "iPhone 16 Pro"))
}
