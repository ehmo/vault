import SwiftUI

struct FileOperationProgressCard: View {
    let completed: Int
    let total: Int
    let message: String
    var onCancel: (() -> Void)?

    private var percentage: Int {
        total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
    }

    var body: some View {
        VStack(spacing: 20) {
            PixelLoader.standard(size: 80)

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

            if let onCancel {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.vaultHighlight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .background(Color.vaultHighlight.opacity(0.1))
                .clipShape(Capsule())
                .accessibilityIdentifier("operation_cancel_button")
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .vaultGlassBackground(cornerRadius: 16)
    }
}
