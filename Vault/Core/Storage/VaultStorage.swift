import Foundation

enum VaultStorageError: Error {
    case blobNotInitialized
    case writeError
    case readError
    case insufficientSpace
    case fileNotFound
    case corruptedData
}

final class VaultStorage {
    static let shared = VaultStorage()

    private let fileManager = FileManager.default
    private let blobFileName = "vault_data.bin"
    private let indexFileName = "vault_index.bin"

    // Pre-allocated blob size (500 MB)
    private let defaultBlobSize: Int = 500 * 1024 * 1024

    private var blobURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(blobFileName)
    }

    private var indexURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(indexFileName)
    }

    private init() {
        initializeBlobIfNeeded()
    }

    // MARK: - Blob Initialization

    private func initializeBlobIfNeeded() {
        guard !fileManager.fileExists(atPath: blobURL.path) else { return }

        // Create pre-allocated blob filled with random data
        createRandomBlob()
    }

    private func createRandomBlob() {
        // Create file with random data
        fileManager.createFile(atPath: blobURL.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.complete
        ])

        guard let handle = try? FileHandle(forWritingTo: blobURL) else { return }
        defer { try? handle.close() }

        // Write random data in chunks
        let chunkSize = 1024 * 1024 // 1 MB chunks
        let totalChunks = defaultBlobSize / chunkSize

        for _ in 0..<totalChunks {
            if let randomData = CryptoEngine.shared.generateRandomBytes(count: chunkSize) {
                handle.write(randomData)
            }
        }
    }

    // MARK: - Vault Index Management

    struct VaultIndex: Codable {
        var files: [VaultFileEntry]
        var nextOffset: Int
        var totalSize: Int

        struct VaultFileEntry: Codable {
            let fileId: UUID
            let offset: Int
            let size: Int
            let encryptedHeaderPreview: Data // First 64 bytes for quick lookup
            let isDeleted: Bool
        }
    }

    func loadIndex(with key: Data) throws -> VaultIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            // Return empty index for new vaults
            return VaultIndex(files: [], nextOffset: 0, totalSize: defaultBlobSize)
        }

        let encryptedData = try Data(contentsOf: indexURL)

        // Try to decrypt - if it fails, this key doesn't match any vault
        do {
            let decryptedData = try CryptoEngine.shared.decrypt(encryptedData, with: key)
            return try JSONDecoder().decode(VaultIndex.self, from: decryptedData)
        } catch {
            // Decryption failed - return empty index (appears as empty vault)
            return VaultIndex(files: [], nextOffset: 0, totalSize: defaultBlobSize)
        }
    }

    func saveIndex(_ index: VaultIndex, with key: Data) throws {
        let encoded = try JSONEncoder().encode(index)
        let encrypted = try CryptoEngine.shared.encrypt(encoded, with: key)

        try encrypted.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: - File Operations

    func storeFile(data: Data, filename: String, mimeType: String, with key: Data) throws -> UUID {
        var index = try loadIndex(with: key)

        // Encrypt the file
        let encryptedFile = try CryptoEngine.shared.encryptFile(
            data: data,
            filename: filename,
            mimeType: mimeType,
            with: key
        )

        let fileData = encryptedFile.encryptedContent
        let fileSize = fileData.count

        // Check if we have space
        guard index.nextOffset + fileSize <= index.totalSize else {
            throw VaultStorageError.insufficientSpace
        }

        // Write to blob at next available offset
        guard let handle = try? FileHandle(forWritingTo: blobURL) else {
            throw VaultStorageError.writeError
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(index.nextOffset))
        handle.write(fileData)

        // Update index
        let entry = VaultIndex.VaultFileEntry(
            fileId: encryptedFile.header.fileId,
            offset: index.nextOffset,
            size: fileSize,
            encryptedHeaderPreview: fileData.prefix(64),
            isDeleted: false
        )
        index.files.append(entry)
        index.nextOffset += fileSize

        try saveIndex(index, with: key)

        return encryptedFile.header.fileId
    }

    func retrieveFile(id: UUID, with key: Data) throws -> (header: CryptoEngine.EncryptedFileHeader, content: Data) {
        let index = try loadIndex(with: key)

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

        // Decrypt
        return try CryptoEngine.shared.decryptFile(data: encryptedData, with: key)
    }

    func deleteFile(id: UUID, with key: Data) throws {
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
            isDeleted: true
        )

        try saveIndex(index, with: key)
    }

    func listFiles(with key: Data) throws -> [VaultFileEntry] {
        let index = try loadIndex(with: key)
        return index.files.filter { !$0.isDeleted }.map { entry in
            VaultFileEntry(fileId: entry.fileId, size: entry.size)
        }
    }

    struct VaultFileEntry {
        let fileId: UUID
        let size: Int
    }

    // MARK: - Vault Destruction (for duress)

    func destroyAllVaultData() {
        // Overwrite entire blob with random data
        guard let handle = try? FileHandle(forWritingTo: blobURL) else { return }
        defer { try? handle.close() }

        let chunkSize = 1024 * 1024
        var offset = 0

        while offset < defaultBlobSize {
            if let randomData = CryptoEngine.shared.generateRandomBytes(count: chunkSize) {
                try? handle.seek(toOffset: UInt64(offset))
                handle.write(randomData)
            }
            offset += chunkSize
        }

        // Delete index files
        try? fileManager.removeItem(at: indexURL)
    }

    // MARK: - Storage Info

    var usedSpace: Int {
        guard fileManager.fileExists(atPath: blobURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: blobURL.path),
              let size = attributes[.size] as? Int else {
            return 0
        }
        return size
    }

    var availableSpace: Int {
        defaultBlobSize - usedSpace
    }
}
