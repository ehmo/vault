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
                .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.black)
            Divider()

            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if let error = error {
                    errorView(error)
                }
            }
        }
        .onAppear(perform: loadVideo)
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
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)
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
                let (header, content) = try VaultStorage.shared.retrieveFile(id: file.id, with: key)

                // Videos need to be written to a temp file for playback
                // This is a security tradeoff - we delete immediately after
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(header.originalFilename.components(separatedBy: ".").last ?? "mp4")

                try content.write(to: tempURL, options: [.atomic, .completeFileProtection])

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
            size: 1024, thumbnailData: nil,
            mimeType: "video/mp4",
            filename: "preview-video.mp4"
        ),
        vaultKey: nil
    )
}

