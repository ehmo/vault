import SwiftUI

struct ThankYouView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 0)

                    Image("ProtectedByDesignSeal")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        .accessibilityIdentifier("thankyou_seal_image")

                    VStack(spacing: 0) {
                        Text("Protected by Design")
                            .font(.title)
                            .fontWeight(.bold)
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

                        FeatureRow(
                            icon: "eye.slash.circle",
                            title: "Hidden from all",
                            description: "Nobody can tell how many vaults you have."
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 0)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .vaultProminentButtonStyle()
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
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
    ThankYouView(onContinue: {
        // No-op: preview stub
    })
}
