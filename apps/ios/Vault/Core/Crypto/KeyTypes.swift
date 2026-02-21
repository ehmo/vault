import Foundation

/// Type-safe wrapper for vault encryption keys derived from unlock patterns.
/// Uses SecureBytes for auto-zeroing on deallocation — when `currentVaultKey`
/// is set to nil during lockVault(), the underlying key material is zeroed.
struct VaultKey: Sendable, Equatable {
    private let secureStorage: SecureBytes

    /// A read-only Data copy. Callers should avoid retaining this long-term.
    var rawBytes: Data { secureStorage.rawBytes }

    init(_ data: Data) {
        self.secureStorage = SecureBytes(data)
    }
}

/// Type-safe wrapper for master keys (derived from vault key, used for thumbnails).
/// Auto-zeroes on deallocation via SecureBytes.
struct MasterKey: Sendable, Equatable {
    private let secureStorage: SecureBytes

    var rawBytes: Data { secureStorage.rawBytes }

    init(_ data: Data) {
        self.secureStorage = SecureBytes(data)
    }
}

/// Type-safe wrapper for share encryption keys derived from share phrases.
/// Auto-zeroes on deallocation via SecureBytes.
struct ShareKey: Sendable, Equatable {
    private let secureStorage: SecureBytes

    var rawBytes: Data { secureStorage.rawBytes }

    init(_ data: Data) {
        self.secureStorage = SecureBytes(data)
    }
}
