import Foundation
import CryptoKit
import os

enum VaultStorageError: Error, LocalizedError {
    case blobNotInitialized
    case writeError
    case readError
    case insufficientSpace
    case fileNotFound
    case corruptedData
    case vaultAlreadyExists
    case expansionNotAllowed
    case secureOverwriteFailed
    case indexDecryptionFailed

    var errorDescription: String? {
        switch self {
        case .blobNotInitialized: return "Vault storage is not initialized"
        case .writeError: return "Failed to write to vault storage"
        case .readError: return "Failed to read from vault storage"
        case .insufficientSpace: return "Not enough space in vault"
        case .fileNotFound: return "File not found in vault"
        case .corruptedData: return "Vault data is corrupted"
        case .vaultAlreadyExists: return "A vault with this pattern already exists"
        case .expansionNotAllowed: return "Unable to expand storage"
        case .secureOverwriteFailed: return "Failed to generate random data for secure overwrite"
        case .indexDecryptionFailed: return "Vault index is corrupted and could not be decrypted"
        }
    }
}

/// CONCURRENCY: Not an actor because blocking file I/O would starve the cooperative
/// thread pool. `blobReady` race is benign: `ensureBlobReady()` uses `initQueue.sync`
/// as a barrier. Callers serialize at a higher level (`@MainActor` views, single
/// `Task.detached`). Full actor refactor deferred to future work.
final class VaultStorage {
    private static let logger = Logger(subsystem: "com.vaultaire.vault", category: "storage")
    static let shared = VaultStorage()

    private let fileManager = FileManager.default
    private let blobFileName = "vault_data.bin"

    // Note: We don't use a single index file anymore - each vault gets its own
    // based on a hash of the vault key

    // Pre-allocated blob size (50 MB)
    private let defaultBlobSize: Int = 50 * 1024 * 1024

    // Global cursor block lives in the last 16 bytes of the blob
    private var cursorBlockOffset: Int { defaultBlobSize - 16 }
    private let cursorMagic: UInt64 = 0x5641553100000000

    /// Derives the cursor footer offset from the actual file size on disk.
    /// Handles legacy 500MB blobs where the footer is at 500MB-16, not 50MB-16.
    private func cursorFooterOffset() -> Int {
        if let attrs = try? fileManager.attributesOfItem(atPath: blobURL.path),
           let size = attrs[.size] as? Int, size > 16 {
            return size - 16
        }
        return cursorBlockOffset
    }

    private let initQueue = DispatchQueue(label: "vault.blob.init")
    private var blobReady = false

    /// Index manager handles all index CRUD, caching, locking, and migration.
    let indexManager: VaultIndexManager

    private var blobURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(blobFileName)
    }

    /// Expose blob URL for secure overwrites during pattern changes
    func getBlobURL() -> URL {
        return blobURL
    }

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let blobSize = 50 * 1024 * 1024
        indexManager = VaultIndexManager(
            documentsURL: documents,
            blobFileName: "vault_data.bin",
            defaultBlobSize: blobSize,
            cursorBlockOffset: blobSize - 16
        )
        // Wire up closures that depend on VaultStorage's blob state
        indexManager.readGlobalCursor = { [weak self] in
            self?.readGlobalCursor() ?? 0
        }
        indexManager.cursorFooterOffset = { [weak self] in
            self?.cursorFooterOffset() ?? (blobSize - 16)
        }

        initializeBlobIfNeeded()
        cleanupStaleTempFiles()
    }

    /// Remove any .tmp index files left behind by interrupted changeVaultKey operations
    private func cleanupStaleTempFiles() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("vault_index_") && file.pathExtension == "tmp" {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Index Delegation

    func loadIndex(with key: VaultKey) throws -> VaultIndex {
        return try indexManager.loadIndex(with: key)
    }

    func saveIndex(_ index: VaultIndex, with key: VaultKey) throws {
        try indexManager.saveIndex(index, with: key)
    }

    private func getMasterKey(from index: VaultIndex, vaultKey: VaultKey) throws -> Data {
        return try indexManager.getMasterKey(from: index, vaultKey: vaultKey)
    }

    // MARK: - Blob Initialization

    private func initializeBlobIfNeeded() {
        if fileManager.fileExists(atPath: blobURL.path) {
            blobReady = true
            return
        }

        // Dispatch blob creation to background queue so init() doesn't block
        initQueue.async { [self] in
            createRandomBlob()
            blobReady = true
            Self.logger.info("Background blob creation complete")
        }
    }

    /// Blocks until the blob file is ready. Call before any blob read/write operation.
    private func ensureBlobReady() {
        guard !blobReady else { return }
        initQueue.sync {
            // By the time we acquire the lock, blob creation has finished
        }
    }

    private func createRandomBlob() {
        // Create file with random data
        fileManager.createFile(atPath: blobURL.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.complete
        ])

        guard let handle = try? FileHandle(forWritingTo: blobURL) else { return }

        // Write random data in chunks
        let chunkSize = 1024 * 1024 // 1 MB chunks
        let totalChunks = defaultBlobSize / chunkSize

        for _ in 0..<totalChunks {
            if let randomData = CryptoEngine.generateRandomBytes(count: chunkSize) {
                handle.write(randomData)
            }
        }

        try? handle.close()

        // Initialize the global cursor to 0
        writeGlobalCursor(0)
    }

    // MARK: - Global Blob Cursor

    /// Reads the global write cursor from the last 16 bytes of the blob.
    /// Returns 0 if the cursor is uninitialized (magic validation fails).
    private func readGlobalCursor() -> Int {
        guard let handle = try? FileHandle(forReadingFrom: blobURL) else { return 0 }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(cursorFooterOffset()))
            guard let block = try handle.read(upToCount: 16), block.count == 16 else { return 0 }

            let xorKey = SecureEnclaveManager.shared.getBlobCursorXORKey()

            // XOR the block with the key
            var decoded = Data(count: 16)
            for i in 0..<16 {
                decoded[i] = block[i] ^ xorKey[i]
            }

            // Extract offset (first 8 bytes) and magic (last 8 bytes)
            let storedOffset = decoded.withUnsafeBytes { ptr -> UInt64 in
                ptr.load(fromByteOffset: 0, as: UInt64.self)
            }
            let storedMagic = decoded.withUnsafeBytes { ptr -> UInt64 in
                ptr.load(fromByteOffset: 8, as: UInt64.self)
            }

            guard storedMagic == cursorMagic else {
                Self.logger.warning("Global cursor magic mismatch — treating as uninitialized")
                return 0
            }

            Self.logger.debug("readGlobalCursor: \(storedOffset, privacy: .public)")
            return Int(storedOffset)
        } catch {
            return 0
        }
    }

    /// Writes the global write cursor to the last 16 bytes of the blob.
    private func writeGlobalCursor(_ offset: Int) {
        guard let handle = try? FileHandle(forWritingTo: blobURL) else { return }
        defer { try? handle.close() }

        let xorKey = SecureEnclaveManager.shared.getBlobCursorXORKey()

        // Build plaintext: [offset (8 bytes)][magic (8 bytes)]
        var plain = Data(count: 16)
        plain.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt64(offset), toByteOffset: 0, as: UInt64.self)
            ptr.storeBytes(of: cursorMagic, toByteOffset: 8, as: UInt64.self)
        }

        // XOR with key
        var encoded = Data(count: 16)
        for i in 0..<16 {
            encoded[i] = plain[i] ^ xorKey[i]
        }

        do {
            try handle.seek(toOffset: UInt64(cursorFooterOffset()))
            handle.write(encoded)
            Self.logger.debug("writeGlobalCursor: \(offset, privacy: .public)")
        } catch {
            Self.logger.error("Failed to write global cursor: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Multi-Blob Management

    /// Documents directory for all blob files
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Resolve a blobId to its file URL. nil or "primary" -> primary blob.
    private func blobURL(for blobId: String?) -> URL {
        guard let blobId = blobId, blobId != "primary" else {
            return blobURL
        }
        // Expansion blobs are stored by their fileName in the blobs array,
        // but we can also look up by blobId directly using the naming convention.
        return documentsDirectory.appendingPathComponent("vd_\(blobId).bin")
    }

    /// Resolve a blobId using the index's blob descriptors for the correct fileName.
    private func blobURL(for blobId: String?, in index: VaultIndex) -> URL {
        guard let blobId = blobId, blobId != "primary" else {
            return blobURL
        }
        if let descriptor = index.blobs?.first(where: { $0.blobId == blobId }) {
            return documentsDirectory.appendingPathComponent(descriptor.fileName)
        }
        // Fallback to naming convention
        return documentsDirectory.appendingPathComponent("vd_\(blobId).bin")
    }

    /// Create a new expansion blob filled with random data.
    /// Returns a BlobDescriptor for the new blob.
    private func createExpansionBlob() -> BlobDescriptor? {
        let hexId = (0..<16).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
        let fileName = "vd_\(hexId).bin"
        let url = documentsDirectory.appendingPathComponent(fileName)

        fileManager.createFile(atPath: url.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.complete
        ])

        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }

        let chunkSize = 1024 * 1024
        let totalChunks = defaultBlobSize / chunkSize

        for _ in 0..<totalChunks {
            if let randomData = CryptoEngine.generateRandomBytes(count: chunkSize) {
                handle.write(randomData)
            }
        }

        try? handle.close()

        Self.logger.debug("Created expansion blob: \(fileName, privacy: .public)")

        return BlobDescriptor(
            blobId: hexId,
            fileName: fileName,
            capacity: defaultBlobSize, // Full capacity — no footer reservation
            cursor: 0
        )
    }

    /// Enumerate all blob files on disk (primary + expansion).
    func allBlobURLs() -> [URL] {
        var urls = [blobURL]
        if let files = try? fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("vd_") && file.pathExtension == "bin" {
                urls.append(file)
            }
        }
        return urls
    }

    // MARK: - Blob Pool Write Helper

    struct BlobWriteResult {
        let writeOffset: Int
        let blobId: String
        let blobIdx: Int
        let handle: FileHandle
    }

    /// Finds a blob with enough space (or creates one), opens a FileHandle at the write offset.
    /// Caller is responsible for closing the handle and calling `finalizeBlobWrite` after writing.
    private func allocateBlobSpace(size: Int, index: inout VaultIndex) throws -> BlobWriteResult {
        var targetBlobIndex: Int? = nil
        if let blobs = index.blobs {
            for (i, blob) in blobs.enumerated() {
                if blob.cursor + size <= blob.capacity {
                    targetBlobIndex = i
                    break
                }
            }
        }

        if targetBlobIndex == nil {
            guard let newBlob = createExpansionBlob() else {
                throw VaultStorageError.writeError
            }
            if index.blobs == nil { index.blobs = [] }
            index.blobs!.append(newBlob)
            targetBlobIndex = index.blobs!.count - 1
        }

        guard let blobIdx = targetBlobIndex, let blobs = index.blobs else {
            throw VaultStorageError.writeError
        }
        let writeOffset = blobs[blobIdx].cursor
        let targetBlobId = blobs[blobIdx].blobId
        let targetURL = blobURL(for: targetBlobId, in: index)

        guard let handle = try? FileHandle(forWritingTo: targetURL) else {
            throw VaultStorageError.writeError
        }

        try handle.seek(toOffset: UInt64(writeOffset))

        return BlobWriteResult(
            writeOffset: writeOffset,
            blobId: targetBlobId,
            blobIdx: blobIdx,
            handle: handle
        )
    }

    /// Variant of allocateBlobSpace that reuses cached FileHandles for the same blob.
    private func allocateBlobSpace(size: Int, index: inout VaultIndex, handleCache: inout [String: FileHandle]) throws -> BlobWriteResult {
        var targetBlobIndex: Int? = nil
        if let blobs = index.blobs {
            for (i, blob) in blobs.enumerated() {
                if blob.cursor + size <= blob.capacity {
                    targetBlobIndex = i
                    break
                }
            }
        }

        if targetBlobIndex == nil {
            guard let newBlob = createExpansionBlob() else {
                throw VaultStorageError.writeError
            }
            if index.blobs == nil { index.blobs = [] }
            index.blobs!.append(newBlob)
            targetBlobIndex = index.blobs!.count - 1
        }

        guard let blobIdx = targetBlobIndex, let blobs = index.blobs else {
            throw VaultStorageError.writeError
        }
        let writeOffset = blobs[blobIdx].cursor
        let targetBlobId = blobs[blobIdx].blobId

        let handle: FileHandle
        if let cached = handleCache[targetBlobId] {
            handle = cached
        } else {
            let targetURL = blobURL(for: targetBlobId, in: index)
            guard let newHandle = try? FileHandle(forWritingTo: targetURL) else {
                throw VaultStorageError.writeError
            }
            handleCache[targetBlobId] = newHandle
            handle = newHandle
        }

        try handle.seek(toOffset: UInt64(writeOffset))

        return BlobWriteResult(
            writeOffset: writeOffset,
            blobId: targetBlobId,
            blobIdx: blobIdx,
            handle: handle
        )
    }

    /// Updates blob cursor and global cursor after writing data to the blob.
    private func finalizeBlobWrite(size: Int, result: BlobWriteResult, index: inout VaultIndex) {
        let newCursor = result.writeOffset + size
        index.blobs![result.blobIdx].cursor = newCursor

        if result.blobId == "primary" {
            writeGlobalCursor(newCursor)
            index.nextOffset = newCursor
        }
    }

    // MARK: - File Operations

    func storeFile(data: Data, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data? = nil, duration: TimeInterval? = nil, fileId: UUID? = nil) throws -> UUID {
        let span = EmbraceManager.shared.startTransaction(name: "storage.store_file", operation: "storage.store_file")
        span.setTag(value: "\(data.count / 1024)", key: "fileSizeKB")
        span.setTag(value: mimeType, key: "mimeType")

        ensureBlobReady()
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }
        Self.logger.debug("storeFile called")
        Self.logger.debug("filename: \(filename, privacy: .public), size: \(data.count, privacy: .public) bytes")
        Self.logger.debug("mimeType: \(mimeType, privacy: .public)")
        Self.logger.debug("key hash: \(key.rawBytes.hashValue, privacy: .private)")
        Self.logger.debug("thumbnail provided: \(thumbnailData != nil, privacy: .public)")
        if let providedId = fileId {
            Self.logger.debug("Using provided fileId: \(providedId.uuidString, privacy: .public)")
        }

        var index = try loadIndex(with: key)

        Self.logger.debug("Current index loaded. Files: \(index.files.count, privacy: .public), nextOffset: \(index.nextOffset, privacy: .public)")

        // Get the master key for encrypting file data
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        // Encrypt the file with MASTER KEY (not vault key)
        let encryptedFile = try CryptoEngine.encryptFile(
            data: data,
            filename: filename,
            mimeType: mimeType,
            with: masterKey,  // <- Use master key here
            fileId: fileId   // <- Preserve original file ID if provided
        )

        let fileData = encryptedFile.encryptedContent
        let fileSize = fileData.count

        let blobWrite = try allocateBlobSpace(size: fileSize, index: &index)
        defer { try? blobWrite.handle.close() }

        blobWrite.handle.write(fileData)

        // Encrypt thumbnail with MASTER KEY if provided
        var encryptedThumbnail: Data? = nil
        if let thumbnail = thumbnailData {
            encryptedThumbnail = try? CryptoEngine.encrypt(thumbnail, with: masterKey)
        }

        finalizeBlobWrite(size: fileSize, result: blobWrite, index: &index)

        let entry = VaultIndex.VaultFileEntry(
            fileId: encryptedFile.header.fileId,
            offset: blobWrite.writeOffset,
            size: fileSize,
            encryptedHeaderPreview: fileData.prefix(64),
            isDeleted: false,
            thumbnailData: encryptedThumbnail,
            mimeType: mimeType,
            filename: filename,
            blobId: blobWrite.blobId == "primary" ? nil : blobWrite.blobId,
            createdAt: Date(),
            duration: duration
        )
        index.files.append(entry)

        try saveIndex(index, with: key)
        span.finish(status: .ok)
        return encryptedFile.header.fileId
    }

    /// Store multiple files in a single index load/save cycle.
    /// Calls `onProgress` after each file is written (on the calling thread).
    struct FileToStore {
        let data: Data
        let filename: String
        let mimeType: String
        let thumbnailData: Data?
    }

    func storeFiles(_ files: [FileToStore], with key: VaultKey, onProgress: ((Int) -> Void)? = nil) throws -> [UUID] {
        ensureBlobReady()
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }

        var index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)
        var storedIds: [UUID] = []
        var handleCache: [String: FileHandle] = [:]
        defer { handleCache.values.forEach { try? $0.close() } }

        for (i, file) in files.enumerated() {
            let encryptedFile = try CryptoEngine.encryptFile(
                data: file.data, filename: file.filename, mimeType: file.mimeType, with: masterKey
            )
            let fileData = encryptedFile.encryptedContent
            let fileSize = fileData.count

            let blobWrite = try allocateBlobSpace(size: fileSize, index: &index, handleCache: &handleCache)

            blobWrite.handle.write(fileData)

            var encryptedThumbnail: Data? = nil
            if let thumbnail = file.thumbnailData {
                encryptedThumbnail = try? CryptoEngine.encrypt(thumbnail, with: masterKey)
            }

            finalizeBlobWrite(size: fileSize, result: blobWrite, index: &index)

            let entry = VaultIndex.VaultFileEntry(
                fileId: encryptedFile.header.fileId,
                offset: blobWrite.writeOffset,
                size: fileSize,
                encryptedHeaderPreview: fileData.prefix(64),
                isDeleted: false,
                thumbnailData: encryptedThumbnail,
                mimeType: file.mimeType,
                filename: file.filename,
                blobId: blobWrite.blobId == "primary" ? nil : blobWrite.blobId,
                createdAt: Date()
            )
            index.files.append(entry)
            storedIds.append(encryptedFile.header.fileId)

            onProgress?(i + 1)
        }

        // Save index once for all files
        try saveIndex(index, with: key)

        Self.logger.info("Batch stored \(storedIds.count, privacy: .public) files")

        return storedIds
    }

    /// Store a file from a URL without loading the entire raw content into memory.
    /// Uses streaming encryption for large files (VCSE for files > 1MB).
    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: VaultKey, thumbnailData: Data? = nil, duration: TimeInterval? = nil, fileId: UUID? = nil, originalDate: Date? = nil) throws -> UUID {
        ensureBlobReady()
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }

        var index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        // Build header (small — stays in memory)
        let actualFileId = fileId ?? UUID()
        let originalFileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        let header = CryptoEngine.EncryptedFileHeader(
            fileId: actualFileId,
            originalFilename: filename,
            mimeType: mimeType,
            originalSize: UInt64(originalFileSize),
            createdAt: Date()
        )
        let encryptedHeader = try CryptoEngine.encrypt(header.serialize(), with: masterKey)

        // Calculate total size WITHOUT loading the file into memory
        let encContentSize = CryptoEngine.encryptedContentSize(forFileOfSize: originalFileSize)
        let totalSize = 4 + encryptedHeader.count + encContentSize

        let blobWrite = try allocateBlobSpace(size: totalSize, index: &index)
        defer { try? blobWrite.handle.close() }

        // Write header to blob
        var headerSize = UInt32(encryptedHeader.count)
        let headerSizeData = Data(bytes: &headerSize, count: 4)
        blobWrite.handle.write(headerSizeData)
        blobWrite.handle.write(encryptedHeader)

        // Stream-encrypt content directly to blob — peak memory: ~256KB
        try CryptoEngine.encryptFileStreamingToHandle(from: fileURL, to: blobWrite.handle, with: masterKey)

        // Build header preview for index (first 64 bytes of on-disk format)
        var headerPreview = Data()
        headerPreview.append(headerSizeData)
        headerPreview.append(encryptedHeader.prefix(60))

        var encryptedThumbnail: Data? = nil
        if let thumbnail = thumbnailData {
            encryptedThumbnail = try? CryptoEngine.encrypt(thumbnail, with: masterKey)
        }

        finalizeBlobWrite(size: totalSize, result: blobWrite, index: &index)

        let entry = VaultIndex.VaultFileEntry(
            fileId: actualFileId,
            offset: blobWrite.writeOffset,
            size: totalSize,
            encryptedHeaderPreview: headerPreview,
            isDeleted: false,
            thumbnailData: encryptedThumbnail,
            mimeType: mimeType,
            filename: filename,
            blobId: blobWrite.blobId == "primary" ? nil : blobWrite.blobId,
            createdAt: Date(),
            duration: duration,
            originalDate: originalDate
        )
        index.files.append(entry)

        try saveIndex(index, with: key)
        return actualFileId
    }

    func retrieveFile(id: UUID, with key: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        let span = EmbraceManager.shared.startTransaction(name: "storage.retrieve_file", operation: "storage.retrieve_file")
        ensureBlobReady()
        let index = try loadIndex(with: key)

        // Get the master key for decrypting file data
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        guard let entry = index.files.first(where: { $0.fileId == id && !$0.isDeleted }) else {
            throw VaultStorageError.fileNotFound
        }
        let result = try retrieveFileContent(entry: entry, index: index, masterKey: masterKey)
        span.setTag(value: "\(result.header.originalSize / 1024)", key: "fileSizeKB")
        span.finish(status: .ok)
        return result
    }

    /// Retrieves file content using a pre-loaded index and master key, avoiding redundant index/key derivation.
    func retrieveFileContent(
        entry: VaultIndex.VaultFileEntry,
        index: VaultIndex,
        masterKey: Data
    ) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        ensureBlobReady()

        let targetURL = blobURL(for: entry.blobId, in: index)

        guard let handle = try? FileHandle(forReadingFrom: targetURL) else {
            throw VaultStorageError.readError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(entry.offset))
        guard let encryptedData = try handle.read(upToCount: entry.size) else {
            throw VaultStorageError.readError
        }

        return try CryptoEngine.decryptFile(data: encryptedData, with: masterKey)
    }

    /// Retrieves and decrypts a file directly to a temp URL, minimizing peak memory.
    /// For VCSE-encrypted content, stream-decrypts in 256KB chunks (~512KB peak).
    func retrieveFileToTempURL(id: UUID, with key: VaultKey) throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL) {
        ensureBlobReady()
        let index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        guard let entry = index.files.first(where: { $0.fileId == id && !$0.isDeleted }) else {
            throw VaultStorageError.fileNotFound
        }

        let targetURL = blobURL(for: entry.blobId, in: index)

        guard let handle = try? FileHandle(forReadingFrom: targetURL) else {
            throw VaultStorageError.readError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(entry.offset))
        guard let headerSizeData = try handle.read(upToCount: 4), headerSizeData.count == 4 else {
            throw VaultStorageError.readError
        }
        let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt32.self) }
        let encryptedHeaderSize = Int(headerSize)
        guard encryptedHeaderSize > 0 else {
            throw VaultStorageError.corruptedData
        }
        guard let encryptedHeader = try handle.read(upToCount: encryptedHeaderSize),
              encryptedHeader.count == encryptedHeaderSize else {
            throw VaultStorageError.readError
        }
        let decryptedHeaderData = try CryptoEngine.decrypt(encryptedHeader, with: masterKey)
        let header = try CryptoEngine.EncryptedFileHeader.deserialize(from: decryptedHeaderData)

        let encryptedContentSize = entry.size - 4 - encryptedHeaderSize
        guard encryptedContentSize > 0 else {
            throw VaultStorageError.corruptedData
        }
        let contentOffset = UInt64(entry.offset + 4 + encryptedHeaderSize)
        try handle.seek(toOffset: contentOffset)
        let magicProbe = handle.readData(ofLength: 4)
        guard magicProbe.count == 4 else { throw VaultStorageError.readError }
        try handle.seek(toOffset: contentOffset)

        let ext = (entry.filename as NSString?)?.pathExtension ?? "mp4"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        let magic = magicProbe.withUnsafeBytes { $0.load(as: UInt32.self) }
        if magic == VaultCoreConstants.streamingMagic {
            try CryptoEngine.decryptStreamingFromHandleToFile(
                handle: handle,
                contentLength: encryptedContentSize,
                with: masterKey,
                outputURL: tempURL
            )
        } else {
            guard let encryptedContent = try handle.read(upToCount: encryptedContentSize),
                  encryptedContent.count == encryptedContentSize else {
                throw VaultStorageError.readError
            }
            let decrypted = try CryptoEngine.decrypt(encryptedContent, with: masterKey)
            try decrypted.write(to: tempURL, options: [.atomic, .completeFileProtection])
        }

        return (header, tempURL)
    }

    func deleteFile(id: UUID, with key: VaultKey) throws {
        ensureBlobReady()
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }
        var index = try loadIndex(with: key)

        guard let entryIndex = index.files.firstIndex(where: { $0.fileId == id && !$0.isDeleted }) else {
            throw VaultStorageError.fileNotFound
        }

        let entry = index.files[entryIndex]

        // Securely overwrite the file data with random bytes in the correct blob
        let targetURL = blobURL(for: entry.blobId, in: index)
        guard let handle = try? FileHandle(forWritingTo: targetURL) else {
            throw VaultStorageError.writeError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(entry.offset))
        guard let randomData = CryptoEngine.generateRandomBytes(count: entry.size) else {
            throw VaultStorageError.secureOverwriteFailed
        }
        handle.write(randomData)

        // Mark as deleted in index
        index.files[entryIndex] = VaultIndex.VaultFileEntry(
            fileId: entry.fileId,
            offset: entry.offset,
            size: entry.size,
            encryptedHeaderPreview: entry.encryptedHeaderPreview,
            isDeleted: true,
            thumbnailData: entry.thumbnailData,
            mimeType: entry.mimeType,
            filename: entry.filename,
            blobId: entry.blobId,
            createdAt: entry.createdAt,
            duration: entry.duration,
            originalDate: entry.originalDate
        )

        try saveIndex(index, with: key)
    }

    /// Delete multiple files in a single index load/save cycle.
    /// Calls `onProgress` after each file is securely overwritten (on the calling thread).
    func deleteFiles(ids: Set<UUID>, with key: VaultKey, onProgress: ((Int) -> Void)? = nil) throws {
        ensureBlobReady()
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }
        var index = try loadIndex(with: key)

        // Group entries by blob to reuse file handles (nil blobId = "primary")
        var entriesByBlob: [String: [(arrayIndex: Int, entry: VaultIndex.VaultFileEntry)]] = [:]
        for (arrayIndex, entry) in index.files.enumerated() {
            guard ids.contains(entry.fileId), !entry.isDeleted else { continue }
            let effectiveBlobId = entry.blobId ?? "primary"
            entriesByBlob[effectiveBlobId, default: []].append((arrayIndex, entry))
        }

        var deletedCount = 0

        for (blobId, entries) in entriesByBlob {
            let targetURL = blobURL(for: blobId, in: index)
            guard let handle = try? FileHandle(forWritingTo: targetURL) else { continue }
            defer { try? handle.close() }

            for (arrayIndex, entry) in entries {
                // Securely overwrite file data with random bytes
                try handle.seek(toOffset: UInt64(entry.offset))
                guard let randomData = CryptoEngine.generateRandomBytes(count: entry.size) else {
                    throw VaultStorageError.secureOverwriteFailed
                }
                handle.write(randomData)

                // Mark as deleted in index
                index.files[arrayIndex] = VaultIndex.VaultFileEntry(
                    fileId: entry.fileId,
                    offset: entry.offset,
                    size: entry.size,
                    encryptedHeaderPreview: entry.encryptedHeaderPreview,
                    isDeleted: true,
                    thumbnailData: entry.thumbnailData,
                    mimeType: entry.mimeType,
                    filename: entry.filename,
                    blobId: entry.blobId,
                    createdAt: entry.createdAt,
                    duration: entry.duration,
                    originalDate: entry.originalDate
                )

                deletedCount += 1
                onProgress?(deletedCount)
            }
        }

        // Save index once for all deletions
        try saveIndex(index, with: key)
    }

    func listFiles(with key: VaultKey) throws -> [VaultFileEntry] {
        let span = EmbraceManager.shared.startTransaction(name: "storage.list_files", operation: "storage.list_files")
        defer { span.finish(status: .ok) }
        let index = try loadIndex(with: key)

        // Get the master key for decrypting thumbnails
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        return index.files.filter { !$0.isDeleted }.map { entry in
            // Decrypt thumbnail with MASTER KEY if available
            var decryptedThumbnail: Data? = nil
            if let encryptedThumb = entry.thumbnailData {
                decryptedThumbnail = try? CryptoEngine.decrypt(encryptedThumb, with: masterKey)
            }

            return VaultFileEntry(
                fileId: entry.fileId,
                size: entry.size,
                thumbnailData: decryptedThumbnail,
                mimeType: entry.mimeType,
                filename: entry.filename
            )
        }
    }

    struct VaultFileEntry: Sendable {
        let fileId: UUID
        let size: Int
        let thumbnailData: Data?
        let mimeType: String?
        let filename: String?
    }

    /// Lightweight file entry that keeps thumbnail data encrypted (no decryption at listing time).
    struct LightweightFileEntry: Sendable {
        let fileId: UUID
        let size: Int
        let encryptedThumbnail: Data?
        let mimeType: String?
        let filename: String?
        let createdAt: Date?
        let duration: TimeInterval?
        let originalDate: Date?
    }

    /// Returns the master key and file entries without decrypting thumbnails.
    /// Use this for lazy thumbnail loading — thumbnails are decrypted on-demand per cell.
    func listFilesLightweight(with key: VaultKey) throws -> (masterKey: Data, files: [LightweightFileEntry]) {
        let span = EmbraceManager.shared.startTransaction(name: "storage.list_files_lightweight", operation: "storage.list_files_lightweight")
        defer { span.finish(status: .ok) }

        let index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        let entries = index.files.filter { !$0.isDeleted }.map { entry in
            LightweightFileEntry(
                fileId: entry.fileId,
                size: entry.size,
                encryptedThumbnail: entry.thumbnailData,
                mimeType: entry.mimeType,
                filename: entry.filename,
                createdAt: entry.createdAt,
                duration: entry.duration,
                originalDate: entry.originalDate
            )
        }

        return (masterKey, entries)
    }

    // MARK: - Pattern/Key Management

    /// Count the number of existing vault index files on disk
    func existingVaultCount() -> Int {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let contents = (try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix("vault_index_") && $0.pathExtension == "bin" }.count
    }

    /// Check if a vault already exists for the given key
    func vaultExists(for key: VaultKey) -> Bool {
        let url = indexManager.indexURL(for: key)
        let exists = fileManager.fileExists(atPath: url.path)

        Self.logger.debug("Checking if vault exists for key hash \(key.rawBytes.hashValue, privacy: .private): \(exists, privacy: .public)")

        return exists
    }

    /// Returns true only when a vault index exists AND contains at least one non-deleted file.
    /// Use this for collision checks where overwriting an empty vault is acceptable.
    func vaultHasFiles(for key: VaultKey) -> Bool {
        guard vaultExists(for: key) else { return false }
        guard let index = try? loadIndex(with: key) else { return false }
        return index.files.contains(where: { !$0.isDeleted })
    }

    /// Change the vault key (pattern) without re-encrypting files
    /// This is extremely fast because we only re-encrypt the master key, not the file data
    func changeVaultKey(from oldKey: VaultKey, to newKey: VaultKey) throws {
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }
        Self.logger.debug("Changing vault key (pattern change)")
        Self.logger.debug("Old key hash: \(oldKey.rawBytes.hashValue, privacy: .private)")
        Self.logger.debug("New key hash: \(newKey.rawBytes.hashValue, privacy: .private)")

        // Check if new key would overwrite an existing vault with actual files
        if vaultHasFiles(for: newKey) {
            Self.logger.error("Cannot change to this pattern - vault with files already exists!")
            throw VaultStorageError.vaultAlreadyExists
        }
        // Clean up empty vault index at target key if it exists
        if vaultExists(for: newKey) {
            try? deleteVaultIndex(for: newKey)
        }

        // 1. Load index with old key
        let index = try loadIndex(with: oldKey)

        Self.logger.debug("Index loaded with old key. Files: \(index.files.count, privacy: .public)")

        // 2. Decrypt master key with old vault key
        let masterKey = try getMasterKey(from: index, vaultKey: oldKey)

        Self.logger.debug("Master key decrypted with old vault key")

        // 3. Re-encrypt master key with NEW vault key
        let newEncryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: newKey.rawBytes)

        Self.logger.debug("Master key re-encrypted with new vault key")

        // 4. Copy index and replace only the master key (future-proof — new fields are preserved)
        var newIndex = index
        newIndex.encryptedMasterKey = newEncryptedMasterKey

        // 5. Write-ahead: save new index to temp file, verify, then move into place
        let newIndexURL = indexManager.indexURL(for: newKey)
        let tempURL = newIndexURL.appendingPathExtension("tmp")

        // Encode and encrypt
        let encoded = try JSONEncoder().encode(newIndex)
        let encrypted = try CryptoEngine.encrypt(encoded, with: newKey.rawBytes)
        try encrypted.write(to: tempURL, options: [.atomic, .completeFileProtection])

        // Verify: read back and decrypt to confirm integrity
        let readBack = try Data(contentsOf: tempURL)
        let decrypted = try CryptoEngine.decrypt(readBack, with: newKey.rawBytes)
        let verified = try JSONDecoder().decode(VaultIndex.self, from: decrypted)
        guard verified.files.count == newIndex.files.count,
              verified.encryptedMasterKey == newEncryptedMasterKey else {
            try? fileManager.removeItem(at: tempURL)
            throw VaultStorageError.corruptedData
        }

        // Atomic move temp -> final (replaces if exists)
        if fileManager.fileExists(atPath: newIndexURL.path) {
            try fileManager.removeItem(at: newIndexURL)
        }
        try fileManager.moveItem(at: tempURL, to: newIndexURL)

        Self.logger.debug("New index verified and moved into place")

        // 6. Delete old index file (safe — new index is confirmed on disk)
        try deleteVaultIndex(for: oldKey)

        Self.logger.debug("Old index deleted")
        Self.logger.info("Vault key change complete! No files were re-encrypted.")
    }

    // MARK: - Vault Destruction (for duress)

    func deleteVaultIndex(for key: VaultKey) throws {
        let url = indexManager.indexURL(for: key)

        // Invalidate cache for this key
        indexManager.invalidateCache(for: key)

        if fileManager.fileExists(atPath: url.path) {
            Self.logger.debug("Deleting vault index file")
            try fileManager.removeItem(at: url)
        }
    }

    /// Quick wipe: delete all index files + keychain items. Keys gone = data unrecoverable.
    func destroyAllVaultData() {
        ensureBlobReady()
        Self.logger.warning("Destroying all vault data!")

        // Invalidate cached index
        indexManager.invalidateCache()

        // Delete ALL index files (all vaults) — without keys, blob data is unrecoverable
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.hasPrefix("vault_index_") {
                    Self.logger.warning("Deleting index file: \(file.lastPathComponent, privacy: .public)")
                    try? fileManager.removeItem(at: file)
                }
            }
        }

        // Re-initialize global cursor to 0
        writeGlobalCursor(0)
    }

    /// Overwrite entire file with random data, using actual file size (not constant).
    /// Handles legacy 500MB blobs and new 50MB blobs correctly.
    private func secureOverwrite(url: URL) {
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? defaultBlobSize
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        let chunkSize = 1024 * 1024
        var offset = 0
        while offset < fileSize {
            if let random = CryptoEngine.generateRandomBytes(count: min(chunkSize, fileSize - offset)) {
                try? handle.seek(toOffset: UInt64(offset))
                handle.write(random)
            }
            offset += chunkSize
        }
        try? handle.close()
    }

    /// Secure wipe: overwrite all blob files with random data, then delete expansion blobs.
    func secureWipeAllBlobs() {
        ensureBlobReady()
        Self.logger.warning("Secure wiping all blobs!")

        for url in allBlobURLs() {
            secureOverwrite(url: url)

            // Delete expansion blobs; keep primary
            if url.lastPathComponent != blobFileName {
                try? fileManager.removeItem(at: url)
            }
        }

        writeGlobalCursor(0)
    }

    /// Destroys all vault indexes except the one for the specified key
    /// Used during duress mode to preserve only the duress vault
    func destroyAllIndexesExcept(_ preservedKey: VaultKey) {
        Self.logger.debug("Destroying all vault indexes except preserved key")

        // Get the index URL for the preserved vault
        let preservedIndexURL = indexManager.indexURL(for: preservedKey)
        let preservedFilename = preservedIndexURL.lastPathComponent

        Self.logger.debug("Preserving index file: \(preservedFilename, privacy: .public)")

        // Delete all OTHER index files
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.hasPrefix("vault_index_") &&
                   file.lastPathComponent != preservedFilename {
                    Self.logger.debug("Deleting index file: \(file.lastPathComponent, privacy: .public)")
                    try? fileManager.removeItem(at: file)
                }
            }
        }

        Self.logger.info("All vault indexes destroyed except \(preservedFilename, privacy: .public)")
    }

    // MARK: - Storage Info

    /// Total bytes consumed across all blobs (sum of cursors).
    var usedSpace: Int {
        // Fall back to global cursor for un-migrated state
        readGlobalCursor()
    }

    /// Bytes remaining in the primary blob only (free tier view).
    var availableSpace: Int {
        cursorBlockOffset - usedSpace
    }

    /// Total capacity across all blobs for a given vault.
    func totalCapacity(for index: VaultIndex) -> Int {
        guard let blobs = index.blobs else { return cursorBlockOffset }
        return blobs.reduce(0) { $0 + $1.capacity }
    }

    /// Total used across all blobs for a given vault.
    func totalUsed(for index: VaultIndex) -> Int {
        guard let blobs = index.blobs else { return readGlobalCursor() }
        return blobs.reduce(0) { $0 + $1.cursor }
    }

    /// Bytes of deleted (reclaimable) space in a vault.
    func deletedSpace(for index: VaultIndex) -> Int {
        index.files.filter { $0.isDeleted }.reduce(0) { $0 + $1.size }
    }

    // MARK: - Compaction

    /// Reclaim deleted space by copying live files to fresh blobs.
    /// Returns the updated index.
    func compactBlobs(with key: VaultKey) throws -> VaultIndex {
        indexManager.indexLock.lock()
        defer { indexManager.indexLock.unlock() }
        var index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)
        _ = masterKey // Silence unused warning — masterKey needed if we re-encrypt; here we copy raw

        let liveEntries = index.files.filter { !$0.isDeleted }

        // Collect old blob URLs for cleanup
        let oldBlobURLs = allBlobURLs()

        // Create fresh primary blob
        let freshPrimaryURL = documentsDirectory.appendingPathComponent("vault_data_compact.bin")
        fileManager.createFile(atPath: freshPrimaryURL.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.complete
        ])

        // Fill with random data
        if let handle = try? FileHandle(forWritingTo: freshPrimaryURL) {
            let chunkSize = 1024 * 1024
            for _ in 0..<(defaultBlobSize / chunkSize) {
                if let randomData = CryptoEngine.generateRandomBytes(count: chunkSize) {
                    handle.write(randomData)
                }
            }
            try? handle.close()
        }

        var newBlobs: [BlobDescriptor] = []
        var newFiles: [VaultIndex.VaultFileEntry] = []
        var currentBlobURL = freshPrimaryURL
        var currentBlobId = "primary"
        var currentCapacity = cursorBlockOffset
        var currentCursor = 0
        var expansionCount = 0

        for entry in liveEntries {
            // Read the raw encrypted data from old blob
            let sourceURL = blobURL(for: entry.blobId, in: index)
            guard let readHandle = try? FileHandle(forReadingFrom: sourceURL) else {
                throw VaultStorageError.readError
            }
            try readHandle.seek(toOffset: UInt64(entry.offset))
            guard let fileData = try readHandle.read(upToCount: entry.size) else {
                try? readHandle.close()
                throw VaultStorageError.readError
            }
            try? readHandle.close()

            // Check if current blob has space
            if currentCursor + entry.size > currentCapacity {
                // Finalize current blob descriptor
                newBlobs.append(BlobDescriptor(
                    blobId: currentBlobId,
                    fileName: currentBlobURL.lastPathComponent,
                    capacity: currentCapacity,
                    cursor: currentCursor
                ))

                // Create a new expansion blob
                guard let newBlob = createExpansionBlob() else {
                    throw VaultStorageError.writeError
                }
                expansionCount += 1
                currentBlobId = newBlob.blobId
                currentBlobURL = documentsDirectory.appendingPathComponent(newBlob.fileName)
                currentCapacity = newBlob.capacity
                currentCursor = 0
            }

            // Write to current blob
            guard let writeHandle = try? FileHandle(forWritingTo: currentBlobURL) else {
                throw VaultStorageError.writeError
            }
            try writeHandle.seek(toOffset: UInt64(currentCursor))
            writeHandle.write(fileData)
            try? writeHandle.close()

            // Create updated file entry
            let newEntry = VaultIndex.VaultFileEntry(
                fileId: entry.fileId,
                offset: currentCursor,
                size: entry.size,
                encryptedHeaderPreview: entry.encryptedHeaderPreview,
                isDeleted: false,
                thumbnailData: entry.thumbnailData,
                mimeType: entry.mimeType,
                filename: entry.filename,
                blobId: currentBlobId == "primary" ? nil : currentBlobId,
                createdAt: entry.createdAt,
                duration: entry.duration,
                originalDate: entry.originalDate
            )
            newFiles.append(newEntry)
            currentCursor += entry.size
        }

        // Finalize last blob
        newBlobs.append(BlobDescriptor(
            blobId: currentBlobId,
            fileName: currentBlobURL.lastPathComponent,
            capacity: currentCapacity,
            cursor: currentCursor
        ))

        // Overwrite old blobs with random data (uses actual file size), then delete
        for url in oldBlobURLs {
            secureOverwrite(url: url)
            try? fileManager.removeItem(at: url)
        }

        // Rename compacted primary to vault_data.bin
        try fileManager.moveItem(at: freshPrimaryURL, to: blobURL)

        // Fix the primary blob's fileName in descriptors
        if let primaryIdx = newBlobs.firstIndex(where: { $0.blobId == "primary" }) {
            newBlobs[primaryIdx] = BlobDescriptor(
                blobId: "primary",
                fileName: blobFileName,
                capacity: cursorBlockOffset,
                cursor: newBlobs[primaryIdx].cursor
            )
        }

        // Update global cursor for primary blob
        let primaryCursor = newBlobs.first(where: { $0.blobId == "primary" })?.cursor ?? 0
        writeGlobalCursor(primaryCursor)

        // Update index
        index.files = newFiles
        index.blobs = newBlobs
        index.nextOffset = primaryCursor

        try saveIndex(index, with: key)

        Self.logger.info("Compaction complete. \(newFiles.count, privacy: .public) files in \(newBlobs.count, privacy: .public) blob(s)")

        return index
    }
}
