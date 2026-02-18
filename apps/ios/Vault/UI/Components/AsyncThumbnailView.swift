import SwiftUI

struct AsyncThumbnailView: View {
    let fileId: UUID
    let hasThumbnail: Bool
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
            guard hasThumbnail else { return }

            // Check decoded image cache first
            if let cached = await ThumbnailCache.shared.image(for: fileId) {
                image = cached
                return
            }

            // Decrypt from stored encrypted data
            let result = await ThumbnailCache.shared.decryptAndCache(
                id: fileId,
                masterKey: masterKey
            )
            if !Task.isCancelled {
                image = result
            }
        }
    }
}
