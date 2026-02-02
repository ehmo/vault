import UIKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    func image(for id: UUID) -> UIImage? {
        cache.object(forKey: id.uuidString as NSString)
    }

    func setImage(_ image: UIImage, for id: UUID) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: id.uuidString as NSString, cost: cost)
    }

    /// Decrypt encrypted thumbnail data using the master key, decode to UIImage, cache, and return.
    func decryptAndCache(id: UUID, encryptedThumbnail: Data, masterKey: Data) -> UIImage? {
        // Check cache first
        if let cached = image(for: id) {
            return cached
        }

        do {
            let decrypted = try CryptoEngine.decrypt(encryptedThumbnail, with: masterKey)
            guard let uiImage = UIImage(data: decrypted) else { return nil }
            setImage(uiImage, for: id)
            return uiImage
        } catch {
            return nil
        }
    }

    func clear() {
        cache.removeAllObjects()
    }
}
