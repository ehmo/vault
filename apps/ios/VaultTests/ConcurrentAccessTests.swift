import XCTest
@testable import Vault

/// Concurrent access tests designed to surface data races under Thread Sanitizer (TSAN).
/// These tests hammer shared state from multiple threads simultaneously.
final class ConcurrentAccessTests: XCTestCase {

    // MARK: - CryptoEngine (Stateless)

    /// Concurrent encrypt/decrypt should be safe — CryptoEngine methods are stateless.
    func testConcurrentEncryptDecrypt() async throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = Data(repeating: 0xAB, count: 1024)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
                    let decrypted = try CryptoEngine.decrypt(encrypted, with: key)
                    XCTAssertEqual(decrypted, plaintext)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Concurrent HMAC compute + verify from multiple tasks.
    func testConcurrentHMACComputeAndVerify() async {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 4096)!
        let expectedHMAC = CryptoEngine.computeHMAC(for: data, with: key)

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    let hmac = CryptoEngine.computeHMAC(for: data, with: key)
                    return CryptoEngine.verifyHMAC(hmac, for: data, with: key)
                }
                group.addTask {
                    CryptoEngine.verifyHMAC(expectedHMAC, for: data, with: key)
                }
            }
            for await result in group {
                XCTAssertTrue(result)
            }
        }
    }

    /// Concurrent random byte generation.
    func testConcurrentRandomBytesGeneration() async {
        await withTaskGroup(of: Data?.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    CryptoEngine.generateRandomBytes(count: 256)
                }
            }
            var results: [Data] = []
            for await data in group {
                XCTAssertNotNil(data)
                if let data { results.append(data) }
            }
            // All should be unique (random)
            let unique = Set(results.map { $0.base64EncodedString() })
            XCTAssertEqual(unique.count, results.count, "Random bytes should all be unique")
        }
    }

    // MARK: - ThumbnailCache (Actor)

    /// Concurrent reads and writes to actor-isolated ThumbnailCache.
    func testConcurrentThumbnailCacheAccess() async {
        let cache = ThumbnailCache()
        let ids = (0..<20).map { _ in UUID() }

        // Create a simple 1x1 test image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let testImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for id in ids {
                group.addTask {
                    await cache.setImage(testImage, for: id)
                }
            }
            // Concurrent readers
            for id in ids {
                group.addTask {
                    _ = await cache.image(for: id)
                }
            }
            // Concurrent encrypted data writers
            for id in ids {
                group.addTask {
                    await cache.storeEncrypted(id: id, data: Data(repeating: 0xFF, count: 64))
                }
            }
            // Concurrent encrypted data readers
            for id in ids {
                group.addTask {
                    _ = await cache.encryptedThumbnail(for: id)
                }
            }
            await group.waitForAll()
        }

        // Verify all entries were stored
        for id in ids {
            let img = await cache.image(for: id)
            XCTAssertNotNil(img, "Image should be cached for \(id)")
        }
    }

    /// Concurrent clear + read/write on ThumbnailCache.
    func testConcurrentThumbnailCacheClearDuringAccess() async {
        let cache = ThumbnailCache()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let testImage = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let id = UUID()
                group.addTask {
                    await cache.setImage(testImage, for: id)
                }
                group.addTask {
                    _ = await cache.image(for: id)
                }
                if i % 10 == 0 {
                    group.addTask {
                        await cache.clear()
                    }
                }
            }
            await group.waitForAll()
        }
        // No crash = success. TSAN will flag any data race.
    }

    // MARK: - VaultIndexManager (NSRecursiveLock)

    /// Concurrent load + save on VaultIndexManager using the same key.
    func testConcurrentIndexManagerLoadSave() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = VaultIndexManager(
            documentsURL: tempDir,
            blobFileName: "test_blob.bin",
            defaultBlobSize: 50 * 1024 * 1024,
            cursorBlockOffset: 50 * 1024 * 1024
        )
        manager.readGlobalCursor = { 0 }
        manager.cursorFooterOffset = { 50 * 1024 * 1024 }

        let key = VaultKey(CryptoEngine.generateRandomBytes(count: 32)!)

        // Initial load to create index
        let index = try manager.loadIndex(with: key)
        try manager.saveIndex(index, with: key)

        // Hammer concurrent loads and saves
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let loaded = try manager.loadIndex(with: key)
                    XCTAssertNotNil(loaded.encryptedMasterKey)
                }
                group.addTask {
                    let loaded = try manager.loadIndex(with: key)
                    try manager.saveIndex(loaded, with: key)
                }
            }
            try await group.waitForAll()
        }

        // Verify consistency after concurrent operations
        let final_ = try manager.loadIndex(with: key)
        XCTAssertEqual(final_.version, 3)
        XCTAssertNotNil(final_.encryptedMasterKey)
    }

    /// Concurrent access with different keys should not interfere.
    func testConcurrentIndexManagerMultipleKeys() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = VaultIndexManager(
            documentsURL: tempDir,
            blobFileName: "test_blob.bin",
            defaultBlobSize: 50 * 1024 * 1024,
            cursorBlockOffset: 50 * 1024 * 1024
        )
        manager.readGlobalCursor = { 0 }
        manager.cursorFooterOffset = { 50 * 1024 * 1024 }

        let keys = (0..<5).map { _ in VaultKey(CryptoEngine.generateRandomBytes(count: 32)!) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    let index = try manager.loadIndex(with: key)
                    try manager.saveIndex(index, with: key)
                    let reloaded = try manager.loadIndex(with: key)
                    XCTAssertEqual(reloaded.version, 3)
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - File Encryption Round-Trip Under Concurrency

    /// Multiple file encrypt/decrypt round-trips running concurrently.
    func testConcurrentFileEncryptDecrypt() async throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let plaintext = CryptoEngine.generateRandomBytes(count: 1024 * (i + 1))!
                    let encrypted = try CryptoEngine.encryptFile(
                        data: plaintext,
                        filename: "test_\(i).bin",
                        mimeType: "application/octet-stream",
                        with: key
                    )
                    let (_, decrypted) = try CryptoEngine.decryptFile(
                        data: encrypted.encryptedContent,
                        with: key
                    )
                    XCTAssertEqual(decrypted, plaintext)
                }
            }
            try await group.waitForAll()
        }
    }
}
