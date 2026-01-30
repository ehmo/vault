import SwiftUI

struct AnalyticsConsentView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Help Improve Vault")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                Text("Share anonymous crash reports and usage statistics to help us make Vault better.")
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text("No personal data is collected. You can change this anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    AnalyticsManager.shared.setEnabled(true)
                    onContinue()
                }) {
                    Text("Enable Analytics")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Button(action: onContinue) {
                    Text("No Thanks")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    AnalyticsConsentView(onContinue: {})
}
