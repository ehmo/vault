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
            // Background
            Rectangle()
                .fill(Color(.systemGray5))

            // Display thumbnail or icon
            if let uiImage = file.thumbnailImage ?? file.thumbnailData.flatMap({ UIImage(data: $0) }) {
                // Show actual thumbnail
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Show icon for non-image files
                VStack(spacing: 4) {
                    Image(systemName: iconName(for: file.mimeType))
                        .font(.title)
                        .foregroundStyle(.secondary)

                    if let filename = file.filename {
                        Text(filename)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    } else {
                        Text(formatSize(file.size))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func iconName(for mimeType: String?) -> String {
        guard let mimeType = mimeType else { return "doc.fill" }
        
        if mimeType.hasPrefix("image/") {
            return "photo.fill"
        } else if mimeType.hasPrefix("video/") {
            return "video.fill"
        } else if mimeType.hasPrefix("application/pdf") {
            return "doc.text.fill"
        } else if mimeType.hasPrefix("text/") {
            return "doc.text.fill"
        } else {
            return "doc.fill"
        }
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
            VaultFileItem(id: UUID(), size: 1024 * 500, thumbnailData: nil, mimeType: "image/jpeg", filename: "Photo.jpg"),
            VaultFileItem(id: UUID(), size: 1024 * 1024 * 2, thumbnailData: nil, mimeType: "video/mp4", filename: "Video.mp4"),
            VaultFileItem(id: UUID(), size: 1024 * 100, thumbnailData: nil, mimeType: "application/pdf", filename: "Document.pdf"),
        ],
        onSelect: { _ in }
    )
}
