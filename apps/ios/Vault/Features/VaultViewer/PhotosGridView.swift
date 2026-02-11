import SwiftUI

struct PhotosGridView: View {
    let files: [VaultFileItem]
    let masterKey: Data
    let onSelect: (VaultFileItem, Int) -> Void
    var onDelete: ((UUID) -> Void)?
    var isEditing: Bool = false
    var selectedIds: Set<UUID> = []
    var onToggleSelect: ((UUID) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(files) { file in
                Button {
                    if isEditing {
                        onToggleSelect?(file.id)
                    } else {
                        let index = files.firstIndex(where: { $0.id == file.id }) ?? 0
                        onSelect(file, index)
                    }
                } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            AsyncThumbnailView(
                                fileId: file.id,
                                encryptedThumbnail: file.encryptedThumbnail,
                                masterKey: masterKey,
                                contentMode: .fill
                            )
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.vaultSecondaryText.opacity(0.15), lineWidth: 0.5)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            if isEditing {
                                selectionCircle(selected: selectedIds.contains(file.id))
                                    .padding(6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(file.filename ?? "Photo")
                .accessibilityHint(isEditing ? "Double tap to \(selectedIds.contains(file.id) ? "deselect" : "select")" : "Double tap to view full screen")
                .contextMenu {
                    if let onDelete, !isEditing {
                        Button(role: .destructive, action: { onDelete(file.id) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
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
}
