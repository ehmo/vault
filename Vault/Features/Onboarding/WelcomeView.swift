import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    @State private var animateIcon = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(animateIcon ? 1.1 : 1.0)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
            }
            .onAppear {
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

            Spacer()

            // Description
            VStack(spacing: 16) {
                Text("Protect your private files with pattern-based encryption.")
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text("Each pattern creates a separate vault. Nobody can prove which vaults exist.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
