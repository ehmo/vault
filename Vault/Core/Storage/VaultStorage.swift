import Foundation
import CryptoKit

enum VaultStorageError: Error {
    case blobNotInitialized
    case writeError
    case readError
    case insufficientSpace
    case fileNotFound
    case corruptedData
    case vaultAlreadyExists
}

final class VaultStorage {
    static let shared = VaultStorage()

    private let fileManager = FileManager.default
    private let blobFileName = "vault_data.bin"

    // Note: We don't use a single index file anymore - each vault gets its own
    // based on a hash of the vault key

    // Pre-allocated blob size (500 MB)
    private let defaultBlobSize: Int = 500 * 1024 * 1024

    // Global cursor block lives in the last 16 bytes of the blob
    private var cursorBlockOffset: Int { defaultBlobSize - 16 }
    private let cursorMagic: UInt64 = 0x5641553100000000

    private let initQueue = DispatchQueue(label: "vault.blob.init")
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
            if let randomData = CryptoEngine.shared.generateRandomBytes(count: chunkSize) {
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
            try handle.seek(toOffset: UInt64(cursorBlockOffset))
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
            try handle.seek(toOffset: UInt64(cursorBlockOffset))
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

    struct SharePolicy: Codable, Equatable {
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

    struct ShareRecord: Codable, Identifiable {
        let id: String              // share vault ID in CloudKit
        let createdAt: Date
        let policy: SharePolicy
        var lastSyncedAt: Date?
        var shareKeyData: Data?     // phrase-derived share key (stored in encrypted index)

        var shareId: String { id }
    }

    struct VaultIndex: Codable {
        var files: [VaultFileEntry]
        var nextOffset: Int
        var totalSize: Int
        var encryptedMasterKey: Data? // Master key encrypted with vault key (32 bytes encrypted)
        var version: Int // Index format version for future migrations

        // Owner side: active shares for this vault
        var activeShares: [ShareRecord]?

        // Recipient side: marks this as a received shared vault
        var isSharedVault: Bool?
        var sharedVaultId: String?       // CloudKit vault ID for update checks
        var sharePolicy: SharePolicy?    // restrictions set by owner
        var openCount: Int?              // track opens for maxOpens
        var shareKeyData: Data?          // phrase-derived share key for update downloads

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

        struct VaultFileEntry: Codable {
            let fileId: UUID
            let offset: Int
            let size: Int
            let encryptedHeaderPreview: Data // First 64 bytes for quick lookup
            let isDeleted: Bool
            let thumbnailData: Data? // Encrypted thumbnail data (JPEG, 200x200 max)
            let mimeType: String?
            let filename: String?
            
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
            }
            
            // Full initializer with thumbnail
            init(fileId: UUID, offset: Int, size: Int, encryptedHeaderPreview: Data, isDeleted: Bool, 
                 thumbnailData: Data?, mimeType: String?, filename: String?) {
                self.fileId = fileId
                self.offset = offset
                self.size = size
                self.encryptedHeaderPreview = encryptedHeaderPreview
                self.isDeleted = isDeleted
                self.thumbnailData = thumbnailData
                self.mimeType = mimeType
                self.filename = filename
            }
        }
    }

    func loadIndex(with key: Data) throws -> VaultIndex {
        let span = SentryManager.shared.startTransaction(name: "storage.index_load", operation: "storage.index_load")
        defer { span.finish(status: .ok) }

        #if DEBUG
        print("📇 [VaultStorage] loadIndex called with key hash: \(key.hashValue)")
        #endif

        let indexURL = indexURL(for: key)

        guard fileManager.fileExists(atPath: indexURL.path) else {
            #if DEBUG
            print("📇 [VaultStorage] No index file exists, creating new vault with master key")
            #endif
            // Return empty index for new vaults with a fresh master key
            let masterKey = CryptoEngine.shared.generateRandomBytes(count: 32)!
            let encryptedMasterKey = try CryptoEngine.shared.encrypt(masterKey, with: key)
            return VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: cursorBlockOffset,
                encryptedMasterKey: encryptedMasterKey,
                version: 2
            )
        }

        let encryptedData = try Data(contentsOf: indexURL)
        
        #if DEBUG
        print("📇 [VaultStorage] Index file loaded, size: \(encryptedData.count) bytes")
        #endif

        // Try to decrypt - if it fails, this key doesn't match any vault
        do {
            let decryptedData = try CryptoEngine.shared.decrypt(encryptedData, with: key)
            var index = try JSONDecoder().decode(VaultIndex.self, from: decryptedData)
            
            #if DEBUG
            print("✅ [VaultStorage] Index decrypted. Files: \(index.files.count), nextOffset: \(index.nextOffset), version: \(index.version)")
            #endif
            
            // Migration: If index doesn't have a master key (version 1), create one
            if index.encryptedMasterKey == nil {
                #if DEBUG
                print("🔄 [VaultStorage] Migrating vault to use master key (v1 -> v2)")
                #endif
                let masterKey = CryptoEngine.shared.generateRandomBytes(count: 32)!
                index.encryptedMasterKey = try CryptoEngine.shared.encrypt(masterKey, with: key)
                index.version = 2
                
                // Save the updated index
                try saveIndex(index, with: key)
                
                #if DEBUG
                print("✅ [VaultStorage] Vault migrated to v2 with master key")
                #endif
            }
            
            return index
        } catch {
            #if DEBUG
            print("⚠️ [VaultStorage] Failed to decrypt index (wrong key?): \(error)")
            print("⚠️ [VaultStorage] Returning empty index")
            #endif
            // Decryption failed - return empty index with new master key (appears as empty vault)
            let masterKey = CryptoEngine.shared.generateRandomBytes(count: 32)!
            let encryptedMasterKey = try CryptoEngine.shared.encrypt(masterKey, with: key)
            return VaultIndex(
                files: [],
                nextOffset: 0,
                totalSize: cursorBlockOffset,
                encryptedMasterKey: encryptedMasterKey,
                version: 2
            )
        }
    }

    func saveIndex(_ index: VaultIndex, with key: Data) throws {
        let span = SentryManager.shared.startTransaction(name: "storage.index_save", operation: "storage.index_save")
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
        
        let encrypted = try CryptoEngine.shared.encrypt(encoded, with: key)
        
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
        
        let masterKey = try CryptoEngine.shared.decrypt(encryptedMasterKey, with: vaultKey)
        
        #if DEBUG
        print("🔑 [VaultStorage] Master key decrypted")
        #endif
        
        return masterKey
    }

    // MARK: - File Operations

    func storeFile(data: Data, filename: String, mimeType: String, with key: Data, thumbnailData: Data? = nil) throws -> UUID {
        let span = SentryManager.shared.startTransaction(name: "storage.store_file", operation: "storage.store_file")
        span.setTag(value: "\(data.count / 1024)", key: "fileSizeKB")
        span.setTag(value: mimeType, key: "mimeType")

        ensureBlobReady()
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
        let encryptedFile = try CryptoEngine.shared.encryptFile(
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

        // Resolve write offset from global cursor vs vault's own nextOffset
        let globalCursor = readGlobalCursor()
        let writeOffset = max(globalCursor, index.nextOffset)

        #if DEBUG
        print("💾 [VaultStorage] globalCursor: \(globalCursor), index.nextOffset: \(index.nextOffset), writeOffset: \(writeOffset)")
        #endif

        // Check if we have space (usable region ends at cursorBlockOffset)
        guard writeOffset + fileSize <= cursorBlockOffset else {
            #if DEBUG
            print("❌ [VaultStorage] Insufficient space! writeOffset: \(writeOffset), fileSize: \(fileSize), limit: \(cursorBlockOffset)")
            #endif
            throw VaultStorageError.insufficientSpace
        }

        // Write to blob at resolved offset
        guard let handle = try? FileHandle(forWritingTo: blobURL) else {
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
            encryptedThumbnail = try? CryptoEngine.shared.encrypt(thumbnail, with: masterKey)
            #if DEBUG
            print("💾 [VaultStorage] Thumbnail encrypted with master key")
            #endif
        }

        // Update global cursor
        let newCursor = writeOffset + fileSize
        writeGlobalCursor(newCursor)

        // Update index
        let entry = VaultIndex.VaultFileEntry(
            fileId: encryptedFile.header.fileId,
            offset: writeOffset,
            size: fileSize,
            encryptedHeaderPreview: fileData.prefix(64),
            isDeleted: false,
            thumbnailData: encryptedThumbnail,
            mimeType: mimeType,
            filename: filename
        )
        index.files.append(entry)
        index.nextOffset = newCursor

        try saveIndex(index, with: key)

        span.finish(status: .ok)

        #if DEBUG
        print("✅ [VaultStorage] File stored successfully with ID: \(encryptedFile.header.fileId)")
        print("✅ [VaultStorage] New index: \(index.files.count) files, nextOffset: \(index.nextOffset)")
        #endif

        return encryptedFile.header.fileId
    }

    func retrieveFile(id: UUID, with key: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        let span = SentryManager.shared.startTransaction(name: "storage.retrieve_file", operation: "storage.retrieve_file")
        ensureBlobReady()
        let index = try loadIndex(with: key)
        
        // Get the master key for decrypting file data
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        guard let entry = index.files.first(where: { $0.fileId == id && !$0.isDeleted }) else {
            throw VaultStorageError.fileNotFound
        }

        // Read from blob
        guard let handle = try? FileHandle(forReadingFrom: blobURL) else {
            throw VaultStorageError.readError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(entry.offset))
        guard let encryptedData = try handle.read(upToCount: entry.size) else {
            throw VaultStorageError.readError
        }

        // Decrypt with MASTER KEY (not vault key)
        let result = try CryptoEngine.shared.decryptFile(data: encryptedData, with: masterKey)
        span.setTag(value: "\(entry.size / 1024)", key: "fileSizeKB")
        span.finish(status: .ok)
        return result
    }

    func deleteFile(id: UUID, with key: Data) throws {
        ensureBlobReady()
        var index = try loadIndex(with: key)

        guard let entryIndex = index.files.firstIndex(where: { $0.fileId == id && !$0.isDeleted }) else {
            throw VaultStorageError.fileNotFound
        }

        let entry = index.files[entryIndex]

        // Securely overwrite the file data with random bytes
        guard let handle = try? FileHandle(forWritingTo: blobURL) else {
            throw VaultStorageError.writeError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(entry.offset))
        if let randomData = CryptoEngine.shared.generateRandomBytes(count: entry.size) {
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
            filename: entry.filename
        )

        try saveIndex(index, with: key)
    }

    func listFiles(with key: Data) throws -> [VaultFileEntry] {
        let span = SentryManager.shared.startTransaction(name: "storage.list_files", operation: "storage.list_files")
        defer { span.finish(status: .ok) }
        let index = try loadIndex(with: key)
        
        // Get the master key for decrypting thumbnails
        let masterKey = try getMasterKey(from: index, vaultKey: key)
        
        return index.files.filter { !$0.isDeleted }.map { entry in
            // Decrypt thumbnail with MASTER KEY if available
            var decryptedThumbnail: Data? = nil
            if let encryptedThumb = entry.thumbnailData {
                decryptedThumbnail = try? CryptoEngine.shared.decrypt(encryptedThumb, with: masterKey)
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

    struct VaultFileEntry {
        let fileId: UUID
        let size: Int
        let thumbnailData: Data?
        let mimeType: String?
        let filename: String?
    }

    /// Lightweight file entry that keeps thumbnail data encrypted (no decryption at listing time).
    struct LightweightFileEntry {
        let fileId: UUID
        let size: Int
        let encryptedThumbnail: Data?
        let mimeType: String?
        let filename: String?
    }

    /// Returns the master key and file entries without decrypting thumbnails.
    /// Use this for lazy thumbnail loading — thumbnails are decrypted on-demand per cell.
    func listFilesLightweight(with key: Data) throws -> (masterKey: Data, files: [LightweightFileEntry]) {
        let span = SentryManager.shared.startTransaction(name: "storage.list_files_lightweight", operation: "storage.list_files_lightweight")
        defer { span.finish(status: .ok) }

        let index = try loadIndex(with: key)
        let masterKey = try getMasterKey(from: index, vaultKey: key)

        let entries = index.files.filter { !$0.isDeleted }.map { entry in
            LightweightFileEntry(
                fileId: entry.fileId,
                size: entry.size,
                encryptedThumbnail: entry.thumbnailData,
                mimeType: entry.mimeType,
                filename: entry.filename
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
        let newEncryptedMasterKey = try CryptoEngine.shared.encrypt(masterKey, with: newKey)
        
        #if DEBUG
        print("🔐 [VaultStorage] Master key re-encrypted with new vault key")
        #endif
        
        // 4. Create new index with re-encrypted master key
        let newIndex = VaultIndex(
            files: index.files,
            nextOffset: index.nextOffset,
            totalSize: index.totalSize,
            encryptedMasterKey: newEncryptedMasterKey,
            version: index.version
        )
        
        // 5. Save index with NEW vault key (creates new index file)
        try saveIndex(newIndex, with: newKey)
        
        #if DEBUG
        print("💾 [VaultStorage] New index saved with new vault key")
        #endif
        
        // 6. Delete old index file
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

    func destroyAllVaultData() {
        ensureBlobReady()
        #if DEBUG
        print("💣 [VaultStorage] Destroying all vault data!")
        #endif

        // Overwrite entire blob with random data
        do {
            let handle = try FileHandle(forWritingTo: blobURL)
            let chunkSize = 1024 * 1024
            var offset = 0

            while offset < defaultBlobSize {
                if let randomData = CryptoEngine.shared.generateRandomBytes(count: chunkSize) {
                    try? handle.seek(toOffset: UInt64(offset))
                    handle.write(randomData)
                }
                offset += chunkSize
            }
            try? handle.close()
        } catch {
            return
        }

        // Re-initialize global cursor to 0
        writeGlobalCursor(0)

        // Delete ALL index files (all vaults)
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

    /// Bytes consumed by vault data (based on global cursor position).
    var usedSpace: Int {
        readGlobalCursor()
    }

    /// Bytes remaining for new file writes.
    var availableSpace: Int {
        cursorBlockOffset - usedSpace
    }
}
