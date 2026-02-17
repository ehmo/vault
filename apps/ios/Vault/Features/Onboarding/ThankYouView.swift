import SwiftUI

struct ThankYouView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(24)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                )

            VStack(spacing: 12) {
                Text("Protected by Design")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("No accounts. No personal data. No backdoors.")
                    .font(.title3)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.vaultSecondaryText.opacity(0.6))

                Text("Nobody can spy on your vault.")
                    .font(.headline)

                Text("Only your pattern can decrypt your files — not us, not anyone else.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .vaultGlassBackground(cornerRadius: 16)
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onContinue) {
                Text("Create My Secure Vault")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .vaultProminentButtonStyle()
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .accessibilityIdentifier("thankyou_continue")
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }
}

#Preview {
    ThankYouView(onContinue: {})
}
