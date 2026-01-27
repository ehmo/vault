import Foundation

/// Secure deletion utilities that overwrite data before deletion.
final class SecureDelete {

    /// Number of overwrite passes for secure deletion.
    /// 1 pass is sufficient for modern storage, but we use 3 for extra security.
    static let overwritePasses = 3

    // MARK: - Secure File Deletion

    /// Securely deletes a file by overwriting it with random data before removal.
    static func deleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int, fileSize > 0 else {
            try FileManager.default.removeItem(at: url)
            return
        }

        // Overwrite file contents
        for pass in 0..<overwritePasses {
            guard let handle = try? FileHandle(forWritingTo: url) else {
                throw VaultStorageError.writeError
            }
            defer { try? handle.close() }

            try handle.seek(toOffset: 0)

            // Choose overwrite pattern based on pass
            let pattern: Data
            switch pass {
            case 0:
                pattern = Data(repeating: 0x00, count: fileSize) // Zeros
            case 1:
                pattern = Data(repeating: 0xFF, count: fileSize) // Ones
            default:
                pattern = CryptoEngine.shared.generateRandomBytes(count: fileSize) ?? Data(repeating: 0x55, count: fileSize)
            }

            handle.write(pattern)
            try handle.synchronize()
        }

        // Finally remove the file
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Secure Memory Clearing

    /// Securely clears a Data object by overwriting its bytes.
    static func clearData(_ data: inout Data) {
        data.resetBytes(in: 0..<data.count)
    }

    /// Securely clears an array of bytes.
    static func clearBytes(_ bytes: inout [UInt8]) {
        for i in 0..<bytes.count {
            bytes[i] = 0
        }
    }

    // MARK: - Secure Region Overwrite

    /// Overwrites a region of a file with random data.
    static func overwriteRegion(in fileURL: URL, offset: Int, length: Int) throws {
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw VaultStorageError.writeError
        }
        defer { try? handle.close() }

        for _ in 0..<overwritePasses {
            try handle.seek(toOffset: UInt64(offset))
            if let randomData = CryptoEngine.shared.generateRandomBytes(count: length) {
                handle.write(randomData)
                try handle.synchronize()
            }
        }
    }

    // MARK: - Secure Temporary File

    /// Creates a temporary file that will be securely deleted.
    final class SecureTemporaryFile {
        let url: URL
        private var isDeleted = false

        init() {
            let tempDir = FileManager.default.temporaryDirectory
            url = tempDir.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
                .protectionKey: FileProtectionType.complete
            ])
        }

        deinit {
            deleteSecurely()
        }

        func write(_ data: Data) throws {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        }

        func read() throws -> Data {
            try Data(contentsOf: url)
        }

        func deleteSecurely() {
            guard !isDeleted else { return }
            try? SecureDelete.deleteFile(at: url)
            isDeleted = true
        }
    }
}
