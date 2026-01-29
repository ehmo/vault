import Foundation
import UserNotifications

/// Manages local notifications for background share transfers.
/// All messages are privacy-safe: no vault name, no file details.
@MainActor
final class LocalNotificationManager {
    static let shared = LocalNotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            #if DEBUG
            print("⚠️ [Notifications] Permission request failed: \(error)")
            #endif
            return false
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
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // Immediate delivery
        )

        center.add(request) { error in
            #if DEBUG
            if let error {
                print("⚠️ [Notifications] Failed to send \(id): \(error)")
            }
            #endif
        }
    }
}
