import SwiftUI
import UIKit

// MARK: - Phrase Display Card

struct PhraseDisplayCard: View {
    let phrase: String

    @State private var copied = false

    var body: some View {
        ZStack {
            Text(phrase)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .opacity(copied ? 0.3 : 1)

            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: copied)
        .padding()
        .frame(maxWidth: .infinity)
        .vaultGlassBackground(cornerRadius: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            copyPhrase()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to copy phrase")
    }

    private func copyPhrase() {
        UIPasteboard.general.string = phrase
        copied = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
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
                        .frame(width: 20) // Fixed width for icon
                    Text(copied ? "Copied!" : "Copy")
                        .frame(minWidth: 60, idealWidth: 60, maxWidth: 60) // Fixed width for text
                }
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22) // Fixed height to prevent vertical jump
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
