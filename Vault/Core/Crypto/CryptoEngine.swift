import Foundation
import CryptoKit
import Security

enum CryptoError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case keyGenerationFailed
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .invalidData: return "Invalid or corrupted data"
        case .keyGenerationFailed: return "Failed to generate encryption key"
        case .integrityCheckFailed: return "Data integrity check failed"
        }
    }
}

enum CryptoEngine {

    // MARK: - AES-256-GCM Encryption

    static func encrypt(_ data: Data, with key: Data) throws -> Data {
        guard key.count == 32 else {
            #if !EXTENSION
            Task { @MainActor in
                SentryManager.shared.captureError(CryptoError.keyGenerationFailed)
            }
            #endif
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

    static func decrypt(_ encryptedData: Data, with key: Data) throws -> Data {
        guard key.count == 32 else {
            #if !EXTENSION
            Task { @MainActor in
                SentryManager.shared.captureError(CryptoError.keyGenerationFailed)
            }
            #endif
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

    static func encryptFile(data: Data, filename: String, mimeType: String, with key: Data) throws -> EncryptedFile {
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

    static func decryptFile(data: Data, with key: Data) throws -> (header: EncryptedFileHeader, content: Data) {
        guard data.count > 4 else {
            #if !EXTENSION
            Task { @MainActor in
                SentryManager.shared.captureError(CryptoError.invalidData)
            }
            #endif
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

    // MARK: - Streaming Encryption (chunked AES-GCM)

    /// Encrypts a file using chunked AES-GCM for memory-efficient processing of large files.
    /// Files ≤ streamingThreshold use single-shot encryption (no streaming header).
    /// Files > streamingThreshold use the VCSE streaming format.
    static func encryptForStaging(_ fileURL: URL, with key: Data) throws -> Data {
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0

        if fileSize <= VaultCoreConstants.streamingThreshold {
            let data = try Data(contentsOf: fileURL)
            return try encrypt(data, with: key)
        }

        return try encryptStreaming(fileURL: fileURL, originalSize: fileSize, with: key)
    }

    /// Stream-encrypts a file with chunked AES-GCM.
    /// Format: [magic 4B][version 1B][chunkSize 4B][totalChunks 4B][originalSize 8B][baseNonce 12B]
    ///         then per chunk: [encryptedChunkSize 4B][AES-GCM encrypted chunk]
    static func encryptStreaming(fileURL: URL, originalSize: Int, with key: Data) throws -> Data {
        guard key.count == 32 else { throw CryptoError.keyGenerationFailed }

        let chunkSize = VaultCoreConstants.streamingChunkSize
        let totalChunks = (originalSize + chunkSize - 1) / chunkSize
        let symmetricKey = SymmetricKey(data: key)

        // Generate base nonce (12 bytes)
        guard let baseNonceData = generateRandomBytes(count: 12) else {
            throw CryptoError.encryptionFailed
        }

        // Write header
        var output = Data()
        var magic = VaultCoreConstants.streamingMagic
        output.append(Data(bytes: &magic, count: 4))
        var version = VaultCoreConstants.streamingVersion
        output.append(Data(bytes: &version, count: 1))
        var cs = UInt32(chunkSize)
        output.append(Data(bytes: &cs, count: 4))
        var tc = UInt32(totalChunks)
        output.append(Data(bytes: &tc, count: 4))
        var os = UInt64(originalSize)
        output.append(Data(bytes: &os, count: 8))
        output.append(baseNonceData)

        // Read and encrypt chunks
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        for chunkIndex in 0..<totalChunks {
            let chunkData = handle.readData(ofLength: chunkSize)
            guard !chunkData.isEmpty else { break }

            // XOR base nonce with chunk index
            let nonce = try xorNonce(baseNonceData, with: UInt64(chunkIndex))
            let gcmNonce = try AES.GCM.Nonce(data: nonce)

            let sealedBox = try AES.GCM.seal(chunkData, using: symmetricKey, nonce: gcmNonce)
            guard let combined = sealedBox.combined else {
                throw CryptoError.encryptionFailed
            }

            // Write [encryptedChunkSize][encryptedChunk]
            var encSize = UInt32(combined.count)
            output.append(Data(bytes: &encSize, count: 4))
            output.append(combined)
        }

        return output
    }

    /// Decrypts streaming-encrypted data (VCSE format).
    static func decryptStreaming(_ data: Data, with key: Data) throws -> Data {
        guard key.count == 32 else { throw CryptoError.keyGenerationFailed }

        // Parse header: magic(4) + version(1) + chunkSize(4) + totalChunks(4) + originalSize(8) + baseNonce(12) = 33 bytes
        guard data.count >= 33 else { throw CryptoError.invalidData }

        let magic = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard magic == VaultCoreConstants.streamingMagic else { throw CryptoError.invalidData }

        let totalChunks = data.subdata(in: 9..<13).withUnsafeBytes { $0.load(as: UInt32.self) }
        let baseNonceData = data.subdata(in: 21..<33)
        let symmetricKey = SymmetricKey(data: key)

        var output = Data()
        var offset = 33

        for chunkIndex in 0..<Int(totalChunks) {
            guard offset + 4 <= data.count else { throw CryptoError.invalidData }
            let encSize = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4

            guard offset + Int(encSize) <= data.count else { throw CryptoError.invalidData }
            let encChunk = data.subdata(in: offset..<(offset + Int(encSize)))
            offset += Int(encSize)

            let nonce = try xorNonce(baseNonceData, with: UInt64(chunkIndex))
            _ = try AES.GCM.Nonce(data: nonce)
            let sealedBox = try AES.GCM.SealedBox(combined: encChunk)
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            output.append(decrypted)
        }

        return output
    }

    /// Detects whether data is in VCSE streaming format.
    static func isStreamingFormat(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let magic = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        return magic == VaultCoreConstants.streamingMagic
    }

    /// Decrypts data that may be either single-shot or streaming format.
    static func decryptStaged(_ data: Data, with key: Data) throws -> Data {
        if isStreamingFormat(data) {
            return try decryptStreaming(data, with: key)
        } else {
            return try decrypt(data, with: key)
        }
    }

    /// XORs a 12-byte nonce with a chunk index (big-endian, into the last 8 bytes).
    private static func xorNonce(_ baseNonce: Data, with index: UInt64) throws -> Data {
        guard baseNonce.count == 12 else { throw CryptoError.invalidData }
        var nonce = baseNonce
        var bigEndianIndex = index.bigEndian
        let indexBytes = withUnsafeBytes(of: &bigEndianIndex) { Data($0) }
        // XOR into last 8 bytes of nonce
        for i in 0..<8 {
            nonce[4 + i] ^= indexBytes[i]
        }
        return nonce
    }

    // MARK: - Secure Random

    static func generateRandomBytes(count: Int) -> Data? {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return result == errSecSuccess ? data : nil
    }

    // MARK: - HMAC for Integrity

    static func computeHMAC(for data: Data, with key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let authCode = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(authCode)
    }

    static func verifyHMAC(_ hmac: Data, for data: Data, with key: Data) -> Bool {
        let computed = computeHMAC(for: data, with: key)
        return hmac == computed
    }
}
