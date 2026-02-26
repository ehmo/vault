import SwiftUI
import AVKit

struct FullScreenPhotoViewer: View {
    let files: [VaultFileItem]
    let vaultKey: VaultKey?
    let masterKey: MasterKey?
    let initialIndex: Int
    var onDelete: ((UUID) -> Void)?
    var allowDownloads: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var pageScrollID: Int?
    @State private var images: [UUID: UIImage] = [:]
    @State private var showControls = true
    @State private var showingActions = false
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var shareURL: URL?
    @State private var showingVideoPlayer: VaultFileItem?
    @State private var verticalDismissOffset: CGFloat = 0
    @State private var currentZoomScale: CGFloat = 1.0

    init(files: [VaultFileItem], vaultKey: VaultKey?, masterKey: MasterKey? = nil, initialIndex: Int,
         onDelete: ((UUID) -> Void)? = nil, allowDownloads: Bool = true) {
        self.files = files
        self.vaultKey = vaultKey
        self.masterKey = masterKey
        self.initialIndex = initialIndex
        self.onDelete = onDelete
        self.allowDownloads = allowDownloads
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var currentFile: VaultFileItem? {
        guard files.indices.contains(currentIndex) else { return nil }
        return files[currentIndex]
    }

    private var isZoomed: Bool {
        currentZoomScale > ZoomableImageContainer.zoomThreshold
    }

    private var backgroundOpacity: Double {
        let progress = min(max(verticalDismissOffset / 300, 0), 1)
        return max(0.45, 1 - Double(progress) * 0.55)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                // Photo paging
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            photoPage(file: file, geometry: geometry)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageScrollID)
                .scrollDisabled(isZoomed)
                .ignoresSafeArea()
                .onAppear {
                    pageScrollID = currentIndex
                }
                .onChange(of: pageScrollID) { _, newID in
                    guard let newID else { return }
                    if currentIndex != newID {
                        currentIndex = newID
                    }
                }
                .onChange(of: currentIndex) { _, newIndex in
                    if pageScrollID != newIndex {
                        pageScrollID = newIndex
                    }
                    preloadAdjacent(around: newIndex)
                    evictDistant(from: newIndex)
                }
                .offset(y: verticalDismissOffset)

                // Controls overlay
                if showControls {
                    VStack {
                        // Top bar with gradient
                        HStack {
                            Button("Done") { dismiss() }
                                .font(.body.weight(.medium))
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("viewer_done")
                            Spacer()
                            if onDelete != nil || allowDownloads {
                                Button(action: { showingActions = true }) {
                                    Image(systemName: "ellipsis.circle")
                                        .imageScale(.large)
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("viewer_actions")
                                .accessibilityLabel("More actions")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.black.opacity(0.5), .black.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea(edges: .top)
                        )

                        Spacer()

                        // Bottom bar — file info
                        if let file = currentFile {
                            HStack {
                                Text(file.filename ?? "Photo")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(currentIndex + 1) / \(files.count)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [.black.opacity(0), .black.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .ignoresSafeArea(edges: .bottom)
                            )
                        }
                    }
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .offset(y: verticalDismissOffset)
                }
            }
        }
        .statusBarHidden(!showControls)
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .task {
            preloadAdjacent(around: initialIndex)
        }
        .confirmationDialog("Actions", isPresented: $showingActions, titleVisibility: .visible) {
            if allowDownloads {
                Button("Export") { showingExportConfirmation = true }
            }
            if onDelete != nil {
                Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
            }
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
        }
        .alert("Export File?", isPresented: $showingExportConfirmation) {
            Button("Export") { exportFile() }
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
        } message: {
            Text("This will save the file outside the vault. It will no longer be protected.")
        }
        .alert("Delete File?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteFile() }
            Button("Cancel", role: .cancel) {
                // No-op: dismiss handled by SwiftUI
            }
        } message: {
            Text("This file will be permanently deleted from the vault.")
        }
        .onChange(of: shareURL) { _, url in
            guard let url else { return }
            ShareSheetHelper.present(items: [url]) {
                try? FileManager.default.removeItem(at: url)
                self.shareURL = nil
            }
        }
        .fullScreenCover(item: $showingVideoPlayer) { file in
            SecureVideoPlayer(file: file, vaultKey: vaultKey)
        }
    }

    // MARK: - Page Content

    @ViewBuilder
    private func photoPage(file: VaultFileItem, geometry: GeometryProxy) -> some View {
        let isVideo = (file.mimeType ?? "").hasPrefix("video/")

        if let image = images[file.id] {
            ZStack {
                ZoomableImageContainer(
                    image: image,
                    containerSize: geometry.size,
                    onSingleTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    },
                    onVerticalDrag: { offset in
                        verticalDismissOffset = offset
                    },
                    onVerticalDragEnd: { velocity, offset in
                        let shouldDismiss = offset > 90 || velocity > 800
                        if shouldDismiss {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                verticalDismissOffset = 0
                            }
                        }
                    },
                    onZoomChange: { scale in
                        currentZoomScale = scale
                    }
                )

                if isVideo {
                    Button {
                        showingVideoPlayer = file
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("viewer_play_video")
                    .allowsHitTesting(!isZoomed)
                }
            }
        } else {
            ProgressView()
                .tint(.white)
                .containerRelativeFrame([.horizontal, .vertical])
                .task(id: file.id) {
                    await loadFullImage(for: file)
                }
        }
    }

    // MARK: - Image Loading

    private func loadFullImage(for file: VaultFileItem) async {
        guard images[file.id] == nil else { return }

        let isVideo = (file.mimeType ?? "").hasPrefix("video/")

        if isVideo {
            guard let masterKey = masterKey, file.hasThumbnail else { return }
            if let uiImage = await ThumbnailCache.shared.decryptAndCache(id: file.id, masterKey: masterKey.rawBytes) {
                images[file.id] = uiImage
            }
        } else {
            guard let key = vaultKey else { return }
            let fileId = file.id
            // Decrypt and decode off main thread, downsampled to screen resolution
            let screenScale = UIScreen.main.scale
            let uiImage: UIImage? = await Task.detached(priority: .userInitiated) {
                do {
                    let (header, content) = try await VaultStorage.shared.retrieveFile(id: fileId, with: key)
                    guard header.mimeType.hasPrefix("image/") else { return nil }
                    return Self.downsampledImage(from: content, maxPixelSize: 1920 * Int(screenScale))
                } catch {
                    return nil
                }
            }.value
            if let uiImage {
                images[file.id] = uiImage
            }
        }
    }

    private func preloadAdjacent(around index: Int) {
        let range = max(0, index - 1)...min(files.count - 1, index + 1)
        for i in range {
            let file = files[i]
            if images[file.id] == nil {
                Task { await loadFullImage(for: file) }
            }
        }
    }

    private func evictDistant(from index: Int) {
        for (i, file) in files.enumerated() {
            if abs(i - index) > 2 {
                images.removeValue(forKey: file.id)
            }
        }
    }

    // MARK: - Image Decoding

    /// Decodes image data with downsampling to avoid loading full-resolution bitmaps.
    /// For a 12MP image on a 3x screen, this decodes at ~5.7MP instead of ~48MP bitmap.
    private nonisolated static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }

        // Check if downsampling is actually needed
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maxDim = max(width, height)

        if maxDim <= maxPixelSize {
            // Image is already small enough — use UIImage(data:) to preserve EXIF orientation.
            // CGImageSourceCreateImageAtIndex with nil options strips orientation metadata.
            return UIImage(data: data)
        }

        // Downsample to target size
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        // kCGImageSourceCreateThumbnailWithTransform already rotates pixels to correct
        // orientation, so use .up to avoid applying the EXIF rotation a second time.
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    // MARK: - Actions

    private func exportFile() {
        guard let file = currentFile, let key = vaultKey else { return }

        Task.detached(priority: .userInitiated) {
            do {
                // Use streaming decryption to avoid 2x memory peak for large files
                let (header, tempURL) = try await VaultStorage.shared.retrieveFileToTempURL(id: file.id, with: key)
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let ext = (file.filename as NSString?)?.pathExtension ?? header.mimeType.split(separator: "/").last.map(String.init) ?? "bin"
                let filename = "Export_\(file.id.uuidString).\(ext)"
                let url = tempDir.appendingPathComponent(filename)
                try FileManager.default.moveItem(at: tempURL, to: url)
                await MainActor.run {
                    self.shareURL = url
                }
            } catch {
                // Export failed silently
            }
        }
    }

    private func deleteFile() {
        guard let file = currentFile, let key = vaultKey else { return }

        Task {
            do {
                try await VaultStorage.shared.deleteFile(id: file.id, with: key)
            } catch {
                EmbraceManager.shared.captureError(error)
            }
            await MainActor.run {
                onDelete?(file.id)
                dismiss()
            }
        }
    }
}
