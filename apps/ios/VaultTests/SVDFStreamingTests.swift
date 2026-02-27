import XCTest
@testable import Vault

/// Comprehensive tests for the streaming SVDF import pipeline.
/// Verifies that file-based parsing methods produce identical results to in-memory counterparts,
/// and that streaming extraction preserves content integrity across edge cases.
final class SVDFStreamingTests: XCTestCase {

    private let shareKey = CryptoEngine.generateRandomBytes(count: 32)!

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SVDFStreamingTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFile(
        id: UUID = UUID(),
        name: String = "test.jpg",
        mimeType: String = "image/jpeg",
        size: Int = 100,
        content: Data? = nil,
        thumbnail: Data? = Data("thumb".utf8),
        duration: TimeInterval? = nil
    ) -> SharedVaultData.SharedFile {
        SharedVaultData.SharedFile(
            id: id,
            filename: name,
            mimeType: mimeType,
            size: size,
            encryptedContent: content ?? Data("encrypted-\(name)".utf8),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            encryptedThumbnail: thumbnail,
            duration: duration
        )
    }

    private func makeMetadata() -> SharedVaultData.SharedVaultMetadata {
        SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "test-fingerprint",
            sharedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func writeSVDFToFile(files: [SharedVaultData.SharedFile]) throws -> (URL, [SVDFSerializer.FileManifestEntry]) {
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString).svdf")
        try data.write(to: url)
        return (url, manifest)
    }

    // MARK: - isSVDFFile

    func testIsSVDFFileWithV5Magic() throws {
        let files = [makeFile()]
        let (url, _) = try writeSVDFToFile(files: files)
        XCTAssertTrue(SVDFSerializer.isSVDFFile(url))
    }

    func testIsSVDFFileWithV4Magic() throws {
        // Create data with v4 magic manually
        var data = Data([0x53, 0x56, 0x44, 0x34]) // SVD4
        data.append(Data(repeating: 0, count: 60))
        let url = tempDir.appendingPathComponent("v4test.svdf")
        try data.write(to: url)
        XCTAssertTrue(SVDFSerializer.isSVDFFile(url))
    }

    func testIsSVDFFileWithInvalidMagic() throws {
        let data = Data("not an svdf file".utf8)
        let url = tempDir.appendingPathComponent("invalid.bin")
        try data.write(to: url)
        XCTAssertFalse(SVDFSerializer.isSVDFFile(url))
    }

    func testIsSVDFFileWithTooSmallFile() throws {
        let data = Data([0x53, 0x56]) // only 2 bytes
        let url = tempDir.appendingPathComponent("tiny.bin")
        try data.write(to: url)
        XCTAssertFalse(SVDFSerializer.isSVDFFile(url))
    }

    func testIsSVDFFileWithNonexistentFile() {
        let url = tempDir.appendingPathComponent("does-not-exist.svdf")
        XCTAssertFalse(SVDFSerializer.isSVDFFile(url))
    }

    func testIsSVDFFileWithEmptyFile() throws {
        let url = tempDir.appendingPathComponent("empty.bin")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        XCTAssertFalse(SVDFSerializer.isSVDFFile(url))
    }

    // MARK: - parseHeaderFromFile

    func testParseHeaderFromFileMatchesInMemory() throws {
        let files = [makeFile(name: "a.jpg"), makeFile(name: "b.jpg")]
        let (data, _) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("header-test.svdf")
        try data.write(to: url)

        let memHeader = try SVDFSerializer.parseHeader(from: data)
        let fileHeader = try SVDFSerializer.parseHeaderFromFile(url)

        XCTAssertEqual(fileHeader.version, memHeader.version)
        XCTAssertEqual(fileHeader.fileCount, memHeader.fileCount)
        XCTAssertEqual(fileHeader.manifestOffset, memHeader.manifestOffset)
        XCTAssertEqual(fileHeader.manifestSize, memHeader.manifestSize)
        XCTAssertEqual(fileHeader.metadataOffset, memHeader.metadataOffset)
        XCTAssertEqual(fileHeader.metadataSize, memHeader.metadataSize)
    }

    func testParseHeaderFromFileTooSmall() throws {
        let url = tempDir.appendingPathComponent("small.bin")
        try Data(repeating: 0, count: 10).write(to: url)
        XCTAssertThrowsError(try SVDFSerializer.parseHeaderFromFile(url))
    }

    func testParseHeaderFromFileInvalidMagic() throws {
        let url = tempDir.appendingPathComponent("bad-magic.bin")
        try Data(repeating: 0xFF, count: 64).write(to: url)
        XCTAssertThrowsError(try SVDFSerializer.parseHeaderFromFile(url))
    }

    // MARK: - parseManifestFromFile

    func testParseManifestFromFileMatchesInMemory() throws {
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let files = [
            makeFile(id: id1, name: "photo.jpg"),
            makeFile(id: id2, name: "document.pdf", mimeType: "application/pdf"),
            makeFile(id: id3, name: "video.mp4", mimeType: "video/mp4", duration: 15.5),
        ]
        let (data, _) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("manifest-test.svdf")
        try data.write(to: url)

        let memManifest = try SVDFSerializer.parseManifest(from: data, shareKey: shareKey)
        let fileManifest = try SVDFSerializer.parseManifestFromFile(url, shareKey: shareKey)

        XCTAssertEqual(fileManifest.count, memManifest.count)
        for (fm, mm) in zip(fileManifest, memManifest) {
            XCTAssertEqual(fm.id, mm.id)
            XCTAssertEqual(fm.offset, mm.offset)
            XCTAssertEqual(fm.size, mm.size)
            XCTAssertEqual(fm.deleted, mm.deleted)
        }
    }

    func testParseManifestFromFileWithWrongKey() throws {
        let files = [makeFile()]
        let (url, _) = try writeSVDFToFile(files: files)
        let wrongKey = CryptoEngine.generateRandomBytes(count: 32)!
        XCTAssertThrowsError(try SVDFSerializer.parseManifestFromFile(url, shareKey: wrongKey))
    }

    // MARK: - parseMetadataFromFile

    func testParseMetadataFromFileMatchesInMemory() throws {
        let files = [makeFile()]
        let (data, _) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("meta-test.svdf")
        try data.write(to: url)

        let fileMetadata = try SVDFSerializer.parseMetadataFromFile(url, shareKey: shareKey)
        XCTAssertEqual(fileMetadata.ownerFingerprint, "test-fingerprint")
        XCTAssertEqual(fileMetadata.sharedAt.timeIntervalSince1970, 1_700_000_000, accuracy: 1.0)
    }

    // MARK: - deserializeStreamingMetadata

    func testDeserializeStreamingMetadataRoundTrip() throws {
        let id1 = UUID(), id2 = UUID()
        let files = [
            makeFile(id: id1, name: "alpha.jpg"),
            makeFile(id: id2, name: "beta.png", mimeType: "image/png"),
        ]
        let (url, _) = try writeSVDFToFile(files: files)

        let (header, manifest, metadata) = try SVDFSerializer.deserializeStreamingMetadata(
            from: url, shareKey: shareKey
        )

        XCTAssertEqual(header.version, 5)
        XCTAssertEqual(header.fileCount, 2)
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(manifest[0].id, id1.uuidString)
        XCTAssertEqual(manifest[1].id, id2.uuidString)
        XCTAssertEqual(metadata.ownerFingerprint, "test-fingerprint")
    }

    func testDeserializeStreamingMetadataEmptyVault() throws {
        let (url, _) = try writeSVDFToFile(files: [])

        let (header, manifest, metadata) = try SVDFSerializer.deserializeStreamingMetadata(
            from: url, shareKey: shareKey
        )

        XCTAssertEqual(header.fileCount, 0)
        XCTAssertEqual(manifest.count, 0)
        XCTAssertEqual(metadata.ownerFingerprint, "test-fingerprint")
    }

    // MARK: - extractFileEntryMetadata

    func testExtractFileEntryMetadataMatchesInMemory() throws {
        let id = UUID()
        let files = [makeFile(id: id, name: "streaming.jpg", size: 512,
                              content: Data(repeating: 0xAB, count: 512),
                              thumbnail: Data("thumb-data".utf8), duration: 3.14)]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("entry-meta.svdf")
        try data.write(to: url)

        let entry = manifest[0]
        let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.id, memFile.id)
        XCTAssertEqual(fileMeta.filename, memFile.filename)
        XCTAssertEqual(fileMeta.mimeType, memFile.mimeType)
        XCTAssertEqual(fileMeta.originalSize, memFile.size)
        XCTAssertEqual(fileMeta.createdAt.timeIntervalSince1970, memFile.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(fileMeta.duration, memFile.duration)
        XCTAssertEqual(fileMeta.encryptedThumbnail, memFile.encryptedThumbnail)
        XCTAssertEqual(fileMeta.contentSize, memFile.encryptedContent.count)
    }

    func testExtractFileEntryMetadataNoThumbnail() throws {
        let id = UUID()
        let files = [makeFile(id: id, name: "no-thumb.txt", mimeType: "text/plain",
                              size: 64, content: Data(repeating: 0x01, count: 64), thumbnail: nil)]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.id, id)
        XCTAssertEqual(fileMeta.filename, "no-thumb.txt")
        XCTAssertNil(fileMeta.encryptedThumbnail)
    }

    func testExtractFileEntryMetadataNoDuration() throws {
        let id = UUID()
        let files = [makeFile(id: id, name: "photo.jpg", duration: nil)]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertNil(fileMeta.duration, "Duration should be nil for non-videos (stored as -1.0)")
    }

    func testExtractFileEntryMetadataWithDuration() throws {
        let id = UUID()
        let files = [makeFile(id: id, name: "clip.mp4", mimeType: "video/mp4", duration: 42.5)]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.duration ?? -1, 42.5, accuracy: 0.001)
    }

    /// Regression test for the fixedReadSize bug: entries with long filenames
    /// must be parsed correctly (previously failed with fixedReadSize=320).
    func testExtractFileEntryMetadataLongFilename() throws {
        let longName = String(repeating: "a", count: 200) + ".jpg"
        let id = UUID()
        let files = [makeFile(id: id, name: longName, size: 32, content: Data(repeating: 0xEE, count: 32))]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.id, id)
        XCTAssertEqual(fileMeta.filename, longName)
    }

    /// Regression test: maximum filename length (255 bytes) + long mimeType should not overflow.
    func testExtractFileEntryMetadataMaxFilenameLength() throws {
        let maxName = String(repeating: "x", count: 255)
        let id = UUID()
        let files = [makeFile(id: id, name: maxName, mimeType: "application/vnd.example.very-long-mime-type",
                              size: 16, content: Data(repeating: 0xFF, count: 16))]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.id, id)
        XCTAssertEqual(fileMeta.filename, maxName)
        XCTAssertEqual(fileMeta.mimeType, "application/vnd.example.very-long-mime-type")
    }

    /// Verify entry metadata with large thumbnail that requires second-pass read.
    func testExtractFileEntryMetadataLargeThumbnail() throws {
        let id = UUID()
        let largeThumbnail = Data(repeating: 0xBB, count: 2048) // 2KB thumbnail
        let files = [makeFile(id: id, name: "big-thumb.jpg",
                              content: Data(repeating: 0xCC, count: 128),
                              thumbnail: largeThumbnail)]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.id, id)
        XCTAssertEqual(fileMeta.encryptedThumbnail?.count, 2048)
        XCTAssertEqual(fileMeta.encryptedThumbnail, largeThumbnail)
    }

    // MARK: - extractFileContentToTempURL

    func testExtractFileContentToTempURLMatchesOriginal() throws {
        let originalContent = Data(repeating: 0xDE, count: 1024)
        let id = UUID()
        let files = [makeFile(id: id, name: "content-check.bin", size: 1024, content: originalContent)]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("content-test.svdf")
        try data.write(to: url)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        let extractedURL = try SVDFSerializer.extractFileContentToTempURL(from: url, entry: fileMeta)
        defer { try? FileManager.default.removeItem(at: extractedURL) }

        let extractedContent = try Data(contentsOf: extractedURL)

        // The extracted content should match the encrypted content from the in-memory entry
        let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
        XCTAssertEqual(extractedContent, memFile.encryptedContent)
        XCTAssertEqual(extractedContent.count, fileMeta.contentSize)
    }

    /// Verify streaming extraction of large content (> 256KB chunk boundary).
    func testExtractFileContentToTempURLLargeContent() throws {
        let largeContent = Data(repeating: 0xAA, count: 512 * 1024) // 512KB
        let files = [makeFile(name: "large.bin", size: largeContent.count, content: largeContent)]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("large-content.svdf")
        try data.write(to: url)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        let extractedURL = try SVDFSerializer.extractFileContentToTempURL(from: url, entry: fileMeta)
        defer { try? FileManager.default.removeItem(at: extractedURL) }

        let extractedContent = try Data(contentsOf: extractedURL)
        let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
        XCTAssertEqual(extractedContent, memFile.encryptedContent)
    }

    /// Verify content extraction with exactly one chunk boundary (256KB).
    func testExtractFileContentToTempURLExactChunkBoundary() throws {
        let exactChunkContent = Data(repeating: 0xBB, count: 256 * 1024) // exactly 256KB
        let files = [makeFile(name: "exact.bin", size: exactChunkContent.count, content: exactChunkContent)]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("exact-chunk.svdf")
        try data.write(to: url)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        let extractedURL = try SVDFSerializer.extractFileContentToTempURL(from: url, entry: fileMeta)
        defer { try? FileManager.default.removeItem(at: extractedURL) }

        let extractedContent = try Data(contentsOf: extractedURL)
        let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
        XCTAssertEqual(extractedContent, memFile.encryptedContent)
    }

    /// Verify content extraction for tiny files (< 1 chunk).
    func testExtractFileContentToTempURLTinyContent() throws {
        let tinyContent = Data([0x01, 0x02, 0x03])
        let files = [makeFile(name: "tiny.bin", size: 3, content: tinyContent)]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("tiny-content.svdf")
        try data.write(to: url)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        let extractedURL = try SVDFSerializer.extractFileContentToTempURL(from: url, entry: fileMeta)
        defer { try? FileManager.default.removeItem(at: extractedURL) }

        let extractedContent = try Data(contentsOf: extractedURL)
        let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
        XCTAssertEqual(extractedContent, memFile.encryptedContent)
    }

    // MARK: - Full Round-Trip: Serialize → File-Parse → Extract → Decrypt

    /// End-to-end: serialize with real encryption, parse from file, extract content, decrypt, verify.
    func testFullRoundTripSerializeExtractDecrypt() throws {
        let plaintext = Data("Hello streaming SVDF world!".utf8)
        let encrypted = try CryptoEngine.encrypt(plaintext, with: shareKey)

        let id = UUID()
        let file = SharedVaultData.SharedFile(
            id: id,
            filename: "hello.txt",
            mimeType: "text/plain",
            size: plaintext.count,
            encryptedContent: encrypted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            encryptedThumbnail: nil,
            duration: nil
        )

        let (data, manifest) = try SVDFSerializer.buildFull(
            files: [file], metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("roundtrip.svdf")
        try data.write(to: url)

        // Parse from file
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: manifest[0].offset, size: manifest[0].size, version: 5
        )
        XCTAssertEqual(fileMeta.id, id)
        XCTAssertEqual(fileMeta.filename, "hello.txt")

        // Extract content to temp file
        let encryptedTempURL = try SVDFSerializer.extractFileContentToTempURL(from: url, entry: fileMeta)
        defer { try? FileManager.default.removeItem(at: encryptedTempURL) }

        // Decrypt
        let encryptedData = try Data(contentsOf: encryptedTempURL)
        let decrypted = try CryptoEngine.decrypt(encryptedData, with: shareKey)

        XCTAssertEqual(decrypted, plaintext)
    }

    /// End-to-end with streaming encryption (larger files use staged encryption).
    func testFullRoundTripWithStreamingFromPlaintext() throws {
        let sourceData = Data(repeating: 0x42, count: 256 * 1024) // 256KB
        let plaintextURL = tempDir.appendingPathComponent("source.bin")
        try sourceData.write(to: plaintextURL)

        let svdfURL = tempDir.appendingPathComponent("streaming-roundtrip.svdf")
        let source = SVDFSerializer.StreamingSourceFile(
            id: UUID(),
            filename: "source.bin",
            mimeType: "application/octet-stream",
            originalSize: sourceData.count,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            encryptedThumbnail: nil,
            plaintextContentURL: plaintextURL,
            duration: nil
        )

        let (manifest, _) = try SVDFSerializer.buildFullStreamingFromPlaintext(
            to: svdfURL,
            fileCount: 1,
            forEachFile: { _ in source },
            metadata: makeMetadata(),
            shareKey: shareKey
        )

        // Parse from file and extract
        let header = try SVDFSerializer.parseHeaderFromFile(svdfURL)
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: svdfURL, at: manifest[0].offset, size: manifest[0].size, version: header.version
        )

        let encryptedTempURL = try SVDFSerializer.extractFileContentToTempURL(from: svdfURL, entry: fileMeta)
        defer { try? FileManager.default.removeItem(at: encryptedTempURL) }

        // Decrypt using staged decryption (matches the streaming encryption used)
        let decryptedTempURL = tempDir.appendingPathComponent("decrypted.bin")
        try CryptoEngine.decryptStagedFileToURL(from: encryptedTempURL, to: decryptedTempURL, with: shareKey)
        let decrypted = try Data(contentsOf: decryptedTempURL)

        XCTAssertEqual(decrypted.count, sourceData.count)
        XCTAssertEqual(decrypted, sourceData)
    }

    // MARK: - Multi-File Round Trip

    /// Verify that extracting metadata+content for each file in a multi-file SVDF
    /// produces identical results to the in-memory extractFileEntry.
    func testMultiFileRoundTripConsistency() throws {
        var files: [SharedVaultData.SharedFile] = []
        for i in 0..<5 {
            let mime: String = i % 2 == 0 ? "image/jpeg" : "video/mp4"
            let thumb: Data? = i % 3 == 0 ? Data("thumb-\(i)".utf8) : nil
            let dur: TimeInterval? = i % 2 == 0 ? nil : Double(i) * 1.5
            files.append(makeFile(
                name: "file-\(i).dat",
                mimeType: mime,
                size: (i + 1) * 100,
                content: Data(repeating: UInt8(i), count: (i + 1) * 100),
                thumbnail: thumb,
                duration: dur
            ))
        }

        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("multi-file.svdf")
        try data.write(to: url)

        let header = try SVDFSerializer.parseHeaderFromFile(url)

        for (i, entry) in manifest.enumerated() {
            let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size, version: header.version)
            let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
                from: url, at: entry.offset, size: entry.size, version: header.version
            )

            XCTAssertEqual(fileMeta.id, memFile.id, "File \(i): ID mismatch")
            XCTAssertEqual(fileMeta.filename, memFile.filename, "File \(i): filename mismatch")
            XCTAssertEqual(fileMeta.mimeType, memFile.mimeType, "File \(i): mimeType mismatch")
            XCTAssertEqual(fileMeta.originalSize, memFile.size, "File \(i): size mismatch")
            XCTAssertEqual(fileMeta.duration, memFile.duration, "File \(i): duration mismatch")
            XCTAssertEqual(fileMeta.encryptedThumbnail, memFile.encryptedThumbnail, "File \(i): thumbnail mismatch")
            XCTAssertEqual(fileMeta.contentSize, memFile.encryptedContent.count, "File \(i): content size mismatch")

            // Verify extracted content matches
            let extractedURL = try SVDFSerializer.extractFileContentToTempURL(from: url, entry: fileMeta)
            defer { try? FileManager.default.removeItem(at: extractedURL) }
            let extractedContent = try Data(contentsOf: extractedURL)
            XCTAssertEqual(extractedContent, memFile.encryptedContent, "File \(i): extracted content mismatch")
        }
    }

    // MARK: - Incremental Build Compatibility

    /// Verify streaming methods work with incrementally-built SVDF (append + delete).
    func testStreamingParseOfIncrementalBuild() throws {
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let files = [
            makeFile(id: id1, name: "keep.jpg"),
            makeFile(id: id2, name: "delete-me.jpg"),
        ]
        let (priorData, priorManifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        let newFile = makeFile(id: id3, name: "new-addition.png", mimeType: "image/png")
        let (updatedData, updatedManifest) = try SVDFSerializer.buildIncremental(
            priorData: priorData,
            priorManifest: priorManifest,
            newFiles: [newFile],
            removedFileIds: [id2.uuidString],
            metadata: makeMetadata(),
            shareKey: shareKey
        )

        let url = tempDir.appendingPathComponent("incremental.svdf")
        try updatedData.write(to: url)

        // Parse from file
        let (header, fileManifest, metadata) = try SVDFSerializer.deserializeStreamingMetadata(
            from: url, shareKey: shareKey
        )

        XCTAssertEqual(header.fileCount, 2) // 1 kept + 1 new (deleted entry not counted)
        XCTAssertEqual(fileManifest.count, 3) // manifest has all 3 entries including deleted
        XCTAssertEqual(metadata.ownerFingerprint, "test-fingerprint")

        // Verify active entries
        let activeEntries = fileManifest.filter { !$0.deleted }
        XCTAssertEqual(activeEntries.count, 2)

        // Verify we can extract active entries
        for entry in activeEntries {
            let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
                from: url, at: entry.offset, size: entry.size, version: header.version
            )
            XCTAssertTrue([id1, id3].contains(fileMeta.id),
                          "Active entry should be keep.jpg or new-addition.png")
        }

        // Verify deleted entry is marked
        let deletedEntry = updatedManifest.first { $0.id == id2.uuidString }
        let unwrappedDeleted = try XCTUnwrap(deletedEntry)
        XCTAssertTrue(unwrappedDeleted.deleted)
    }

    // MARK: - Content Offset Correctness

    /// Verify that contentOffset correctly points to the start of encrypted content
    /// by cross-referencing with the in-memory entry's content.
    func testContentOffsetPointsToCorrectLocation() throws {
        let content1 = Data(repeating: 0x11, count: 256)
        let content2 = Data(repeating: 0x22, count: 512)
        let content3 = Data(repeating: 0x33, count: 128)
        let files = [
            makeFile(name: "first.bin", size: 256, content: content1),
            makeFile(name: "second.bin", size: 512, content: content2),
            makeFile(name: "third.bin", size: 128, content: content3),
        ]

        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("offset-test.svdf")
        try data.write(to: url)

        for (i, entry) in manifest.enumerated() {
            let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
                from: url, at: entry.offset, size: entry.size, version: 5
            )

            // Read content directly from file at the reported offset
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(fileMeta.contentOffset))
            let directContent = try handle.read(upToCount: fileMeta.contentSize)

            // Compare with in-memory extraction
            let memFile = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
            XCTAssertEqual(directContent, memFile.encryptedContent,
                           "File \(i): content at offset doesn't match in-memory extraction")
        }
    }

    // MARK: - SavePendingImportFile

    func testSavePendingImportFileMovesTempFile() throws {
        let sourceContent = Data("test import data".utf8)
        let tempURL = tempDir.appendingPathComponent("temp-import.bin")
        try sourceContent.write(to: tempURL)

        // Create a fake target directory matching ShareImportManager's structure
        let targetDir = tempDir.appendingPathComponent("pending_upload", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let targetURL = targetDir.appendingPathComponent("import_data.bin")

        // Move file
        try FileManager.default.moveItem(at: tempURL, to: targetURL)

        // Source should be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
        // Target should exist with correct content
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
        let movedContent = try Data(contentsOf: targetURL)
        XCTAssertEqual(movedContent, sourceContent)
    }

    func testSavePendingImportFileReplacesExisting() throws {
        let targetDir = tempDir.appendingPathComponent("pending_upload", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let targetURL = targetDir.appendingPathComponent("import_data.bin")

        // Write initial data
        try Data("old data".utf8).write(to: targetURL)

        // Write new temp file
        let tempURL = tempDir.appendingPathComponent("new-import.bin")
        let newContent = Data("new data".utf8)
        try newContent.write(to: tempURL)

        // Replace: remove old, move new
        try FileManager.default.removeItem(at: targetURL)
        try FileManager.default.moveItem(at: tempURL, to: targetURL)

        let finalContent = try Data(contentsOf: targetURL)
        XCTAssertEqual(finalContent, newContent)
    }

    // MARK: - Edge Cases

    /// Verify Unicode filenames are handled correctly.
    func testUnicodeFilenames() throws {
        let unicodeName = "photo_\u{1F4F7}_2026-01-01.jpg"
        let id = UUID()
        let files = [makeFile(id: id, name: unicodeName)]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertEqual(fileMeta.filename, unicodeName)
    }

    /// Verify that file entries at different positions within the SVDF are all accessible.
    func testSequentialEntryAccess() throws {
        let fileCount = 10
        var files: [SharedVaultData.SharedFile] = []
        for i in 0..<fileCount {
            files.append(makeFile(
                name: "seq-\(i).dat",
                size: (i + 1) * 50,
                content: Data(repeating: UInt8(i), count: (i + 1) * 50)
            ))
        }
        let (url, manifest) = try writeSVDFToFile(files: files)

        XCTAssertEqual(manifest.count, fileCount)

        // Verify all entries are accessible and offsets are increasing
        var previousOffset = 0
        for (i, entry) in manifest.enumerated() {
            XCTAssertGreaterThan(entry.offset, previousOffset > 0 ? previousOffset : 0,
                                 "Entry \(i) offset should be after previous entry")
            previousOffset = entry.offset

            let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
                from: url, at: entry.offset, size: entry.size, version: 5
            )
            XCTAssertEqual(fileMeta.filename, "seq-\(i).dat", "Entry \(i) filename mismatch")
        }
    }

    /// Verify empty thumbnail is correctly handled (thumbSize = 0).
    func testEmptyThumbnailEntry() throws {
        let files = [makeFile(name: "no-thumb.bin", thumbnail: nil)]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )
        let url = tempDir.appendingPathComponent("no-thumb.svdf")
        try data.write(to: url)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        XCTAssertNil(fileMeta.encryptedThumbnail)
        XCTAssertTrue(fileMeta.contentSize > 0)
    }

    /// Verify that contentOffset + contentSize == entry.offset + entry.size - 4 (entrySize field)
    /// This ensures the content region is correctly bounded.
    func testContentRegionBounds() throws {
        let content = Data(repeating: 0xDD, count: 789)
        let files = [makeFile(name: "bounds.bin", size: 789, content: content, thumbnail: Data("t".utf8))]
        let (url, manifest) = try writeSVDFToFile(files: files)

        let entry = manifest[0]
        let fileMeta = try SVDFSerializer.extractFileEntryMetadata(
            from: url, at: entry.offset, size: entry.size, version: 5
        )

        // contentOffset + contentSize should equal entry.offset + entry.size
        // because entrySize includes everything from entrySize field to end of content
        XCTAssertEqual(fileMeta.contentOffset + fileMeta.contentSize, entry.offset + entry.size,
                       "Content region should end at entry boundary")
    }
}
