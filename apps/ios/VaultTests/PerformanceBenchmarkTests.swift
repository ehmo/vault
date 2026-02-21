import XCTest
@testable import Vault

final class PerformanceBenchmarkTests: XCTestCase {

    // MARK: - PBKDF2 Key Derivation

    func testPBKDF2_600KIterations() async throws {
        let pattern = [0, 1, 2, 5, 8, 7, 6, 3]
        measure {
            let exp = expectation(description: "derive")
            Task {
                _ = try await KeyDerivation.deriveKey(from: pattern, gridSize: 5)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    // MARK: - Symmetric Encryption/Decryption

    func testEncrypt_1MB() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        measure {
            _ = try? CryptoEngine.encrypt(data, with: key)
        }
    }

    func testEncrypt_10MB() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 10_000_000)!
        measure {
            _ = try? CryptoEngine.encrypt(data, with: key)
        }
    }

    func testDecrypt_1MB() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
        measure {
            _ = try? CryptoEngine.decrypt(encrypted, with: key)
        }
    }

    func testDecrypt_10MB() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = CryptoEngine.generateRandomBytes(count: 10_000_000)!
        let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
        measure {
            _ = try? CryptoEngine.decrypt(encrypted, with: key)
        }
    }

    // MARK: - SecureDelete

    func testSecureDelete_1MB() throws {
        measure {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
            try? data.write(to: tempURL)
            try? SecureDelete.deleteFile(at: tempURL)
        }
    }

    func testSecureDelete_10MB() throws {
        measure {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let data = CryptoEngine.generateRandomBytes(count: 10_000_000)!
            try? data.write(to: tempURL)
            try? SecureDelete.deleteFile(at: tempURL)
        }
    }

    // MARK: - HMAC

    func testHMAC_1MB() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        measure {
            _ = CryptoEngine.computeHMAC(for: data, with: key)
        }
    }

    func testHMACVerify_1MB() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        let hmac = CryptoEngine.computeHMAC(for: data, with: key)
        measure {
            _ = CryptoEngine.verifyHMAC(hmac, for: data, with: key)
        }
    }
}
