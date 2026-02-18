import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Actions

extension VaultView {

    func lockVault() {
        appState.lockVault()
    }

    /// Load a video from PHPicker to a temp URL without loading entire file into memory.
    /// The caller is responsible for cleaning up the returned URL.
    static func loadVideoURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                // Copy to our temp directory — provider URL is ephemeral
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate a thumbnail and capture duration from a video URL.
    static func generateVideoMetadata(from url: URL) async -> (thumbnail: Data?, duration: TimeInterval?) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        var thumbnail: Data?
        var duration: TimeInterval?

        // Capture duration
        if let cmDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds > 0 {
                duration = seconds
            }
        }

        // Generate thumbnail frame
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            let uiImage = UIImage(cgImage: cgImage)
            thumbnail = uiImage.jpegData(compressionQuality: 0.7)
        }

        return (thumbnail, duration)
    }
}
