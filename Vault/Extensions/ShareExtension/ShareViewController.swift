import UIKit
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
    private var patternView: PatternInputView!
    private var titleLabel: UILabel!
    private var statusLabel: UILabel!
    private var progressView: UIProgressView!
    private var cancelButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
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

        Task {
            do {
                try await encryptAndStage(with: key)
                await MainActor.run { showSuccess() }
            } catch {
                await MainActor.run { showError() }
            }
        }
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

        // Write manifest LAST (atomic visibility marker)
        let sourceApp = receivedItems.first?.attributedContentText.map { _ in
            Bundle.main.bundleIdentifier
        } ?? nil
        let manifest = StagedImportManifest(
            batchId: batchId,
            keyFingerprint: fingerprint,
            timestamp: Date(),
            sourceAppBundleId: sourceApp,
            files: fileMetadata
        )
        try StagedImportManager.writeManifest(manifest, to: batchURL)

        // Schedule delayed local notification (5 minutes)
        scheduleImportNotification(fileCount: total)

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

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0

        // Encrypt
        let encryptedData: Data
        if fileSize > VaultCoreConstants.streamingThreshold {
            encryptedData = try CryptoEngine.encryptStreaming(
                fileURL: tempURL,
                originalSize: fileSize,
                with: key
            )
        } else {
            let data = try Data(contentsOf: tempURL)
            encryptedData = try CryptoEngine.encrypt(data, with: key)
        }

        try StagedImportManager.writeEncryptedFile(encryptedData, fileId: fileId, to: batchURL)

        // Generate and encrypt thumbnail for images
        var hasThumbnail = false
        if utType.conforms(to: .image), let thumbData = generateThumbnail(from: tempURL) {
            let encThumb = try CryptoEngine.encrypt(thumbData, with: key)
            try StagedImportManager.writeEncryptedThumbnail(encThumb, fileId: fileId, to: batchURL)
            hasThumbnail = true
        }

        return StagedFileMetadata(
            fileId: fileId,
            filename: filename,
            mimeType: mimeType,
            utType: utType.identifier,
            originalSize: fileSize,
            encryptedSize: encryptedData.count,
            hasThumbnail: hasThumbnail,
            timestamp: Date()
        )
    }

    private func loadFile(
        from provider: NSItemProvider,
        utType: UTType
    ) async throws -> (url: URL, filename: String, mimeType: String) {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: utType.identifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: StagedImportError.encryptionFailed)
                    return
                }

                // Copy to a temp location since the provided URL may be deleted
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let filename = url.lastPathComponent
                let mimeType = utType.preferredMIMEType ?? "application/octet-stream"
                continuation.resume(returning: (tempURL, filename, mimeType))
            }
        }
    }

    private func generateThumbnail(from url: URL) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let maxDimension: CGFloat = 200
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return thumbImage.jpegData(compressionQuality: 0.6)
    }

    // MARK: - Notification

    private func scheduleImportNotification(fileCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Files Ready"
        content.body = "\(fileCount) file\(fileCount == 1 ? "" : "s") waiting to import in Vaultaire"
        content.sound = .default
        content.categoryIdentifier = "PENDING_IMPORT"

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
        Task {
            let key = try await KeyDerivation.deriveKey(from: pattern, gridSize: VaultCoreConstants.gridSize)
            await MainActor.run {
                self.processSharedContent(with: key)
            }
        }
    }
}
