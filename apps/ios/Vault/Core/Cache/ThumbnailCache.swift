import UIKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()
    private var encryptedThumbnails: [UUID: Data] = [:]

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

    // MARK: - Encrypted Thumbnail Storage

    func storeEncrypted(id: UUID, data: Data) {
        encryptedThumbnails[id] = data
    }

    func encryptedThumbnail(for id: UUID) -> Data? {
        encryptedThumbnails[id]
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

    /// Decrypt from stored encrypted thumbnail, decode to UIImage, cache, and return.
    func decryptAndCache(id: UUID, masterKey: Data) -> UIImage? {
        if let cached = image(for: id) {
            return cached
        }
        guard let encrypted = encryptedThumbnails[id] else { return nil }
        do {
            let decrypted = try CryptoEngine.decrypt(encrypted, with: masterKey)
            guard let uiImage = UIImage(data: decrypted) else { return nil }
            setImage(uiImage, for: id)
            return uiImage
        } catch {
            return nil
        }
    }

    func clear() {
        cache.removeAllObjects()
        encryptedThumbnails.removeAll()
    }
}
