import Foundation

/// Tracks first-time achievements for celebration toasts
final class MilestoneTracker {
    static let shared = MilestoneTracker()

    @UserDefaultsBacked(key: "milestone_firstFile", defaultValue: false)
    var hasSeenFirstFile: Bool

    @UserDefaultsBacked(key: "milestone_firstShare", defaultValue: false)
    var hasSeenFirstShare: Bool

    @UserDefaultsBacked(key: "milestone_firstExport", defaultValue: false)
    var hasSeenFirstExport: Bool

    private init() {}

    /// Returns a milestone message if this is a first-time event, nil otherwise.
    func checkFirstFile(totalCount: Int) -> String? {
        guard totalCount == 1, !hasSeenFirstFile else { return nil }
        hasSeenFirstFile = true
        return "Your first file is protected"
    }

    func checkFirstShare() -> String? {
        guard !hasSeenFirstShare else { return nil }
        hasSeenFirstShare = true
        return "Vault shared securely"
    }

    func checkFirstExport() -> String? {
        guard !hasSeenFirstExport else { return nil }
        hasSeenFirstExport = true
        return "File exported successfully"
    }
}

// MARK: - UserDefaults Property Wrapper

@propertyWrapper
struct UserDefaultsBacked<Value> {
    let key: String
    let defaultValue: Value
    var storage: UserDefaults = .standard

    var wrappedValue: Value {
        get { storage.object(forKey: key) as? Value ?? defaultValue }
        set { storage.set(newValue, forKey: key) }
    }
}
