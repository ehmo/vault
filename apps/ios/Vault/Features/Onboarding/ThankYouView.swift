import SwiftUI

struct ThankYouView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        Text("Protected by Design")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("No accounts.\nNo personal data.\nNo backdoors.")
                            .font(.title3)
                            .foregroundStyle(.vaultSecondaryText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(
                            icon: "person.crop.circle.badge.xmark",
                            title: "No accounts",
                            description: "No sign-ups. No personal profiles."
                        )

                        FeatureRow(
                            icon: "eye.slash",
                            title: "No way to spy",
                            description: "Your vault stays private by design."
                        )

                        FeatureRow(
                            icon: "lock.shield",
                            title: "No backdoors",
                            description: "Only your pattern can decrypt your files."
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 0)

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
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }
}

#Preview {
    ThankYouView(onContinue: {})
}
