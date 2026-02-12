import SwiftUI
import AVFoundation
import UserNotifications
import os.log

private let permissionsLogger = Logger(subsystem: "app.vaultaire.ios", category: "Permissions")

struct PermissionsView: View {
    let onContinue: () -> Void

    @State private var notificationStatus: PermissionStatus = .notDetermined
    @State private var cameraStatus: PermissionStatus = .notDetermined

    enum PermissionStatus {
        case notDetermined, granted, denied
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Enable Permissions")
                .font(.title)
                .fontWeight(.bold)

            Text("Vaultaire works best with these permissions. You can change them anytime in Settings.")
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 16) {
                permissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Know when backups and imports finish",
                    status: notificationStatus,
                    action: requestNotifications
                )

                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Capture photos directly into your vault",
                    status: cameraStatus,
                    action: requestCamera
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .vaultProminentButtonStyle()
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .accessibilityIdentifier("permissions_continue")
        }
        .task {
            await checkCurrentStatuses()
        }
    }

    // MARK: - Views

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        status: PermissionStatus,
        action: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.vaultSecondaryText)
            }

            Spacer()

            switch status {
            case .notDetermined:
                Button("Allow") {
                    Task { await action() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.vaultSecondaryText)
                    .font(.title3)
            }
        }
        .padding()
        .vaultGlassBackground(cornerRadius: 12)
    }

    // MARK: - Permission Requests

    private func checkCurrentStatuses() async {
        // Notifications
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            switch settings.authorizationStatus {
            case .authorized, .provisional: notificationStatus = .granted
            case .denied: notificationStatus = .denied
            default: notificationStatus = .notDetermined
            }
        }

        // Camera
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run {
            switch cameraAuth {
            case .authorized: cameraStatus = .granted
            case .denied, .restricted: cameraStatus = .denied
            default: cameraStatus = .notDetermined
            }
        }
    }

    private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            permissionsLogger.info("Notification permission: \(granted)")
            await MainActor.run {
                notificationStatus = granted ? .granted : .denied
            }
        } catch {
            permissionsLogger.error("Notification request failed: \(error.localizedDescription)")
            await MainActor.run { notificationStatus = .denied }
        }
    }

    private func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permissionsLogger.info("Camera permission: \(granted)")
        await MainActor.run {
            cameraStatus = granted ? .granted : .denied
        }
    }
}

#Preview {
    PermissionsView(onContinue: {})
}
