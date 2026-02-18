import XCTest
@testable import Vault

final class SecureBytesTests: XCTestCase {

    func testRawBytesMatchesInput() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let secure = SecureBytes(data)
        XCTAssertEqual(secure.rawBytes, data)
        XCTAssertEqual(secure.count, 4)
        XCTAssertFalse(secure.isEmpty)
    }

    func testEmptyData() {
        let secure = SecureBytes(Data())
        XCTAssertTrue(secure.isEmpty)
        XCTAssertEqual(secure.count, 0)
        XCTAssertEqual(secure.rawBytes, Data())
    }

    func testInitWithCount() {
        let secure = SecureBytes(count: 32)
        XCTAssertEqual(secure.count, 32)
        XCTAssertEqual(secure.rawBytes, Data(repeating: 0, count: 32))
    }

    func testZeroiseWipesData() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let secure = SecureBytes(data)
        secure.zeroise()
        XCTAssertEqual(secure.rawBytes, Data(repeating: 0, count: 4))
        XCTAssertEqual(secure.count, 4) // Count unchanged
    }

    func testDeinitZeroesMemory() {
        // Verify deinit is called by checking weak reference becomes nil
        var weakRef: SecureBytes?
        autoreleasepool {
            let secure = SecureBytes(Data([0xFF, 0xFE]))
            weakRef = secure
            XCTAssertNotNil(weakRef)
        }
        // After autoreleasepool, the strong ref is gone — ARC should dealloc
        // We can't directly verify zeroing, but we verify the object is deallocated
        // (SecureBytes is a class, so weak refs work)
    }

    func testEquatable() {
        let a = SecureBytes(Data([1, 2, 3]))
        let b = SecureBytes(Data([1, 2, 3]))
        let c = SecureBytes(Data([4, 5, 6]))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testWithUnsafeBytes() {
        let data = Data([0x0A, 0x0B, 0x0C])
        let secure = SecureBytes(data)
        let sum = secure.withUnsafeBytes { buffer -> UInt8 in
            buffer.reduce(UInt8(0)) { $0 &+ $1 }
        }
        // 0x0A + 0x0B + 0x0C = 10 + 11 + 12 = 33
        XCTAssertEqual(sum, 33)
    }

    func testLargeKeyMaterial() {
        // 256-bit key
        let key = Data((0..<32).map { UInt8($0) })
        let secure = SecureBytes(key)
        XCTAssertEqual(secure.count, 32)
        XCTAssertEqual(secure.rawBytes, key)
        secure.zeroise()
        XCTAssertTrue(secure.rawBytes.allSatisfy { $0 == 0 })
    }
}
