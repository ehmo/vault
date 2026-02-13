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
                Text("Thank You for Trusting Us")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Now let's set up your first vault")
                    .font(.title3)
                    .foregroundStyle(.vaultSecondaryText)
            }

            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.vaultSecondaryText.opacity(0.6))

                Text("Your privacy and security matter to us.")
                    .font(.headline)

                Text("We promise to always keep your personal information private and secure.")
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
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .vaultProminentButtonStyle()
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .accessibilityIdentifier("thankyou_continue")
        }
    }
}

#Preview {
    ThankYouView(onContinue: {})
}
