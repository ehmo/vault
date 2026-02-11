import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

enum FileFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    case documents = "Documents"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .photos: "photo"
        case .videos: "video"
        case .documents: "doc"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case sizeSmallest = "Smallest"
    case sizeLargest = "Largest"
    case name = "Name"
}

enum PendingImport {
    case photos([PHPickerResult])
    case files([URL])
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
    @State private var showingFanMenu = false
    @State private var exportURLs: [URL] = []
    @State private var toastMessage: ToastMessage?
    @State private var importProgress: (completed: Int, total: Int)?
    @State private var showingLimitAlert = false
    @State private var pendingImport: PendingImport?
    @State private var limitAlertRemaining = 0
    @State private var limitAlertSelected = 0
    private let floatingButtonTrailingInset: CGFloat = 15
    private let floatingButtonBottomInset: CGFloat = -15

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
        case .photos: result = result.filter { ($0.mimeType ?? "").hasPrefix("image/") }
        case .videos: result = result.filter { ($0.mimeType ?? "").hasPrefix("video/") }
        case .documents: result = result.filter {
            let mime = $0.mimeType ?? ""
            return !mime.hasPrefix("image/") && !mime.hasPrefix("video/")
        }
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

    private var splitFiles: (all: [VaultFileItem], images: [VaultFileItem], videos: [VaultFileItem], documents: [VaultFileItem]) {
        let result = sortedFiles
        let images = result.filter { ($0.mimeType ?? "").hasPrefix("image/") }
        let videos = result.filter { ($0.mimeType ?? "").hasPrefix("video/") }
        let documents = result.filter {
            let mime = $0.mimeType ?? ""
            return !mime.hasPrefix("image/") && !mime.hasPrefix("video/")
        }
        return (result, images, videos, documents)
    }

    private var useDateGrouping: Bool {
        sortOrder == .dateNewest || sortOrder == .dateOldest
    }

    @ViewBuilder
    private func fileGridContent(split: (all: [VaultFileItem], images: [VaultFileItem], videos: [VaultFileItem], documents: [VaultFileItem])) -> some View {
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
                            let allImages = sortedFiles.filter { ($0.mimeType ?? "").hasPrefix("image/") }
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
    private func flatContent(split: (all: [VaultFileItem], images: [VaultFileItem], videos: [VaultFileItem], documents: [VaultFileItem]), masterKey: Data) -> some View {
        let nonImages = split.videos + split.documents
        switch fileFilter {
        case .all:
            if !split.images.isEmpty {
                PhotosGridView(files: split.images, masterKey: masterKey, onSelect: { file, index in
                    SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                    selectedPhotoIndex = index
                }, onDelete: isSharedVault ? nil : deleteFileById,
                   isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
            }
            if !nonImages.isEmpty {
                FilesGridView(files: nonImages, onSelect: { file in
                    SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                    selectedFile = file
                }, onDelete: isSharedVault ? nil : deleteFileById,
                   isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                .padding(.top, split.images.isEmpty ? 0 : 12)
            }
        case .photos:
            PhotosGridView(files: split.images, masterKey: masterKey, onSelect: { file, index in
                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedPhotoIndex = index
            }, onDelete: isSharedVault ? nil : deleteFileById,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
        case .videos:
            FilesGridView(files: split.videos, onSelect: { file in
                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedFile = file
            }, onDelete: isSharedVault ? nil : deleteFileById,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
        case .documents:
            FilesGridView(files: split.documents, onSelect: { file in
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
            .toolbar {
                if !showingSettings {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                        .accessibilityIdentifier("vault_settings_button")
                        .accessibilityLabel("Settings")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            if !files.isEmpty {
                                StorageRingView(
                                    fileCount: files.count,
                                    maxFiles: subscriptionManager.isPremium ? nil : SubscriptionManager.maxFreeFilesPerVault,
                                    totalBytes: Int64(files.reduce(0) { $0 + $1.size })
                                )
                            }

                            Button(action: lockVault) {
                                Image(systemName: "lock.fill")
                            }
                            .accessibilityIdentifier("vault_lock_button")
                            .accessibilityLabel("Lock vault")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    if !files.isEmpty && !showingSettings {
                        HStack(spacing: 8) {
                            if isEditing {
                                // Select All / Deselect All button
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedIds.count == sortedFiles.count {
                                            selectedIds.removeAll()
                                        } else {
                                            selectedIds = Set(sortedFiles.map(\.id))
                                        }
                                    }
                                } label: {
                                    Text(selectedIds.count == sortedFiles.count ? "Deselect All" : "Select All (\(sortedFiles.count))")
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .vaultGlassBackground(cornerRadius: 12)
                                }
                                .accessibilityIdentifier("vault_select_all")

                                // Done button
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isEditing = false
                                        selectedIds.removeAll()
                                    }
                                } label: {
                                    Text("Done")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .vaultGlassBackground(cornerRadius: 12)
                                }
                                .accessibilityIdentifier("vault_edit_done")
                            } else {
                                // Search bar
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.vaultSecondaryText)
                                    TextField("Search files", text: $searchText)
                                        .textFieldStyle(.plain)
                                        .accessibilityIdentifier("vault_search_field")
                                    if !searchText.isEmpty {
                                        Button {
                                            searchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.vaultSecondaryText)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                                .vaultGlassBackground(cornerRadius: 12)

                                // Filter & sort menu
                                Menu {
                                    Section("Filter") {
                                        ForEach(FileFilter.allCases) { filter in
                                            Button {
                                                fileFilter = filter
                                            } label: {
                                                if fileFilter == filter {
                                                    Label(filter.rawValue, systemImage: "checkmark")
                                                } else {
                                                    Label(filter.rawValue, systemImage: filter.icon)
                                                }
                                            }
                                        }
                                    }
                                    Section("Sort") {
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
                                    }
                                } label: {
                                    Image(systemName: fileFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                                        .fontWeight(.medium)
                                        .padding(10)
                                        .vaultGlassBackground(cornerRadius: 12)
                                }
                                .accessibilityIdentifier("vault_filter_menu")
                                .accessibilityLabel("Filter and sort")

                                // Select button (hidden for shared vaults)
                                if !isSharedVault {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isEditing = true
                                        }
                                    } label: {
                                        Image(systemName: "checkmark.circle")
                                            .fontWeight(.medium)
                                            .padding(10)
                                            .vaultGlassBackground(cornerRadius: 12)
                                    }
                                    .accessibilityIdentifier("vault_select_button")
                                    .accessibilityLabel("Select files")
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
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
                if isEditing && !selectedIds.isEmpty && !files.isEmpty && !showingSettings {
                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            showingBatchDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityIdentifier("vault_edit_delete")

                        Button {
                            batchExport()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .vaultProminentButtonStyle()
                        .accessibilityIdentifier("vault_edit_export")
                    }
                    .padding(.horizontal)
                    .vaultBarMaterial()
                }
            }
            .overlay {
                Color.black.opacity(showingFanMenu ? 0.3 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(showingFanMenu)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            showingFanMenu = false
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: showingFanMenu)
            }
            .overlay {
                if let progress = importProgress {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        localImportProgressView(completed: progress.completed, total: progress.total)
                    }
                    .accessibilityIdentifier("vault_local_import_progress")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                fanMenuItems
                    .padding(.trailing, floatingButtonTrailingInset)
                    .padding(.bottom, floatingButtonBottomInset)
                    .opacity(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing ? 1 : 0)
                    .allowsHitTesting(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing)
            }
            .overlay(alignment: .bottomTrailing) {
                mainPlusButton
                    .padding(.trailing, floatingButtonTrailingInset)
                    .padding(.bottom, floatingButtonBottomInset)
                    .opacity(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing ? 1 : 0)
                    .allowsHitTesting(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing)
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
        .confirmationDialog("Protect New Files", isPresented: $showingImportOptions) {
            Button("Take Secure Photo") { showingCamera = true }
            Button("Import from Library") { showingPhotoPicker = true }
            Button("Import Documents") { showingFilePicker = true }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingCamera) {
            SecureCameraView(onCapture: handleCapturedImage)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker(onPhotosSelected: handleSelectedPhotos)
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
        .toast($toastMessage)
        .alert("Delete \(selectedIds.count) Files?", isPresented: $showingBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { batchDelete() }
        } message: {
            Text("These files will be permanently deleted from the vault.")
        }
        .premiumPaywall(isPresented: $showingPaywall)
        .alert("Free Plan Limit", isPresented: $showingLimitAlert) {
            if limitAlertRemaining > 0 {
                Button("Import \(limitAlertRemaining) Files") {
                    proceedWithLimitedImport()
                }
            }
            Button("Upgrade to PRO") {
                pendingImport = nil
                showingPaywall = true
            }
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
        } message: {
            if limitAlertRemaining > 0 {
                Text("You selected \(limitAlertSelected) files, but free vaults can only store 100 files. You have room for \(limitAlertRemaining) more.")
            } else {
                Text("Free vaults can only store 100 files. Upgrade to PRO for unlimited storage.")
            }
        }
        .onChange(of: exportURLs) { _, urls in
            guard !urls.isEmpty else { return }
            ShareSheetHelper.present(items: urls) {
                cleanupExportFiles()
                selectedIds.removeAll()
                isEditing = false
            }
        }
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
            if case .importing = transferManager.status {
                Spacer()
                importingProgressView
                Spacer()
            } else if isSharedVault {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.vaultSecondaryText)
                    .accessibilityHidden(true)

                Text("Waiting for files")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("The vault owner hasn't added any files yet")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Spacer()

                // 3-step walkthrough
                VStack(spacing: 12) {
                    walkthroughCard(
                        icon: "plus.circle.fill",
                        title: "Add your files",
                        description: "Photos, videos, documents — anything you want to protect"
                    )
                    walkthroughCard(
                        icon: "lock.shield.fill",
                        title: "Encrypted instantly",
                        description: "Your files are scrambled with military-grade encryption"
                    )
                    walkthroughCard(
                        icon: "eye.slash.fill",
                        title: "Only you can access",
                        description: "Your pattern is the only key. Not even us."
                    )
                }

                Spacer()

                Button(action: {
                    if subscriptionManager.canAddFile(currentFileCount: files.count) {
                        showingImportOptions = true
                    } else {
                        showingPaywall = true
                    }
                }) {
                    Label("Protect Your First Files", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .vaultProminentButtonStyle()
                .accessibilityIdentifier("vault_first_files")
                .accessibilityHint("Import photos, videos, or files into the vault")
            }
        }
        .padding()
    }

    @ViewBuilder
    private func walkthroughCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.vaultSecondaryText)
            }

            Spacer()
        }
        .padding(14)
        .vaultGlassBackground(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Import Progress

    private var importingProgressView: some View {
        VStack(spacing: 24) {
            PixelAnimation.loading(size: 60)

            Text("Downloading shared vault...")
                .font(.title3)
                .fontWeight(.medium)

            if transferManager.displayProgress > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(transferManager.displayProgress), total: 100)
                        .tint(.accentColor)
                        .padding(.horizontal, 40)

                    Text("\(transferManager.displayProgress)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.vaultSecondaryText)
                }
            }

            Text(transferManager.currentMessage)
                .font(.caption)
                .foregroundStyle(.vaultSecondaryText)
        }
        .accessibilityIdentifier("vault_import_progress")
    }

    // MARK: - Local Import Progress

    private func localImportProgressView(completed: Int, total: Int) -> some View {
        let percentage = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
        return VStack(spacing: 24) {
            PixelAnimation.loading(size: 60)

            Text("Importing \(completed) of \(total)...")
                .font(.title3)
                .fontWeight(.medium)

            VStack(spacing: 8) {
                ProgressView(value: Double(completed), total: Double(total))
                    .tint(.accentColor)
                    .padding(.horizontal, 40)

                Text("\(percentage)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.vaultSecondaryText)
            }
        }
    }

    // MARK: - Fan Menu

    private struct FanItem {
        let icon: String
        let label: String
        var accessibilityId: String? = nil
        let action: () -> Void
    }

    private var fanMenuItems: some View {
        let items = [
            FanItem(icon: "camera.fill", label: "Camera", accessibilityId: "vault_add_camera") {
                showingFanMenu = false
                showingCamera = true
            },
            FanItem(icon: "photo.on.rectangle", label: "Library", accessibilityId: "vault_add_library") {
                showingFanMenu = false
                showingPhotoPicker = true
            },
            FanItem(icon: "doc.fill", label: "Files", accessibilityId: "vault_add_files") {
                showingFanMenu = false
                showingFilePicker = true
            },
        ]

        // Fan spreads upward-left from the + button in a quarter-circle
        let fanRadius: CGFloat = 80
        let startAngle: Double = 180 // straight left (camera aligned with + button)
        let endAngle: Double = 270   // straight up (documents aligned with + button)

        return ZStack(alignment: .bottomTrailing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let angle: Double = items.count == 1
                    ? startAngle
                    : startAngle + (endAngle - startAngle) * Double(index) / Double(items.count - 1)
                let radians = angle * .pi / 180

                Button {
                    item.action()
                } label: {
                    Image(systemName: item.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .accessibilityLabel(item.label)
                .accessibilityIdentifier(item.accessibilityId ?? item.label)
                .offset(
                    x: showingFanMenu ? cos(radians) * fanRadius : 0,
                    y: showingFanMenu ? sin(radians) * fanRadius : 0
                )
                .scaleEffect(showingFanMenu ? 1 : 0.3)
                .opacity(showingFanMenu ? 1 : 0)
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.7)
                        .delay(showingFanMenu ? Double(index) * 0.05 : 0),
                    value: showingFanMenu
                )
            }
            // Invisible spacer so ZStack matches button size for alignment
            Color.clear.frame(width: 52, height: 52)
        }
    }

    private var mainPlusButton: some View {
        Button {
            if subscriptionManager.canAddFile(currentFileCount: files.count) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showingFanMenu.toggle()
                }
            } else {
                showingPaywall = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(showingFanMenu ? Color(.systemGray) : Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .rotationEffect(.degrees(showingFanMenu ? 45 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vault_add_button")
        .accessibilityLabel(showingFanMenu ? "Close menu" : "Add files")
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

            if SVDFSerializer.isSVDF(data) {
                // SVDF v4 delta import: only import new files, delete removed files
                try await importSVDFDelta(data: data, shareKey: shareKey, vaultKey: key, index: index)
            } else {
                // Legacy v1-v3: full wipe-and-replace
                try await importLegacyFull(data: data, shareKey: shareKey, vaultKey: key, index: index)
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

    /// SVDF v4 delta import: parse manifest, diff file IDs vs local, import only new files.
    private func importSVDFDelta(data: Data, shareKey: Data, vaultKey: Data, index: VaultStorage.VaultIndex) async throws {
        let manifest = try SVDFSerializer.parseManifest(from: data, shareKey: shareKey)
        let remoteFileIds = Set(manifest.filter { !$0.deleted }.map { $0.id })
        let localFileIds = Set(index.files.filter { !$0.isDeleted }.map { $0.fileId.uuidString })

        // Delete files that were removed remotely
        let removedIds = localFileIds.subtracting(remoteFileIds)
        for removedId in removedIds {
            if let uuid = UUID(uuidString: removedId) {
                try? VaultStorage.shared.deleteFile(id: uuid, with: vaultKey)
            }
        }

        // Import only new files
        let newIds = remoteFileIds.subtracting(localFileIds)
        for entry in manifest where newIds.contains(entry.id) && !entry.deleted {
            let file = try SVDFSerializer.extractFileEntry(from: data, at: entry.offset, size: entry.size)
            let decrypted = try CryptoEngine.decrypt(file.encryptedContent, with: shareKey)

            var thumbnailData: Data? = nil
            if file.mimeType.hasPrefix("image/") {
                thumbnailData = FileUtilities.generateThumbnail(from: decrypted)
            }

            _ = try VaultStorage.shared.storeFile(
                data: decrypted,
                filename: file.filename,
                mimeType: file.mimeType,
                with: vaultKey,
                thumbnailData: thumbnailData
            )
        }

        #if DEBUG
        print("📦 [VaultView] SVDF delta: \(newIds.count) new, \(removedIds.count) removed, \(localFileIds.intersection(remoteFileIds).count) unchanged")
        #endif
    }

    /// Legacy v1-v3 full wipe-and-replace import.
    private func importLegacyFull(data: Data, shareKey: Data, vaultKey: Data, index: VaultStorage.VaultIndex) async throws {
        let sharedVault = try SharedVaultData.decode(from: data)

        // Delete all existing files
        for existingFile in index.files where !existingFile.isDeleted {
            try? VaultStorage.shared.deleteFile(id: existingFile.fileId, with: vaultKey)
        }

        // Import all files
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
                with: vaultKey,
                thumbnailData: thumbnailData
            )
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
        let count = idsToDelete.count
        Task {
            for id in idsToDelete {
                try? VaultStorage.shared.deleteFile(id: id, with: key)
            }
            await MainActor.run {
                files.removeAll { idsToDelete.contains($0.id) }
                selectedIds.removeAll()
                isEditing = false
                toastMessage = .filesDeleted(count)
            }
        }
    }

    private func batchExport() {
        guard let key = appState.currentVaultKey else { return }
        let idsToExport = selectedIds
        let filesList = files

        Task.detached(priority: .userInitiated) {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            var urls: [URL] = []

            for id in idsToExport {
                guard let result = try? VaultStorage.shared.retrieveFile(id: id, with: key) else { continue }
                let file = filesList.first { $0.id == id }
                let filename = file?.filename ?? "Export_\(id.uuidString)"
                let url = tempDir.appendingPathComponent(filename)
                try? result.content.write(to: url, options: [.atomic])
                urls.append(url)
            }
            
            let finalizedURLs = urls
            
            await MainActor.run { [finalizedURLs] in
                self.exportURLs = finalizedURLs
            }
        }
    }

    private func cleanupExportFiles() {
        for url in exportURLs {
            try? FileManager.default.removeItem(at: url)
        }
        exportURLs = []
    }

    private func deleteFileById(_ id: UUID) {
        guard let key = appState.currentVaultKey else { return }
        Task {
            try? VaultStorage.shared.deleteFile(id: id, with: key)
            await MainActor.run {
                if let idx = files.firstIndex(where: { $0.id == id }) {
                    files.remove(at: idx)
                }
                toastMessage = .filesDeleted(1)
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
                    if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: files.count) {
                        toastMessage = .milestone(milestone)
                    } else {
                        toastMessage = .fileEncrypted()
                    }
                }

                // Trigger sync if sharing
                await ShareSyncManager.shared.scheduleSync(vaultKey: key)
            } catch {
                // Handle error silently
            }
        }
    }

    private func handleSelectedPhotos(_ results: [PHPickerResult]) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - files.count)
            if remaining == 0 {
                showingPaywall = true
                return
            }
            if results.count > remaining {
                pendingImport = .photos(results)
                limitAlertSelected = results.count
                limitAlertRemaining = remaining
                showingLimitAlert = true
                return
            }
        }

        performPhotoImport(results)
    }

    private func performPhotoImport(_ results: [PHPickerResult]) {
        guard let key = appState.currentVaultKey else { return }
        let encryptionKey = self.masterKey ?? key
        let count = results.count

        // Show progress IMMEDIATELY — before any async image loading
        importProgress = (0, count)

        Task.detached(priority: .userInitiated) {
            var successCount = 0
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

                do {
                    let (data, filename, mimeType, thumbnail): (Data, String, String, Data?)

                    if isVideo {
                        // Load video via file representation
                        let videoData = try await Self.loadVideoData(from: provider)
                        let ext = provider.suggestedName.flatMap { URL(string: $0)?.pathExtension } ?? "mov"
                        let mime = FileUtilities.mimeType(forExtension: ext)
                        let thumbData = await Self.generateVideoThumbnail(from: videoData)

                        data = videoData
                        filename = provider.suggestedName ?? "VID_\(Date().timeIntervalSince1970)_\(index).\(ext)"
                        mimeType = mime.hasPrefix("video/") ? mime : "video/quicktime"
                        thumbnail = thumbData
                    } else {
                        // Load image via UIImage
                        guard provider.canLoadObject(ofClass: UIImage.self) else {
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }

                        let image: UIImage? = await withCheckedContinuation { continuation in
                            provider.loadObject(ofClass: UIImage.self) { object, _ in
                                continuation.resume(returning: object as? UIImage)
                            }
                        }

                        guard let image, let jpegData = image.jpegData(compressionQuality: 0.8) else {
                            await MainActor.run { self.importProgress = (index + 1, count) }
                            continue
                        }

                        data = jpegData
                        filename = "IMG_\(Date().timeIntervalSince1970)_\(index).jpg"
                        mimeType = "image/jpeg"
                        thumbnail = FileUtilities.generateThumbnail(from: jpegData)
                    }

                    let fileId = try VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: mimeType,
                        with: key,
                        thumbnailData: thumbnail
                    )
                    let encThumb = thumbnail.flatMap { try? CryptoEngine.encrypt($0, with: encryptionKey) }
                    await MainActor.run {
                        self.files.append(VaultFileItem(
                            id: fileId,
                            size: data.count,
                            encryptedThumbnail: encThumb,
                            mimeType: mimeType,
                            filename: filename
                        ))
                        self.importProgress = (index + 1, count)
                    }
                    successCount += 1
                } catch {
                    await MainActor.run { self.importProgress = (index + 1, count) }
                    #if DEBUG
                    print("❌ [VaultView] Failed to import item \(index): \(error)")
                    #endif
                }
            }

            await MainActor.run {
                self.importProgress = nil
                if let milestone = MilestoneTracker.shared.checkFirstFile(totalCount: self.files.count) {
                    self.toastMessage = .milestone(milestone)
                } else {
                    self.toastMessage = .filesImported(successCount)
                }
            }

            await ShareSyncManager.shared.scheduleSync(vaultKey: key)
        }
    }

    /// Load video data from a PHPicker item provider
    private static func loadVideoData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                // Must copy data before the callback returns — the URL is temporary
                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate a thumbnail from video data using AVAssetImageGenerator
    private static func generateVideoThumbnail(from data: Data) async -> Data? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try data.write(to: tempURL)
            let asset = AVAsset(url: tempURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            return nil
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard !isSharedVault, let key = appState.currentVaultKey else { return }
        guard case .success(let urls) = result else { return }

        if !subscriptionManager.isPremium {
            let remaining = max(0, SubscriptionManager.maxFreeFilesPerVault - files.count)
            if remaining == 0 {
                showingPaywall = true
                return
            }
            if urls.count > remaining {
                pendingImport = .files(urls)
                limitAlertSelected = urls.count
                limitAlertRemaining = remaining
                showingLimitAlert = true
                return
            }
        }

        performFileImport(urls)
    }

    private func performFileImport(_ urls: [URL]) {
        guard let key = appState.currentVaultKey else { return }
        let encryptionKey = self.masterKey ?? key
        let count = urls.count
        let showProgress = count > 1

        // Show progress immediately on main actor before detaching
        if showProgress {
            importProgress = (0, count)
        }

        Task.detached(priority: .userInitiated) {
            var successCount = 0
            for (index, url) in urls.enumerated() {
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
                await MainActor.run {
                    self.files.append(VaultFileItem(
                        id: fileId,
                        size: data.count,
                        encryptedThumbnail: encThumb,
                        mimeType: mimeType,
                        filename: filename
                    ))
                    if showProgress {
                        self.importProgress = (index + 1, count)
                    }
                }
                successCount += 1
            }

            await MainActor.run {
                self.importProgress = nil
                self.toastMessage = .filesImported(successCount)
            }

            await ShareSyncManager.shared.scheduleSync(vaultKey: key)
        }
    }

    private func proceedWithLimitedImport() {
        guard let pending = pendingImport else { return }
        let remaining = limitAlertRemaining
        pendingImport = nil

        switch pending {
        case .photos(let results):
            performPhotoImport(Array(results.prefix(remaining)))
        case .files(let urls):
            performFileImport(Array(urls.prefix(remaining)))
        }
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
    let onPhotosSelected: ([PHPickerResult]) -> Void

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
        Coordinator(onPhotosSelected: onPhotosSelected)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPhotosSelected: ([PHPickerResult]) -> Void

        init(onPhotosSelected: @escaping ([PHPickerResult]) -> Void) {
            self.onPhotosSelected = onPhotosSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            onPhotosSelected(results)
        }
    }
}

#Preview {
    VaultView()
        .environment(AppState())
        .environment(SubscriptionManager.shared)
}
