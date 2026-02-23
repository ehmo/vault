import SwiftUI
import UIKit

struct FilesGridView: View {
    let files: [VaultFileItem]
    let onSelect: (VaultFileItem) -> Void
    var onDelete: ((UUID) -> Void)?
    var masterKey: Data? = nil
    var isEditing: Bool = false
    var selectedIds: Set<UUID> = []
    var onToggleSelect: ((UUID) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    // Drag-to-select state
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var isDragSelecting = true
    @State private var isDragging = false
    @State private var dragStartIndex: Int?
    @State private var currentDragTargetIds: Set<UUID> = []
    @State private var dragToggledIds: Set<UUID> = []

    var body: some View {
        grid
            .padding(.horizontal, 16)
            .coordinateSpace(name: "filesGrid")
            .onPreferenceChange(FileCellFramePreference.self) { cellFrames = $0 }
            .onChange(of: isEditing) { _, editing in
                if !editing {
                    cellFrames.removeAll()
                    isDragging = false
                    dragStartIndex = nil
                    currentDragTargetIds.removeAll()
                    dragToggledIds.removeAll()
                }
            }
    }

    @ViewBuilder
    private var grid: some View {
        let base = LazyVGrid(columns: columns, spacing: 12) {
            ForEach(files) { file in
                cellView(for: file)
                    .background {
                        if isEditing {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: FileCellFramePreference.self,
                                    value: [file.id: geo.frame(in: .named("filesGrid"))]
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
        VStack(spacing: 8) {
            thumbnailOrIcon(for: file)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                onToggleSelect?(file.id)
            } else {
                onSelect(file)
            }
        }
        .accessibilityLabel("\(file.filename ?? "File"), \(formatSize(file.size))")
        .accessibilityHint(accessibilityHint(for: file))
        .contextMenu {
            if let onDelete, !isEditing {
                Button(role: .destructive, action: { onDelete(file.id) }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func accessibilityHint(for file: VaultFileItem) -> String {
        if isEditing {
            return selectedIds.contains(file.id) ? "Double tap to deselect" : "Double tap to select"
        }
        return "Double tap to open"
    }

    @ViewBuilder
    private func thumbnailOrIcon(for file: VaultFileItem) -> some View {
        if let masterKey, file.hasThumbnail {
            Color.clear
                .overlay {
                    AsyncThumbnailView(
                        fileId: file.id,
                        hasThumbnail: file.hasThumbnail,
                        masterKey: masterKey,
                        contentMode: .fill
                    )
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if (file.mimeType ?? "").hasPrefix("video/") {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
        } else {
            Color.vaultSurface
                .overlay {
                    Image(systemName: iconName(for: file.mimeType))
                        .font(.title)
                        .foregroundStyle(.vaultSecondaryText)
                }
        }
    }

    // MARK: - Drag-to-Select

    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .named("filesGrid"))
            .onChanged { value in
                guard isEditing else { return }

                // Setup on first callback
                if !isDragging {
                    isDragging = true
                    dragStartIndex = nearestItemIndex(to: value.startLocation)

                    if let startIdx = dragStartIndex {
                        isDragSelecting = !selectedIds.contains(files[startIdx].id)
                    }
                }

                guard let startIdx = dragStartIndex, startIdx < files.count else { return }
                guard let currentIdx = nearestItemIndex(to: value.location) else { return }

                // Always use row-span selection (Photos-app style)
                let indices = DragRowSelector.indicesInRowSpan(
                    itemCount: files.count,
                    columns: columns.count,
                    startIndex: startIdx,
                    endIndex: currentIdx
                )
                let newTargetIds = Set(indices.map { files[$0].id })

                var changed = false

                // Items entering the drag range
                for id in newTargetIds.subtracting(currentDragTargetIds) {
                    let isSelected = selectedIds.contains(id)
                    if (isDragSelecting && !isSelected) || (!isDragSelecting && isSelected) {
                        onToggleSelect?(id)
                        dragToggledIds.insert(id)
                        changed = true
                    }
                }

                // Items leaving the drag range (user dragged back)
                for id in currentDragTargetIds.subtracting(newTargetIds) {
                    if dragToggledIds.contains(id) {
                        onToggleSelect?(id)
                        dragToggledIds.remove(id)
                        changed = true
                    }
                }

                currentDragTargetIds = newTargetIds

                if changed {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                isDragging = false
                dragStartIndex = nil
                currentDragTargetIds.removeAll()
                dragToggledIds.removeAll()
            }
    }

    /// Finds the index in `files` of the cell nearest to `point` by distance to frame center.
    private func nearestItemIndex(to point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDist = CGFloat.infinity
        for (i, file) in files.enumerated() {
            guard let frame = cellFrames[file.id] else { continue }
            let dist = hypot(frame.midX - point.x, frame.midY - point.y)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
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

    // MARK: - Helpers

    private func iconName(for mimeType: String?) -> String {
        guard let mimeType else { return "doc.fill" }
        if mimeType.hasPrefix("image/") { return "photo.fill" }
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

// MARK: - Preference Key

private struct FileCellFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
