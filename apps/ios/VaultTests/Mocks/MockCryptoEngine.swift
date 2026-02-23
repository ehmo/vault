import Foundation
@testable import Vault

/// Mock CryptoEngine for testing. Records calls and allows configuring results.
final class MockCryptoEngine: CryptoEngineProtocol {
    var encryptCallCount = 0
    var decryptCallCount = 0
    var encryptResult: Result<Data, Error> = .success(Data())
    var decryptResult: Result<Data, Error> = .success(Data())

    func encrypt(_ data: Data, with key: Data) throws -> Data {
        encryptCallCount += 1
        return try encryptResult.get()
    }

    func decrypt(_ encryptedData: Data, with key: Data) throws -> Data {
        decryptCallCount += 1
        return try decryptResult.get()
    }

    func encryptFile(data: Data, filename: String, mimeType: String, with key: Data, fileId: UUID?) throws -> CryptoEngine.EncryptedFile {
        try CryptoEngine.encryptFile(data: data, filename: filename, mimeType: mimeType, with: key, fileId: fileId)
    }

    func decryptFile(data: Data, with key: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        try CryptoEngine.decryptFile(data: data, with: key)
    }

    func computeHMAC(for data: Data, with key: Data) -> Data {
        CryptoEngine.computeHMAC(for: data, with: key)
    }

    func verifyHMAC(_ hmac: Data, for data: Data, with key: Data) -> Bool {
        CryptoEngine.verifyHMAC(hmac, for: data, with: key)
    }

    func generateRandomBytes(count: Int) -> Data? {
        CryptoEngine.generateRandomBytes(count: count)
    }
}
