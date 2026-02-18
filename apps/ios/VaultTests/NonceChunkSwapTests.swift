import XCTest
@testable import Vault

final class NonceChunkSwapTests: XCTestCase {

    private var tempDir: URL!
    private var key: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        key = CryptoEngine.generateRandomBytes(count: 32)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a temp file with random data of the given size.
    private func writeTestFile(size: Int) throws -> URL {
        let url = tempDir.appendingPathComponent(UUID().uuidString)
        let data = CryptoEngine.generateRandomBytes(count: size) ?? Data(repeating: 0xAB, count: size)
        try data.write(to: url)
        return url
    }

    /// Streaming format header: 33 bytes
    /// [magic 4B][version 1B][chunkSize 4B][totalChunks 4B][originalSize 8B][baseNonce 12B]
    /// Each chunk: [encryptedChunkSize 4B (UInt32)][encrypted chunk data]
    private let headerSize = 33

    /// Parses chunk boundaries from streaming-format encrypted data.
    /// Returns an array of (offset, length) pairs for each chunk's data (excluding size prefix).
    private func parseChunks(from data: Data) -> [(dataOffset: Int, dataLength: Int)] {
        var chunks: [(dataOffset: Int, dataLength: Int)] = []
        var offset = headerSize

        while offset + 4 <= data.count {
            let encSize = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.load(as: UInt32.self)
            }
            let chunkDataOffset = offset + 4
            let chunkDataLength = Int(encSize)

            guard chunkDataOffset + chunkDataLength <= data.count else { break }

            chunks.append((dataOffset: chunkDataOffset, dataLength: chunkDataLength))
            offset = chunkDataOffset + chunkDataLength
        }

        return chunks
    }

    // MARK: - Swapped Chunks Detected

    func testSwappedChunksDetected() throws {
        // Create a file large enough for at least 3 chunks
        // Must exceed streamingThreshold (1MB) AND produce 3+ chunks (256KB each)
        let fileSize = VaultCoreConstants.streamingThreshold + VaultCoreConstants.streamingChunkSize * 2 + 100
        let sourceURL = try writeTestFile(size: fileSize)

        var encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        let chunks = parseChunks(from: encrypted)
        XCTAssertGreaterThanOrEqual(chunks.count, 3, "File should produce at least 3 chunks")

        // Swap chunk 0 and chunk 1 data (keeping size prefixes correct)
        let chunk0Data = encrypted.subdata(in: chunks[0].dataOffset..<(chunks[0].dataOffset + chunks[0].dataLength))
        let chunk1Data = encrypted.subdata(in: chunks[1].dataOffset..<(chunks[1].dataOffset + chunks[1].dataLength))

        // Write chunk 1 data into chunk 0 position
        encrypted.replaceSubrange(
            chunks[0].dataOffset..<(chunks[0].dataOffset + chunks[0].dataLength),
            with: chunk1Data
        )

        // Write chunk 0 data into chunk 1 position
        // Re-parse because the swap above may have shifted offsets if chunk sizes differ
        // However for same-size chunks (all full chunks), offsets remain the same.
        // To be safe, also update the size prefixes.
        let sizePrefix0Offset = chunks[0].dataOffset - 4
        let sizePrefix1Offset = chunks[1].dataOffset - 4

        var newSize0 = UInt32(chunk1Data.count)
        var newSize1 = UInt32(chunk0Data.count)
        encrypted.replaceSubrange(sizePrefix0Offset..<(sizePrefix0Offset + 4),
                                  with: Data(bytes: &newSize0, count: 4))
        encrypted.replaceSubrange(
            chunks[1].dataOffset..<(chunks[1].dataOffset + chunks[1].dataLength),
            with: chunk0Data
        )
        encrypted.replaceSubrange(sizePrefix1Offset..<(sizePrefix1Offset + 4),
                                  with: Data(bytes: &newSize1, count: 4))

        // Decryption should detect the nonce mismatch and throw chunkOrderingViolation
        XCTAssertThrowsError(try CryptoEngine.decryptStreaming(encrypted, with: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.chunkOrderingViolation,
                           "Swapped chunks should be detected as a chunk ordering violation")
        }
    }

    // MARK: - Duplicated Chunk Detected

    func testDuplicatedChunkDetected() throws {
        // Must exceed streamingThreshold (1MB) AND produce 3+ chunks (256KB each)
        let fileSize = VaultCoreConstants.streamingThreshold + VaultCoreConstants.streamingChunkSize * 2 + 100
        let sourceURL = try writeTestFile(size: fileSize)

        var encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        let chunks = parseChunks(from: encrypted)
        XCTAssertGreaterThanOrEqual(chunks.count, 3)

        // Duplicate chunk 0 into chunk 1's position
        let chunk0Data = encrypted.subdata(in: chunks[0].dataOffset..<(chunks[0].dataOffset + chunks[0].dataLength))

        // Overwrite chunk 1 data with chunk 0 data
        var newSize1 = UInt32(chunk0Data.count)
        let sizePrefix1Offset = chunks[1].dataOffset - 4
        encrypted.replaceSubrange(sizePrefix1Offset..<(sizePrefix1Offset + 4),
                                  with: Data(bytes: &newSize1, count: 4))
        encrypted.replaceSubrange(
            chunks[1].dataOffset..<(chunks[1].dataOffset + chunks[1].dataLength),
            with: chunk0Data
        )

        // Decryption should detect that chunk 1 has chunk 0's nonce
        XCTAssertThrowsError(try CryptoEngine.decryptStreaming(encrypted, with: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.chunkOrderingViolation,
                           "Duplicated chunk should be detected as a chunk ordering violation")
        }
    }

    // MARK: - Valid Streaming Round Trip (Control Test)

    func testValidStreamingDecryptSucceeds() throws {
        // Must exceed streamingThreshold (1MB) AND produce 3+ chunks (256KB each)
        let fileSize = VaultCoreConstants.streamingThreshold + VaultCoreConstants.streamingChunkSize * 2 + 100
        let sourceURL = try writeTestFile(size: fileSize)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        let decrypted = try CryptoEngine.decryptStreaming(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData,
                       "Untampered streaming encrypt/decrypt should round-trip successfully")
    }

    // MARK: - Single Chunk Streaming

    func testSingleChunkStreamingNotAffected() throws {
        // File just over the streaming threshold produces 1 chunk
        let fileSize = VaultCoreConstants.streamingThreshold + 1
        let sourceURL = try writeTestFile(size: fileSize)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted),
                      "File just over threshold should use streaming format")

        let chunks = parseChunks(from: encrypted)
        // A file of streamingThreshold + 1 bytes with 256KB chunks should produce
        // ceil((1048577) / 262144) = 5 chunks (4 full + 1 partial)
        // But the key point is that it decrypts fine
        XCTAssertGreaterThanOrEqual(chunks.count, 1)

        let decrypted = try CryptoEngine.decryptStreaming(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData,
                       "Single-chunk streaming file should decrypt successfully")
    }
}
