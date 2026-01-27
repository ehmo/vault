import Foundation
import CryptoKit
import Security

enum CryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case keyGenerationFailed
    case integrityCheckFailed
}

final class CryptoEngine {
    static let shared = CryptoEngine()
    private init() {}

    // MARK: - AES-256-GCM Encryption

    func encrypt(_ data: Data, with key: Data) throws -> Data {
        guard key.count == 32 else {
            throw CryptoError.keyGenerationFailed
        }

        let symmetricKey = SymmetricKey(data: key)

        // Generate random nonce (12 bytes for GCM)
        var nonceData = Data(count: 12)
        let result = nonceData.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 12, ptr.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw CryptoError.encryptionFailed
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)

        // Encrypt with AES-256-GCM (includes authentication tag)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        return combined
    }

    func decrypt(_ encryptedData: Data, with key: Data) throws -> Data {
        guard key.count == 32 else {
            throw CryptoError.keyGenerationFailed
        }

        let symmetricKey = SymmetricKey(data: key)

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)

        return decrypted
    }

    // MARK: - Encrypted File Structure

    struct EncryptedFile {
        let header: EncryptedFileHeader
        let encryptedContent: Data

        func serialize() -> Data {
            var data = Data()
            data.append(header.serialize())
            data.append(encryptedContent)
            return data
        }

        static func deserialize(from data: Data) throws -> EncryptedFile {
            guard data.count > EncryptedFileHeader.headerSize else {
                throw CryptoError.invalidData
            }

            let headerData = data.prefix(EncryptedFileHeader.headerSize)
            let header = try EncryptedFileHeader.deserialize(from: Data(headerData))
            let content = data.dropFirst(EncryptedFileHeader.headerSize)

            return EncryptedFile(header: header, encryptedContent: Data(content))
        }
    }

    struct EncryptedFileHeader {
        static let headerSize = 256 // Fixed header size

        let fileId: UUID
        let originalFilename: String
        let mimeType: String
        let originalSize: UInt64
        let createdAt: Date

        func serialize() -> Data {
            var data = Data(count: Self.headerSize)

            // File ID (16 bytes)
            data.replaceSubrange(0..<16, with: withUnsafeBytes(of: fileId.uuid) { Data($0) })

            // Original size (8 bytes)
            var size = originalSize
            data.replaceSubrange(16..<24, with: Data(bytes: &size, count: 8))

            // Created timestamp (8 bytes)
            var timestamp = createdAt.timeIntervalSince1970
            data.replaceSubrange(24..<32, with: Data(bytes: &timestamp, count: 8))

            // Filename (up to 100 bytes, UTF-8)
            let filenameData = originalFilename.data(using: .utf8) ?? Data()
            let filenameLength = min(filenameData.count, 100)
            data.replaceSubrange(32..<(32 + filenameLength), with: filenameData.prefix(filenameLength))

            // MIME type (up to 50 bytes, UTF-8) starting at offset 132
            let mimeData = mimeType.data(using: .utf8) ?? Data()
            let mimeLength = min(mimeData.count, 50)
            data.replaceSubrange(132..<(132 + mimeLength), with: mimeData.prefix(mimeLength))

            // Rest is padding (filled with zeros by default)
            return data
        }

        static func deserialize(from data: Data) throws -> EncryptedFileHeader {
            guard data.count >= headerSize else {
                throw CryptoError.invalidData
            }

            // File ID
            let uuidBytes = data.subdata(in: 0..<16)
            let uuid = uuidBytes.withUnsafeBytes { ptr -> UUID in
                let tuple = ptr.load(as: uuid_t.self)
                return UUID(uuid: tuple)
            }

            // Original size
            let sizeData = data.subdata(in: 16..<24)
            let size = sizeData.withUnsafeBytes { $0.load(as: UInt64.self) }

            // Timestamp
            let timestampData = data.subdata(in: 24..<32)
            let timestamp = timestampData.withUnsafeBytes { $0.load(as: Double.self) }
            let date = Date(timeIntervalSince1970: timestamp)

            // Filename
            let filenameData = data.subdata(in: 32..<132)
            let filename = String(data: filenameData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""

            // MIME type
            let mimeData = data.subdata(in: 132..<182)
            let mimeType = String(data: mimeData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""

            return EncryptedFileHeader(
                fileId: uuid,
                originalFilename: filename,
                mimeType: mimeType,
                originalSize: size,
                createdAt: date
            )
        }
    }

    // MARK: - File Encryption

    func encryptFile(data: Data, filename: String, mimeType: String, with key: Data) throws -> EncryptedFile {
        let header = EncryptedFileHeader(
            fileId: UUID(),
            originalFilename: filename,
            mimeType: mimeType,
            originalSize: UInt64(data.count),
            createdAt: Date()
        )

        // Encrypt the header
        let encryptedHeader = try encrypt(header.serialize(), with: key)

        // Encrypt the content
        let encryptedContent = try encrypt(data, with: key)

        // Combine: [encrypted header size (4 bytes)][encrypted header][encrypted content]
        var combined = Data()
        var headerSize = UInt32(encryptedHeader.count)
        combined.append(Data(bytes: &headerSize, count: 4))
        combined.append(encryptedHeader)
        combined.append(encryptedContent)

        return EncryptedFile(
            header: header,
            encryptedContent: combined
        )
    }

    func decryptFile(data: Data, with key: Data) throws -> (header: EncryptedFileHeader, content: Data) {
        guard data.count > 4 else {
            throw CryptoError.invalidData
        }

        // Read encrypted header size
        let headerSizeData = data.prefix(4)
        let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }

        guard data.count > 4 + Int(headerSize) else {
            throw CryptoError.invalidData
        }

        // Extract and decrypt header
        let encryptedHeader = data.subdata(in: 4..<(4 + Int(headerSize)))
        let decryptedHeaderData = try decrypt(encryptedHeader, with: key)
        let header = try EncryptedFileHeader.deserialize(from: decryptedHeaderData)

        // Extract and decrypt content
        let encryptedContent = data.subdata(in: (4 + Int(headerSize))..<data.count)
        let content = try decrypt(encryptedContent, with: key)

        return (header, content)
    }

    // MARK: - Secure Random

    func generateRandomBytes(count: Int) -> Data? {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return result == errSecSuccess ? data : nil
    }

    // MARK: - HMAC for Integrity

    func computeHMAC(for data: Data, with key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let authCode = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(authCode)
    }

    func verifyHMAC(_ hmac: Data, for data: Data, with key: Data) -> Bool {
        let computed = computeHMAC(for: data, with: key)
        return hmac == computed
    }
}
