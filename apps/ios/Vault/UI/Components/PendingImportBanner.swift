import SwiftUI

/// Banner shown at the top of VaultView when there are pending imports
/// from the share extension waiting to be processed.
struct PendingImportBanner: View {
    let fileCount: Int
    let onImport: () -> Void
    @Binding var isImporting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)

            Text("\(fileCount) file\(fileCount == 1 ? "" : "s") ready to import")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            if isImporting {
                ProgressView()
                    .tint(.white)
            } else {
                Button("Import") {
                    onImport()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.white.opacity(0.25))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.accentColor.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Banner shown when there's an interrupted shared vault download that can be resumed.
/// Unlike PendingImportBanner (for share extension imports), this handles shared vault
/// downloads that were interrupted mid-way.
struct PendingSharedVaultImportBanner: View {
    let importedCount: Int
    let totalCount: Int
    let onResume: () -> Void
    @Binding var isResuming: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Shared vault download interrupted")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text("\(importedCount) of \(totalCount) files downloaded")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            if isResuming {
                ProgressView()
                    .tint(.white)
            } else {
                Button("Resume") {
                    onResume()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.white.opacity(0.25))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.accentColor.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
