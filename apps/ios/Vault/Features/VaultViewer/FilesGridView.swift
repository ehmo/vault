import SwiftUI
import UIKit

struct FilesGridView: View {
    let files: [VaultFileItem]
    let onSelect: (VaultFileItem) -> Void
    var onDelete: ((UUID) -> Void)?
    var isEditing: Bool = false
    var selectedIds: Set<UUID> = []
    var onToggleSelect: ((UUID) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    // Drag-to-select state
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var dragAffectedIds: Set<UUID> = []
    @State private var isDragSelecting = true
    @State private var isDragging = false

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(files) { file in
                cellView(for: file)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: FileCellFramePreference.self,
                                value: [file.id: geo.frame(in: .named("filesGrid"))]
                            )
                        }
                    )
            }
        }
        .padding(.horizontal, 16)
        .coordinateSpace(name: "filesGrid")
        .onPreferenceChange(FileCellFramePreference.self) { cellFrames = $0 }
        .simultaneousGesture(dragSelectGesture)
    }

    @ViewBuilder
    private func cellView(for file: VaultFileItem) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                onToggleSelect?(file.id)
            } else {
                onSelect(file)
            }
        }
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

    // MARK: - Drag-to-Select

    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("filesGrid"))
            .onChanged { value in
                guard isEditing else { return }

                if !isDragging {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard dx + dy >= 10 else { return }
                    guard dx > dy * 0.5 else { return }

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

    // MARK: - Helpers

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

// MARK: - Preference Key

private struct FileCellFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
