import Foundation
import os.log

@MainActor
@Observable
final class DeepLinkHandler {
    private static let logger = Logger(subsystem: "app.vaultaire.ios", category: "DeepLink")
    var pendingSharePhrase: String?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        // DEBUG: Print to console for immediate visibility
        print("🔗 DEEP LINK: Received URL: \(url.absoluteString)")
        print("🔗 DEEP LINK: URL scheme: \(url.scheme ?? "nil")")
        print("🔗 DEEP LINK: URL host: \(url.host ?? "nil")")
        print("🔗 DEEP LINK: URL path: \(url.path)")
        print("🔗 DEEP LINK: URL fragment: \(url.fragment ?? "nil")")
        
        Self.logger.info("Handling URL: \(url.absoluteString, privacy: .private)")
        
        guard let phrase = ShareLinkEncoder.phrase(from: url) else {
            print("🔗 DEEP LINK: ❌ Could not extract phrase from URL!")
            Self.logger.warning("Could not extract phrase from URL: \(url.absoluteString, privacy: .private)")
            return false
        }

        print("🔗 DEEP LINK: ✓ Extracted phrase (length: \(phrase.count))")
        print("🔗 DEEP LINK: Phrase first 20 chars: \(phrase.prefix(20))...")
        Self.logger.info("Received share link, phrase length: \(phrase.count), phrase prefix: \(phrase.prefix(10), privacy: .private)")

        pendingSharePhrase = phrase
        return true
    }

    func clearPending() {
        pendingSharePhrase = nil
    }
}
