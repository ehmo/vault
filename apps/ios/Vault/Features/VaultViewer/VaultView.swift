import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

enum FileFilter: String, CaseIterable, Identifiable {
    case media = "Media"
    case documents = "Documents"
    case all = "All"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .documents: "doc"
        case .all: "square.grid.2x2"
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
    let items: [VaultFileItem] // all items in original order
    let media: [VaultFileItem] // images + videos
    let files: [VaultFileItem] // non-media files
}

func groupFilesByDate(_ items: [VaultFileItem], newestFirst: Bool = true) -> [DateGroup] {
    let calendar = Calendar.current
    let now = Date()
    let startOfToday = calendar.startOfDay(for: now)
    let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!

    // Group items by calendar day
    var dayBuckets: [(dayStart: Date, title: String, items: [VaultFileItem])] = []
    var bucketIndex: [Date: Int] = [:]

    let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = false
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    for item in items {
        let date = item.createdAt ?? .distantPast
        let dayStart = calendar.startOfDay(for: date)

        let title: String
        if dayStart >= startOfToday {
            title = "Today"
        } else if dayStart >= startOfYesterday {
            title = "Yesterday"
        } else {
            title = dayFormatter.string(from: date)
        }

        if let idx = bucketIndex[dayStart] {
            dayBuckets[idx].items.append(item)
        } else {
            bucketIndex[dayStart] = dayBuckets.count
            dayBuckets.append((dayStart: dayStart, title: title, items: [item]))
        }
    }

    // Sort buckets to match the chosen sort direction
    dayBuckets.sort { newestFirst ? $0.dayStart > $1.dayStart : $0.dayStart < $1.dayStart }

    let isoFormatter = ISO8601DateFormatter()
    return dayBuckets.map { bucket in
        let media = bucket.items.filter { $0.isMedia }
        let files = bucket.items.filter { !$0.isMedia }
        let uniqueId = isoFormatter.string(from: bucket.dayStart)
        return DateGroup(id: uniqueId, title: bucket.title, items: bucket.items, media: media, files: files)
    }
}

struct VaultView: View {
    @Environment(AppState.self) var appState
    @Environment(SubscriptionManager.self) var subscriptionManager
    @State var files: [VaultFileItem] = []
    @State var masterKey: Data?
    @State var selectedFile: VaultFileItem?
    @State var selectedPhotoIndex: Int?
    @State var showingImportOptions = false
    @State var showingCamera = false
    @State var showingPhotoPicker = false
    @State var showingFilePicker = false
    @State var showingSettings = false
    @State var isLoading = true
    @State var searchText = ""
    @State var fileFilter: FileFilter = .media
    @State var sortOrder: SortOrder = .dateNewest
    @State var isEditing = false
    @State var selectedIds: Set<UUID> = []
    @State var showingBatchDeleteConfirmation = false
    @State var showingPaywall = false
    @State var showingFanMenu = false
    @State var exportURLs: [URL] = []
    @State var toastMessage: ToastMessage?
    @State var importProgress: (completed: Int, total: Int)?
    @State var isDeleteInProgress = false
    @State var showingLimitAlert = false
    @State var pendingImport: PendingImport?
    @State var limitAlertRemaining = 0
    @State var limitAlertSelected = 0
    @State var activeImportTask: Task<Void, Never>?
    let floatingButtonTrailingInset: CGFloat = 15
    let floatingButtonBottomInset: CGFloat = -15

    // Transfer status
    var transferManager = BackgroundShareTransferManager.shared

    // Shared vault state
    @State var isSharedVault = false
    @State var sharePolicy: VaultStorage.SharePolicy?
    @State var sharedVaultId: String?
    @State var updateAvailable = false
    @State var isUpdating = false
    @State var selfDestructMessage: String?
    @State var showSelfDestructAlert = false

    struct VisibleFiles {
        let all: [VaultFileItem]
        let media: [VaultFileItem]
        let documents: [VaultFileItem]
        let mediaIndexById: [UUID: Int]
    }

    func computeVisibleFiles() -> VisibleFiles {
        var visible = files
        switch fileFilter {
        case .all:
            break
        case .media:
            visible = visible.filter {
                let mime = $0.mimeType ?? ""
                return mime.hasPrefix("image/") || mime.hasPrefix("video/")
            }
        case .documents:
            visible = visible.filter {
                let mime = $0.mimeType ?? ""
                return !mime.hasPrefix("image/") && !mime.hasPrefix("video/")
            }
        }
        if !searchText.isEmpty {
            visible = visible.filter {
                ($0.filename ?? "").localizedStandardContains(searchText) ||
                ($0.mimeType ?? "").localizedStandardContains(searchText)
            }
        }
        switch sortOrder {
        case .dateNewest:
            visible.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .dateOldest:
            visible.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .sizeSmallest:
            visible.sort { $0.size < $1.size }
        case .sizeLargest:
            visible.sort { $0.size > $1.size }
        case .name:
            visible.sort { ($0.filename ?? "").localizedStandardCompare($1.filename ?? "") == .orderedAscending }
        }

        let media = visible.filter { $0.isMedia }
        let documents = visible.filter { !$0.isMedia }
        let mediaIndexById = Dictionary(
            uniqueKeysWithValues: media.enumerated().map { ($1.id, $0) }
        )
        return VisibleFiles(
            all: visible,
            media: media,
            documents: documents,
            mediaIndexById: mediaIndexById
        )
    }

    var sortedFiles: [VaultFileItem] {
        computeVisibleFiles().all
    }

    var splitFiles: (all: [VaultFileItem], media: [VaultFileItem], documents: [VaultFileItem]) {
        let visible = computeVisibleFiles()
        return (visible.all, visible.media, visible.documents)
    }

    var useDateGrouping: Bool {
        sortOrder == .dateNewest || sortOrder == .dateOldest
    }

    /// Keep cover presentation stable while allowing index changes inside the viewer.
    private var isPhotoViewerPresented: Binding<Bool> {
        Binding(
            get: { selectedPhotoIndex != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPhotoIndex = nil
                }
            }
        )
    }

    var body: some View {
        let visible = computeVisibleFiles()
        NavigationStack {
            Group {
                if isLoading {
                    skeletonGridContent
                } else if files.isEmpty {
                    emptyStateContent
                } else {
                    ZStack {
                        if visible.all.isEmpty {
                            ContentUnavailableView(
                                "No matching files",
                                systemImage: "magnifyingglass",
                                description: Text("No files match \"\(searchText.isEmpty ? fileFilter.rawValue : searchText)\"")
                            )
                        } else {
                            fileGridContentView(visible: visible)
                        }
                    }
                }
            }
            .navigationTitle(appState.vaultName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showingSettings {
                    vaultToolbarContent
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                topSafeAreaContent
            }
            .safeAreaInset(edge: .bottom) {
                if isEditing && !selectedIds.isEmpty && !files.isEmpty && !showingSettings {
                    bottomEditBar
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
                        localImportProgressContent(completed: progress.completed, total: progress.total)
                    }
                    .accessibilityIdentifier("vault_local_import_progress")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                fanMenuContent
                    .padding(.trailing, floatingButtonTrailingInset)
                    .padding(.bottom, floatingButtonBottomInset)
                    .opacity(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing ? 1 : 0)
                    .allowsHitTesting(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing)
            }
            .overlay(alignment: .bottomTrailing) {
                mainPlusButtonView
                    .padding(.trailing, floatingButtonTrailingInset)
                    .padding(.bottom, floatingButtonBottomInset)
                    .opacity(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing ? 1 : 0)
                    .allowsHitTesting(!files.isEmpty && !showingSettings && !isSharedVault && !isEditing)
            }
        }
        .task {
            loadVault()
        }
        .onChange(of: appState.currentVaultKey) { oldKey, newKey in
            // Cancel any in-flight imports immediately on vault key change
            activeImportTask?.cancel()
            activeImportTask = nil
            importProgress = nil
            isDeleteInProgress = false
            UIApplication.shared.isIdleTimerDisabled = false

            if oldKey != newKey {
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
        .fullScreenCover(isPresented: isPhotoViewerPresented, onDismiss: { selectedPhotoIndex = nil }) {
            if let initialIndex = selectedPhotoIndex, !visible.media.isEmpty {
                let clampedIndex = min(max(initialIndex, 0), visible.media.count - 1)
                FullScreenPhotoViewer(
                    files: visible.media,
                    vaultKey: appState.currentVaultKey,
                    masterKey: masterKey,
                    initialIndex: clampedIndex,
                    onDelete: isSharedVault ? nil : { deletedId in
                        if let idx = files.firstIndex(where: { $0.id == deletedId }) {
                            files.remove(at: idx)
                        }
                    },
                    allowDownloads: sharePolicy?.allowDownloads ?? true
                )
            } else {
                Color.vaultBackground.ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $selectedFile) { file in
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
        }
        .fullScreenCover(isPresented: $showingSettings) {
            NavigationStack {
                VaultSettingsView()
            }
            .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        }
        .ignoresSafeArea(.keyboard)
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
}

// MARK: - Vault File Item

struct VaultFileItem: Identifiable, Sendable {
    let id: UUID
    let size: Int
    let encryptedThumbnail: Data?
    let mimeType: String?
    let filename: String?
    let createdAt: Date?
    let duration: TimeInterval?

    init(id: UUID, size: Int, encryptedThumbnail: Data?, mimeType: String?, filename: String?, createdAt: Date? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.size = size
        self.encryptedThumbnail = encryptedThumbnail
        self.mimeType = mimeType
        self.filename = filename
        self.createdAt = createdAt
        self.duration = duration
    }

    var isImage: Bool {
        (mimeType ?? "").hasPrefix("image/")
    }

    var isMedia: Bool {
        let mime = mimeType ?? ""
        return mime.hasPrefix("image/") || mime.hasPrefix("video/")
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
