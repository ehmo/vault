import SwiftUI
import PhotosUI
import UIKit

enum FileFilter: String, CaseIterable {
    case all = "All"
    case images = "Images"
    case other = "Other"
}

struct VaultView: View {
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var files: [VaultFileItem] = []
    @State private var masterKey: Data?
    @State private var selectedFile: VaultFileItem?
    @State private var selectedPhotoIndex: Int?
    @State private var showingImportOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingSettings = false
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var fileFilter: FileFilter = .all
    @State private var showingPaywall = false

    // Transfer status
    private var transferManager = BackgroundShareTransferManager.shared

    // Shared vault state
    @State private var isSharedVault = false
    @State private var sharePolicy: VaultStorage.SharePolicy?
    @State private var sharedVaultId: String?
    @State private var updateAvailable = false
    @State private var isUpdating = false
    @State private var selfDestructMessage: String?
    @State private var showSelfDestructAlert = false

    private var splitFiles: (all: [VaultFileItem], images: [VaultFileItem], nonImages: [VaultFileItem]) {
        var result = files
        switch fileFilter {
        case .all: break
        case .images: result = result.filter { ($0.mimeType ?? "").hasPrefix("image/") }
        case .other: result = result.filter { !($0.mimeType ?? "").hasPrefix("image/") }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.filename ?? "").localizedStandardContains(searchText) ||
                ($0.mimeType ?? "").localizedStandardContains(searchText)
            }
        }
        let images = result.filter { $0.isImage }
        let nonImages = result.filter { !$0.isImage }
        return (result, images, nonImages)
    }

    @ViewBuilder
    private var fileGridContent: some View {
        let split = splitFiles
        ScrollView {
            if let masterKey {
                switch fileFilter {
                case .all:
                    if !split.images.isEmpty {
                        PhotosGridView(files: split.images, masterKey: masterKey, onSelect: { file, index in
                            SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                            selectedPhotoIndex = index
                        }, onDelete: isSharedVault ? nil : deleteFileById)
                    }
                    if !split.nonImages.isEmpty {
                        FilesGridView(files: split.nonImages, onSelect: { file in
                            SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                            selectedFile = file
                        }, onDelete: isSharedVault ? nil : deleteFileById)
                        .padding(.top, split.images.isEmpty ? 0 : 12)
                    }
                case .images:
                    PhotosGridView(files: split.images, masterKey: masterKey, onSelect: { file, index in
                        SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                        selectedPhotoIndex = index
                    }, onDelete: isSharedVault ? nil : deleteFileById)
                case .other:
                    FilesGridView(files: split.nonImages, onSelect: { file in
                        SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                        selectedFile = file
                    }, onDelete: isSharedVault ? nil : deleteFileById)
                }
            } else {
                ProgressView("Decrypting...")
            }
        }
    }

    /// Identifiable wrapper so `fullScreenCover(item:)` can drive presentation from an Int index.
    private struct PhotoViewerItem: Identifiable {
        let id: Int // index into splitFiles.images
    }

    private var photoViewerItem: Binding<PhotoViewerItem?> {
        Binding(
            get: { selectedPhotoIndex.map { PhotoViewerItem(id: $0) } },
            set: { selectedPhotoIndex = $0?.id }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    skeletonGridView
                } else if files.isEmpty {
                    emptyStateView
                } else {
                    ZStack {
                        if splitFiles.all.isEmpty {
                            ContentUnavailableView(
                                "No matching files",
                                systemImage: "magnifyingglass",
                                description: Text("No files match \"\(searchText.isEmpty ? fileFilter.rawValue : searchText)\"")
                            )
                        } else {
                            fileGridContent
                        }
                    }
                }
            }
            .navigationTitle(appState.vaultName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search files")
            .toolbar {
                if !showingSettings {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: lockVault) {
                            Image(systemName: "lock.fill")
                        }
                        .accessibilityLabel("Lock vault")
                    }

                    if !files.isEmpty {
                        ToolbarItem(placement: .bottomBar) {
                            Picker("Filter", selection: $fileFilter) {
                                ForEach(FileFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    if isSharedVault {
                        sharedVaultBanner
                    }
                    if appState.hasPendingImports {
                        PendingImportBanner(fileCount: appState.pendingImportCount) {
                            importPendingFiles()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isSharedVault && !files.isEmpty && !showingSettings {
                    Button(action: {
                        if subscriptionManager.canAddFile(currentFileCount: files.count) {
                            showingImportOptions = true
                        } else {
                            showingPaywall = true
                        }
                    }) {
                        Label("Add Files", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .vaultProminentButtonStyle()
                    .padding(.horizontal)
                    .vaultBarMaterial()
                    .accessibilityHint("Import photos, videos, or files into the vault")
                }
            }
        }
        .task {
            loadVault()
        }
        .onChange(of: appState.currentVaultKey) { _, newKey in
            if newKey == nil {
                files = []
                masterKey = nil
                Task { await ThumbnailCache.shared.clear() }
                isLoading = false
                isSharedVault = false
            }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                SentryManager.shared.addBreadcrumb(category: "search.used")
            }
        }
        .onChange(of: fileFilter) { _, _ in
            SentryManager.shared.addBreadcrumb(category: "filter.changed")
        }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing {
                // Reload file list in case files were deleted or vault changed,
                // but don't clear existing files to preserve scroll position
                loadFiles()
                checkSharedVaultStatus()
            }
        }
        .onChange(of: transferManager.status) { _, newStatus in
            if case .importComplete = newStatus {
                loadVault()
                // Auto-reset after reload
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    transferManager.reset()
                }
            } else if case .uploadComplete = newStatus {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    transferManager.reset()
                }
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
        .fullScreenCover(item: photoViewerItem) { item in
            FullScreenPhotoViewer(
                files: splitFiles.images,
                vaultKey: appState.currentVaultKey,
                initialIndex: item.id,
                onDelete: isSharedVault ? nil : { deletedId in
                    if let idx = files.firstIndex(where: { $0.id == deletedId }) {
                        files.remove(at: idx)
                    }
                    selectedPhotoIndex = nil
                },
                allowDownloads: sharePolicy?.allowDownloads ?? true
            )
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
                },
                allowDownloads: sharePolicy?.allowDownloads ?? true
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                VaultSettingsView()
            }
            .presentationDetents([.large])
        }
        .alert("Vault Unavailable", isPresented: $showSelfDestructAlert) {
            Button("OK") {
                selfDestruct()
            }
        } message: {
            Text(selfDestructMessage ?? "This shared vault is no longer available.")
        }
        .premiumPaywall(isPresented: $showingPaywall)
    }

    // MARK: - Shared Vault Banner

    private var sharedVaultBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared Vault")
                        .font(.caption).fontWeight(.medium)

                    if let expires = sharePolicy?.expiresAt {
                        Text("Expires: \(expires, style: .date)")
                            .font(.caption2).foregroundStyle(.vaultSecondaryText)
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
                    .vaultProminentButtonStyle()
                    .controlSize(.mini)
                    .disabled(isUpdating)
                    .accessibilityLabel(isUpdating ? "Updating shared vault" : "Update shared vault")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            if updateAvailable {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    Text("New files available")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
            }
        }
        .vaultBannerBackground()
    }

    // MARK: - Skeleton Loading

    private var skeletonGridView: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<12, id: \.self) { _ in
                    Color.vaultSurface
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.vaultSecondaryText)
                .accessibilityHidden(true)

            Text("This vault is empty")
                .font(.title2)
                .fontWeight(.medium)

            if isSharedVault {
                Text("Waiting for the vault owner to add files")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("Add photos, videos, or files to keep them secure")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)

                Button(action: {
                    if subscriptionManager.canAddFile(currentFileCount: files.count) {
                        showingImportOptions = true
                    } else {
                        showingPaywall = true
                    }
                }) {
                    Label("Add Files", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .vaultProminentButtonStyle()
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
                        let currentVersion = index.sharedVaultVersion ?? 1
                        if let _ = try await CloudKitSharingManager.shared.checkForUpdates(
                            shareVaultId: vaultId, currentVersion: currentVersion
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

            let sharedVault = try SharedVaultData.decode(from: data)

            // Re-import files (delete old, add new)
            for existingFile in index.files where !existingFile.isDeleted {
                try? VaultStorage.shared.deleteFile(id: existingFile.fileId, with: key)
            }

            for file in sharedVault.files {
                let decrypted = try CryptoEngine.decrypt(file.encryptedContent, with: shareKey)

                var thumbnailData: Data? = nil
                if file.mimeType.hasPrefix("image/") {
                    thumbnailData = FileUtilities.generateThumbnail(from: decrypted)
                }

                _ = try VaultStorage.shared.storeFile(
                    data: decrypted,
                    filename: file.filename,
                    mimeType: file.mimeType,
                    with: key,
                    thumbnailData: thumbnailData
                )
            }

            // Store the new version to avoid false "new files available"
            if let newVersion = try? await CloudKitSharingManager.shared.checkForUpdates(
                shareVaultId: vaultId, currentVersion: 0
            ) {
                var updatedIndex = try VaultStorage.shared.loadIndex(with: key)
                updatedIndex.sharedVaultVersion = newVersion
                try VaultStorage.shared.saveIndex(updatedIndex, with: key)
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

    private func deleteFileById(_ id: UUID) {
        guard let key = appState.currentVaultKey else { return }
        Task {
            try? VaultStorage.shared.deleteFile(id: id, with: key)
            await MainActor.run {
                if let idx = files.firstIndex(where: { $0.id == id }) {
                    files.remove(at: idx)
                }
            }
        }
    }

    /// Loads the vault index once and uses it for both file listing and shared-vault checks.
    private func loadVault() {
        guard appState.currentVaultKey != nil else {
            isLoading = false
            return
        }

        // File listing runs off main thread; shared vault check can run concurrently
        loadFiles()
        checkSharedVaultStatus()
    }

    private func importPendingFiles() {
        guard let vaultKey = appState.currentVaultKey else { return }
        Task {
            let result = await ImportIngestor.processPendingImports(for: vaultKey)
            await MainActor.run {
                appState.hasPendingImports = false
                appState.pendingImportCount = 0
                if result.imported > 0 {
                    loadFiles()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }
    }

    private func loadFiles() {
        #if DEBUG
        print("📂 [VaultView] loadFiles() called")
        #endif

        guard let key = appState.currentVaultKey else {
            isLoading = false
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                let result = try VaultStorage.shared.listFilesLightweight(with: key)
                let items = result.files.map { entry in
                    VaultFileItem(
                        id: entry.fileId,
                        size: entry.size,
                        encryptedThumbnail: entry.encryptedThumbnail,
                        mimeType: entry.mimeType,
                        filename: entry.filename
                    )
                }
                await MainActor.run {
                    self.masterKey = result.masterKey
                    self.files = items
                    self.isLoading = false
                    SentryManager.shared.addBreadcrumb(category: "vault.opened", data: ["fileCount": items.count])
                }
            } catch {
                #if DEBUG
                print("❌ [VaultView] Error loading files: \(error)")
                #endif
                await MainActor.run {
                    self.files = []
                    self.isLoading = false
                }
            }
        }
    }

    private func handleCapturedImage(_ imageData: Data) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }

        Task {
            do {
                let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                let thumbnail = FileUtilities.generateThumbnail(from: imageData)
                let fileId = try VaultStorage.shared.storeFile(
                    data: imageData,
                    filename: filename,
                    mimeType: "image/jpeg",
                    with: key,
                    thumbnailData: thumbnail
                )
                // Re-encrypt thumbnail for in-memory model (matches what's stored in index)
                let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: self.masterKey ?? key) }
                await MainActor.run {
                    files.append(VaultFileItem(
                        id: fileId,
                        size: imageData.count,
                        encryptedThumbnail: encThumb,
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
                    let thumbnail = FileUtilities.generateThumbnail(from: data)
                    let fileId = try VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: "image/jpeg",
                        with: key,
                        thumbnailData: thumbnail
                    )
                    let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: self.masterKey ?? key) }
                    await MainActor.run {
                        files.append(VaultFileItem(
                            id: fileId,
                            size: data.count,
                            encryptedThumbnail: encThumb,
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
        let encryptionKey = self.masterKey ?? key

        Task {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else { continue }
                let filename = url.lastPathComponent
                let mimeType = FileUtilities.mimeType(forExtension: url.pathExtension)
                let thumbnail = mimeType.hasPrefix("image/") ? FileUtilities.generateThumbnail(from: data) : nil

                guard let fileId = try? VaultStorage.shared.storeFile(
                    data: data,
                    filename: filename,
                    mimeType: mimeType,
                    with: key,
                    thumbnailData: thumbnail
                ) else { continue }

                let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                files.append(VaultFileItem(
                    id: fileId,
                    size: data.count,
                    encryptedThumbnail: encThumb,
                    mimeType: mimeType,
                    filename: filename
                ))
            }
        }

        // Trigger sync if sharing
        ShareSyncManager.shared.scheduleSync(vaultKey: key)
    }

}

// MARK: - Vault File Item

struct VaultFileItem: Identifiable, Sendable {
    let id: UUID
    let size: Int
    let encryptedThumbnail: Data?
    let mimeType: String?
    let filename: String?

    var isImage: Bool {
        (mimeType ?? "").hasPrefix("image/")
    }
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

            let callback = onImagesSelected
            Task {
                var imagesData: [Data] = []
                for result in results {
                    let provider = result.itemProvider
                    guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                    let image: UIImage? = await withCheckedContinuation { continuation in
                        provider.loadObject(ofClass: UIImage.self) { object, _ in
                            continuation.resume(returning: object as? UIImage)
                        }
                    }
                    if let image, let data = image.jpegData(compressionQuality: 0.8) {
                        imagesData.append(data)
                    }
                }
                await MainActor.run {
                    callback(imagesData)
                }
            }
        }
    }
}

#Preview {
    VaultView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}

