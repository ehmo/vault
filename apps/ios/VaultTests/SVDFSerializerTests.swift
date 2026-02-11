import XCTest
@testable import Vault

final class SVDFSerializerTests: XCTestCase {

    private let shareKey = CryptoEngine.generateRandomBytes(count: 32)!

    private func makeFile(id: UUID = UUID(), name: String = "test.jpg", content: Data? = nil) -> SharedVaultData.SharedFile {
        SharedVaultData.SharedFile(
            id: id,
            filename: name,
            mimeType: "image/jpeg",
            size: 100,
            encryptedContent: content ?? Data("encrypted-\(name)".utf8),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            encryptedThumbnail: Data("thumb".utf8)
        )
    }

    private func makeMetadata() -> SharedVaultData.SharedVaultMetadata {
        SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "abc123",
            sharedAt: Date(timeIntervalSince1970: 1700000000)
        )
    }

    // MARK: - Build Full

    func testBuildFullAndParseHeader() throws {
        let files = [makeFile(name: "a.jpg"), makeFile(name: "b.jpg")]
        let (data, _) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        let header = try SVDFSerializer.parseHeader(from: data)
        XCTAssertEqual(header.version, 4)
        XCTAssertEqual(header.fileCount, 2)
        XCTAssertTrue(header.manifestOffset > 0)
        XCTAssertTrue(header.manifestSize > 0)
        XCTAssertTrue(header.metadataOffset > header.manifestOffset)
    }

    func testBuildFullManifest() throws {
        let id1 = UUID(), id2 = UUID()
        let files = [makeFile(id: id1, name: "a.jpg"), makeFile(id: id2, name: "b.jpg")]
        let (data, _) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        let manifest = try SVDFSerializer.parseManifest(from: data, shareKey: shareKey)
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(manifest[0].id, id1.uuidString)
        XCTAssertEqual(manifest[1].id, id2.uuidString)
        XCTAssertFalse(manifest[0].deleted)
    }

    // MARK: - Magic Bytes

    func testIsSVDF() {
        let validMagic = Data([0x53, 0x56, 0x44, 0x34]) + Data(repeating: 0, count: 60)
        XCTAssertTrue(SVDFSerializer.isSVDF(validMagic))

        let invalidMagic = Data([0x00, 0x00, 0x00, 0x00])
        XCTAssertFalse(SVDFSerializer.isSVDF(invalidMagic))

        let tooShort = Data([0x53, 0x56])
        XCTAssertFalse(SVDFSerializer.isSVDF(tooShort))
    }

    // MARK: - Extract File Entry

    func testExtractFileEntry() throws {
        let id = UUID()
        let files = [makeFile(id: id, name: "extract-me.jpg")]
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        let entry = manifest[0]
        let file = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
        XCTAssertEqual(file.id, id)
        XCTAssertEqual(file.filename, "extract-me.jpg")
        XCTAssertEqual(file.mimeType, "image/jpeg")
    }

    // MARK: - Incremental Append

    func testBuildIncrementalAppend() throws {
        let files = [makeFile(name: "a.jpg"), makeFile(name: "b.jpg")]
        let (priorData, priorManifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        let newFile = makeFile(name: "c.jpg")
        let (updatedData, updatedManifest) = try SVDFSerializer.buildIncremental(
            priorData: priorData,
            priorManifest: priorManifest,
            newFiles: [newFile],
            removedFileIds: [],
            metadata: makeMetadata(),
            shareKey: shareKey
        )

        XCTAssertEqual(updatedManifest.count, 3)
        let header = try SVDFSerializer.parseHeader(from: updatedData)
        XCTAssertEqual(header.fileCount, 3)
    }

    // MARK: - Incremental Delete

    func testBuildIncrementalDelete() throws {
        let id1 = UUID(), id2 = UUID()
        let files = [makeFile(id: id1, name: "a.jpg"), makeFile(id: id2, name: "b.jpg")]
        let (priorData, priorManifest) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        let (updatedData, updatedManifest) = try SVDFSerializer.buildIncremental(
            priorData: priorData,
            priorManifest: priorManifest,
            newFiles: [],
            removedFileIds: [id1.uuidString],
            metadata: makeMetadata(),
            shareKey: shareKey
        )

        XCTAssertTrue(updatedManifest[0].deleted)
        XCTAssertFalse(updatedManifest[1].deleted)
        let header = try SVDFSerializer.parseHeader(from: updatedData)
        XCTAssertEqual(header.fileCount, 1) // active count
    }

    // MARK: - Header Field Offsets

    func testHeaderFieldOffsets() throws {
        let files = [makeFile()]
        let (data, _) = try SVDFSerializer.buildFull(
            files: files, metadata: makeMetadata(), shareKey: shareKey
        )

        // Verify magic at bytes 0-3
        XCTAssertEqual(data[0], 0x53) // S
        XCTAssertEqual(data[1], 0x56) // V
        XCTAssertEqual(data[2], 0x44) // D
        XCTAssertEqual(data[3], 0x34) // 4

        let header = try SVDFSerializer.parseHeader(from: data)
        XCTAssertEqual(header.version, SVDFSerializer.currentVersion)
        XCTAssertTrue(header.manifestOffset >= UInt64(SVDFSerializer.headerSize))
        XCTAssertTrue(header.metadataOffset > header.manifestOffset)
    }

    // MARK: - Empty Files

    func testEmptyFilesArray() throws {
        let (data, manifest) = try SVDFSerializer.buildFull(
            files: [], metadata: makeMetadata(), shareKey: shareKey
        )

        XCTAssertTrue(SVDFSerializer.isSVDF(data))
        XCTAssertEqual(manifest.count, 0)
        let header = try SVDFSerializer.parseHeader(from: data)
        XCTAssertEqual(header.fileCount, 0)
    }
}
