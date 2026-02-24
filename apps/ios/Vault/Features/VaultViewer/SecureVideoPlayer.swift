import SwiftUI
import AVKit
import AVFoundation

/// Configures AVAudioSession for video playback once, on first use.
/// Deferred from app launch to avoid blocking the launch critical path
/// (~5s AudioSession subsystem spin observed in Instruments).
private enum AudioSessionSetup {
    private static let once: Void = {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }()

    static func ensureConfigured() { _ = once }
}

struct SecureVideoPlayer: View {
    let file: VaultFileItem
    let vaultKey: VaultKey?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var tempFileURL: URL?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isPlaying = false
    @State private var timeObserver: Any?

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .ignoresSafeArea()
                } else if let error = error {
                    errorView(error)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { loadVideo() }
        .onDisappear(perform: cleanup)
        .onChange(of: isPlaying) { _, playing in
            if playing {
                InactivityLockManager.shared.videoPlaybackStarted()
            } else {
                InactivityLockManager.shared.videoPlaybackStopped()
            }
        }
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

        AudioSessionSetup.ensureConfigured()

        Task {
            do {
                // Decrypt directly to temp file — avoids holding entire decrypted video in memory
                let (_, tempURL) = try await VaultStorage.shared.retrieveFileToTempURL(id: file.id, with: key)

                await MainActor.run {
                    self.tempFileURL = tempURL
                    let newPlayer = AVPlayer(url: tempURL)
                    self.player = newPlayer
                    
                    // Observe playback state for inactivity lock manager
                    self.timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { _ in
                        // Note: Can't use weak self in struct, but the observer is cleaned up in cleanup()
                        let wasPlaying = self.isPlaying
                        let nowPlaying = newPlayer.timeControlStatus == .playing
                        if wasPlaying != nowPlaying {
                            self.isPlaying = nowPlaying
                        }
                    }
                    
                    newPlayer.play()
                    self.isPlaying = true
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
        // Report playback stopped
        InactivityLockManager.shared.videoPlaybackStopped()
        
        // Remove time observer
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
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
