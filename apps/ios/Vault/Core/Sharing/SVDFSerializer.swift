import Foundation
import CryptoKit

/// SVDF v4 — Shared Vault Data Format.
///
/// Append-stable binary layout:
/// ```
/// [64-byte header]
/// [File entries, concatenated in insertion order]
/// [Encrypted file manifest — JSON array]
/// [Encrypted metadata — JSON object]
/// ```
///
/// Appending files only adds bytes at end + rewrites trailing manifest/metadata.
/// Existing file entry bytes never move. Deletions mark `deleted: true` in manifest.
enum SVDFSerializer {

    // MARK: - Constants

    static let magic: [UInt8] = [0x53, 0x56, 0x44, 0x34] // "SVD4"
    static let headerSize = 64
    static let currentVersion: UInt16 = 4

    /// Threshold for triggering a full rebuild: when deleted bytes exceed 30% of total.
    static let compactionThreshold: Double = 0.30

    // MARK: - Manifest Entry

    struct FileManifestEntry: Codable, Sendable {
        let id: String          // UUID string
        let offset: Int         // byte offset in SVDF data (after header)
        let size: Int           // byte size of entry block
        var deleted: Bool

        init(id: String, offset: Int, size: Int, deleted: Bool = false) {
            self.id = id
            self.offset = offset
            self.size = size
            self.deleted = deleted
        }
    }

    // MARK: - Header

    /// 64-byte fixed header.
    struct Header {
        var magic: (UInt8, UInt8, UInt8, UInt8) = (0x53, 0x56, 0x44, 0x34)
        var version: UInt16 = SVDFSerializer.currentVersion
        var fileCount: UInt32 = 0
        var manifestOffset: UInt64 = 0
        var manifestSize: UInt32 = 0
        var metadataOffset: UInt64 = 0
        var metadataSize: UInt32 = 0
        // 26 bytes of reserved padding to reach 64
    }

    // MARK: - Build Full

    /// Builds a complete SVDF blob from scratch.
    /// - Parameters:
    ///   - files: Files to include (already re-encrypted with shareKey).
    ///   - metadata: Metadata to encrypt and embed.
    ///   - shareKey: Encryption key for manifest and metadata.
    /// - Returns: The complete SVDF blob and file manifest.
    static func buildFull(
        files: [SharedVaultData.SharedFile],
        metadata: SharedVaultData.SharedVaultMetadata,
        shareKey: Data
    ) throws -> (data: Data, manifest: [FileManifestEntry]) {
        var output = Data()
        // Reserve space for header (will be written at the end)
        output.append(Data(count: headerSize))

        var manifest: [FileManifestEntry] = []

        for file in files {
            let entryStart = output.count
            let entry = encodeFileEntry(file)
            output.append(entry)
            manifest.append(FileManifestEntry(
                id: file.id.uuidString,
                offset: entryStart,
                size: entry.count
            ))
        }

        // Encrypt and append manifest
        let manifestJSON = try JSONEncoder().encode(manifest)
        let encryptedManifest = try CryptoEngine.encrypt(manifestJSON, with: shareKey)
        let manifestOffset = output.count
        output.append(encryptedManifest)

        // Encrypt and append metadata
        let metadataJSON = try JSONEncoder().encode(metadata)
        let encryptedMetadata = try CryptoEngine.encrypt(metadataJSON, with: shareKey)
        let metadataOffset = output.count
        output.append(encryptedMetadata)

        // Write header
        writeHeader(
            into: &output,
            fileCount: UInt32(files.count),
            manifestOffset: UInt64(manifestOffset),
            manifestSize: UInt32(encryptedManifest.count),
            metadataOffset: UInt64(metadataOffset),
            metadataSize: UInt32(encryptedMetadata.count)
        )

        return (output, manifest)
    }

    // MARK: - Build Incremental

    /// Appends new files and marks deletions on an existing SVDF blob.
    /// - Parameters:
    ///   - priorData: The existing SVDF blob.
    ///   - priorManifest: The existing file manifest (decrypted).
    ///   - newFiles: Files to append (already re-encrypted with shareKey).
    ///   - removedFileIds: UUIDs of files to mark as deleted.
    ///   - metadata: Updated metadata.
    ///   - shareKey: Encryption key for manifest and metadata.
    /// - Returns: The updated SVDF blob and new manifest.
    static func buildIncremental(
        priorData: Data,
        priorManifest: [FileManifestEntry],
        newFiles: [SharedVaultData.SharedFile],
        removedFileIds: Set<String>,
        metadata: SharedVaultData.SharedVaultMetadata,
        shareKey: Data
    ) throws -> (data: Data, manifest: [FileManifestEntry]) {
        // Start with all file entry bytes (everything before the old manifest)
        let header = try parseHeader(from: priorData)
        let fileEntriesEnd = Int(header.manifestOffset)
        var output = Data(priorData.prefix(fileEntriesEnd))

        // Update existing manifest: mark deletions
        var manifest = priorManifest
        for i in manifest.indices {
            if removedFileIds.contains(manifest[i].id) {
                manifest[i].deleted = true
            }
        }

        // Append new file entries
        for file in newFiles {
            let entryStart = output.count
            let entry = encodeFileEntry(file)
            output.append(entry)
            manifest.append(FileManifestEntry(
                id: file.id.uuidString,
                offset: entryStart,
                size: entry.count
            ))
        }

        let activeCount = manifest.filter { !$0.deleted }.count

        // Encrypt and append manifest
        let manifestJSON = try JSONEncoder().encode(manifest)
        let encryptedManifest = try CryptoEngine.encrypt(manifestJSON, with: shareKey)
        let manifestOffset = output.count
        output.append(encryptedManifest)

        // Encrypt and append metadata
        let metadataJSON = try JSONEncoder().encode(metadata)
        let encryptedMetadata = try CryptoEngine.encrypt(metadataJSON, with: shareKey)
        let metadataOffset = output.count
        output.append(encryptedMetadata)

        // Rewrite header
        writeHeader(
            into: &output,
            fileCount: UInt32(activeCount),
            manifestOffset: UInt64(manifestOffset),
            manifestSize: UInt32(encryptedManifest.count),
            metadataOffset: UInt64(metadataOffset),
            metadataSize: UInt32(encryptedMetadata.count)
        )

        return (output, manifest)
    }

    // MARK: - Parse

    /// Checks if data begins with SVDF v4 magic bytes.
    static func isSVDF(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == magic[0]
            && data[data.startIndex + 1] == magic[1]
            && data[data.startIndex + 2] == magic[2]
            && data[data.startIndex + 3] == magic[3]
    }

    /// Parses the 64-byte header from SVDF data.
    static func parseHeader(from data: Data) throws -> Header {
        guard data.count >= headerSize else {
            throw SVDFError.invalidHeader
        }
        guard isSVDF(data) else {
            throw SVDFError.invalidMagic
        }

        var header = Header()
        header.version = data.readUInt16(at: 4)
        header.fileCount = data.readUInt32(at: 6)
        header.manifestOffset = data.readUInt64(at: 10)
        header.manifestSize = data.readUInt32(at: 18)
        header.metadataOffset = data.readUInt64(at: 22)
        header.metadataSize = data.readUInt32(at: 30)
        return header
    }

    /// Decrypts and parses the file manifest from SVDF data.
    static func parseManifest(from data: Data, shareKey: Data) throws -> [FileManifestEntry] {
        let header = try parseHeader(from: data)
        let mStart = Int(header.manifestOffset)
        let mEnd = mStart + Int(header.manifestSize)
        guard mEnd <= data.count else { throw SVDFError.invalidManifest }

        let encryptedManifest = data[mStart..<mEnd]
        let manifestJSON = try CryptoEngine.decrypt(Data(encryptedManifest), with: shareKey)
        return try JSONDecoder().decode([FileManifestEntry].self, from: manifestJSON)
    }

    /// Extracts a single file entry from the SVDF blob at the given offset and size.
    static func extractFileEntry(from data: Data, at offset: Int, size: Int) throws -> SharedVaultData.SharedFile {
        let end = offset + size
        guard end <= data.count else { throw SVDFError.invalidEntry }
        let entryData = data[offset..<end]
        return try decodeFileEntry(Data(entryData))
    }

    /// Deserializes a complete SVDF blob into a SharedVaultData object.
    static func deserialize(from data: Data, shareKey: Data) throws -> SharedVaultData {
        let header = try parseHeader(from: data)
        let manifest = try parseManifest(from: data, shareKey: shareKey)

        var files: [SharedVaultData.SharedFile] = []
        for entry in manifest where !entry.deleted {
            let file = try extractFileEntry(from: data, at: entry.offset, size: entry.size)
            files.append(file)
        }

        // Decrypt metadata
        let metaStart = Int(header.metadataOffset)
        let metaEnd = metaStart + Int(header.metadataSize)
        guard metaEnd <= data.count else { throw SVDFError.invalidManifest }
        let encryptedMeta = data[metaStart..<metaEnd]
        let metaJSON = try CryptoEngine.decrypt(Data(encryptedMeta), with: shareKey)
        let metadata = try JSONDecoder().decode(SharedVaultData.SharedVaultMetadata.self, from: metaJSON)

        return SharedVaultData(
            files: files,
            metadata: metadata,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - File Entry Encoding

    /// Binary layout per file entry:
    /// ```
    /// entrySize(4) + fileId(16 bytes UUID) + filenameLen(2) + filename
    /// + mimeTypeLen(1) + mimeType + originalSize(4) + createdAt(8)
    /// + thumbSize(4) + thumbData + contentSize(4) + contentData
    /// ```
    private static func encodeFileEntry(_ file: SharedVaultData.SharedFile) -> Data {
        var entry = Data()

        // Placeholder for entrySize (will overwrite)
        let sizePos = entry.count
        entry.appendUInt32(0)

        // File ID (16 bytes)
        let uuidBytes = withUnsafeBytes(of: file.id.uuid) { Data($0) }
        entry.append(uuidBytes)

        // Filename
        let filenameData = Data(file.filename.utf8)
        entry.appendUInt16(UInt16(filenameData.count))
        entry.append(filenameData)

        // MIME type
        let mimeData = Data(file.mimeType.utf8)
        entry.append(UInt8(min(mimeData.count, 255)))
        entry.append(mimeData.prefix(255))

        // Original size
        entry.appendUInt32(UInt32(file.size))

        // Created at (Unix timestamp as Double)
        entry.appendFloat64(file.createdAt.timeIntervalSince1970)

        // Thumbnail
        let thumb = file.encryptedThumbnail ?? Data()
        entry.appendUInt32(UInt32(thumb.count))
        entry.append(thumb)

        // Content
        entry.appendUInt32(UInt32(file.encryptedContent.count))
        entry.append(file.encryptedContent)

        // Write total entry size
        let totalSize = UInt32(entry.count)
        entry.replaceSubrange(sizePos..<(sizePos + 4), with: totalSize.littleEndianBytes)

        return entry
    }

    private static func decodeFileEntry(_ data: Data) throws -> SharedVaultData.SharedFile {
        guard data.count >= 4 else { throw SVDFError.invalidEntry }
        var cursor = 0

        // Entry size (skip — we already have the slice)
        let entrySize = data.readUInt32(at: cursor); cursor += 4
        guard entrySize <= data.count else { throw SVDFError.invalidEntry }

        // File ID
        guard cursor + 16 <= data.count else { throw SVDFError.invalidEntry }
        let uuidBytes = data[cursor..<(cursor + 16)]
        let uuid = uuidBytes.withUnsafeBytes { buf -> UUID in
            var raw = uuid_t(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
            withUnsafeMutableBytes(of: &raw) { dest in
                dest.copyBytes(from: buf)
            }
            return UUID(uuid: raw)
        }
        cursor += 16

        // Filename
        guard cursor + 2 <= data.count else { throw SVDFError.invalidEntry }
        let filenameLen = Int(data.readUInt16(at: cursor)); cursor += 2
        guard cursor + filenameLen <= data.count else { throw SVDFError.invalidEntry }
        let filename = String(data: data[cursor..<(cursor + filenameLen)], encoding: .utf8) ?? ""
        cursor += filenameLen

        // MIME type
        guard cursor + 1 <= data.count else { throw SVDFError.invalidEntry }
        let mimeLen = Int(data[cursor]); cursor += 1
        guard cursor + mimeLen <= data.count else { throw SVDFError.invalidEntry }
        let mimeType = String(data: data[cursor..<(cursor + mimeLen)], encoding: .utf8) ?? ""
        cursor += mimeLen

        // Original size
        guard cursor + 4 <= data.count else { throw SVDFError.invalidEntry }
        let originalSize = Int(data.readUInt32(at: cursor)); cursor += 4

        // Created at
        guard cursor + 8 <= data.count else { throw SVDFError.invalidEntry }
        let timestamp = data.readFloat64(at: cursor); cursor += 8
        let createdAt = Date(timeIntervalSince1970: timestamp)

        // Thumbnail
        guard cursor + 4 <= data.count else { throw SVDFError.invalidEntry }
        let thumbSize = Int(data.readUInt32(at: cursor)); cursor += 4
        guard cursor + thumbSize <= data.count else { throw SVDFError.invalidEntry }
        let thumb: Data? = thumbSize > 0 ? Data(data[cursor..<(cursor + thumbSize)]) : nil
        cursor += thumbSize

        // Content
        guard cursor + 4 <= data.count else { throw SVDFError.invalidEntry }
        let contentSize = Int(data.readUInt32(at: cursor)); cursor += 4
        guard cursor + contentSize <= data.count else { throw SVDFError.invalidEntry }
        let content = Data(data[cursor..<(cursor + contentSize)])

        return SharedVaultData.SharedFile(
            id: uuid,
            filename: filename,
            mimeType: mimeType,
            size: originalSize,
            encryptedContent: content,
            createdAt: createdAt,
            encryptedThumbnail: thumb
        )
    }

    // MARK: - Header Writing

    private static func writeHeader(
        into data: inout Data,
        fileCount: UInt32,
        manifestOffset: UInt64,
        manifestSize: UInt32,
        metadataOffset: UInt64,
        metadataSize: UInt32
    ) {
        // Write at byte 0
        data.replaceSubrange(0..<4, with: magic)
        data.replaceSubrange(4..<6, with: currentVersion.littleEndianBytes)
        data.replaceSubrange(6..<10, with: fileCount.littleEndianBytes)
        data.replaceSubrange(10..<18, with: manifestOffset.littleEndianBytes)
        data.replaceSubrange(18..<22, with: manifestSize.littleEndianBytes)
        data.replaceSubrange(22..<30, with: metadataOffset.littleEndianBytes)
        data.replaceSubrange(30..<34, with: metadataSize.littleEndianBytes)
        // Bytes 34-63 reserved (zeroed from initial Data(count:))
    }

    // MARK: - Errors

    enum SVDFError: Error, LocalizedError {
        case invalidHeader
        case invalidMagic
        case invalidManifest
        case invalidEntry

        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "Invalid SVDF header"
            case .invalidMagic: return "Not an SVDF v4 file"
            case .invalidManifest: return "Could not read SVDF manifest"
            case .invalidEntry: return "Corrupted file entry in SVDF"
            }
        }
    }
}

// MARK: - Data Encoding Helpers

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            self[offset..<(offset + 2)].copyBytes(to: dest)
        }
        return UInt16(littleEndian: value)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            self[offset..<(offset + 4)].copyBytes(to: dest)
        }
        return UInt32(littleEndian: value)
    }

    func readUInt64(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            self[offset..<(offset + 8)].copyBytes(to: dest)
        }
        return UInt64(littleEndian: value)
    }

    func readFloat64(at offset: Int) -> Double {
        let bits = readUInt64(at: offset)
        return Double(bitPattern: bits)
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: value.littleEndianBytes)
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: value.littleEndianBytes)
    }

    mutating func appendFloat64(_ value: Double) {
        let bits = value.bitPattern
        append(contentsOf: bits.littleEndianBytes)
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        let le = self.littleEndian
        return withUnsafeBytes(of: le) { Array($0) }
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        let le = self.littleEndian
        return withUnsafeBytes(of: le) { Array($0) }
    }
}

private extension UInt64 {
    var littleEndianBytes: [UInt8] {
        let le = self.littleEndian
        return withUnsafeBytes(of: le) { Array($0) }
    }
}
