import SwiftUI

struct FilesGridView: View {
    let files: [VaultFileItem]
    let onSelect: (VaultFileItem) -> Void
    var onDelete: ((UUID) -> Void)?
    var isEditing: Bool = false
    var selectedIds: Set<UUID> = []
    var onToggleSelect: ((UUID) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(files) { file in
                Button {
                    if isEditing {
                        onToggleSelect?(file.id)
                    } else {
                        onSelect(file)
                    }
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
                            .overlay(alignment: .bottomTrailing) {
                                if isEditing {
                                    selectionCircle(selected: selectedIds.contains(file.id))
                                        .padding(6)
                                }
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
                .accessibilityHint(isEditing ? "Double tap to \(selectedIds.contains(file.id) ? "deselect" : "select")" : "Double tap to open")
                .contextMenu {
                    if let onDelete, !isEditing {
                        Button(role: .destructive, action: { onDelete(file.id) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func selectionCircle(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? Color.accentColor : Color.black.opacity(0.3))
                .frame(width: 24, height: 24)
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 24, height: 24)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
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
