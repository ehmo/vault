import SwiftUI

struct FileGridView: View {
    let files: [VaultFileItem]
    let onSelect: (VaultFileItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 4)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(files) { file in
                    FileThumbnailView(file: file)
                        .onTapGesture {
                            onSelect(file)
                        }
                }
            }
            .padding(4)
        }
    }
}

struct FileThumbnailView: View {
    let file: VaultFileItem

    var body: some View {
        ZStack {
            // Placeholder background
            Rectangle()
                .fill(Color(.systemGray5))

            // File icon (actual thumbnails would be generated in memory)
            VStack(spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)

                Text(formatSize(file.size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func formatSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

#Preview {
    FileGridView(
        files: [
            VaultFileItem(id: UUID(), size: 1024 * 500),
            VaultFileItem(id: UUID(), size: 1024 * 1024 * 2),
            VaultFileItem(id: UUID(), size: 1024 * 100),
        ],
        onSelect: { _ in }
    )
}
