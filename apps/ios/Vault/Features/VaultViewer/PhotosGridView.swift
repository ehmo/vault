import SwiftUI
import UIKit

struct PhotosGridView: View {
    let files: [VaultFileItem]
    let masterKey: Data
    let onSelect: (VaultFileItem, Int) -> Void
    var onDelete: ((UUID) -> Void)?
    var isEditing: Bool = false
    var selectedIds: Set<UUID> = []
    var onToggleSelect: ((UUID) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    // Drag-to-select state
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var dragAffectedIds: Set<UUID> = []
    @State private var isDragSelecting = true
    @State private var isDragging = false

    var body: some View {
        grid
            .coordinateSpace(name: "photosGrid")
            .onPreferenceChange(PhotoCellFramePreference.self) { cellFrames = $0 }
    }

    @ViewBuilder
    private var grid: some View {
        let base = LazyVGrid(columns: columns, spacing: 2) {
            ForEach(files) { file in
                cellView(for: file)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: PhotoCellFramePreference.self,
                                value: [file.id: geo.frame(in: .named("photosGrid"))]
                            )
                        }
                    )
            }
        }
        if isEditing {
            base.simultaneousGesture(dragSelectGesture)
        } else {
            base
        }
    }

    @ViewBuilder
    private func cellView(for file: VaultFileItem) -> some View {
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
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditing {
                    onToggleSelect?(file.id)
                } else {
                    let index = files.firstIndex(where: { $0.id == file.id }) ?? 0
                    onSelect(file, index)
                }
            }
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

    // MARK: - Drag-to-Select

    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .named("photosGrid"))
            .onChanged { value in
                guard isEditing else { return }

                if !isDragging {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    // Only activate on predominantly horizontal drags
                    guard dx > dy else { return }

                    isDragging = true
                    if let id = cellId(at: value.startLocation) {
                        isDragSelecting = !selectedIds.contains(id)
                        applyDragSelection(to: id)
                    }
                }

                if let id = cellId(at: value.location) {
                    applyDragSelection(to: id)
                }
            }
            .onEnded { _ in
                dragAffectedIds.removeAll()
                isDragging = false
            }
    }

    private func cellId(at point: CGPoint) -> UUID? {
        cellFrames.first(where: { $0.value.contains(point) })?.key
    }

    private func applyDragSelection(to id: UUID) {
        guard !dragAffectedIds.contains(id) else { return }
        dragAffectedIds.insert(id)

        let isSelected = selectedIds.contains(id)
        if (isDragSelecting && !isSelected) || (!isDragSelecting && isSelected) {
            onToggleSelect?(id)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Selection Circle

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

// MARK: - Preference Key

private struct PhotoCellFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
