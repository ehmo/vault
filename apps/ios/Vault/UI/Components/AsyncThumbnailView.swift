import SwiftUI

struct AsyncThumbnailView: View {
    let fileId: UUID
    let encryptedThumbnail: Data?
    let masterKey: Data
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.vaultSurface
            }
        }
        .task(id: fileId) {
            guard let encryptedThumbnail else { return }

            // Check cache first
            if let cached = await ThumbnailCache.shared.image(for: fileId) {
                image = cached
                return
            }

            // Decrypt off-main (task already runs on cooperative pool)
            let result = await ThumbnailCache.shared.decryptAndCache(
                id: fileId,
                encryptedThumbnail: encryptedThumbnail,
                masterKey: masterKey
            )
            if !Task.isCancelled {
                image = result
            }
        }
    }
}
