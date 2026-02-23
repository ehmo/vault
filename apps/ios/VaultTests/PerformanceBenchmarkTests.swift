import XCTest
@testable import Vault

final class PerformanceBenchmarkTests: XCTestCase {

    // MARK: - PBKDF2 Key Derivation

    func testPbkdf2600kIterations() async throws {
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

    func testEncrypt1mb() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        measure {
            _ = try? CryptoEngine.encrypt(data, with: key)
        }
    }

    func testEncrypt10mb() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 10_000_000)!
        measure {
            _ = try? CryptoEngine.encrypt(data, with: key)
        }
    }

    func testDecrypt1mb() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
        measure {
            _ = try? CryptoEngine.decrypt(encrypted, with: key)
        }
    }

    func testDecrypt10mb() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let plaintext = CryptoEngine.generateRandomBytes(count: 10_000_000)!
        let encrypted = try CryptoEngine.encrypt(plaintext, with: key)
        measure {
            _ = try? CryptoEngine.decrypt(encrypted, with: key)
        }
    }

    // MARK: - SecureDelete

    func testSecureDelete1mb() throws {
        measure {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
            try? data.write(to: tempURL)
            try? SecureDelete.deleteFile(at: tempURL)
        }
    }

    func testSecureDelete10mb() throws {
        measure {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let data = CryptoEngine.generateRandomBytes(count: 10_000_000)!
            try? data.write(to: tempURL)
            try? SecureDelete.deleteFile(at: tempURL)
        }
    }

    // MARK: - HMAC

    func testHmac1mb() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        measure {
            _ = CryptoEngine.computeHMAC(for: data, with: key)
        }
    }

    func testHmacVerify1mb() throws {
        let key = CryptoEngine.generateRandomBytes(count: 32)!
        let data = CryptoEngine.generateRandomBytes(count: 1_000_000)!
        let hmac = CryptoEngine.computeHMAC(for: data, with: key)
        measure {
            _ = CryptoEngine.verifyHMAC(hmac, for: data, with: key)
        }
    }
}
