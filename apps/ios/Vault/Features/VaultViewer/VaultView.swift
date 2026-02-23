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
    case fileDate = "File Date"
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

func groupFilesByDate(_ items: [VaultFileItem], newestFirst: Bool = true, dateKeyPath: KeyPath<VaultFileItem, Date?> = \.createdAt) -> [DateGroup] {
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
        let date = item[keyPath: dateKeyPath] ?? .distantPast
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
    @State var viewModel = VaultViewModel()

    // UI-only presentation state
    @State var selectedFile: VaultFileItem?
    @State var selectedPhotoIndex: Int?
    @State var selectedVideoFile: VaultFileItem?
    @State var showingImportOptions = false
    @State var showingCamera = false
    @State var showingPhotoPicker = false
    @State var showingFilePicker = false
    @State var showingSettings = false
    @State var showingPaywall = false
    @State var showingFanMenu = false
    @State var showingLimitAlert = false
    @State var limitAlertRemaining = 0
    @State var limitAlertSelected = 0

    let floatingButtonTrailingInset: CGFloat = 15
    let floatingButtonBottomInset: CGFloat = -15

    struct VisibleFiles: Equatable {
        let all: [VaultFileItem]
        let media: [VaultFileItem]
        let documents: [VaultFileItem]
        let mediaIndexById: [UUID: Int]
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

    @ViewBuilder
    private func mainContentView(visible: VisibleFiles) -> some View {
        if viewModel.isLoading {
            skeletonGridContent
        } else if viewModel.files.isEmpty {
            emptyStateContent
        } else {
            ZStack {
                if visible.all.isEmpty {
                    ContentUnavailableView(
                        "No matching files",
                        systemImage: "magnifyingglass",
                        description: Text("No files match \"\(viewModel.searchText.isEmpty ? viewModel.fileFilter.rawValue : viewModel.searchText)\"")
                    )
                } else {
                    fileGridContentView(visible: visible)
                }
            }
        }
    }

    @ViewBuilder
    private func navigationContent(visible: VisibleFiles) -> some View {
        mainContentView(visible: visible)
            .background(Color.vaultBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                topSafeAreaContent(visible: visible)
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isEditing && !viewModel.selectedIds.isEmpty && !viewModel.files.isEmpty && !showingSettings {
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
                if let progress = viewModel.activeOperationProgress {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        FileOperationProgressCard(
                            completed: progress.completed,
                            total: progress.total,
                            message: progress.message,
                            onCancel: {
                                viewModel.cancelCurrentOperation()
                            }
                        )
                    }
                    .accessibilityIdentifier("vault_operation_progress")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                fanMenuContent
                    .padding(.trailing, floatingButtonTrailingInset)
                    .padding(.bottom, floatingButtonBottomInset)
                    .opacity(!viewModel.files.isEmpty && !showingSettings && !viewModel.isSharedVault && !viewModel.isEditing ? 1 : 0)
                    .allowsHitTesting(!viewModel.files.isEmpty && !showingSettings && !viewModel.isSharedVault && !viewModel.isEditing)
            }
            .overlay(alignment: .bottomTrailing) {
                mainPlusButtonView
                    .padding(.trailing, floatingButtonTrailingInset)
                    .padding(.bottom, floatingButtonBottomInset)
                    .opacity(!viewModel.files.isEmpty && !showingSettings && !viewModel.isSharedVault && !viewModel.isEditing ? 1 : 0)
                    .allowsHitTesting(!viewModel.files.isEmpty && !showingSettings && !viewModel.isSharedVault && !viewModel.isEditing)
            }
    }

    @ViewBuilder
    private func sheetsAndAlerts(visible: VisibleFiles) -> some View {
        Color.clear
            .confirmationDialog("Protect New Files", isPresented: $showingImportOptions) {
                Button("Take Secure Photo") { showingCamera = true }
                Button("Import from Library") { showingPhotoPicker = true }
                Button("Import Documents") { showingFilePicker = true }
                Button("Cancel", role: .cancel) {
                    // No-op: dismiss handled by SwiftUI
                }
            }
            .sheet(isPresented: $showingCamera) {
                SecureCameraView(onCapture: { imageData in
                    viewModel.handleCapturedImage(imageData)
                })
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker(onPhotosSelected: { results in
                    if let limit = viewModel.handleSelectedPhotos(results) {
                        if limit.remaining == 0 {
                            showingPaywall = true
                        } else {
                            limitAlertSelected = limit.selected
                            limitAlertRemaining = limit.remaining
                            showingLimitAlert = true
                        }
                    }
                })
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if let limit = viewModel.handleImportedFiles(result) {
                    if limit.remaining == 0 {
                        showingPaywall = true
                    } else {
                        limitAlertSelected = limit.selected
                        limitAlertRemaining = limit.remaining
                        showingLimitAlert = true
                    }
                }
            }
            .fullScreenCover(isPresented: isPhotoViewerPresented, onDismiss: { selectedPhotoIndex = nil }) {
                if let initialIndex = selectedPhotoIndex, !visible.media.isEmpty {
                    let clampedIndex = min(max(initialIndex, 0), visible.media.count - 1)
                    FullScreenPhotoViewer(
                        files: visible.media,
                        vaultKey: appState.currentVaultKey,
                        masterKey: viewModel.masterKey,
                        initialIndex: clampedIndex,
                        onDelete: viewModel.isSharedVault ? nil : { deletedId in
                            if let idx = viewModel.files.firstIndex(where: { $0.id == deletedId }) {
                                viewModel.files.remove(at: idx)
                            }
                            // Trigger sync for shared vaults after deletion
                            if let key = appState.currentVaultKey {
                                ShareSyncManager.shared.scheduleSync(vaultKey: key)
                            }
                        },
                        allowDownloads: viewModel.sharePolicy?.allowDownloads ?? true
                    )
                } else {
                    Color.vaultBackground.ignoresSafeArea()
                }
            }
            .fullScreenCover(item: $selectedFile) { file in
                SecureImageViewer(
                    file: file,
                    vaultKey: appState.currentVaultKey,
                    onDelete: viewModel.isSharedVault ? nil : { deletedId in
                        if let idx = viewModel.files.firstIndex(where: { $0.id == deletedId }) {
                            viewModel.files.remove(at: idx)
                        }
                        selectedFile = nil
                        // Trigger sync for shared vaults after deletion
                        if let key = appState.currentVaultKey {
                            ShareSyncManager.shared.scheduleSync(vaultKey: key)
                        }
                    },
                    allowDownloads: viewModel.sharePolicy?.allowDownloads ?? true
                )
            }
            .fullScreenCover(item: $selectedVideoFile) { file in
                SecureVideoPlayer(
                    file: file,
                    vaultKey: appState.currentVaultKey
                )
            }
            .fullScreenCover(isPresented: $showingSettings) {
                NavigationStack {
                    VaultSettingsView()
                }
            }
            .alert("Vault Unavailable", isPresented: $viewModel.showSelfDestructAlert) {
                Button("OK") {
                    viewModel.selfDestruct()
                }
            } message: {
                Text(viewModel.selfDestructMessage ?? "This shared vault is no longer available.")
            }
            .toast($viewModel.toastMessage)
            .alert("Delete \(viewModel.selectedIds.count) Files?", isPresented: $viewModel.showingBatchDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    // No-op: dismiss handled by SwiftUI
                }
                Button("Delete", role: .destructive) { viewModel.batchDelete() }
            } message: {
                Text("These files will be permanently deleted from the vault.")
            }
            .premiumPaywall(isPresented: $showingPaywall)
            .alert("Free Plan Limit", isPresented: $showingLimitAlert) {
                if limitAlertRemaining > 0 {
                    Button("Import \(limitAlertRemaining) Files") {
                        viewModel.proceedWithLimitedImport(limitAlertRemaining: limitAlertRemaining)
                    }
                }
                Button("Upgrade to PRO") {
                    viewModel.pendingImport = nil
                    showingPaywall = true
                }
                Button("Cancel", role: .cancel) {
                    viewModel.pendingImport = nil
                }
            } message: {
                if limitAlertRemaining > 0 {
                    Text("You selected \(limitAlertSelected) files, but free vaults can only store 100 files. You have room for \(limitAlertRemaining) more.")
                } else {
                    Text("Free vaults can only store 100 files. Upgrade to PRO for unlimited storage.")
                }
            }
    }

    var body: some View {
        let visible = viewModel.computeVisibleFiles()
        NavigationStack {
            navigationContent(visible: visible)
        }
        .background { sheetsAndAlerts(visible: visible) }
        .task {
            viewModel.configure(appState: appState, subscriptionManager: subscriptionManager)
            viewModel.loadVault()
            ShareUploadManager.shared.resumePendingUploadsIfNeeded(trigger: "vault_view_task")
        }
        .onAppear {
            // Check shared vault status immediately when view appears
            // This ensures revoked shares are detected right away
            viewModel.checkSharedVaultStatus()
            // Report activity to inactivity lock manager
            InactivityLockManager.shared.userDidInteract()
        }
        .onTapGesture {
            // Report any tap as user activity
            InactivityLockManager.shared.userDidInteract()
            // Dismiss keyboard when tapping outside search field
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onChange(of: appState.currentVaultKey) { oldKey, newKey in
            viewModel.handleVaultKeyChange(oldKey: oldKey, newKey: newKey)
        }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing {
                viewModel.loadFiles()
                viewModel.checkSharedVaultStatus()
            }
        }
        .onChange(of: showingPhotoPicker) { _, _ in
            appState.suppressLockForShareSheet = showingPhotoPicker || showingFilePicker
        }
        .onChange(of: showingFilePicker) { _, _ in
            appState.suppressLockForShareSheet = showingPhotoPicker || showingFilePicker
        }
        .onChange(of: viewModel.transferManager.status) { _, newStatus in
            if case .importComplete = newStatus {
                viewModel.loadVault()
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    viewModel.transferManager.reset()
                }
            }
        }
        .onChange(of: viewModel.exportURLs) { _, urls in
            guard !urls.isEmpty else { return }
            ShareSheetHelper.present(items: urls) {
                viewModel.cleanupExportFiles()
                viewModel.selectedIds.removeAll()
                viewModel.isEditing = false
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Vault File Item

struct VaultFileItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let size: Int
    let hasThumbnail: Bool
    let mimeType: String?
    let filename: String?
    let createdAt: Date?
    let duration: TimeInterval?
    let originalDate: Date?

    init(id: UUID, size: Int, hasThumbnail: Bool = false, mimeType: String?, filename: String?, createdAt: Date? = nil, duration: TimeInterval? = nil, originalDate: Date? = nil) {
        self.id = id
        self.size = size
        self.hasThumbnail = hasThumbnail
        self.mimeType = mimeType
        self.filename = filename
        self.createdAt = createdAt
        self.duration = duration
        self.originalDate = originalDate
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

    func updateUIViewController(_ _: PHPickerViewController, context _: Context) {
        // No update needed
    }

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
