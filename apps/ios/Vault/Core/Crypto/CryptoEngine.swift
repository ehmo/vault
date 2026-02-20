import Foundation
import CryptoKit
import Security

enum CryptoError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case keyGenerationFailed
    case integrityCheckFailed
    case chunkOrderingViolation

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .invalidData: return "Invalid or corrupted data"
        case .keyGenerationFailed: return "Failed to generate encryption key"
        case .integrityCheckFailed: return "Data integrity check failed"
        case .chunkOrderingViolation: return "Encrypted chunk ordering has been tampered with"
        }
    }
}

enum CryptoEngine {

    // MARK: - AES-256-GCM Encryption

    static func encrypt(_ data: Data, with key: Data) throws -> Data {
        guard key.count == 32 else {
            #if !EXTENSION
            Task { @MainActor in
                EmbraceManager.shared.captureError(CryptoError.keyGenerationFailed)
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
                EmbraceManager.shared.captureError(CryptoError.keyGenerationFailed)
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

    static func encryptFile(data: Data, filename: String, mimeType: String, with key: Data, fileId: UUID? = nil) throws -> EncryptedFile {
        let header = EncryptedFileHeader(
            fileId: fileId ?? UUID(),
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

    /// Encrypts a file from a URL without loading the entire raw content into memory.
    /// Uses streaming encryption (VCSE) for files > 1MB.
    static func encryptFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: Data, fileId: UUID? = nil) throws -> EncryptedFile {
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0

        let header = EncryptedFileHeader(
            fileId: fileId ?? UUID(),
            originalFilename: filename,
            mimeType: mimeType,
            originalSize: UInt64(fileSize),
            createdAt: Date()
        )

        let encryptedHeader = try encrypt(header.serialize(), with: key)
        let encryptedContent = try encryptForStaging(fileURL, with: key)

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
                EmbraceManager.shared.captureError(CryptoError.invalidData)
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
        let content = try decryptStaged(encryptedContent, with: key)

        return (header, content)
    }

    /// Decrypts an encrypted file directly to a temp URL, minimizing peak memory.
    /// For VCSE content: stream-decrypts 256KB chunks to file (~512KB peak).
    /// For single-shot content: decrypts in memory and writes to file.
    @discardableResult
    static func decryptFileToTempURL(data: Data, with key: Data, tempURL: URL) throws -> EncryptedFileHeader {
        guard data.count > 4 else {
            throw CryptoError.invalidData
        }

        let headerSizeData = data.prefix(4)
        let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }

        guard data.count > 4 + Int(headerSize) else {
            throw CryptoError.invalidData
        }

        let encryptedHeader = data.subdata(in: 4..<(4 + Int(headerSize)))
        let decryptedHeaderData = try decrypt(encryptedHeader, with: key)
        let header = try EncryptedFileHeader.deserialize(from: decryptedHeaderData)

        let encryptedContent = data.subdata(in: (4 + Int(headerSize))..<data.count)

        if isStreamingFormat(encryptedContent) {
            try decryptStreamingToFile(encryptedContent, with: key, outputURL: tempURL)
        } else {
            let content = try decrypt(encryptedContent, with: key)
            try content.write(to: tempURL, options: [.atomic, .completeFileProtection])
        }

        return header
    }

    /// Stream-decrypts VCSE data directly to a file, writing each chunk as it's decrypted.
    private static func decryptStreamingToFile(_ data: Data, with key: Data, outputURL: URL) throws {
        guard key.count == 32 else { throw CryptoError.keyGenerationFailed }
        guard data.count >= 33 else { throw CryptoError.invalidData }

        let magic = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard magic == VaultCoreConstants.streamingMagic else { throw CryptoError.invalidData }

        let totalChunks = data.subdata(in: 9..<13).withUnsafeBytes { $0.load(as: UInt32.self) }
        let baseNonceData = data.subdata(in: 21..<33)
        let symmetricKey = SymmetricKey(data: key)

        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.complete
        ])
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        var offset = 33

        for chunkIndex in 0..<Int(totalChunks) {
            guard offset + 4 <= data.count else { throw CryptoError.invalidData }
            let encSize = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4

            guard offset + Int(encSize) <= data.count else { throw CryptoError.invalidData }
            let encChunk = data.subdata(in: offset..<(offset + Int(encSize)))
            offset += Int(encSize)

            let expectedNonce = try AES.GCM.Nonce(data: xorNonce(baseNonceData, with: UInt64(chunkIndex)))
            let sealedBox = try AES.GCM.SealedBox(combined: encChunk)
            guard Data(sealedBox.nonce) == Data(expectedNonce) else { throw CryptoError.chunkOrderingViolation }
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            try handle.write(contentsOf: decrypted)
        }
    }

    /// Stream-decrypts VCSE content directly from an already-positioned file handle.
    /// The handle must be positioned at the start of streaming content and `contentLength`
    /// must match the encrypted content length (not including vault entry header bytes).
    static func decryptStreamingFromHandleToFile(
        handle: FileHandle,
        contentLength: Int,
        with key: Data,
        outputURL: URL
    ) throws {
        guard key.count == 32 else { throw CryptoError.keyGenerationFailed }
        guard contentLength >= 33 else { throw CryptoError.invalidData }

        let header = try readExact(33, from: handle)
        let magic = header.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        guard magic == VaultCoreConstants.streamingMagic else { throw CryptoError.invalidData }

        let totalChunks = header.subdata(in: 9..<13).withUnsafeBytes { $0.load(as: UInt32.self) }
        let baseNonceData = header.subdata(in: 21..<33)
        let symmetricKey = SymmetricKey(data: key)

        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.complete
        ])
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        var consumedBytes = 33
        for chunkIndex in 0..<Int(totalChunks) {
            let encSizeData = try readExact(4, from: handle)
            consumedBytes += 4
            let encSize = encSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }
            guard encSize > 0 else { throw CryptoError.invalidData }
            guard consumedBytes + Int(encSize) <= contentLength else { throw CryptoError.invalidData }

            let encChunk = try readExact(Int(encSize), from: handle)
            consumedBytes += Int(encSize)

            let expectedNonce = try AES.GCM.Nonce(data: xorNonce(baseNonceData, with: UInt64(chunkIndex)))
            let sealedBox = try AES.GCM.SealedBox(combined: encChunk)
            guard Data(sealedBox.nonce) == Data(expectedNonce) else { throw CryptoError.chunkOrderingViolation }
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            try outputHandle.write(contentsOf: decrypted)
        }

        guard consumedBytes == contentLength else {
            throw CryptoError.invalidData
        }
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

    /// Stream-encrypts a file with chunked AES-GCM but accumulates entire output in memory.
    /// Prefer `encryptFileStreamingToHandle` for true O(chunk) memory usage.
    /// Format: [magic 4B][version 1B][chunkSize 4B][totalChunks 4B][originalSize 8B][baseNonce 12B]
    ///         then per chunk: [encryptedChunkSize 4B][AES-GCM encrypted chunk]
    @available(*, deprecated, message: "Accumulates entire output in memory. Use encryptFileStreamingToHandle for true streaming.")
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

            let expectedNonce = try AES.GCM.Nonce(data: xorNonce(baseNonceData, with: UInt64(chunkIndex)))
            let sealedBox = try AES.GCM.SealedBox(combined: encChunk)
            guard Data(sealedBox.nonce) == Data(expectedNonce) else { throw CryptoError.chunkOrderingViolation }
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            output.append(decrypted)
        }

        return output
    }

    // MARK: - Streaming Encryption to FileHandle (zero-copy)

    /// Calculates the exact encrypted content size for a file, without encrypting it.
    /// This allows pre-allocating blob space before streaming encryption.
    static func encryptedContentSize(forFileOfSize fileSize: Int) -> Int {
        if fileSize <= VaultCoreConstants.streamingThreshold {
            // Single-shot AES-GCM: nonce(12) + ciphertext(fileSize) + tag(16)
            return fileSize + 28
        }
        let chunkSize = VaultCoreConstants.streamingChunkSize
        let totalChunks = (fileSize + chunkSize - 1) / chunkSize
        // Streaming header(33) + per-chunk overhead(4 size prefix + 28 AES-GCM) + raw data
        return 33 + totalChunks * 32 + fileSize
    }

    /// Stream-encrypts a file directly to a FileHandle, writing chunks as they're encrypted.
    /// Peak memory: ~256KB (one chunk) instead of the entire file.
    /// Uses throwing `write(contentsOf:)` so disk-full errors propagate as Swift errors
    /// instead of crashing via uncatchable Objective-C NSExceptions.
    static func encryptFileStreamingToHandle(from sourceURL: URL, to handle: FileHandle, with key: Data) throws {
        guard key.count == 32 else { throw CryptoError.keyGenerationFailed }
        let fileSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int ?? 0

        if fileSize <= VaultCoreConstants.streamingThreshold {
            // Small file: single-shot encrypt and write
            let data = try Data(contentsOf: sourceURL)
            let encrypted = try encrypt(data, with: key)
            try handle.write(contentsOf: encrypted)
            return
        }

        // Streaming encryption — write directly to handle instead of accumulating in memory
        let chunkSize = VaultCoreConstants.streamingChunkSize
        let totalChunks = (fileSize + chunkSize - 1) / chunkSize
        let symmetricKey = SymmetricKey(data: key)

        guard let baseNonceData = generateRandomBytes(count: 12) else {
            throw CryptoError.encryptionFailed
        }

        // Write streaming header (33 bytes)
        var magic = VaultCoreConstants.streamingMagic
        try handle.write(contentsOf: Data(bytes: &magic, count: 4))
        var version = VaultCoreConstants.streamingVersion
        try handle.write(contentsOf: Data(bytes: &version, count: 1))
        var cs = UInt32(chunkSize)
        try handle.write(contentsOf: Data(bytes: &cs, count: 4))
        var tc = UInt32(totalChunks)
        try handle.write(contentsOf: Data(bytes: &tc, count: 4))
        var os = UInt64(fileSize)
        try handle.write(contentsOf: Data(bytes: &os, count: 8))
        try handle.write(contentsOf: baseNonceData)

        // Stream chunks: read → encrypt → write, one chunk at a time
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? sourceHandle.close() }

        for chunkIndex in 0..<totalChunks {
            let chunkData = sourceHandle.readData(ofLength: chunkSize)
            guard !chunkData.isEmpty else { break }

            let nonce = try xorNonce(baseNonceData, with: UInt64(chunkIndex))
            let gcmNonce = try AES.GCM.Nonce(data: nonce)
            let sealedBox = try AES.GCM.seal(chunkData, using: symmetricKey, nonce: gcmNonce)
            guard let combined = sealedBox.combined else {
                throw CryptoError.encryptionFailed
            }

            var encSize = UInt32(combined.count)
            try handle.write(contentsOf: Data(bytes: &encSize, count: 4))
            try handle.write(contentsOf: combined)
        }
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

    /// Decrypts a staged encrypted file directly to a temp URL without loading the entire
    /// encrypted file into memory. For streaming format (VCSE), reads and decrypts one chunk
    /// at a time (~256KB peak). For single-shot (≤1MB), loads into memory since it's small.
    static func decryptStagedFileToURL(from encryptedURL: URL, to outputURL: URL, with key: Data) throws {
        let handle = try FileHandle(forReadingFrom: encryptedURL)
        defer { try? handle.close() }

        // Read first 4 bytes to detect format
        let magic = handle.readData(ofLength: 4)
        guard magic.count == 4 else { throw CryptoError.invalidData }

        let magicValue = magic.withUnsafeBytes { $0.load(as: UInt32.self) }

        if magicValue == VaultCoreConstants.streamingMagic {
            // Streaming format — seek back and use FileHandle-based decryption
            handle.seek(toFileOffset: 0)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: encryptedURL.path)[.size] as? Int) ?? 0
            try decryptStreamingFromHandleToFile(
                handle: handle,
                contentLength: fileSize,
                with: key,
                outputURL: outputURL
            )
        } else {
            // Single-shot format — small file, safe to load into memory
            handle.seek(toFileOffset: 0)
            let encryptedData = try Data(contentsOf: encryptedURL)
            let decrypted = try decrypt(encryptedData, with: key)
            try decrypted.write(to: outputURL, options: [.atomic, .completeFileProtection])
        }
    }

    /// XORs a 12-byte nonce with a chunk index (big-endian, into the last 8 bytes).
    static func xorNonce(_ baseNonce: Data, with index: UInt64) throws -> Data {
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

    static func readExact(_ count: Int, from handle: FileHandle) throws -> Data {
        let data = handle.readData(ofLength: count)
        guard data.count == count else { throw CryptoError.invalidData }
        return data
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
