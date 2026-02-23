import Foundation
import os.log

@MainActor
@Observable
final class DeepLinkHandler {
    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "DeepLink")
    var pendingSharePhrase: String?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        Self.logger.info("Handling URL: \(url.absoluteString, privacy: .private)")
        
        guard let phrase = ShareLinkEncoder.phrase(from: url) else {
            Self.logger.warning("Could not extract phrase from URL: \(url.absoluteString, privacy: .private)")
            return false
        }

        Self.logger.info("Received share link, phrase length: \(phrase.count), phrase prefix: \(phrase.prefix(10), privacy: .private)")

        pendingSharePhrase = phrase
        return true
    }

    func clearPending() {
        pendingSharePhrase = nil
    }
}
