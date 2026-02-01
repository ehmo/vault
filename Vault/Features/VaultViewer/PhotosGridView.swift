import SwiftUI

struct PhotosGridView: View {
    let files: [VaultFileItem]
    let masterKey: Data
    let onSelect: (VaultFileItem, Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                Button {
                    onSelect(file, index)
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
                }
                .buttonStyle(.plain)
            }
        }
    }
}
