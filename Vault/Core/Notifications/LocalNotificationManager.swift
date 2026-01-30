import Foundation
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
}
