import UIKit
import UniformTypeIdentifiers

/// Share Extension that allows importing files from other apps into Vault.
/// IMPORTANT: This extension requires pattern authentication before accepting files.
class ShareViewController: UIViewController {

    private var patternState = PatternInputState()
    private var receivedItems: [NSExtensionItem] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSharedItems()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let patternView = PatternInputView(frame: .zero)
        patternView.translatesAutoresizingMaskIntoConstraints = false
        patternView.delegate = self
        view.addSubview(patternView)

        let titleLabel = UILabel()
        titleLabel.text = "Draw pattern to add to Vault"
        titleLabel.textAlignment = .center
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            patternView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            patternView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            patternView.widthAnchor.constraint(equalToConstant: 280),
            patternView.heightAnchor.constraint(equalToConstant: 280),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    // MARK: - Load Shared Items

    private func loadSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return
        }
        receivedItems = extensionItems
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.vault.app", code: 0))
    }

    private func completeWithSuccess() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Process Shared Content

    private func processSharedContent(with key: Data) {
        for item in receivedItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                processAttachment(attachment, with: key)
            }
        }
    }

    private func processAttachment(_ attachment: NSItemProvider, with key: Data) {
        // Try to load as image
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            attachment.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.saveToVault(data: data, filename: "IMG_\(Date().timeIntervalSince1970).jpg", mimeType: "image/jpeg", key: key)
            }
            return
        }

        // Try to load as video
        if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            attachment.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                guard let url = url, error == nil,
                      let data = try? Data(contentsOf: url) else { return }
                self?.saveToVault(data: data, filename: url.lastPathComponent, mimeType: "video/quicktime", key: key)
            }
            return
        }

        // Try to load as generic data
        if attachment.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            attachment.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.saveToVault(data: data, filename: "file_\(Date().timeIntervalSince1970)", mimeType: "application/octet-stream", key: key)
            }
        }
    }

    private func saveToVault(data: Data, filename: String, mimeType: String, key: Data) {
        // Save to App Group shared container for main app to process
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.vault.app") else {
            return
        }

        let pendingDir = containerURL.appendingPathComponent("pending_imports")
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        // Encrypt the data before saving
        guard let encrypted = try? CryptoEngineShared.encrypt(data, with: key) else {
            return
        }

        // Create metadata
        let metadata = ImportMetadata(
            filename: filename,
            mimeType: mimeType,
            originalSize: data.count,
            timestamp: Date()
        )

        // Save encrypted file
        let fileId = UUID().uuidString
        let encryptedURL = pendingDir.appendingPathComponent("\(fileId).encrypted")
        let metadataURL = pendingDir.appendingPathComponent("\(fileId).meta")

        try? encrypted.write(to: encryptedURL)
        try? JSONEncoder().encode(metadata).write(to: metadataURL)

        DispatchQueue.main.async {
            self.completeWithSuccess()
        }
    }
}

// MARK: - Pattern Input State

class PatternInputState {
    var selectedNodes: [Int] = []
    var gridSize: Int = 4
}

// MARK: - Pattern Input View (UIKit version for extension)

class PatternInputView: UIView {
    weak var delegate: PatternInputDelegate?

    private var gridSize = 4
    private var selectedNodes: [Int] = []
    private var nodeViews: [UIView] = []
    private var currentPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupNodes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupNodes()
    }

    private func setupNodes() {
        backgroundColor = .clear

        let spacing: CGFloat = 70
        let nodeRadius: CGFloat = 12

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = CGFloat(col) * spacing + nodeRadius
                let y = CGFloat(row) * spacing + nodeRadius

                let nodeView = UIView()
                nodeView.backgroundColor = .secondaryLabel
                nodeView.layer.cornerRadius = nodeRadius
                nodeView.frame = CGRect(x: x - nodeRadius, y: y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
                addSubview(nodeView)
                nodeViews.append(nodeView)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        handleTouch(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        handleTouch(at: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !selectedNodes.isEmpty {
            delegate?.patternInputView(self, didCompleteWithPattern: selectedNodes)
        }
        resetPattern()
    }

    private func handleTouch(at point: CGPoint) {
        currentPoint = point

        for (index, nodeView) in nodeViews.enumerated() {
            let center = nodeView.center
            let distance = hypot(point.x - center.x, point.y - center.y)

            if distance < 30 && !selectedNodes.contains(index) {
                selectedNodes.append(index)
                nodeView.backgroundColor = .systemBlue
            }
        }

        setNeedsDisplay()
    }

    private func resetPattern() {
        selectedNodes = []
        for nodeView in nodeViews {
            nodeView.backgroundColor = .secondaryLabel
        }
        setNeedsDisplay()
    }
}

// MARK: - Pattern Input Delegate

protocol PatternInputDelegate: AnyObject {
    func patternInputView(_ view: PatternInputView, didCompleteWithPattern pattern: [Int])
}

extension ShareViewController: PatternInputDelegate {
    func patternInputView(_ view: PatternInputView, didCompleteWithPattern pattern: [Int]) {
        Task {
            do {
                let key = try await KeyDerivationShared.deriveKey(from: pattern)
                processSharedContent(with: key)
            } catch {
                // Pattern invalid - show as accepted anyway (no error indication)
                completeWithSuccess()
            }
        }
    }
}

// MARK: - Import Metadata

struct ImportMetadata: Codable {
    let filename: String
    let mimeType: String
    let originalSize: Int
    let timestamp: Date
}

// MARK: - Shared Crypto (simplified for extension)

enum CryptoEngineShared {
    static func encrypt(_ data: Data, with key: Data) throws -> Data {
        // Simplified encryption for extension
        // In production, would share code with main app via framework
        guard key.count == 32 else { throw NSError(domain: "crypto", code: 1) }

        // Use CommonCrypto for AES encryption
        var outData = Data(count: data.count + 16)
        var numBytesEncrypted: size_t = 0

        // Generate IV
        var iv = Data(count: 16)
        _ = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }

        let status = outData.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outPtr.baseAddress, outData.count,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw NSError(domain: "crypto", code: Int(status))
        }

        outData.count = numBytesEncrypted

        // Prepend IV
        var result = iv
        result.append(outData)
        return result
    }
}

enum KeyDerivationShared {
    static func deriveKey(from pattern: [Int]) async throws -> Data {
        // Simplified key derivation for extension
        guard pattern.count >= 6 else {
            throw NSError(domain: "pattern", code: 1)
        }

        let patternData = Data(pattern.map { UInt8($0) })
        var derivedKey = Data(count: 32)

        // Get salt from shared keychain
        let salt = try await getSalt()

        let result = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            patternData.withUnsafeBytes { patternPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        patternPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        patternData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        600_000,
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw NSError(domain: "kdf", code: Int(result))
        }

        return derivedKey
    }

    private static func getSalt() async throws -> Data {
        // Access shared keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vault.app.device.salt",
            kSecAttrAccessGroup as String: "group.com.vault.app",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            // Return dummy salt if not found (will fail decryption)
            return Data(count: 32)
        }

        return data
    }
}

import CommonCrypto
import Security
