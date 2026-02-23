import Foundation

/// Protocol for type-safe key passing. Allows CryptoEngine, DuressHandler, etc.
/// to accept VaultKey/MasterKey/ShareKey directly instead of raw Data.
protocol SymmetricKeyData: Sendable, Equatable {
    var rawBytes: Data { get }
}

/// Type-safe wrapper for vault encryption keys derived from unlock patterns.
/// Uses SecureBytes for auto-zeroing on deallocation — when `currentVaultKey`
/// is set to nil during lockVault(), the underlying key material is zeroed.
struct VaultKey: SymmetricKeyData {
    private let secureStorage: SecureBytes

    /// A read-only Data copy. Callers should avoid retaining this long-term.
    var rawBytes: Data { secureStorage.rawBytes }

    init(_ data: Data) {
        self.secureStorage = SecureBytes(data)
    }
}

/// Type-safe wrapper for master keys (derived from vault key, used for thumbnails).
/// Auto-zeroes on deallocation via SecureBytes.
struct MasterKey: SymmetricKeyData {
    private let secureStorage: SecureBytes

    var rawBytes: Data { secureStorage.rawBytes }

    init(_ data: Data) {
        self.secureStorage = SecureBytes(data)
    }
}

/// Type-safe wrapper for share encryption keys derived from share phrases.
/// Auto-zeroes on deallocation via SecureBytes.
struct ShareKey: SymmetricKeyData {
    private let secureStorage: SecureBytes

    var rawBytes: Data { secureStorage.rawBytes }

    init(_ data: Data) {
        self.secureStorage = SecureBytes(data)
    }
}
