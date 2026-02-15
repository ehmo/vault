import XCTest
@testable import Vault

final class CryptoStreamingTests: XCTestCase {

    private var tempDir: URL!
    private var key: Data!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        key = CryptoEngine.generateRandomBytes(count: 32)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeTestFile(size: Int) -> URL {
        let url = tempDir.appendingPathComponent(UUID().uuidString)
        let data = CryptoEngine.generateRandomBytes(count: size) ?? Data(repeating: 0xAB, count: size)
        try! data.write(to: url)
        return url
    }

    // MARK: - Streaming Encrypt / Decrypt Round Trip

    func testStreamingEncryptDecryptRoundTrip() throws {
        let size = VaultCoreConstants.streamingThreshold + 1024
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        let decrypted = try CryptoEngine.decryptStreaming(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    func testSingleShotEncryptDecryptAtThreshold() throws {
        let size = VaultCoreConstants.streamingThreshold
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertFalse(CryptoEngine.isStreamingFormat(encrypted), "At-threshold files should use single-shot")

        let decrypted = try CryptoEngine.decryptStaged(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    func testStreamingEncryptDecryptOneByteOverThreshold() throws {
        let size = VaultCoreConstants.streamingThreshold + 1
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted), "1 byte over threshold should use streaming")

        let decrypted = try CryptoEngine.decryptStaged(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    func testEncryptDecryptEmptyFile() throws {
        let sourceURL = writeTestFile(size: 0)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertFalse(CryptoEngine.isStreamingFormat(encrypted))
        XCTAssertEqual(encrypted.count, 28, "0-byte file → 12 nonce + 0 ciphertext + 16 tag = 28")

        let decrypted = try CryptoEngine.decryptStaged(encrypted, with: key)
        XCTAssertEqual(decrypted, Data())
    }

    func testEncryptDecryptOneByte() throws {
        let sourceURL = writeTestFile(size: 1)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertEqual(encrypted.count, 29, "1-byte file → 12 nonce + 1 ciphertext + 16 tag = 29")

        let decrypted = try CryptoEngine.decryptStaged(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    func testEncryptDecryptLastChunkPartial() throws {
        // 256KB chunk size. Use a size that doesn't divide evenly: 256KB * 4 + 100 bytes
        let chunkSize = VaultCoreConstants.streamingChunkSize
        let size = chunkSize * 4 + 100
        XCTAssertTrue(size > VaultCoreConstants.streamingThreshold)
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        let decrypted = try CryptoEngine.decryptStreaming(encrypted, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    // MARK: - Streaming to FileHandle

    func testStreamingToHandleRoundTrip() throws {
        let size = VaultCoreConstants.streamingThreshold + 512
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encryptedURL = tempDir.appendingPathComponent("encrypted.bin")
        FileManager.default.createFile(atPath: encryptedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: encryptedURL)
        try CryptoEngine.encryptFileStreamingToHandle(from: sourceURL, to: handle, with: key)
        try handle.close()

        let encryptedData = try Data(contentsOf: encryptedURL)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encryptedData))

        let decrypted = try CryptoEngine.decryptStreaming(encryptedData, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    func testStreamingToHandleSmallFile() throws {
        let size = 512
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encryptedURL = tempDir.appendingPathComponent("encrypted_small.bin")
        FileManager.default.createFile(atPath: encryptedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: encryptedURL)
        try CryptoEngine.encryptFileStreamingToHandle(from: sourceURL, to: handle, with: key)
        try handle.close()

        let encryptedData = try Data(contentsOf: encryptedURL)
        XCTAssertFalse(CryptoEngine.isStreamingFormat(encryptedData), "Small file should use single-shot via handle path")

        let decrypted = try CryptoEngine.decrypt(encryptedData, with: key)
        XCTAssertEqual(decrypted, originalData)
    }

    // MARK: - decryptStaged Auto-Detection

    func testDecryptStagedAutoDetectsFormat() throws {
        // Single-shot
        let smallData = CryptoEngine.generateRandomBytes(count: 100)!
        let singleShot = try CryptoEngine.encrypt(smallData, with: key)
        let decryptedSingle = try CryptoEngine.decryptStaged(singleShot, with: key)
        XCTAssertEqual(decryptedSingle, smallData)

        // Streaming
        let largeURL = writeTestFile(size: VaultCoreConstants.streamingThreshold + 256)
        let originalLarge = try Data(contentsOf: largeURL)
        let streaming = try CryptoEngine.encryptForStaging(largeURL, with: key)
        let decryptedStreaming = try CryptoEngine.decryptStaged(streaming, with: key)
        XCTAssertEqual(decryptedStreaming, originalLarge)
    }

    // MARK: - Encrypted Content Size Accuracy

    func testEncryptedContentSizeAccuracy() throws {
        let sizes = [0, 1, 100, VaultCoreConstants.streamingThreshold, VaultCoreConstants.streamingThreshold + 1,
                     VaultCoreConstants.streamingChunkSize * 3 + 99]

        for size in sizes {
            let sourceURL = writeTestFile(size: size)
            let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
            let predicted = CryptoEngine.encryptedContentSize(forFileOfSize: size)
            XCTAssertEqual(predicted, encrypted.count, "Size prediction mismatch for file size \(size)")
        }
    }

    // MARK: - Streaming From Handle To File

    func testStreamingFromHandleToFileRoundTrip() throws {
        let size = VaultCoreConstants.streamingThreshold + 2048
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        // Encrypt to streaming format
        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        // Write encrypted data to a file so we can read via handle
        let encryptedURL = tempDir.appendingPathComponent("handle_input.bin")
        try encrypted.write(to: encryptedURL)

        let readHandle = try FileHandle(forReadingFrom: encryptedURL)
        defer { try? readHandle.close() }

        let outputURL = tempDir.appendingPathComponent("decrypted_output.bin")

        try CryptoEngine.decryptStreamingFromHandleToFile(
            handle: readHandle,
            contentLength: encrypted.count,
            with: key,
            outputURL: outputURL
        )

        let decrypted = try Data(contentsOf: outputURL)
        XCTAssertEqual(decrypted, originalData)
    }

    // MARK: - Error Cases

    func testWrongKeyDecryptionFails() throws {
        let sourceURL = writeTestFile(size: 256)
        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)

        let wrongKey = CryptoEngine.generateRandomBytes(count: 32)!
        XCTAssertThrowsError(try CryptoEngine.decryptStaged(encrypted, with: wrongKey))
    }

    func testTruncatedStreamingHeaderThrows() {
        // Build data with valid magic but < 33 bytes total
        var magic = VaultCoreConstants.streamingMagic
        var data = Data(bytes: &magic, count: 4)
        data.append(Data(repeating: 0, count: 20)) // 24 bytes total, < 33

        XCTAssertThrowsError(try CryptoEngine.decryptStreaming(data, with: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.invalidData)
        }
    }

    func testWrongMagicNumberThrows() {
        // 33 bytes but wrong magic
        var wrongMagic: UInt32 = 0xDEADBEEF
        var data = Data(bytes: &wrongMagic, count: 4)
        data.append(Data(repeating: 0, count: 29))

        XCTAssertThrowsError(try CryptoEngine.decryptStreaming(data, with: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.invalidData)
        }
    }

    func testTruncatedChunkDataThrows() throws {
        // Encrypt a file to get valid streaming data, then truncate it
        let sourceURL = writeTestFile(size: VaultCoreConstants.streamingThreshold + 512)
        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        // Truncate: keep header (33 bytes) + chunk size prefix (4 bytes) but remove chunk data
        let truncated = encrypted.prefix(37 + 10)

        XCTAssertThrowsError(try CryptoEngine.decryptStreaming(truncated, with: key)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.invalidData)
        }
    }

    func testCorruptedChunkContentThrows() throws {
        let sourceURL = writeTestFile(size: VaultCoreConstants.streamingThreshold + 512)
        var encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        // Corrupt a byte in the first chunk's ciphertext (after header + chunk size prefix)
        let corruptOffset = 33 + 4 + 10
        encrypted[corruptOffset] ^= 0xFF

        XCTAssertThrowsError(try CryptoEngine.decryptStreaming(encrypted, with: key))
    }

    func testInvalidKeyLengthThrows() {
        let sourceURL = writeTestFile(size: 100)
        let badKeys: [Data] = [
            Data(repeating: 0xAA, count: 16),
            Data(repeating: 0xAA, count: 64),
            Data(),
        ]

        for badKey in badKeys {
            XCTAssertThrowsError(try CryptoEngine.encryptForStaging(sourceURL, with: badKey),
                                 "Key of length \(badKey.count) should throw") { error in
                if badKey.count == 16 || badKey.count == 64 || badKey.isEmpty {
                    XCTAssertEqual(error as? CryptoError, CryptoError.keyGenerationFailed)
                }
            }
        }
    }

    // MARK: - XOR Nonce

    func testXorNonceProducesDifferentNonces() throws {
        let baseNonce = CryptoEngine.generateRandomBytes(count: 12)!
        let nonce0 = try CryptoEngine.xorNonce(baseNonce, with: 0)
        let nonce1 = try CryptoEngine.xorNonce(baseNonce, with: 1)

        XCTAssertEqual(nonce0, baseNonce, "XOR with 0 should be identity")
        XCTAssertNotEqual(nonce0, nonce1, "Different indices should produce different nonces")
    }

    func testXorNonceInvalidBaseLengthThrows() {
        let shortNonce = Data(repeating: 0xAA, count: 11)
        XCTAssertThrowsError(try CryptoEngine.xorNonce(shortNonce, with: 0)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.invalidData)
        }
    }

    // MARK: - readExact

    func testReadExactShortReadThrows() throws {
        let fileURL = tempDir.appendingPathComponent("short.bin")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        XCTAssertThrowsError(try CryptoEngine.readExact(10, from: handle)) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.invalidData)
        }
    }

    // MARK: - Multi-Chunk Integrity

    func testMultiChunkStreamingIntegrity() throws {
        // 3MB+ file → multiple 256KB chunks
        let size = VaultCoreConstants.streamingChunkSize * 12 + 137
        let sourceURL = writeTestFile(size: size)
        let originalData = try Data(contentsOf: sourceURL)

        let encrypted = try CryptoEngine.encryptForStaging(sourceURL, with: key)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(encrypted))

        let decrypted = try CryptoEngine.decryptStreaming(encrypted, with: key)
        XCTAssertEqual(decrypted.count, originalData.count)
        XCTAssertEqual(decrypted, originalData, "Every byte must survive round-trip")
    }
}
