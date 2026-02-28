import XCTest
import CryptoKit
@testable import Vault

/// Tests for backup key derivation and AES-GCM structural invariants
/// that the opaque backup system relies on.
@MainActor
final class ICloudBackupCryptoTests: XCTestCase {

    // MARK: - Backup Key Derivation

    func testBackupKeyIsDeterministic() throws {
        let pattern = [0, 1, 2, 3, 4, 5, 6]
        let key1 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        let key2 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        XCTAssertEqual(key1, key2)
    }

    func testBackupKeyIs32Bytes() throws {
        let key = try KeyDerivation.deriveBackupKey(from: [0, 1, 2, 3, 4, 5, 6], gridSize: 5)
        XCTAssertEqual(key.count, 32)
    }

    func testBackupKeyVariesWithPattern() throws {
        let key1 = try KeyDerivation.deriveBackupKey(from: [0, 1, 2, 3, 4, 5, 6], gridSize: 5)
        let key2 = try KeyDerivation.deriveBackupKey(from: [6, 5, 4, 3, 2, 1, 0], gridSize: 5)
        XCTAssertNotEqual(key1, key2)
    }

    func testBackupKeyVariesWithGridSize() throws {
        let pattern = [0, 1, 2, 3, 4, 5, 6]
        let key1 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 5)
        let key2 = try KeyDerivation.deriveBackupKey(from: pattern, gridSize: 6)
        XCTAssertNotEqual(key1, key2)
    }

    func testBackupKeyRejectsShortPattern() {
        XCTAssertThrowsError(try KeyDerivation.deriveBackupKey(from: [0, 1, 2, 3, 4], gridSize: 5)) { error in
            XCTAssertTrue(error is KeyDerivationError)
        }
    }

    func testBackupKeyRejectsEmptyPattern() {
        XCTAssertThrowsError(try KeyDerivation.deriveBackupKey(from: [], gridSize: 5))
    }

    // MARK: - AES-GCM Structural Invariants

    func testTagSizeIs64BytesFor36BytePlaintext() throws {
        // Backup tags: 36B plaintext → 64B (12 nonce + 36 cipher + 16 auth)
        let key = SymmetricKey(data: Data(repeating: 0xAA, count: 32))
        let sealed = try AES.GCM.seal(Data(repeating: 0xBB, count: 36), using: key)
        XCTAssertEqual(sealed.combined!.count, 64)
    }

    func testAESGCMOverheadIs28Bytes() throws {
        let key = SymmetricKey(data: Data(repeating: 0xCC, count: 32))
        for size in [0, 1, 100, 1000] {
            let sealed = try AES.GCM.seal(Data(repeating: 0xDD, count: size), using: key)
            XCTAssertEqual(sealed.combined!.count, size + 28,
                           "Overhead should be 28B for \(size)B plaintext")
        }
    }

    // MARK: - CryptoEngine

    func testEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xEE, count: 32)
        let plaintext = Data(repeating: 0xFF, count: 1024)
        let decrypted = try CryptoEngine.decrypt(CryptoEngine.encrypt(plaintext, with: key), with: key)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptWithWrongKeyFails() throws {
        let encrypted = try CryptoEngine.encrypt(
            Data(repeating: 0xCC, count: 100), with: Data(repeating: 0xAA, count: 32)
        )
        XCTAssertThrowsError(try CryptoEngine.decrypt(encrypted, with: Data(repeating: 0xBB, count: 32)))
    }

    func testEncryptRejectsInvalidKeySize() {
        XCTAssertThrowsError(try CryptoEngine.encrypt(
            Data(repeating: 0xBB, count: 100), with: Data(repeating: 0xAA, count: 16)
        ))
    }
}
