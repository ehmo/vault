import SwiftUI

struct RecoveryPhraseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var phrase: String = ""
    @State private var isRevealed = false
    @State private var showingCopiedAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recovery Phrase")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            Divider()

            VStack(spacing: 24) {
                // Warning
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Keep this phrase secret and secure")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Phrase display
                VStack(spacing: 12) {
                    if isRevealed {
                        Text(phrase)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button(action: copyPhrase) {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: revealPhrase) {
                            VStack(spacing: 8) {
                                Image(systemName: "eye.fill")
                                    .font(.title)
                                Text("Tap to reveal")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .padding(40)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Spacer()

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Write it down and store safely", systemImage: "pencil.and.list.clipboard")
                    Label("Never share it with anyone", systemImage: "person.2.slash")
                    Label("Use it to recover this vault if you forget the pattern", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .onAppear {
            generateOrLoadPhrase()
        }
        .alert("Copied!", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Recovery phrase copied to clipboard. Clear your clipboard after use.")
        }
    }

    private func generateOrLoadPhrase() {
        // In real implementation, would load from secure storage or generate new
        phrase = RecoveryPhraseGenerator.shared.generatePhrase()
    }

    private func revealPhrase() {
        withAnimation {
            isRevealed = true
        }
    }

    private func copyPhrase() {
        UIPasteboard.general.string = phrase
        showingCopiedAlert = true

        // Clear clipboard after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if UIPasteboard.general.string == phrase {
                UIPasteboard.general.string = ""
            }
        }
    }
}

#Preview {
    RecoveryPhraseView()
}
