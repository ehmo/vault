import XCTest
@testable import Vault

final class CryptoEngineTests: XCTestCase {

    // MARK: - Encrypt / Decrypt Round Trip

    func testEncryptDecryptRoundTrip() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = Data("Hello, Vault!".utf8)

        let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
        let decrypted = try CryptoEngine.decrypt(encrypted, with: key)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptWithInvalidKeyThrows() {
        let shortKey = Data(repeating: 0xAA, count: 16)
        let data = Data("test".utf8)

        XCTAssertThrowsError(try CryptoEngine.encrypt(data, with: shortKey)) { error in
            XCTAssertTrue(error is CryptoError)
        }
    }

    func testDecryptCorruptedDataThrows() {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let garbage = CryptoEngine.generateRandomBytes(count: 64)!

        XCTAssertThrowsError(try CryptoEngine.decrypt(garbage, with: key))
    }

    func testEncryptProducesDifferentCiphertexts() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = Data("same input".utf8)

        let a = try CryptoEngine.encrypt(plaintext, with: key)
        let b = try CryptoEngine.encrypt(plaintext, with: key)

        XCTAssertNotEqual(a, b, "Different nonces should produce different ciphertexts")
    }

    // MARK: - File Header

    func testFileHeaderSerializeDeserialize() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1700000000)
        let header = CryptoEngine.EncryptedFileHeader(
            fileId: id,
            originalFilename: "photo.jpg",
            mimeType: "image/jpeg",
            originalSize: 12345,
            createdAt: date
        )

        let data = header.serialize()
        XCTAssertEqual(data.count, CryptoEngine.EncryptedFileHeader.headerSize)

        let restored = try CryptoEngine.EncryptedFileHeader.deserialize(from: data)
        XCTAssertEqual(restored.fileId, id)
        XCTAssertEqual(restored.originalFilename, "photo.jpg")
        XCTAssertEqual(restored.mimeType, "image/jpeg")
        XCTAssertEqual(restored.originalSize, 12345)
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - File Encryption

    func testEncryptFileDecryptFile() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let content = Data("secret document content".utf8)

        let encFile = try CryptoEngine.encryptFile(
            data: content,
            filename: "doc.txt",
            mimeType: "text/plain",
            with: key
        )

        let (header, decrypted) = try CryptoEngine.decryptFile(data: encFile.encryptedContent, with: key)

        XCTAssertEqual(decrypted, content)
        XCTAssertEqual(header.originalFilename, "doc.txt")
        XCTAssertEqual(header.mimeType, "text/plain")
        XCTAssertEqual(header.originalSize, UInt64(content.count))
    }

    // MARK: - Streaming Format Detection

    func testStreamingFormatDetection() {
        // VCSE magic bytes: 0x56435345
        var magic = VaultCoreConstants.streamingMagic
        let vcseData = Data(bytes: &magic, count: 4) + Data(repeating: 0, count: 29)
        XCTAssertTrue(CryptoEngine.isStreamingFormat(vcseData))

        let nonStreaming = Data("not streaming".utf8)
        XCTAssertFalse(CryptoEngine.isStreamingFormat(nonStreaming))

        let tooShort = Data([0x56])
        XCTAssertFalse(CryptoEngine.isStreamingFormat(tooShort))
    }

    // MARK: - HMAC

    func testHMACRoundTrip() {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = Data("integrity check".utf8)

        let hmac = CryptoEngine.computeHMAC(for: data, with: key)
        XCTAssertTrue(CryptoEngine.verifyHMAC(hmac, for: data, with: key))
    }

    func testHMACTamperDetection() {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = Data("original".utf8)

        let hmac = CryptoEngine.computeHMAC(for: data, with: key)

        var tampered = data
        tampered[0] ^= 0xFF
        XCTAssertFalse(CryptoEngine.verifyHMAC(hmac, for: tampered, with: key))
    }
}
