import Foundation
import os.log

@MainActor
@Observable
final class DeepLinkHandler {
    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "DeepLink")
    var pendingSharePhrase: String?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let phrase = ShareLinkEncoder.phrase(from: url) else {
            return false
        }

        Self.logger.info("Received share link, phrase length: \(phrase.count)")

        pendingSharePhrase = phrase
        return true
    }

    func clearPending() {
        pendingSharePhrase = nil
    }
}
