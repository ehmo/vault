import SwiftUI
import AVKit

struct SecureVideoPlayer: View {
    let file: VaultFileItem
    let vaultKey: Data?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var tempFileURL: URL?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") {
                    dismiss()
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.vaultBackground)
            Divider()

            ZStack {
                Color.vaultBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                } else if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if let error = error {
                    errorView(error)
                }
            }
        }
        .task { loadVideo() }
        .onDisappear(perform: cleanup)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text("Unable to play video")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
        }
    }

    // MARK: - Actions

    private func loadVideo() {
        guard let key = vaultKey else {
            error = "No vault key"
            isLoading = false
            return
        }

        Task {
            do {
                // Decrypt directly to temp file — avoids holding entire decrypted video in memory
                let (_, tempURL) = try VaultStorage.shared.retrieveFileToTempURL(id: file.id, with: key)

                await MainActor.run {
                    self.tempFileURL = tempURL
                    self.player = AVPlayer(url: tempURL)
                    self.player?.play()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load video"
                    self.isLoading = false
                }
            }
        }
    }

    private func cleanup() {
        // Stop playback
        player?.pause()
        player = nil

        // Securely delete temp file
        if let tempURL = tempFileURL {
            try? SecureDelete.deleteFile(at: tempURL)
            self.tempFileURL = nil
        }
    }
}

#Preview {
    SecureVideoPlayer(
        file: VaultFileItem(
            id: UUID(),
            size: 1024,
            hasThumbnail: false,
            mimeType: "video/mp4",
            filename: "preview-video.mp4"
        ),
        vaultKey: nil
    )
}

