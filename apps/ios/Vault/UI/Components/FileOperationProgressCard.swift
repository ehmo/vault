import SwiftUI

struct FileOperationProgressCard: View {
    let completed: Int
    let total: Int
    let message: String

    private var percentage: Int {
        total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
    }

    var body: some View {
        VStack(spacing: 20) {
            PixelAnimation.loading(size: 80)

            VStack(spacing: 8) {
                ProgressView(value: Double(completed), total: Double(total))
                    .tint(.accentColor)

                Text("\(percentage)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.vaultSecondaryText)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .vaultGlassBackground(cornerRadius: 16)
    }
}
