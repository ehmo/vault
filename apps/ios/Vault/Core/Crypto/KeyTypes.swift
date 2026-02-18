import Foundation

/// Type-safe wrapper for vault encryption keys derived from unlock patterns.
/// Prevents accidental misuse of key types at compile time.
struct VaultKey: Sendable, Equatable {
    let rawBytes: Data

    init(_ data: Data) {
        self.rawBytes = data
    }
}

/// Type-safe wrapper for master keys (derived from vault key, used for thumbnails).
struct MasterKey: Sendable, Equatable {
    let rawBytes: Data

    init(_ data: Data) {
        self.rawBytes = data
    }
}

/// Type-safe wrapper for share encryption keys derived from share phrases.
struct ShareKey: Sendable, Equatable {
    let rawBytes: Data

    init(_ data: Data) {
        self.rawBytes = data
    }
}
