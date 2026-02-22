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
    @State private var isDragVertical = false

    var body: some View {
        grid
            .coordinateSpace(name: "photosGrid")
            .onPreferenceChange(PhotoCellFramePreference.self) { cellFrames = $0 }
            .onChange(of: isEditing) { _, editing in
                if !editing { cellFrames.removeAll() }
            }
    }

    @ViewBuilder
    private var grid: some View {
        let base = LazyVGrid(columns: columns, spacing: 2) {
            ForEach(files) { file in
                cellView(for: file)
                    .background {
                        if isEditing {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: PhotoCellFramePreference.self,
                                    value: [file.id: geo.frame(in: .named("photosGrid"))]
                                )
                            }
                        }
                    }
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
                    hasThumbnail: file.hasThumbnail,
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
            .overlay(alignment: .bottomLeading) {
                if !isEditing, let duration = file.duration, (file.mimeType ?? "").hasPrefix("video/") {
                    Text(formatDuration(duration))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
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
                    isDragVertical = dy > dx
                    isDragging = true

                    if isDragVertical {
                        let ids = rowCellIds(at: value.startLocation.y)
                        if let first = ids.first {
                            isDragSelecting = !selectedIds.contains(first)
                        }
                        if ids.reduce(false, { changed, id in applyDragSelection(to: id) || changed }) {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    } else if let id = cellId(at: value.startLocation) {
                        isDragSelecting = !selectedIds.contains(id)
                        if applyDragSelection(to: id) {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }

                if isDragVertical {
                    if rowCellIds(at: value.location.y).reduce(false, { changed, id in applyDragSelection(to: id) || changed }) {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                } else if let id = cellId(at: value.location) {
                    if applyDragSelection(to: id) {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }
            .onEnded { _ in
                dragAffectedIds.removeAll()
                isDragging = false
                isDragVertical = false
            }
    }

    private func cellId(at point: CGPoint) -> UUID? {
        cellFrames.first(where: { $0.value.contains(point) })?.key
    }

    private func rowCellIds(at y: CGFloat) -> [UUID] {
        guard let anchor = cellFrames.first(where: { $0.value.minY <= y && y <= $0.value.maxY }) else {
            return []
        }
        let rowMidY = anchor.value.midY
        return cellFrames.compactMap { id, frame in
            abs(frame.midY - rowMidY) <= 5 ? id : nil
        }
    }

    @discardableResult
    private func applyDragSelection(to id: UUID) -> Bool {
        guard !dragAffectedIds.contains(id) else { return false }
        dragAffectedIds.insert(id)

        let isSelected = selectedIds.contains(id)
        if (isDragSelecting && !isSelected) || (!isDragSelecting && isSelected) {
            onToggleSelect?(id)
            return true
        }
        return false
    }

    // MARK: - Duration Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
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
