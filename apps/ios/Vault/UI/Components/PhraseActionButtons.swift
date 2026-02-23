import SwiftUI
import UIKit

// MARK: - Phrase Display Card

struct PhraseDisplayCard: View {
    let phrase: String

    var body: some View {
        Text(phrase)
            .font(.title3)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .vaultGlassBackground(cornerRadius: 12)
    }
}

// MARK: - Phrase Action Buttons

struct PhraseActionButtons: View {
    let phrase: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: copyToClipboard) {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied!" : "Copy")
                        .frame(minWidth: 50) // Fixed minWidth to prevent layout shift
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: downloadPhrase) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = phrase
        copied = true

        // Reset "Copied!" label after 2s
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { copied = false }
        }

        // Auto-clear clipboard after 60s
        let phraseCopy = phrase
        Task {
            try? await Task.sleep(for: .seconds(60))
            if UIPasteboard.general.string == phraseCopy {
                UIPasteboard.general.string = ""
            }
        }
    }

    private func downloadPhrase() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "vaultaire-recovery-phrase-\(formatter.string(from: Date())).txt"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? phrase.write(to: tempURL, atomically: true, encoding: .utf8)

        ShareSheetHelper.present(items: [tempURL]) {
            // Clean up temp file after share sheet dismisses
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
