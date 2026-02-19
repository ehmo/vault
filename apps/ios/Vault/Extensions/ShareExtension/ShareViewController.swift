import UIKit
import ImageIO
import UniformTypeIdentifiers
import CommonCrypto
import CryptoKit
import UserNotifications
import os.log

private let shareExtensionLogger = Logger(subsystem: "app.vaultaire.ios", category: "ShareExtension")

/// Share Extension that encrypts files from other apps and stages them for
/// import into Vaultaire. The user draws their vault pattern to select the
/// target vault; the extension derives the same key as the main app and
/// encrypts all attachments into the app-group pending_imports/ directory.
final class ShareViewController: UIViewController {

    // MARK: - State

    private var receivedItems: [NSExtensionItem] = []
    private var isProcessing = false
    private var patternView: PatternInputView!
    private var titleLabel: UILabel!
    private var statusLabel: UILabel!
    private var progressView: UIProgressView!
    private var cancelButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        setupUI()
        loadSharedItems()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        titleLabel = UILabel()
        titleLabel.text = "Draw pattern to add to Vaultaire"
        titleLabel.textAlignment = .center
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        patternView = PatternInputView(frame: .zero)
        patternView.delegate = self
        patternView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(patternView)

        statusLabel = UILabel()
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            patternView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            patternView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            patternView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            patternView.heightAnchor.constraint(equalTo: patternView.widthAnchor),

            statusLabel.topAnchor.constraint(equalTo: patternView.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Load Shared Items

    private func loadSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        receivedItems = extensionItems
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "app.vaultaire.ios", code: 0))
    }

    // MARK: - Process Shared Content

    private func processSharedContent(with key: Data) {
        patternView.isUserInteractionEnabled = false
        cancelButton.isHidden = true
        titleLabel.text = "Encrypting..."
        statusLabel.isHidden = false
        progressView.isHidden = false
        progressView.progress = 0
        setIdleTimerDisabled(true)

        Task {
            do {
                try await encryptAndStage(with: key)
                await MainActor.run {
                    setIdleTimerDisabled(false)
                    showSuccess()
                }
            } catch {
                await MainActor.run {
                    setIdleTimerDisabled(false)
                    showError()
                }
            }
        }
    }

    /// Prevents the device from sleeping while the extension is encrypting.
    /// Uses KVC to access UIApplication.shared which is compile-time restricted
    /// in extensions but fully functional at runtime.
    private func setIdleTimerDisabled(_ disabled: Bool) {
        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type else { return }
        let selector = NSSelectorFromString("sharedApplication")
        guard appClass.responds(to: selector),
              let result = appClass.perform(selector)?.takeUnretainedValue() else { return }
        (result as AnyObject).setValue(disabled, forKey: "idleTimerDisabled")
    }

    private func encryptAndStage(with key: Data) async throws {
        // First pass: count supported attachments without retaining an extra
        // provider list for the full run.
        let counts = ShareAttachmentProcessor.countSupportedAttachments(in: receivedItems)
        guard counts.total > 0 else {
            throw StagedImportError.encryptionFailed
        }

        // Check free-tier limits
        let isPremium = UserDefaults(suiteName: VaultCoreConstants.appGroupIdentifier)?
            .bool(forKey: VaultCoreConstants.isPremiumKey) ?? false

        if !isPremium,
           counts.images > VaultCoreConstants.freeMaxImages ||
           counts.videos > VaultCoreConstants.freeMaxVideos ||
           counts.files > VaultCoreConstants.freeMaxFiles {
            throw StagedImportError.freeTierLimitExceeded
        }

        // Create batch
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fingerprint = KeyDerivation.keyFingerprint(from: key)
        let total = counts.total
        var fileMetadata: [StagedFileMetadata] = []
        var processed = 0

        let itemsQueue = ArraySlice(receivedItems)
        let sourceApp = itemsQueue.first?.attributedContentText.map { _ in
            Bundle.main.bundleIdentifier
        } ?? nil
        // Release controller-held references as soon as possible.
        receivedItems = []

        for item in itemsQueue {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                guard let utType = ShareAttachmentProcessor.supportedType(for: provider) else { continue }
                processed += 1
                let startedAt = Date()
                await MainActor.run {
                    statusLabel.text = "Encrypting \(processed) of \(total) files..."
                    progressView.progress = total > 0 ? Float(processed - 1) / Float(total) : 0
                }

                let meta = try await ShareAttachmentProcessor.processAttachment(
                    provider,
                    utType: utType,
                    key: key,
                    batchURL: batchURL
                )
                fileMetadata.append(meta)

                // Checkpoint manifest after each file so an extension kill near
                // completion still leaves importable staged progress.
                let checkpoint = StagedImportManifest(
                    batchId: batchId,
                    keyFingerprint: fingerprint,
                    timestamp: Date(),
                    sourceAppBundleId: sourceApp,
                    files: fileMetadata
                )
                try StagedImportManager.writeManifest(checkpoint, to: batchURL)

                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                shareExtensionLogger.info(
                    "Staged file \(processed)/\(total): \(meta.filename, privacy: .public), size=\(meta.originalSize) bytes, elapsed=\(elapsedMs)ms"
                )
            }
        }
        let manifest = StagedImportManifest(
            batchId: batchId,
            keyFingerprint: fingerprint,
            timestamp: Date(),
            sourceAppBundleId: sourceApp,
            files: fileMetadata
        )
        try StagedImportManager.writeManifest(manifest, to: batchURL)

        // Schedule delayed local notification (5 minutes) with TOTAL pending count
        // across all batches — not just this session's count
        let totalPending = StagedImportManager.pendingFileCount(for: fingerprint)
        scheduleImportNotification(fileCount: totalPending)

        await MainActor.run {
            progressView.progress = 1.0
            statusLabel.text = "Done!"
        }
    }

    // MARK: - Notification

    private func scheduleImportNotification(fileCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Files Ready"
        content.body = "\(fileCount) file\(fileCount == 1 ? "" : "s") waiting to import in Vaultaire"
        content.sound = .default
        content.categoryIdentifier = "PENDING_IMPORT"

        // Attach the vault icon from the app group container
        if let iconURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: VaultCoreConstants.appGroupIdentifier)?
            .appendingPathComponent("notification-icon.jpg"),
           FileManager.default.fileExists(atPath: iconURL.path),
           let attachment = try? UNNotificationAttachment(
               identifier: "vault-icon",
               url: iconURL,
               options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
           ) {
            content.attachments = [attachment]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pending-import-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Completion UI

    private func showSuccess() {
        titleLabel.text = "Added to Vaultaire"
        statusLabel.isHidden = true
        progressView.isHidden = true

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .systemGreen
        checkmark.contentMode = .scaleAspectFit
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(checkmark)
        NSLayoutConstraint.activate([
            checkmark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 64),
            checkmark.heightAnchor.constraint(equalToConstant: 64),
        ])

        patternView.isHidden = true

        // Tap anywhere to dismiss early
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissExtension))
        view.addGestureRecognizer(tapGesture)

        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.dismissExtension()
        }
    }

    private func showError() {
        titleLabel.text = "Could not add files"
        statusLabel.text = "Please try again"
        statusLabel.isHidden = false
        progressView.isHidden = true

        cancelButton.setTitle("Done", for: .normal)
        cancelButton.isHidden = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.dismissExtension()
        }
    }

    @objc private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - PatternInputDelegate

extension ShareViewController: PatternInputDelegate {
    func patternComplete(_ pattern: [Int]) {
        guard !isProcessing else { return }
        isProcessing = true

        Task {
            do {
                let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: VaultCoreConstants.gridSize)
                await MainActor.run {
                    self.processSharedContent(with: key)
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.showError()
                }
            }
        }
    }
}

// MARK: - Attachment Processing

private enum ShareAttachmentProcessor {

    struct AttachmentCounts {
        var total = 0
        var images = 0
        var videos = 0
        var files = 0
    }

    static func supportedType(for provider: NSItemProvider) -> UTType? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return .image
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return .movie
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            return .data
        }
        return nil
    }

    static func countSupportedAttachments(in items: [NSExtensionItem]) -> AttachmentCounts {
        var counts = AttachmentCounts()
        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                guard let type = supportedType(for: provider) else { continue }
                counts.total += 1
                if type == .image {
                    counts.images += 1
                } else if type == .movie {
                    counts.videos += 1
                } else {
                    counts.files += 1
                }
            }
        }
        return counts
    }

    static func processAttachment(
        _ provider: NSItemProvider,
        utType: UTType,
        key: Data,
        batchURL: URL
    ) async throws -> StagedFileMetadata {
        let fileId = UUID()

        // File representation loading is asynchronous and typically I/O bound.
        let (tempURL, filename, mimeType) = try await loadFile(from: provider, utType: utType)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0

        // Move all expensive sync work off the main actor to prevent share-extension
        // watchdog kills during large multi-file batches.
        return try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let (encryptedSize, hasThumbnail) = try autoreleasepool {
                // Encrypt directly to output file — peak memory ~256KB instead of entire file.
                let encryptedURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
                FileManager.default.createFile(atPath: encryptedURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: encryptedURL)
                defer { try? outputHandle.close() }
                try CryptoEngine.encryptFileStreamingToHandle(from: tempURL, to: outputHandle, with: key)
                let encSize = (try? FileManager.default.attributesOfItem(atPath: encryptedURL.path)[.size] as? Int) ?? 0

                // Generate and encrypt thumbnail for images using downsampled ImageIO.
                var hasThumb = false
                if utType.conforms(to: .image), let thumbData = generateThumbnail(from: tempURL) {
                    let encThumb = try CryptoEngine.encrypt(thumbData, with: key)
                    try StagedImportManager.writeEncryptedThumbnail(encThumb, fileId: fileId, to: batchURL)
                    hasThumb = true
                }

                return (encSize, hasThumb)
            }

            return StagedFileMetadata(
                fileId: fileId,
                filename: filename,
                mimeType: mimeType,
                utType: utType.identifier,
                originalSize: fileSize,
                encryptedSize: encryptedSize,
                hasThumbnail: hasThumbnail,
                timestamp: Date()
            )
        }.value
    }

    private static func loadFile(
        from provider: NSItemProvider,
        utType: UTType
    ) async throws -> (url: URL, filename: String, mimeType: String) {
        let registeredTypes = provider.registeredTypeIdentifiers
        nonisolated(unsafe) let unsafeProvider = provider
        return try await withCheckedThrowingContinuation { continuation in
            unsafeProvider.loadFileRepresentation(forTypeIdentifier: utType.identifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: StagedImportError.encryptionFailed)
                    return
                }

                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let filename = url.lastPathComponent
                let fileUTType = UTType(filenameExtension: url.pathExtension)
                let mimeType = fileUTType?.preferredMIMEType
                    ?? registeredTypes.lazy.compactMap { UTType($0)?.preferredMIMEType }.first
                    ?? "application/octet-stream"

                continuation.resume(returning: (tempURL, filename, mimeType))
            }
        }
    }

    private static func generateThumbnail(from url: URL) -> Data? {
        let maxDimension: CGFloat = 200
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // kCGImageSourceCreateThumbnailWithTransform already rotates pixels to correct
        // orientation, so use .up to avoid applying the EXIF rotation a second time.
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        return image.jpegData(compressionQuality: 0.6)
    }
}
