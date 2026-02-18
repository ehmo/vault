import XCTest
@testable import Vault

final class EncryptedBlobTests: XCTestCase {

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

    private func createBlob(size: Int, fill: UInt8 = 0x00) throws -> EncryptedBlob {
        let url = tempDir.appendingPathComponent(UUID().uuidString + ".bin")
        let data = Data(repeating: fill, count: size)
        try data.write(to: url)
        return EncryptedBlob(url: url)
    }

    private func createBlobWithData(_ data: Data) throws -> EncryptedBlob {
        let url = tempDir.appendingPathComponent(UUID().uuidString + ".bin")
        try data.write(to: url)
        return EncryptedBlob(url: url)
    }

    // MARK: - Write and Read

    func testWriteAndReadRegion() throws {
        let blob = try createBlob(size: 1024)
        let testData = Data("hello blob world".utf8)
        let offset = 100

        try blob.write(data: testData, at: offset)

        let region = EncryptedBlob.BlobRegion(offset: offset, length: testData.count)
        let readBack = try blob.read(region: region)

        XCTAssertEqual(readBack, testData, "Data read from blob should match data written")
    }

    func testReadRegionAtDifferentOffsets() throws {
        let blob = try createBlob(size: 2048)

        let dataA = Data("alpha".utf8)
        let dataB = Data("bravo".utf8)
        let dataC = Data("charlie".utf8)

        try blob.write(data: dataA, at: 0)
        try blob.write(data: dataB, at: 500)
        try blob.write(data: dataC, at: 1000)

        let readA = try blob.read(region: EncryptedBlob.BlobRegion(offset: 0, length: dataA.count))
        let readB = try blob.read(region: EncryptedBlob.BlobRegion(offset: 500, length: dataB.count))
        let readC = try blob.read(region: EncryptedBlob.BlobRegion(offset: 1000, length: dataC.count))

        XCTAssertEqual(readA, dataA)
        XCTAssertEqual(readB, dataB)
        XCTAssertEqual(readC, dataC)
    }

    // MARK: - Overwrite With Random

    func testOverwriteWithRandom() throws {
        let knownData = Data(repeating: 0xAA, count: 256)
        let blob = try createBlobWithData(knownData)

        let region = EncryptedBlob.BlobRegion(offset: 0, length: 256)
        try blob.overwriteWithRandom(region: region)

        let readBack = try blob.read(region: region)
        XCTAssertNotEqual(readBack, knownData,
                          "Overwritten data should differ from original (overwhelmingly likely for 256 bytes)")
    }

    // MARK: - BlobRegion

    func testBlobRegionEndOffset() {
        let region = EncryptedBlob.BlobRegion(offset: 100, length: 50)
        XCTAssertEqual(region.endOffset, 150, "endOffset should be offset + length")
    }

    // MARK: - File Size

    func testFileSizeReportsCorrectly() throws {
        let size = 4096
        let blob = try createBlob(size: size)
        XCTAssertEqual(blob.fileSize, size, "fileSize should match the size of the underlying file")
    }

    // MARK: - Edge Cases

    func testReadEmptyRegionThrowsReadError() throws {
        let blob = try createBlob(size: 256)
        let region = EncryptedBlob.BlobRegion(offset: 0, length: 0)
        // FileHandle.read(upToCount: 0) returns nil, which triggers readError
        XCTAssertThrowsError(try blob.read(region: region)) { error in
            XCTAssertEqual(error as? VaultStorageError, .readError)
        }
    }

    // MARK: - Randomness Check

    func testRandomnessCheck() throws {
        // Use a large size to minimize statistical flukes (passesRandomnessCheck uses 50% tolerance)
        let size = 100_000
        guard let randomData = CryptoEngine.generateRandomBytes(count: size) else {
            XCTFail("Failed to generate random bytes")
            return
        }

        let url = tempDir.appendingPathComponent("random.bin")
        try randomData.write(to: url)
        let blob = EncryptedBlob(url: url)

        // passesRandomnessCheck() only reads first 10_000 bytes by default
        XCTAssertTrue(blob.passesRandomnessCheck(sampleSize: size),
                      "Cryptographically random data should pass the randomness check")
    }

    func testNonRandomDataFailsRandomnessCheck() throws {
        // Create a file with a repeating pattern (very low entropy)
        let pattern = Data(repeating: 0x42, count: 10_000)
        let url = tempDir.appendingPathComponent("pattern.bin")
        try pattern.write(to: url)
        let blob = EncryptedBlob(url: url)

        XCTAssertFalse(blob.passesRandomnessCheck(),
                       "Repeating pattern data should fail the randomness check")
    }
}
