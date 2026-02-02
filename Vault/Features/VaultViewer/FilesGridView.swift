import SwiftUI

struct FilesGridView: View {
    let files: [VaultFileItem]
    let onSelect: (VaultFileItem) -> Void
    var onDelete: ((UUID) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(files) { file in
                Button {
                    onSelect(file)
                } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.vaultSurface)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(systemName: iconName(for: file.mimeType))
                                    .font(.title)
                                    .foregroundStyle(.vaultSecondaryText)
                            }

                        VStack(spacing: 2) {
                            Text(file.filename ?? "File")
                                .font(.caption)
                                .foregroundStyle(.vaultText)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(formatSize(file.size))
                                .font(.caption2)
                                .foregroundStyle(.vaultSecondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(file.filename ?? "File"), \(formatSize(file.size))")
                .accessibilityHint("Double tap to open")
                .contextMenu {
                    if let onDelete {
                        Button(role: .destructive, action: { onDelete(file.id) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func iconName(for mimeType: String?) -> String {
        guard let mimeType else { return "doc.fill" }
        if mimeType.hasPrefix("video/") { return "video.fill" }
        if mimeType.hasPrefix("application/pdf") { return "doc.text.fill" }
        if mimeType.hasPrefix("text/") { return "doc.text.fill" }
        return "doc.fill"
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func formatSize(_ bytes: Int) -> String {
        Self.byteCountFormatter.string(fromByteCount: Int64(bytes))
    }
}
