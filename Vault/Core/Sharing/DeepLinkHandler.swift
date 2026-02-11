import Foundation

@MainActor
@Observable
final class DeepLinkHandler {
    var pendingSharePhrase: String?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let phrase = ShareLinkEncoder.phrase(from: url) else {
            return false
        }

        #if DEBUG
        print("[DeepLink] Received share link, phrase length: \(phrase.count)")
        #endif

        pendingSharePhrase = phrase
        return true
    }

    func clearPending() {
        pendingSharePhrase = nil
    }
}
