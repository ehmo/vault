import Foundation
import UIKit
import UserNotifications

/// Manages local notifications for background share transfers.
/// All messages are privacy-safe: no vault name, no file details.
@MainActor
final class LocalNotificationManager {
    static let shared = LocalNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var permissionGranted = false

    private init() {}

    // MARK: - Permission

    /// Ensures notification permission has been requested. Called lazily before first send.
    private func ensurePermission() async {
        guard !permissionGranted else { return }
        do {
            permissionGranted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            #if DEBUG
            print("⚠️ [Notifications] Permission request failed: \(error)")
            #endif
        }
    }

    // MARK: - Upload Notifications

    func sendUploadComplete() {
        send(
            id: "upload-complete",
            title: "Vault Shared",
            body: "Your shared vault was uploaded successfully."
        )
    }

    func sendUploadFailed() {
        send(
            id: "upload-failed",
            title: "Sharing Failed",
            body: "Your shared vault upload could not be completed."
        )
    }

    // MARK: - Import Notifications

    func sendImportComplete() {
        send(
            id: "import-complete",
            title: "Vault Ready",
            body: "Your shared vault is ready to use."
        )
    }

    func sendImportFailed() {
        send(
            id: "import-failed",
            title: "Setup Failed",
            body: "Your shared vault could not be set up."
        )
    }

    // MARK: - Private

    private func send(id: String, title: String, body: String) {
        Task {
            await ensurePermission()

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            if let attachment = Self.createIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: nil // Immediate delivery
            )

            do {
                try await center.add(request)
            } catch {
                #if DEBUG
                print("⚠️ [Notifications] Failed to send \(id): \(error)")
                #endif
            }
        }
    }

    /// Creates a notification attachment from the VaultLogo asset.
    /// Returns nil if the image can't be loaded or written to disk.
    nonisolated static func createIconAttachment() -> UNNotificationAttachment? {
        // Try app group first (works in both app and extension)
        let sharedURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: VaultCoreConstants.appGroupIdentifier)?
            .appendingPathComponent("notification-icon.jpg")

        if let sharedURL, FileManager.default.fileExists(atPath: sharedURL.path) {
            return try? UNNotificationAttachment(
                identifier: "vault-icon",
                url: sharedURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
            )
        }

        // Fall back to asset catalog (main app only)
        guard let image = UIImage(named: "VaultLogo"),
              let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        // Write to app group so the extension can use it next time
        if let sharedURL {
            try? data.write(to: sharedURL)
            return try? UNNotificationAttachment(
                identifier: "vault-icon",
                url: sharedURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
            )
        }

        // Last resort: temp directory
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vault-icon.jpg")
        try? data.write(to: tempURL)
        return try? UNNotificationAttachment(
            identifier: "vault-icon",
            url: tempURL,
            options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
        )
    }

    /// Writes the notification icon to the app group container so extensions can use it.
    /// Call once on app launch.
    func warmNotificationIcon() {
        let sharedURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: VaultCoreConstants.appGroupIdentifier)?
            .appendingPathComponent("notification-icon.jpg")

        guard let sharedURL, !FileManager.default.fileExists(atPath: sharedURL.path) else { return }

        if let image = UIImage(named: "VaultLogo"),
           let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: sharedURL)
        }
    }
}
