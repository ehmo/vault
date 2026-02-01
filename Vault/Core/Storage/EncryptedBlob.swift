import Foundation

/// Manages the encrypted blob storage format.
/// The blob is a pre-allocated file filled with random data.
/// Vault data is written at specific offsets, making it indistinguishable from random noise.
final class EncryptedBlob {

    // MARK: - Blob Header Structure

    /// Blob header is NOT stored - the blob has no distinguishing markers.
    /// All metadata is stored in the encrypted index file.

    struct BlobRegion {
        let offset: Int
        let length: Int

        var endOffset: Int { offset + length }
    }

    // MARK: - Blob Management

    private let fileURL: URL
    private let fileManager = FileManager.default

    init(url: URL) {
        self.fileURL = url
    }

    // MARK: - Read/Write Operations

    func read(region: BlobRegion) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw VaultStorageError.readError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(region.offset))
        guard let data = try handle.read(upToCount: region.length) else {
            throw VaultStorageError.readError
        }

        return data
    }

    func write(data: Data, at offset: Int) throws {
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw VaultStorageError.writeError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(offset))
        handle.write(data)
    }

    func overwriteWithRandom(region: BlobRegion) throws {
        guard let randomData = CryptoEngine.shared.generateRandomBytes(count: region.length) else {
            throw VaultStorageError.writeError
        }

        try write(data: randomData, at: region.offset)
    }

    // MARK: - Blob Statistics

    var fileSize: Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int else {
            return 0
        }
        return size
    }

    // MARK: - Blob Enumeration

    /// Returns all blob files (primary + expansion) in the documents directory.
    static func allBlobFiles() -> [URL] {
        VaultStorage.shared.allBlobURLs()
    }

    // MARK: - Randomness Test (for verification that blob looks random)

    /// Performs basic entropy check on a sample of the blob.
    /// Returns true if data appears sufficiently random.
    func passesRandomnessCheck(sampleSize: Int = 10_000) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: sampleSize) else {
            return false
        }

        // Simple frequency test - each byte value should appear roughly equally
        var frequencies = [UInt8: Int]()
        for byte in data {
            frequencies[byte, default: 0] += 1
        }

        let expectedFrequency = Double(sampleSize) / 256.0
        let tolerance = expectedFrequency * 0.5 // Allow 50% deviation

        for value in 0..<256 {
            let freq = Double(frequencies[UInt8(value), default: 0])
            if abs(freq - expectedFrequency) > tolerance {
                return false
            }
        }

        return true
    }
}
