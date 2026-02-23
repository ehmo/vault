import Foundation

/// Protocol abstracting CryptoEngine for testability.
/// Mirrors the static methods used by VaultIndexManager, VaultStorage, and DuressHandler
/// as instance methods on a conforming type.
protocol CryptoEngineProtocol {
    func encrypt(_ data: Data, with key: Data) throws -> Data
    func decrypt(_ encryptedData: Data, with key: Data) throws -> Data
    func encryptFile(data: Data, filename: String, mimeType: String, with key: Data, fileId: UUID?) throws -> CryptoEngine.EncryptedFile
    func decryptFile(data: Data, with key: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data)
    func computeHMAC(for data: Data, with key: Data) -> Data
    func verifyHMAC(_ hmac: Data, for data: Data, with key: Data) -> Bool
    func generateRandomBytes(count: Int) -> Data?
}

/// Default implementation that delegates to CryptoEngine's static methods.
struct DefaultCryptoEngine: CryptoEngineProtocol {
    func encrypt(_ data: Data, with key: Data) throws -> Data {
        try CryptoEngine.encrypt(data, with: key)
    }

    func decrypt(_ encryptedData: Data, with key: Data) throws -> Data {
        try CryptoEngine.decrypt(encryptedData, with: key)
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
