import SwiftUI
import PhotosUI
import UIKit

struct VaultView: View {
    @EnvironmentObject var appState: AppState
    @State private var files: [VaultFileItem] = []
    @State private var selectedFile: VaultFileItem?
    @State private var showingImportOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingSettings = false
    @State private var isLoading = true

    // Transfer status
    @ObservedObject private var transferManager = BackgroundShareTransferManager.shared

    // Shared vault state
    @State private var isSharedVault = false
    @State private var sharePolicy: VaultStorage.SharePolicy?
    @State private var sharedVaultId: String?
    @State private var updateAvailable = false
    @State private var isUpdating = false
    @State private var selfDestructMessage: String?
    @State private var showSelfDestructAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading vault...")
                } else if files.isEmpty {
                    emptyStateView
                } else {
                    FileGridView(files: files, onSelect: { file in
                        selectedFile = file
                    })
                }
            }
            .navigationTitle(appState.vaultName)
            .toolbar {
                if !showingSettings {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: lockVault) {
                            Image(systemName: "lock.fill")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if isSharedVault {
                        sharedVaultBanner
                    }
                    transferStatusBanner
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isSharedVault && !files.isEmpty && !showingSettings {
                    Button(action: { showingImportOptions = true }) {
                        Label("Add Files", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .background(.thinMaterial)
                }
            }
            .overlay {
                // Screenshot prevention for shared vaults
                if isSharedVault && !(sharePolicy?.allowScreenshots ?? false) {
                    ScreenshotPreventionView()
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            loadFiles()
            checkSharedVaultStatus()
        }
        .onChange(of: appState.currentVaultKey) { _, newKey in
            if newKey == nil {
                files = []
                isLoading = false
                isSharedVault = false
            }
        }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing {
                files = []
                isLoading = true
                loadFiles()
                checkSharedVaultStatus()
            }
        }
        .confirmationDialog("Add to Vault", isPresented: $showingImportOptions) {
            Button("Take Photo") { showingCamera = true }
            Button("Choose from Photos") { showingPhotoPicker = true }
            Button("Import File") { showingFilePicker = true }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingCamera) {
            SecureCameraView(onCapture: handleCapturedImage)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker(onImagesSelected: handleSelectedImages)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .sheet(item: $selectedFile) { file in
            SecureImageViewer(
                file: file,
                vaultKey: appState.currentVaultKey,
                onDelete: isSharedVault ? nil : { deletedId in
                    if let idx = files.firstIndex(where: { $0.id == deletedId }) {
                        files.remove(at: idx)
                    }
                    selectedFile = nil
                }
            )
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                VaultSettingsView()
            }
        }
        .alert("Vault Unavailable", isPresented: $showSelfDestructAlert) {
            Button("OK") {
                selfDestruct()
            }
        } message: {
            Text(selfDestructMessage ?? "This shared vault is no longer available.")
        }
    }

    // MARK: - Shared Vault Banner

    private var sharedVaultBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared Vault")
                        .font(.caption).fontWeight(.medium)

                    if let expires = sharePolicy?.expiresAt {
                        Text("Expires: \(expires, style: .date)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if updateAvailable {
                    Button(action: { Task { await downloadUpdate() } }) {
                        if isUpdating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Update Now")
                                .font(.caption).fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(isUpdating)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            if updateAvailable {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("New files available")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
            }
        }
    }

    // MARK: - Transfer Status Banner

    @ViewBuilder
    private var transferStatusBanner: some View {
        switch transferManager.status {
        case .idle:
            EmptyView()

        case .uploading(let progress, let total):
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Uploading shared vault...")
                    .font(.caption)
                Spacer()
                Text("\(progress)/\(total)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))

        case .uploadComplete:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Vault shared successfully")
                    .font(.caption)
                Spacer()
                Button("Dismiss") {
                    transferManager.reset()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .onAppear {
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if case .uploadComplete = transferManager.status {
                        transferManager.reset()
                    }
                }
            }

        case .uploadFailed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Upload failed: \(message)")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button("Dismiss") {
                    transferManager.reset()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))

        case .importing:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Setting up shared vault...")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))

        case .importComplete:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Shared vault is ready")
                    .font(.caption)
                Spacer()
                Button("Dismiss") {
                    transferManager.reset()
                    // Reload files since import completed
                    loadFiles()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .onAppear {
                // Reload files and auto-dismiss
                loadFiles()
                checkSharedVaultStatus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if case .importComplete = transferManager.status {
                        transferManager.reset()
                    }
                }
            }

        case .importFailed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Import failed: \(message)")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button("Dismiss") {
                    transferManager.reset()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("This vault is empty")
                .font(.title2)
                .fontWeight(.medium)

            if isSharedVault {
                Text("Waiting for the vault owner to add files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Add photos, videos, or files to keep them secure")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: { showingImportOptions = true }) {
                    Label("Add Files", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
        }
        .padding()
    }

    // MARK: - Shared Vault Checks

    private func checkSharedVaultStatus() {
        guard let key = appState.currentVaultKey else { return }

        Task {
            do {
                var index = try VaultStorage.shared.loadIndex(with: key)

                let shared = index.isSharedVault ?? false
                await MainActor.run {
                    isSharedVault = shared
                    sharePolicy = index.sharePolicy
                    sharedVaultId = index.sharedVaultId
                }

                guard shared else { return }

                // Check expiration
                if let expires = index.sharePolicy?.expiresAt, Date() > expires {
                    await MainActor.run {
                        selfDestructMessage = "This shared vault has expired. The vault owner set an expiration date of \(expires.formatted(date: .abbreviated, time: .omitted)). All shared files have been removed."
                        showSelfDestructAlert = true
                    }
                    return
                }

                // Check view count
                let currentOpens = (index.openCount ?? 0) + 1
                if let maxOpens = index.sharePolicy?.maxOpens, currentOpens > maxOpens {
                    await MainActor.run {
                        selfDestructMessage = "This shared vault has reached its maximum number of opens. All shared files have been removed."
                        showSelfDestructAlert = true
                    }
                    return
                }

                // Increment open count
                index.openCount = currentOpens
                try VaultStorage.shared.saveIndex(index, with: key)

                // Check for revocation / updates
                if let vaultId = index.sharedVaultId {
                    do {
                        if let _ = try await CloudKitSharingManager.shared.checkForUpdates(
                            shareVaultId: vaultId, currentVersion: 0
                        ) {
                            await MainActor.run {
                                updateAvailable = true
                            }
                        }
                    } catch CloudKitSharingError.revoked {
                        await MainActor.run {
                            selfDestructMessage = "The vault owner has revoked your access to this shared vault. All shared files have been removed."
                            showSelfDestructAlert = true
                        }
                    } catch {
                        // Network error - continue with cached data
                        #if DEBUG
                        print("⚠️ [VaultView] Failed to check for updates: \(error)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("❌ [VaultView] Failed to check shared vault status: \(error)")
                #endif
            }
        }
    }

    private func downloadUpdate() async {
        guard let key = appState.currentVaultKey,
              let vaultId = sharedVaultId else { return }

        isUpdating = true
        defer { isUpdating = false }

        do {
            let index = try VaultStorage.shared.loadIndex(with: key)

            // Use the stored phrase-derived share key
            guard let shareKey = index.shareKeyData else {
                #if DEBUG
                print("❌ [VaultView] No share key stored in vault index")
                #endif
                return
            }

            let data = try await CloudKitSharingManager.shared.downloadUpdatedVault(
                shareVaultId: vaultId,
                shareKey: shareKey
            )

            let sharedVault = try JSONDecoder().decode(SharedVaultData.self, from: data)

            // Re-import files (delete old, add new)
            for existingFile in index.files where !existingFile.isDeleted {
                try? VaultStorage.shared.deleteFile(id: existingFile.fileId, with: key)
            }

            for file in sharedVault.files {
                // Decrypt from share key (files are re-encrypted per-file in SharedVaultData)
                let decrypted = try CryptoEngine.shared.decrypt(file.encryptedContent, with: shareKey)
                _ = try VaultStorage.shared.storeFile(
                    data: decrypted,
                    filename: file.filename,
                    mimeType: file.mimeType,
                    with: key
                )
            }

            updateAvailable = false
            loadFiles()
        } catch {
            #if DEBUG
            print("❌ [VaultView] Failed to download update: \(error)")
            #endif
        }
    }

    private func selfDestruct() {
        guard let key = appState.currentVaultKey else { return }

        // Delete all files and the vault index
        do {
            let index = try VaultStorage.shared.loadIndex(with: key)
            for file in index.files where !file.isDeleted {
                try? VaultStorage.shared.deleteFile(id: file.fileId, with: key)
            }
            try VaultStorage.shared.deleteVaultIndex(for: key)
        } catch {
            #if DEBUG
            print("❌ [VaultView] Self-destruct error: \(error)")
            #endif
        }

        appState.lockVault()
    }

    // MARK: - Actions

    private func lockVault() {
        appState.lockVault()
    }

    private func loadFiles() {
        #if DEBUG
        print("📂 [VaultView] loadFiles() called")
        #endif

        guard let key = appState.currentVaultKey else {
            isLoading = false
            return
        }

        Task {
            do {
                let fileEntries = try VaultStorage.shared.listFiles(with: key)
                let items = fileEntries.map { entry in
                    VaultFileItem(
                        id: entry.fileId,
                        size: entry.size,
                        thumbnailData: entry.thumbnailData,
                        mimeType: entry.mimeType,
                        filename: entry.filename
                    )
                }
                await MainActor.run {
                    files = items
                    isLoading = false
                }
            } catch {
                #if DEBUG
                print("❌ [VaultView] Error loading files: \(error)")
                #endif
                await MainActor.run {
                    files = []
                    isLoading = false
                }
            }
        }
    }

    private func handleCapturedImage(_ imageData: Data) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }

        Task {
            do {
                let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                let thumbnail = generateThumbnail(from: imageData)
                let fileId = try VaultStorage.shared.storeFile(
                    data: imageData,
                    filename: filename,
                    mimeType: "image/jpeg",
                    with: key,
                    thumbnailData: thumbnail
                )
                await MainActor.run {
                    files.append(VaultFileItem(
                        id: fileId,
                        size: imageData.count,
                        thumbnailData: thumbnail,
                        mimeType: "image/jpeg",
                        filename: filename
                    ))
                }

                // Trigger sync if sharing
                ShareSyncManager.shared.scheduleSync(vaultKey: key)
            } catch {
                // Handle error silently
            }
        }
    }

    private func handleSelectedImages(_ imagesData: [Data]) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }

        for (_, data) in imagesData.enumerated() {
            Task {
                do {
                    let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                    let thumbnail = generateThumbnail(from: data)
                    let fileId = try VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: "image/jpeg",
                        with: key,
                        thumbnailData: thumbnail
                    )
                    await MainActor.run {
                        files.append(VaultFileItem(
                            id: fileId,
                            size: data.count,
                            thumbnailData: thumbnail,
                            mimeType: "image/jpeg",
                            filename: filename
                        ))
                    }
                } catch {
                    #if DEBUG
                    print("❌ [VaultView] Failed to add image: \(error)")
                    #endif
                }
            }
        }

        // Trigger sync if sharing
        ShareSyncManager.shared.scheduleSync(vaultKey: key)
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }
        guard case .success(let urls) = result else { return }

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            Task {
                if let data = try? Data(contentsOf: url) {
                    let filename = url.lastPathComponent
                    let mimeType = mimeTypeForExtension(url.pathExtension)
                    let thumbnail = mimeType.hasPrefix("image/") ? generateThumbnail(from: data) : nil

                    if let fileId = try? VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: mimeType,
                        with: key,
                        thumbnailData: thumbnail
                    ) {
                        await MainActor.run {
                            files.append(VaultFileItem(
                                id: fileId,
                                size: data.count,
                                thumbnailData: thumbnail,
                                mimeType: mimeType,
                                filename: filename
                            ))
                        }
                    }
                }
            }
        }

        // Trigger sync if sharing
        ShareSyncManager.shared.scheduleSync(vaultKey: key)
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let maxSize: CGFloat = 200
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.7)
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Vault File Item

struct VaultFileItem: Identifiable {
    let id: UUID
    let size: Int
    let thumbnailData: Data?
    let mimeType: String?
    let filename: String?
}

// MARK: - Screenshot Prevention

/// Uses the UITextField.isSecureTextEntry trick to prevent screen capture.
/// Content placed in this view's layer hierarchy appears black in screenshots/recordings.
struct ScreenshotPreventionView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let secureField = UITextField()
        secureField.isSecureTextEntry = true

        // The secure field's subview blocks screen capture
        guard let secureView = secureField.subviews.first else {
            return UIView()
        }

        let container = UIView()
        container.addSubview(secureView)
        secureView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            secureView.topAnchor.constraint(equalTo: container.topAnchor),
            secureView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            secureView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            secureView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Make it invisible but still blocking captures
        container.isUserInteractionEnabled = false
        container.alpha = 0.01

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Photo Picker Wrapper

struct PhotoPicker: UIViewControllerRepresentable {
    let onImagesSelected: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesSelected: onImagesSelected)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagesSelected: ([Data]) -> Void

        init(onImagesSelected: @escaping ([Data]) -> Void) {
            self.onImagesSelected = onImagesSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            var imagesData: [Data] = []
            let group = DispatchGroup()

            for result in results {
                let itemProvider = result.itemProvider
                if itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                        defer { group.leave() }
                        guard let image = image as? UIImage,
                              let data = image.jpegData(compressionQuality: 0.8) else { return }
                        imagesData.append(data)
                    }
                }
            }

            group.notify(queue: .main) {
                self.onImagesSelected(imagesData)
            }
        }
    }
}

#Preview {
    VaultView()
        .environmentObject(AppState())
}
