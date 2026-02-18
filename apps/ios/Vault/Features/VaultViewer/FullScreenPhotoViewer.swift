import SwiftUI
import AVKit

struct FullScreenPhotoViewer: View {
    let files: [VaultFileItem]
    let vaultKey: Data?
    let masterKey: Data?
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

    init(files: [VaultFileItem], vaultKey: Data?, masterKey: Data? = nil, initialIndex: Int,
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
                .scrollDisabled(currentZoomScale > 1.05)
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
            Button("Cancel", role: .cancel) { /* No-op */ }
        }
        .alert("Export File?", isPresented: $showingExportConfirmation) {
            Button("Export") { exportFile() }
            Button("Cancel", role: .cancel) { /* No-op */ }
        } message: {
            Text("This will save the file outside the vault. It will no longer be protected.")
        }
        .alert("Delete File?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteFile() }
            Button("Cancel", role: .cancel) { /* No-op */ }
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
                        guard currentZoomScale <= 1.05 else { return }
                        verticalDismissOffset = offset
                    },
                    onVerticalDragEnd: { velocity, offset in
                        guard currentZoomScale <= 1.05 else { return }
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
                    .allowsHitTesting(currentZoomScale <= 1.05)
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
            if let uiImage = await ThumbnailCache.shared.decryptAndCache(id: file.id, masterKey: masterKey) {
                await MainActor.run {
                    images[file.id] = uiImage
                }
            }
        } else {
            guard let key = vaultKey else { return }
            do {
                let (header, content) = try VaultStorage.shared.retrieveFile(id: file.id, with: key)
                guard header.mimeType.hasPrefix("image/"),
                      let uiImage = UIImage(data: content) else { return }
                await MainActor.run {
                    images[file.id] = uiImage
                }
            } catch {
                // Loading failed — cell stays as spinner
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

    // MARK: - Actions

    private func exportFile() {
        guard let file = currentFile,
              let image = images[file.id],
              let data = image.jpegData(compressionQuality: 0.95) else { return }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "Export_\(file.id.uuidString).jpg"
        let url = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: [.atomic])
            shareURL = url
        } catch {
            // Ignore
        }
    }

    private func deleteFile() {
        guard let file = currentFile, let key = vaultKey else { return }

        Task {
            do {
                try VaultStorage.shared.deleteFile(id: file.id, with: key)
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

// MARK: - Zoomable Image Container (UIKit wrapper)

/// UIScrollView-based zoomable image view with pinch-to-zoom, double-tap zoom,
/// single-tap for controls toggle, and vertical drag-to-dismiss when not zoomed.
struct ZoomableImageContainer: UIViewRepresentable {
    let image: UIImage
    let containerSize: CGSize
    let onSingleTap: () -> Void
    let onVerticalDrag: (CGFloat) -> Void
    let onVerticalDragEnd: (_ velocity: CGFloat, _ offset: CGFloat) -> Void
    let onZoomChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.tag = 100
        scrollView.addSubview(imageView)

        // Double-tap to zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single-tap for controls toggle (waits for double-tap failure)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        // Vertical pan for drag-to-dismiss (only when not zoomed)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        context.coordinator.panGesture = pan
        scrollView.addGestureRecognizer(pan)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = scrollView.viewWithTag(100) as? UIImageView else { return }

        // Update image if changed
        if imageView.image !== image {
            imageView.image = image
            scrollView.zoomScale = 1.0
        }

        context.coordinator.parent = self
        layoutImageView(imageView, in: scrollView)
    }

    private func layoutImageView(_ imageView: UIImageView, in scrollView: UIScrollView) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)

        let fittedWidth = imageSize.width * fitScale
        let fittedHeight = imageSize.height * fitScale

        imageView.frame = CGRect(x: 0, y: 0, width: fittedWidth, height: fittedHeight)
        scrollView.contentSize = CGSize(width: fittedWidth, height: fittedHeight)

        Self.centerImageView(imageView, in: scrollView)
    }

    static func centerImageView(_ imageView: UIImageView, in scrollView: UIScrollView) {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let xOffset = max(0, (boundsSize.width - contentSize.width * scrollView.zoomScale) / 2)
        let yOffset = max(0, (boundsSize.height - contentSize.height * scrollView.zoomScale) / 2)

        imageView.center = CGPoint(
            x: contentSize.width * scrollView.zoomScale / 2 + xOffset,
            y: contentSize.height * scrollView.zoomScale / 2 + yOffset
        )
    }

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImageContainer
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        weak var panGesture: UIPanGestureRecognizer?
        private var isDraggingVertically = false

        init(parent: ZoomableImageContainer) {
            self.parent = parent
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            ZoomableImageContainer.centerImageView(imageView, in: scrollView)
            parent.onZoomChange(scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.onZoomChange(scale)
        }

        // MARK: Gestures

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: scrollView.subviews.first)
                let zoomRect = zoomRectForScale(2.5, center: point, in: scrollView)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        @objc func handleSingleTap() {
            parent.onSingleTap()
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView, scrollView.zoomScale <= 1.05 else { return }

            switch gesture.state {
            case .began:
                isDraggingVertically = true
            case .changed:
                let translation = gesture.translation(in: scrollView)
                if translation.y > 0 {
                    parent.onVerticalDrag(translation.y)
                }
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: scrollView).y
                let translation = gesture.translation(in: scrollView)
                parent.onVerticalDragEnd(max(0, velocity), max(0, translation.y))
                isDraggingVertically = false
            default:
                break
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panGesture,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView else { return true }

            // Only begin if not zoomed and drag is predominantly downward
            guard scrollView.zoomScale <= 1.05 else { return false }

            let velocity = pan.velocity(in: scrollView)
            let isVertical = abs(velocity.y) > abs(velocity.x) * 1.5
            let isDownward = velocity.y > 0
            return isVertical && isDownward
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Don't conflict with scroll view's own pan
            false
        }

        // MARK: Helpers

        private func zoomRectForScale(_ scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let width = scrollView.bounds.width / scale
            let height = scrollView.bounds.height / scale
            return CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            )
        }
    }
}
