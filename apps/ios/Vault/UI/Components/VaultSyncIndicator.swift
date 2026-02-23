import SwiftUI

/// Drop-in replacement for ProgressView spinners in upload/download/sync banners.
/// Uses the unified PixelLoader for consistent appearance across the app.
struct VaultSyncIndicator: View {
    enum Style {
        case uploading
        case downloading
        case syncing
        case loading
    }

    let style: Style
    var message: String
    var progress: (current: Int, total: Int)?

    var body: some View {
        if style == .loading {
            // Centered vertical layout for full-screen loading
            VStack(spacing: 24) {
                PixelLoader.standard(size: 80)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
            }
        } else {
            // Compact horizontal layout for inline banners
            HStack(spacing: 8) {
                PixelLoader.compact(size: 24)
                Text(message)
                    .font(.caption)
                Spacer()
                if let progress, progress.total > 0 {
                    let pct = Int(round(Double(progress.current) / Double(progress.total) * 100))
                    Text("\(pct)%")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                }
            }
        }
    }
}

#Preview("Upload Banner") {
    VaultSyncIndicator(style: .uploading, message: "Uploading shared vault...", progress: (current: 5, total: 100))
        .padding()
        .background(Color.accentColor.opacity(0.1))
}

#Preview("Loading") {
    VaultSyncIndicator(style: .loading, message: "Unlocking...")
        .padding()
        .background(.black)
}
