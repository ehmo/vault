import XCTest
@testable import Vault

final class SecureDeleteTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func createTempFile(name: String = "test.bin", contents: Data) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    // MARK: - deleteFile

    func testDeleteFileOverwritesBeforeRemoval() throws {
        let data = Data(repeating: 0xAB, count: 1024)
        let url = try createTempFile(contents: data)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try SecureDelete.deleteFile(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                        "File should be removed after secure deletion")
    }

    func testDeleteFileWithZeroLengthFile() throws {
        let url = try createTempFile(contents: Data())

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Should not throw for zero-length files
        try SecureDelete.deleteFile(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                        "Zero-length file should be deleted without error")
    }

    func testDeleteNonExistentFileDoesNotThrow() {
        let nonExistentURL = tempDir.appendingPathComponent("does_not_exist.bin")

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentURL.path))

        // The implementation guards on file existence and returns early
        XCTAssertNoThrow(try SecureDelete.deleteFile(at: nonExistentURL),
                         "Deleting a non-existent file should not throw")
    }

    // MARK: - overwriteRegion

    func testOverwriteRegionWritesRandomData() throws {
        let originalData = Data(repeating: 0xAA, count: 256)
        let url = try createTempFile(contents: originalData)

        try SecureDelete.overwriteRegion(in: url, offset: 0, length: 256)

        let readBack = try Data(contentsOf: url)
        XCTAssertEqual(readBack.count, originalData.count,
                       "File size should remain the same after overwrite")
        XCTAssertNotEqual(readBack, originalData,
                          "Overwritten data should differ from original (overwhelmingly likely for 256 bytes)")
    }

    func testOverwriteRegionPreservesDataOutsideRegion() throws {
        // Create a 300-byte file: [100 bytes 0xAA][100 bytes 0xBB][100 bytes 0xCC]
        var data = Data()
        data.append(Data(repeating: 0xAA, count: 100))
        data.append(Data(repeating: 0xBB, count: 100))
        data.append(Data(repeating: 0xCC, count: 100))
        let url = try createTempFile(contents: data)

        // Overwrite the middle 100 bytes
        try SecureDelete.overwriteRegion(in: url, offset: 100, length: 100)

        let readBack = try Data(contentsOf: url)
        XCTAssertEqual(readBack.count, 300)

        // Head should be unchanged
        let head = readBack.subdata(in: 0..<100)
        XCTAssertEqual(head, Data(repeating: 0xAA, count: 100),
                       "Data before the overwritten region should be preserved")

        // Tail should be unchanged
        let tail = readBack.subdata(in: 200..<300)
        XCTAssertEqual(tail, Data(repeating: 0xCC, count: 100),
                       "Data after the overwritten region should be preserved")

        // Middle should differ
        let middle = readBack.subdata(in: 100..<200)
        XCTAssertNotEqual(middle, Data(repeating: 0xBB, count: 100),
                          "Overwritten region should contain different data")
    }

    // MARK: - SecureTemporaryFile

    func testSecureTemporaryFileWriteReadRoundTrip() throws {
        let tempFile = SecureDelete.SecureTemporaryFile()
        let testData = Data("secure temp file test".utf8)

        try tempFile.write(testData)
        let readBack = try tempFile.read()

        XCTAssertEqual(readBack, testData, "Round-trip through SecureTemporaryFile should preserve data")
    }

    func testSecureTemporaryFileCleanup() throws {
        var tempFile: SecureDelete.SecureTemporaryFile? = SecureDelete.SecureTemporaryFile()
        let testData = Data("cleanup test data".utf8)
        try tempFile!.write(testData)

        let fileURL = tempFile!.url
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "File should exist while SecureTemporaryFile is alive")

        // Release the SecureTemporaryFile — deinit should securely delete the file
        tempFile = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "File should be deleted after SecureTemporaryFile is deallocated")
    }
}
