import XCTest
@testable import Vault

final class SharedVaultDataTests: XCTestCase {

    // MARK: - SharedFile

    func testSharedFileCodable() throws {
        let id = UUID()
        let file = SharedVaultData.SharedFile(
            id: id,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            size: 1024,
            encryptedContent: Data("encrypted".utf8),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            encryptedThumbnail: Data("thumb".utf8)
        )

        let encoded = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SharedVaultData.SharedFile.self, from: encoded)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.filename, "photo.jpg")
        XCTAssertEqual(decoded.mimeType, "image/jpeg")
        XCTAssertEqual(decoded.size, 1024)
        XCTAssertEqual(decoded.encryptedContent, Data("encrypted".utf8))
        XCTAssertEqual(decoded.encryptedThumbnail, Data("thumb".utf8))
    }

    func testSharedFileWithNilThumbnail() throws {
        let file = SharedVaultData.SharedFile(
            id: UUID(),
            filename: "doc.pdf",
            mimeType: "application/pdf",
            size: 2048,
            encryptedContent: Data("data".utf8),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            encryptedThumbnail: nil
        )

        let encoded = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SharedVaultData.SharedFile.self, from: encoded)

        XCTAssertNil(decoded.encryptedThumbnail)
        XCTAssertEqual(decoded.filename, "doc.pdf")
    }

    func testSharedFileIdentifiable() {
        let id = UUID()
        let file = SharedVaultData.SharedFile(
            id: id,
            filename: "test.txt",
            mimeType: "text/plain",
            size: 10,
            encryptedContent: Data(),
            createdAt: Date()
        )
        XCTAssertEqual(file.id, id)
    }

    // MARK: - SharedVaultMetadata

    func testSharedVaultMetadataCodable() throws {
        let meta = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "fingerprint-abc",
            sharedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoded = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(SharedVaultData.SharedVaultMetadata.self, from: encoded)

        XCTAssertEqual(decoded.ownerFingerprint, "fingerprint-abc")
        XCTAssertEqual(decoded.sharedAt.timeIntervalSince1970, 1700000000, accuracy: 0.001)
    }

    // MARK: - SharedVaultData

    func testSharedVaultDataCodable() throws {
        let file = SharedVaultData.SharedFile(
            id: UUID(),
            filename: "pic.png",
            mimeType: "image/png",
            size: 500,
            encryptedContent: Data("content".utf8),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            encryptedThumbnail: Data("t".utf8)
        )
        let meta = SharedVaultData.SharedVaultMetadata(
            ownerFingerprint: "fp",
            sharedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let vault = SharedVaultData(
            files: [file],
            metadata: meta,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            updatedAt: Date(timeIntervalSince1970: 1700000001)
        )

        let encoded = try JSONEncoder().encode(vault)
        let decoded = try JSONDecoder().decode(SharedVaultData.self, from: encoded)

        XCTAssertEqual(decoded.files.count, 1)
        XCTAssertEqual(decoded.files[0].filename, "pic.png")
        XCTAssertEqual(decoded.metadata.ownerFingerprint, "fp")
    }
}
