import SwiftUI
import PhotosUI
import UIKit

enum FileFilter: String, CaseIterable {
    case all = "All"
    case images = "Images"
    case other = "Other"
}

enum SortOrder: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case sizeSmallest = "Smallest"
    case sizeLargest = "Largest"
    case name = "Name"
}

// MARK: - Date Grouping

struct DateGroup: Identifiable {
    let id: String // group title
    let title: String
    let images: [VaultFileItem]
    let files: [VaultFileItem] // non-image files
}

private func groupFilesByDate(_ items: [VaultFileItem]) -> [DateGroup] {
    let calendar = Calendar.current
    let now = Date()
    let startOfToday = calendar.startOfDay(for: now)
    let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
    let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
    let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

    var buckets: [(title: String, items: [VaultFileItem])] = [
        ("Today", []),
        ("Yesterday", []),
        ("This Week", []),
        ("This Month", []),
        ("Earlier", [])
    ]

    for item in items {
        guard let date = item.createdAt else {
            buckets[4].items.append(item)
            continue
        }
        if date >= startOfToday {
            buckets[0].items.append(item)
        } else if date >= startOfYesterday {
            buckets[1].items.append(item)
        } else if date >= startOfWeek {
            buckets[2].items.append(item)
        } else if date >= startOfMonth {
            buckets[3].items.append(item)
        } else {
            buckets[4].items.append(item)
        }
    }

    return buckets.compactMap { bucket in
        guard !bucket.items.isEmpty else { return nil }
        let images = bucket.items.filter { $0.isImage }
        let files = bucket.items.filter { !$0.isImage }
        return DateGroup(id: bucket.title, title: bucket.title, images: images, files: files)
    }
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
    @State private var sortOrder: SortOrder = .dateNewest
    @State private var isEditing = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showingBatchDeleteConfirmation = false
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

    private var sortedFiles: [VaultFileItem] {
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
        switch sortOrder {
        case .dateNewest:
            result.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .dateOldest:
            result.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .sizeSmallest:
            result.sort { $0.size < $1.size }
        case .sizeLargest:
            result.sort { $0.size > $1.size }
        case .name:
            result.sort { ($0.filename ?? "").localizedStandardCompare($1.filename ?? "") == .orderedAscending }
        }
        return result
    }

    private var splitFiles: (all: [VaultFileItem], images: [VaultFileItem], nonImages: [VaultFileItem]) {
        let result = sortedFiles
        let images = result.filter { $0.isImage }
        let nonImages = result.filter { !$0.isImage }
        return (result, images, nonImages)
    }

    private var useDateGrouping: Bool {
        (sortOrder == .dateNewest || sortOrder == .dateOldest) && fileFilter == .all
    }

    @ViewBuilder
    private func fileGridContent(split: (all: [VaultFileItem], images: [VaultFileItem], nonImages: [VaultFileItem])) -> some View {
        ScrollView {
            if let masterKey {
                if useDateGrouping {
                    dateGroupedContent(masterKey: masterKey)
                } else {
                    flatContent(split: split, masterKey: masterKey)
                }
            } else {
                ProgressView("Decrypting...")
            }
        }
    }

    @ViewBuilder
    private func dateGroupedContent(masterKey: Data) -> some View {
        let groups = groupFilesByDate(sortedFiles)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(groups) { group in
                Section {
                    if !group.images.isEmpty {
                        PhotosGridView(files: group.images, masterKey: masterKey, onSelect: { file, _ in
                            SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                            let allImages = sortedFiles.filter { $0.isImage }
                            let globalIndex = allImages.firstIndex(where: { $0.id == file.id }) ?? 0
                            selectedPhotoIndex = globalIndex
                        }, onDelete: isSharedVault ? nil : deleteFileById,
                           isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                    }
                    if !group.files.isEmpty {
                        FilesGridView(files: group.files, onSelect: { file in
                            SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                            selectedFile = file
                        }, onDelete: isSharedVault ? nil : deleteFileById,
                           isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                        .padding(.top, group.images.isEmpty ? 0 : 12)
                    }
                } header: {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.vaultSecondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    @ViewBuilder
    private func flatContent(split: (all: [VaultFileItem], images: [VaultFileItem], nonImages: [VaultFileItem]), masterKey: Data) -> some View {
        switch fileFilter {
        case .all:
            if !split.images.isEmpty {
                PhotosGridView(files: split.images, masterKey: masterKey, onSelect: { file, index in
                    SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                    selectedPhotoIndex = index
                }, onDelete: isSharedVault ? nil : deleteFileById,
                   isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
            }
            if !split.nonImages.isEmpty {
                FilesGridView(files: split.nonImages, onSelect: { file in
                    SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                    selectedFile = file
                }, onDelete: isSharedVault ? nil : deleteFileById,
                   isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                .padding(.top, split.images.isEmpty ? 0 : 12)
            }
        case .images:
            PhotosGridView(files: split.images, masterKey: masterKey, onSelect: { file, index in
                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedPhotoIndex = index
            }, onDelete: isSharedVault ? nil : deleteFileById,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
        case .other:
            FilesGridView(files: split.nonImages, onSelect: { file in
                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedFile = file
            }, onDelete: isSharedVault ? nil : deleteFileById,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
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
        let split = splitFiles
        NavigationStack {
            Group {
                if isLoading {
                    skeletonGridView
                } else if files.isEmpty {
                    emptyStateView
                } else {
                    ZStack {
                        if split.all.isEmpty {
                            ContentUnavailableView(
                                "No matching files",
                                systemImage: "magnifyingglass",
                                description: Text("No files match \"\(searchText.isEmpty ? fileFilter.rawValue : searchText)\"")
                            )
                        } else {
                            fileGridContent(split: split)
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
                        HStack(spacing: 12) {
                            Button(action: { showingSettings = true }) {
                                Image(systemName: "gear")
                            }
                            .accessibilityLabel("Settings")

                            if !files.isEmpty && !isSharedVault {
                                Button(isEditing ? "Done" : "Edit") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isEditing.toggle()
                                        if !isEditing { selectedIds.removeAll() }
                                    }
                                }
                                .accessibilityLabel(isEditing ? "Exit edit mode" : "Enter edit mode")
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Menu {
                                ForEach(SortOrder.allCases, id: \.self) { order in
                                    Button {
                                        sortOrder = order
                                    } label: {
                                        if sortOrder == order {
                                            Label(order.rawValue, systemImage: "checkmark")
                                        } else {
                                            Text(order.rawValue)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .accessibilityLabel("Sort files")

                            Button(action: lockVault) {
                                Image(systemName: "lock.fill")
                            }
                            .accessibilityLabel("Lock vault")
                        }
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
                    if isEditing {
                        HStack(spacing: 16) {
                            Button(role: .destructive) {
                                showingBatchDeleteConfirmation = true
                            } label: {
                                Label("Delete (\(selectedIds.count))", systemImage: "trash")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(selectedIds.isEmpty)
                        }
                        .padding(.horizontal)
                        .vaultBarMaterial()
                    } else {
                        Button(action: {
                            if subscriptionManager.canAddFile(currentFileCount: files.count) {
                                showingImportOptions = true
                            } else {
                                showingPaywall = true
                            }
                        }) {
                            Label("Protect Files", systemImage: "plus.circle.fill")
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
                files: split.images,
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
        .alert("Delete \(selectedIds.count) Files?", isPresented: $showingBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { batchDelete() }
        } message: {
            Text("These files will be permanently deleted from the vault.")
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

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func batchDelete() {
        guard let key = appState.currentVaultKey else { return }
        let idsToDelete = selectedIds
        Task {
            for id in idsToDelete {
                try? VaultStorage.shared.deleteFile(id: id, with: key)
            }
            await MainActor.run {
                files.removeAll { idsToDelete.contains($0.id) }
                selectedIds.removeAll()
                isEditing = false
            }
        }
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
                        filename: entry.filename,
                        createdAt: entry.createdAt
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

        for data in imagesData {
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
    let createdAt: Date?

    init(id: UUID, size: Int, encryptedThumbnail: Data?, mimeType: String?, filename: String?, createdAt: Date? = nil) {
        self.id = id
        self.size = size
        self.encryptedThumbnail = encryptedThumbnail
        self.mimeType = mimeType
        self.filename = filename
        self.createdAt = createdAt
    }

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

