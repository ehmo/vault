import Foundation
import CryptoKit

enum VaultStorageError: Error, LocalizedError {
    case blobNotInitialized
    case writeError
    case readError
    case insufficientSpace
    case fileNotFound
    case corruptedData
    case vaultAlreadyExists
    case expansionNotAllowed

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
        }
    }
}

/// CONCURRENCY: Not an actor because blocking file I/O would starve the cooperative
/// thread pool. `blobReady` race is benign: `ensureBlobReady()` uses `initQueue.sync`
/// as a barrier. Callers serialize at a higher level (`@MainActor` views, single
/// `Task.detached`). Full actor refactor deferred to future work.
final class VaultStorage {
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
    /// Serializes all index read/write operations to prevent concurrent access races
    /// between VaultView, ShareSyncManager, and BackgroundShareTransferManager.
    /// Recursive lock allows compound operations (load+modify+save) to call loadIndex/saveIndex internally.
    private let indexLock = NSRecursiveLock()
    private var blobReady = false

    private var blobURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(blobFileName)
    }
    
    /// Expose blob URL for secure overwrites during pattern changes
    func getBlobURL() -> URL {
        return blobURL
    }

    /// Returns the index file URL for a specific vault key
    /// Each vault gets its own index file based on a hash of the key
    private func indexURL(for key: Data) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create a fingerprint from the key
        let keyHash = SHA256.hash(data: key)
        let fingerprint = keyHash.prefix(16).map { String(format: "%02x", $0) }.joined()
        
        let fileName = "vault_index_\(fingerprint).bin"
        
        #if DEBUG
        print("📇 [VaultStorage] Index file for this vault: \(fileName)")
        #endif
        
        return documents.appendingPathComponent(fileName)
    }

    private init() {
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
            #if DEBUG
            print("✅ [VaultStorage] Background blob creation complete")
            #endif
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
                #if DEBUG
                print("⚠️ [VaultStorage] Global cursor magic mismatch — treating as uninitialized")
                #endif
                return 0
            }

            #if DEBUG
            print("📍 [VaultStorage] readGlobalCursor: \(storedOffset)")
            #endif
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
            #if DEBUG
            print("📍 [VaultStorage] writeGlobalCursor: \(offset)")
            #endif
        } catch {
            #if DEBUG
            print("❌ [VaultStorage] Failed to write global cursor: \(error)")
            #endif
        }
    }

    // MARK: - Vault Index Management

    // MARK: - Share Policy & Records

    struct SharePolicy: Codable, Equatable, Sendable {
        var expiresAt: Date?        // nil = never
        var maxOpens: Int?          // nil = unlimited
        var allowScreenshots: Bool  // default false
        var allowDownloads: Bool    // default true

        init(expiresAt: Date? = nil, maxOpens: Int? = nil, allowScreenshots: Bool = false, allowDownloads: Bool = true) {
            self.expiresAt = expiresAt
            self.maxOpens = maxOpens
            self.allowScreenshots = allowScreenshots
            self.allowDownloads = allowDownloads
        }
    }

    struct ShareRecord: Codable, Identifiable, Sendable {
        let id: String              // share vault ID in CloudKit
        let createdAt: Date
        let policy: SharePolicy
        var lastSyncedAt: Date?
        var shareKeyData: Data?     // phrase-derived share key (stored in encrypted index)
        var syncSequence: Int?      // incremental sync counter (nil = never synced with SVDF)

        var shareId: String { id }
    }

    struct BlobDescriptor: Codable, Sendable {
        let blobId: String      // "primary" or random hex
        let fileName: String    // "vault_data.bin" or "vd_<hex>.bin"
        let capacity: Int       // usable bytes (blob size minus reserved footer for primary)
        var cursor: Int         // next write offset in this blob
    }

    struct VaultIndex: Codable, Sendable {
        var files: [VaultFileEntry]
        var nextOffset: Int
        var totalSize: Int
        var encryptedMasterKey: Data? // Master key encrypted with vault key (32 bytes encrypted)
        var version: Int // Index format version for future migrations

        // Multi-blob pool (nil = v2 single-blob mode)
        var blobs: [BlobDescriptor]?

        // Owner side: active shares for this vault
        var activeShares: [ShareRecord]?

        // Recipient side: marks this as a received shared vault
        var isSharedVault: Bool?
        var sharedVaultId: String?       // CloudKit vault ID for update checks
        var sharePolicy: SharePolicy?    // restrictions set by owner
        var openCount: Int?              // track opens for maxOpens
        var shareKeyData: Data?          // phrase-derived share key for update downloads
        var sharedVaultVersion: Int?     // last known remote version for update checks

        // Legacy initializer for backward compatibility
        init(files: [VaultFileEntry], nextOffset: Int, totalSize: Int) {
            self.files = files
            self.nextOffset = nextOffset
            self.totalSize = totalSize
            self.encryptedMasterKey = nil
            self.version = 1
        }

        // New initializer with master key
        init(files: [VaultFileEntry], nextOffset: Int, totalSize: Int, encryptedMasterKey: Data, version: Int = 2) {
            self.files = files
            self.nextOffset = nextOffset
            self.totalSize = totalSize
            self.encryptedMasterKey = encryptedMasterKey
            self.version = version
        }

        struct VaultFileEntry: Codable, Sendable {
            let fileId: UUID
            let offset: Int
            let size: Int
            let encryptedHeaderPreview: Data // First 64 bytes for quick lookup
            let isDeleted: Bool
            let thumbnailData: Data? // Encrypted thumbnail data (JPEG, 200x200 max)
            let mimeType: String?
            let filename: String?
            let blobId: String? // nil = primary blob (backward compat)
            let createdAt: Date? // When the file was added to the vault
            let duration: TimeInterval? // Video duration in seconds (nil for non-video)

            // Legacy initializer for backward compatibility
            init(fileId: UUID, offset: Int, size: Int, encryptedHeaderPreview: Data, isDeleted: Bool) {
                self.fileId = fileId
                self.offset = offset
                self.size = size
                self.encryptedHeaderPreview = encryptedHeaderPreview
                self.isDeleted = isDeleted
                self.thumbnailData = nil
                self.mimeType = nil
                self.filename = nil
                self.blobId = nil
                self.createdAt = nil
                self.duration = nil
            }

            // Full initializer with thumbnail and blobId
            init(fileId: UUID, offset: Int, size: Int, encryptedHeaderPreview: Data, isDeleted: Bool,
                 thumbnailData: Data?, mimeType: String?, filename: String?, blobId: String? = nil,
                 createdAt: Date? = nil, duration: TimeInterval? = nil) {
                self.fileId = fileId
                self.offset = offset
                self.size = size
                self.encryptedHeaderPreview = encryptedHeaderPreview
                self.isDeleted = isDeleted
                self.thumbnailData = thumbnailData
                self.mimeType = mimeType
                self.filename = filename
                self.blobId = blobId
                self.createdAt = createdAt
                self.duration = duration
            }
        }
    }

    func loadIndex(with key: Data) throws -> VaultIndex {
        indexLock.lock()
        defer { indexLock.unlock() }
        return try _loadIndex(with: key)
    }

    private func _loadIndex(with key: Data) throws -> VaultIndex {
        let span = EmbraceManager.shared.startTransaction(name: "storage.index_load", operation: "storage.index_load")
        defer { span.finish(status: .ok) }

        #if DEBUG
        print("📇 [VaultStorage] loadIndex called with key hash: \(key.hashValue)")
        #endif

        let indexURL = indexURL(for: key)

        guard fileManager.fileExists(atPath: indexURL.path) else {
            #if DEBUG
            print("📇 [VaultStorage] No index file exists, creating new vault with master key")
            #endif
            // Return empty v3 index for new vaults with a fresh master key
            guard let masterKey = CryptoEngine.generateRandomBytes(count: 32) else {
                throw VaultStorageError.corruptedData
            }
            let encryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: key)
            let globalCursor = readGlobalCursor()
            let primary = BlobDescriptor(
                blobId: "primary",
                fileName: blobFileName,
                capacity: cursorBlockOffset,
                cursor: globalCursor
            )
            var newIndex = VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: cursorBlockOffset,
                encryptedMasterKey: encryptedMasterKey,
                version: 3
            )
            newIndex.blobs = [primary]
            return newIndex
        }

        let encryptedData = try Data(contentsOf: indexURL)
        
        #if DEBUG
        print("📇 [VaultStorage] Index file loaded, size: \(encryptedData.count) bytes")
        #endif

        // Try to decrypt - if it fails, this key doesn't match any vault
        do {
            let decryptedData = try CryptoEngine.decrypt(encryptedData, with: key)
            var index = try JSONDecoder().decode(VaultIndex.self, from: decryptedData)
            
            #if DEBUG
            print("✅ [VaultStorage] Index decrypted. Files: \(index.files.count), nextOffset: \(index.nextOffset), version: \(index.version)")
            #endif
            
            // Migration: If index doesn't have a master key (version 1), create one
            if index.encryptedMasterKey == nil {
                #if DEBUG
                print("🔄 [VaultStorage] Migrating vault to use master key (v1 -> v2)")
                #endif
                guard let masterKey = CryptoEngine.generateRandomBytes(count: 32) else {
                    throw VaultStorageError.corruptedData
                }
                index.encryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: key)
                index.version = 2

                try saveIndex(index, with: key)

                #if DEBUG
                print("✅ [VaultStorage] Vault migrated to v2 with master key")
                #endif
            }

            // Migration: v2 → v3 (add blob descriptors)
            if index.version < 3 {
                #if DEBUG
                print("🔄 [VaultStorage] Migrating vault v2 -> v3 (multi-blob)")
                #endif
                migrateToV3(&index)
                try saveIndex(index, with: key)

                #if DEBUG
                print("✅ [VaultStorage] Vault migrated to v3")
                #endif
            }

            return index
        } catch {
            #if DEBUG
            print("⚠️ [VaultStorage] Failed to decrypt index (wrong key?): \(error)")
            print("⚠️ [VaultStorage] Returning empty index")
            #endif
            // Decryption failed - return empty index with new master key (appears as empty vault)
            guard let masterKey = CryptoEngine.generateRandomBytes(count: 32) else {
                throw VaultStorageError.corruptedData
            }
            let encryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: key)
            let globalCursor = readGlobalCursor()
            let primary = BlobDescriptor(
                blobId: "primary",
                fileName: blobFileName,
                capacity: cursorBlockOffset,
                cursor: globalCursor
            )
            var newIndex = VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: cursorBlockOffset,
                encryptedMasterKey: encryptedMasterKey,
                version: 3
            )
            newIndex.blobs = [primary]
            return newIndex
        }
    }

    func saveIndex(_ index: VaultIndex, with key: Data) throws {
        indexLock.lock()
        defer { indexLock.unlock() }
        try _saveIndex(index, with: key)
    }

    private func _saveIndex(_ index: VaultIndex, with key: Data) throws {
        let span = EmbraceManager.shared.startTransaction(name: "storage.index_save", operation: "storage.index_save")
        defer { span.finish(status: .ok) }

        #if DEBUG
        print("💾 [VaultStorage] saveIndex called")
        print("💾 [VaultStorage] Files: \(index.files.count), nextOffset: \(index.nextOffset)")
        print("💾 [VaultStorage] Key hash: \(key.hashValue)")
        #endif

        let encoded = try JSONEncoder().encode(index)
        
        #if DEBUG
        print("💾 [VaultStorage] Index encoded, size: \(encoded.count) bytes")
        #endif
        
        let encrypted = try CryptoEngine.encrypt(encoded, with: key)
        
        #if DEBUG
        print("💾 [VaultStorage] Index encrypted, size: \(encrypted.count) bytes")
        #endif

        let indexURL = indexURL(for: key)
        try encrypted.write(to: indexURL, options: [.atomic, .completeFileProtection])
        
        #if DEBUG
        print("✅ [VaultStorage] Index saved to disk")
        #endif
    }
    
    /// Extract and decrypt the master key from the vault index
    private func getMasterKey(from index: VaultIndex, vaultKey: Data) throws -> Data {
        guard let encryptedMasterKey = index.encryptedMasterKey else {
            throw VaultStorageError.corruptedData
        }
        
        let masterKey = try CryptoEngine.decrypt(encryptedMasterKey, with: vaultKey)
        
        #if DEBUG
        print("🔑 [VaultStorage] Master key decrypted")
        #endif
        
        return masterKey
    }

    // MARK: - Multi-Blob Management

    /// Documents directory for all blob files
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Resolve a blobId to its file URL. nil or "primary" → primary blob.
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

        #if DEBUG
        print("🗄️ [VaultStorage] Created expansion blob: \(fileName)")
        #endif

        return BlobDescriptor(
            blobId: hexId,
            fileName: fileName,
            capacity: defaultBlobSize, // Full capacity — no footer reservation
            cursor: 0
        )
    }

    /// Migrate a v2 index to v3 by adding blob descriptors.
    private func migrateToV3(_ index: inout VaultIndex) {
        let globalCursor = readGlobalCursor()
        let cursor = max(globalCursor, index.nextOffset)

        // Use actual file size for capacity — legacy blobs may be 500MB
        let actualCapacity = cursorFooterOffset()
        let primary = BlobDescriptor(
            blobId: "primary",
            fileName: blobFileName,
            capacity: actualCapacity,
            cursor: cursor
        )
        index.blobs = [primary]
        index.version = 3

        #if DEBUG
        print("🔄 [VaultStorage] Migrated index to v3. Primary blob cursor: \(cursor)")
        #endif
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

    // MARK: - File Operations

    func storeFile(data: Data, filename: String, mimeType: String, with key: Data, thumbnailData: Data? = nil, duration: TimeInterval? = nil) throws -> UUID {
        let span = EmbraceManager.shared.startTransaction(name: "storage.store_file", operation: "storage.store_file")
        span.setTag(value: "\(data.count / 1024)", key: "fileSizeKB")
        span.setTag(value: mimeType, key: "mimeType")

        ensureBlobReady()
        indexLock.lock()
        defer { indexLock.unlock() }
        #if DEBUG
        print("💾 [VaultStorage] storeFile called")
        print("💾 [VaultStorage] filename: \(filename), size: \(data.count) bytes")
        print("💾 [VaultStorage] mimeType: \(mimeType)")
        print("💾 [VaultStorage] key hash: \(key.hashValue)")
        print("💾 [VaultStorage] thumbnail provided: \(thumbnailData != nil)")
        #endif

        var index = try loadIndex(with: key)
        
        #if DEBUG
        print("💾 [VaultStorage] Current index loaded. Files: \(index.files.count), nextOffset: \(index.nextOffset)")
        #endif
        
        // Get the master key for encrypting file data
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        // Encrypt the file with MASTER KEY (not vault key)
        let encryptedFile = try CryptoEngine.encryptFile(
            data: data,
            filename: filename,
            mimeType: mimeType,
            with: masterKey  // ← Use master key here
        )

        let fileData = encryptedFile.encryptedContent
        let fileSize = fileData.count
        
        #if DEBUG
        print("💾 [VaultStorage] File encrypted with master key. Size: \(fileSize) bytes")
        #endif

        // Find a blob with enough space
        var targetBlobIndex: Int? = nil
        if let blobs = index.blobs {
            for (i, blob) in blobs.enumerated() {
                if blob.cursor + fileSize <= blob.capacity {
                    targetBlobIndex = i
                    break
                }
            }
        }

        // No blob has space — expand automatically
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

        #if DEBUG
        print("💾 [VaultStorage] Writing to blob '\(targetBlobId)' at offset \(writeOffset)")
        #endif

        // Write to blob
        guard let handle = try? FileHandle(forWritingTo: targetURL) else {
            #if DEBUG
            print("❌ [VaultStorage] Cannot open blob file for writing")
            #endif
            throw VaultStorageError.writeError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(writeOffset))
        handle.write(fileData)

        #if DEBUG
        print("💾 [VaultStorage] Data written to blob at offset \(writeOffset)")
        #endif

        // Encrypt thumbnail with MASTER KEY if provided
        var encryptedThumbnail: Data? = nil
        if let thumbnail = thumbnailData {
            encryptedThumbnail = try? CryptoEngine.encrypt(thumbnail, with: masterKey)
            #if DEBUG
            print("💾 [VaultStorage] Thumbnail encrypted with master key")
            #endif
        }

        // Update blob cursor
        let newCursor = writeOffset + fileSize
        index.blobs![blobIdx].cursor = newCursor

        // For primary blob, also update the XOR footer cursor (v2 compat)
        if targetBlobId == "primary" {
            writeGlobalCursor(newCursor)
            index.nextOffset = newCursor
        }

        // Update index
        let entry = VaultIndex.VaultFileEntry(
            fileId: encryptedFile.header.fileId,
            offset: writeOffset,
            size: fileSize,
            encryptedHeaderPreview: fileData.prefix(64),
            isDeleted: false,
            thumbnailData: encryptedThumbnail,
            mimeType: mimeType,
            filename: filename,
            blobId: targetBlobId == "primary" ? nil : targetBlobId,
            createdAt: Date(),
            duration: duration
        )
        index.files.append(entry)

        try saveIndex(index, with: key)

        span.finish(status: .ok)

        #if DEBUG
        print("✅ [VaultStorage] File stored successfully with ID: \(encryptedFile.header.fileId)")
        print("✅ [VaultStorage] New index: \(index.files.count) files, blob '\(targetBlobId)' cursor: \(newCursor)")
        #endif

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

    func storeFiles(_ files: [FileToStore], with key: Data, onProgress: ((Int) -> Void)? = nil) throws -> [UUID] {
        ensureBlobReady()
        indexLock.lock()
        defer { indexLock.unlock() }

        var index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)
        var storedIds: [UUID] = []

        for (i, file) in files.enumerated() {
            let encryptedFile = try CryptoEngine.encryptFile(
                data: file.data, filename: file.filename, mimeType: file.mimeType, with: masterKey
            )
            let fileData = encryptedFile.encryptedContent
            let fileSize = fileData.count

            // Find a blob with enough space
            var targetBlobIndex: Int? = nil
            if let blobs = index.blobs {
                for (j, blob) in blobs.enumerated() {
                    if blob.cursor + fileSize <= blob.capacity {
                        targetBlobIndex = j
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
            defer { try? handle.close() }

            try handle.seek(toOffset: UInt64(writeOffset))
            handle.write(fileData)

            var encryptedThumbnail: Data? = nil
            if let thumbnail = file.thumbnailData {
                encryptedThumbnail = try? CryptoEngine.encrypt(thumbnail, with: masterKey)
            }

            let newCursor = writeOffset + fileSize
            index.blobs![blobIdx].cursor = newCursor

            if targetBlobId == "primary" {
                writeGlobalCursor(newCursor)
                index.nextOffset = newCursor
            }

            let entry = VaultIndex.VaultFileEntry(
                fileId: encryptedFile.header.fileId,
                offset: writeOffset,
                size: fileSize,
                encryptedHeaderPreview: fileData.prefix(64),
                isDeleted: false,
                thumbnailData: encryptedThumbnail,
                mimeType: file.mimeType,
                filename: file.filename,
                blobId: targetBlobId == "primary" ? nil : targetBlobId,
                createdAt: Date()
            )
            index.files.append(entry)
            storedIds.append(encryptedFile.header.fileId)

            onProgress?(i + 1)
        }

        // Save index once for all files
        try saveIndex(index, with: key)

        #if DEBUG
        print("✅ [VaultStorage] Batch stored \(storedIds.count) files")
        #endif

        return storedIds
    }

    /// Store a file from a URL without loading the entire raw content into memory.
    /// Uses streaming encryption for large files (VCSE for files > 1MB).
    func storeFileFromURL(_ fileURL: URL, filename: String, mimeType: String, with key: Data, thumbnailData: Data? = nil, duration: TimeInterval? = nil) throws -> UUID {
        ensureBlobReady()
        indexLock.lock()
        defer { indexLock.unlock() }

        var index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        // Build header (small — stays in memory)
        let fileId = UUID()
        let originalFileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        let header = CryptoEngine.EncryptedFileHeader(
            fileId: fileId,
            originalFilename: filename,
            mimeType: mimeType,
            originalSize: UInt64(originalFileSize),
            createdAt: Date()
        )
        let encryptedHeader = try CryptoEngine.encrypt(header.serialize(), with: masterKey)

        // Calculate total size WITHOUT loading the file into memory
        let encContentSize = CryptoEngine.encryptedContentSize(forFileOfSize: originalFileSize)
        let totalSize = 4 + encryptedHeader.count + encContentSize

        // Find a blob with enough space
        var targetBlobIndex: Int? = nil
        if let blobs = index.blobs {
            for (i, blob) in blobs.enumerated() {
                if blob.cursor + totalSize <= blob.capacity {
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
        defer { try? handle.close() }

        // Write header to blob
        try handle.seek(toOffset: UInt64(writeOffset))
        var headerSize = UInt32(encryptedHeader.count)
        let headerSizeData = Data(bytes: &headerSize, count: 4)
        handle.write(headerSizeData)
        handle.write(encryptedHeader)

        // Stream-encrypt content directly to blob — peak memory: ~256KB
        try CryptoEngine.encryptFileStreamingToHandle(from: fileURL, to: handle, with: masterKey)

        // Build header preview for index (first 64 bytes of on-disk format)
        var headerPreview = Data()
        headerPreview.append(headerSizeData)
        headerPreview.append(encryptedHeader.prefix(60))

        var encryptedThumbnail: Data? = nil
        if let thumbnail = thumbnailData {
            encryptedThumbnail = try? CryptoEngine.encrypt(thumbnail, with: masterKey)
        }

        let newCursor = writeOffset + totalSize
        index.blobs![blobIdx].cursor = newCursor

        if targetBlobId == "primary" {
            writeGlobalCursor(newCursor)
            index.nextOffset = newCursor
        }

        let entry = VaultIndex.VaultFileEntry(
            fileId: fileId,
            offset: writeOffset,
            size: totalSize,
            encryptedHeaderPreview: headerPreview,
            isDeleted: false,
            thumbnailData: encryptedThumbnail,
            mimeType: mimeType,
            filename: filename,
            blobId: targetBlobId == "primary" ? nil : targetBlobId,
            createdAt: Date(),
            duration: duration
        )
        index.files.append(entry)

        try saveIndex(index, with: key)

        return fileId
    }

    func retrieveFile(id: UUID, with key: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
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
    func retrieveFileToTempURL(id: UUID, with key: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, tempURL: URL) {
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

    func deleteFile(id: UUID, with key: Data) throws {
        ensureBlobReady()
        indexLock.lock()
        defer { indexLock.unlock() }
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
        if let randomData = CryptoEngine.generateRandomBytes(count: entry.size) {
            handle.write(randomData)
        }

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
            duration: entry.duration
        )

        try saveIndex(index, with: key)
    }

    /// Delete multiple files in a single index load/save cycle.
    /// Calls `onProgress` after each file is securely overwritten (on the calling thread).
    func deleteFiles(ids: Set<UUID>, with key: Data, onProgress: ((Int) -> Void)? = nil) throws {
        ensureBlobReady()
        indexLock.lock()
        defer { indexLock.unlock() }
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
                if let randomData = CryptoEngine.generateRandomBytes(count: entry.size) {
                    handle.write(randomData)
                }

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
                    duration: entry.duration
                )

                deletedCount += 1
                onProgress?(deletedCount)
            }
        }

        // Save index once for all deletions
        try saveIndex(index, with: key)
    }

    func listFiles(with key: Data) throws -> [VaultFileEntry] {
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
    }

    /// Returns the master key and file entries without decrypting thumbnails.
    /// Use this for lazy thumbnail loading — thumbnails are decrypted on-demand per cell.
    func listFilesLightweight(with key: Data) throws -> (masterKey: Data, files: [LightweightFileEntry]) {
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
                duration: entry.duration
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
    func vaultExists(for key: Data) -> Bool {
        let indexURL = indexURL(for: key)
        let exists = fileManager.fileExists(atPath: indexURL.path)
        
        #if DEBUG
        print("🔍 [VaultStorage] Checking if vault exists for key hash \(key.hashValue): \(exists)")
        #endif
        
        return exists
    }
    
    /// Change the vault key (pattern) without re-encrypting files
    /// This is extremely fast because we only re-encrypt the master key, not the file data
    func changeVaultKey(from oldKey: Data, to newKey: Data) throws {
        indexLock.lock()
        defer { indexLock.unlock() }
        #if DEBUG
        print("🔑 [VaultStorage] Changing vault key (pattern change)")
        print("🔑 [VaultStorage] Old key hash: \(oldKey.hashValue)")
        print("🔑 [VaultStorage] New key hash: \(newKey.hashValue)")
        #endif
        
        // Check if new key would overwrite an existing vault
        if vaultExists(for: newKey) {
            #if DEBUG
            print("❌ [VaultStorage] Cannot change to this pattern - vault already exists!")
            #endif
            throw VaultStorageError.vaultAlreadyExists
        }
        
        // 1. Load index with old key
        let index = try loadIndex(with: oldKey)
        
        #if DEBUG
        print("📂 [VaultStorage] Index loaded with old key. Files: \(index.files.count)")
        #endif
        
        // 2. Decrypt master key with old vault key
        let masterKey = try getMasterKey(from: index, vaultKey: oldKey)
        
        #if DEBUG
        print("🔓 [VaultStorage] Master key decrypted with old vault key")
        #endif
        
        // 3. Re-encrypt master key with NEW vault key
        let newEncryptedMasterKey = try CryptoEngine.encrypt(masterKey, with: newKey)
        
        #if DEBUG
        print("🔐 [VaultStorage] Master key re-encrypted with new vault key")
        #endif
        
        // 4. Copy index and replace only the master key (future-proof — new fields are preserved)
        var newIndex = index
        newIndex.encryptedMasterKey = newEncryptedMasterKey

        // 5. Write-ahead: save new index to temp file, verify, then move into place
        let newIndexURL = indexURL(for: newKey)
        let tempURL = newIndexURL.appendingPathExtension("tmp")

        // Encode and encrypt
        let encoded = try JSONEncoder().encode(newIndex)
        let encrypted = try CryptoEngine.encrypt(encoded, with: newKey)
        try encrypted.write(to: tempURL, options: [.atomic, .completeFileProtection])

        // Verify: read back and decrypt to confirm integrity
        let readBack = try Data(contentsOf: tempURL)
        let decrypted = try CryptoEngine.decrypt(readBack, with: newKey)
        let verified = try JSONDecoder().decode(VaultIndex.self, from: decrypted)
        guard verified.files.count == newIndex.files.count,
              verified.encryptedMasterKey == newEncryptedMasterKey else {
            try? fileManager.removeItem(at: tempURL)
            throw VaultStorageError.corruptedData
        }

        // Atomic move temp → final (replaces if exists)
        if fileManager.fileExists(atPath: newIndexURL.path) {
            try fileManager.removeItem(at: newIndexURL)
        }
        try fileManager.moveItem(at: tempURL, to: newIndexURL)

        #if DEBUG
        print("💾 [VaultStorage] New index verified and moved into place")
        #endif

        // 6. Delete old index file (safe — new index is confirmed on disk)
        try deleteVaultIndex(for: oldKey)

        #if DEBUG
        print("🗑️ [VaultStorage] Old index deleted")
        print("✅ [VaultStorage] Vault key change complete! No files were re-encrypted.")
        #endif
    }
    
    // MARK: - Vault Destruction (for duress)

    func deleteVaultIndex(for key: Data) throws {
        let indexURL = indexURL(for: key)
        
        if fileManager.fileExists(atPath: indexURL.path) {
            #if DEBUG
            print("🗑️ [VaultStorage] Deleting vault index file")
            #endif
            try fileManager.removeItem(at: indexURL)
        }
    }

    /// Quick wipe: delete all index files + keychain items. Keys gone = data unrecoverable.
    func destroyAllVaultData() {
        ensureBlobReady()
        #if DEBUG
        print("💣 [VaultStorage] Destroying all vault data!")
        #endif

        // Delete ALL index files (all vaults) — without keys, blob data is unrecoverable
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.hasPrefix("vault_index_") {
                    #if DEBUG
                    print("💣 [VaultStorage] Deleting index file: \(file.lastPathComponent)")
                    #endif
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
        #if DEBUG
        print("💣 [VaultStorage] Secure wiping all blobs!")
        #endif

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
    func destroyAllIndexesExcept(_ preservedKey: Data) {
        #if DEBUG
        print("🗑️ [VaultStorage] Destroying all vault indexes except preserved key")
        #endif
        
        // Get the index URL for the preserved vault
        let preservedIndexURL = indexURL(for: preservedKey)
        let preservedFilename = preservedIndexURL.lastPathComponent
        
        #if DEBUG
        print("🔒 [VaultStorage] Preserving index file: \(preservedFilename)")
        #endif
        
        // Delete all OTHER index files
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.hasPrefix("vault_index_") && 
                   file.lastPathComponent != preservedFilename {
                    #if DEBUG
                    print("🗑️ [VaultStorage] Deleting index file: \(file.lastPathComponent)")
                    #endif
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        
        #if DEBUG
        print("✅ [VaultStorage] All vault indexes destroyed except \(preservedFilename)")
        #endif
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
    func compactBlobs(with key: Data) throws -> VaultIndex {
        indexLock.lock()
        defer { indexLock.unlock() }
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
                duration: entry.duration
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

        #if DEBUG
        print("✅ [VaultStorage] Compaction complete. \(newFiles.count) files in \(newBlobs.count) blob(s)")
        #endif

        return index
    }
}
