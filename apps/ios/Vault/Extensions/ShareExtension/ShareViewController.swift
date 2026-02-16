import UIKit
import ImageIO
import UniformTypeIdentifiers
import CommonCrypto
import CryptoKit
import UserNotifications

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
        // Collect all attachments
        var attachments: [(provider: NSItemProvider, utType: UTType)] = []
        for item in receivedItems {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    attachments.append((provider, .image))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    attachments.append((provider, .movie))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    attachments.append((provider, .data))
                }
            }
        }

        guard !attachments.isEmpty else {
            throw StagedImportError.encryptionFailed
        }

        // Check free-tier limits
        let isPremium = UserDefaults(suiteName: VaultCoreConstants.appGroupIdentifier)?
            .bool(forKey: VaultCoreConstants.isPremiumKey) ?? false

        if !isPremium {
            let imageCount = attachments.filter { $0.utType == .image }.count
            let videoCount = attachments.filter { $0.utType == .movie }.count
            let fileCount = attachments.filter { $0.utType == .data }.count

            if imageCount > VaultCoreConstants.freeMaxImages ||
               videoCount > VaultCoreConstants.freeMaxVideos ||
               fileCount > VaultCoreConstants.freeMaxFiles {
                throw StagedImportError.freeTierLimitExceeded
            }
        }

        // Create batch
        let (batchURL, batchId) = try StagedImportManager.createBatch()
        let fingerprint = KeyDerivation.keyFingerprint(from: key)
        let total = attachments.count
        var fileMetadata: [StagedFileMetadata] = []

        for (index, attachment) in attachments.enumerated() {
            await MainActor.run {
                statusLabel.text = "Encrypting \(index + 1) of \(total) files..."
                progressView.progress = Float(index) / Float(total)
            }

            let meta = try await processAttachment(
                attachment.provider,
                utType: attachment.utType,
                key: key,
                batchURL: batchURL
            )
            fileMetadata.append(meta)
        }

        // Release provider references — NSItemProvider may cache loaded representations
        let sourceApp = receivedItems.first?.attributedContentText.map { _ in
            Bundle.main.bundleIdentifier
        } ?? nil
        receivedItems = []
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

    private func processAttachment(
        _ provider: NSItemProvider,
        utType: UTType,
        key: Data,
        batchURL: URL
    ) async throws -> StagedFileMetadata {
        let fileId = UUID()

        // Load file representation (file URL, not Data — memory safe for large files)
        let (tempURL, filename, mimeType) = try await loadFile(from: provider, utType: utType)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0

        // All synchronous work in autoreleasepool to free UIKit/Foundation temporaries
        // between files, keeping peak memory under the ~120MB extension limit.
        let (encryptedSize, hasThumbnail) = try autoreleasepool {
            // Encrypt directly to output file — peak memory ~256KB instead of entire file
            let encryptedURL = batchURL.appendingPathComponent("\(fileId.uuidString).enc")
            FileManager.default.createFile(atPath: encryptedURL.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: encryptedURL)
            defer { try? outputHandle.close() }
            try CryptoEngine.encryptFileStreamingToHandle(from: tempURL, to: outputHandle, with: key)
            let encSize = (try? FileManager.default.attributesOfItem(atPath: encryptedURL.path)[.size] as? Int) ?? 0

            // Generate and encrypt thumbnail for images using CGImageSource
            // (avoids loading full bitmap — peak memory ~200KB vs ~48MB for UIImage)
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
    }

    private func loadFile(
        from provider: NSItemProvider,
        utType: UTType
    ) async throws -> (url: URL, filename: String, mimeType: String) {
        // Capture registered types and provider reference before the @Sendable closure.
        // NSItemProvider is not Sendable but loadFileRepresentation is thread-safe.
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

                // Copy to a temp location since the provided URL may be deleted.
                // Use UUID prefix to avoid collisions when sharing multiple files.
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let filename = url.lastPathComponent

                // Derive concrete MIME type from the file extension (UTType.image is
                // abstract and has no preferredMIMEType). Fall back to the provider's
                // registered types if the extension doesn't resolve.
                let fileUTType = UTType(filenameExtension: url.pathExtension)
                let mimeType = fileUTType?.preferredMIMEType
                    ?? registeredTypes.lazy
                        .compactMap { UTType($0)?.preferredMIMEType }
                        .first
                    ?? "application/octet-stream"

                continuation.resume(returning: (tempURL, filename, mimeType))
            }
        }
    }

    /// Generates a thumbnail using ImageIO (CGImageSource), which reads only the
    /// metadata and a downsampled version of the image — never the full bitmap.
    /// Peak memory: ~200KB vs ~48MB+ for UIImage on a 12MP photo.
    private func generateThumbnail(from url: URL) -> Data? {
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

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.6)
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
