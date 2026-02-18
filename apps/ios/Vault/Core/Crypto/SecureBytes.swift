import Foundation

/// A class wrapper for sensitive byte data that zeroes memory on deallocation.
/// Use for key material (vault keys, master keys, share keys) to reduce the
/// window where secrets persist in memory after the key is no longer needed.
///
/// Because this is a reference type, all holders share the same backing storage.
/// When the last reference drops, `deinit` zeroes the buffer.
final class SecureBytes: @unchecked Sendable {
    private var storage: ContiguousArray<UInt8>

    /// The byte count of the wrapped data.
    var count: Int { storage.count }

    /// Whether the wrapped data is empty.
    var isEmpty: Bool { storage.isEmpty }

    /// A read-only `Data` copy of the current contents.
    var rawBytes: Data { Data(storage) }

    // MARK: - Init

    init(_ data: Data) {
        self.storage = ContiguousArray(data)
    }

    init(count: Int) {
        self.storage = ContiguousArray(repeating: 0, count: count)
    }

    // MARK: - Access

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.withUnsafeBytes(body)
    }

    // MARK: - Cleanup

    /// Explicitly zero the backing memory. Also called automatically in `deinit`.
    func zeroise() {
        for i in storage.indices {
            storage[i] = 0
        }
    }

    deinit {
        zeroise()
    }
}

// MARK: - Equatable

extension SecureBytes: Equatable {
    static func == (lhs: SecureBytes, rhs: SecureBytes) -> Bool {
        lhs.storage.elementsEqual(rhs.storage)
    }
}
