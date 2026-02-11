import SwiftUI

struct FullScreenPhotoViewer: View {
    let files: [VaultFileItem]
    let vaultKey: Data?
    let initialIndex: Int
    var onDelete: ((UUID) -> Void)?
    var allowDownloads: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var images: [UUID: UIImage] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var showingActions = false
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var shareURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(files: [VaultFileItem], vaultKey: Data?, initialIndex: Int,
         onDelete: ((UUID) -> Void)? = nil, allowDownloads: Bool = true) {
        self.files = files
        self.vaultKey = vaultKey
        self.initialIndex = initialIndex
        self.onDelete = onDelete
        self.allowDownloads = allowDownloads
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var currentFile: VaultFileItem? {
        guard files.indices.contains(currentIndex) else { return nil }
        return files[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(files) { file in
                    photoPage(file: file)
                        .tag(files.firstIndex(where: { $0.id == file.id }) ?? 0)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .gesture(dragToDissmissGesture)

            // Top bar overlay
            VStack {
                HStack {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("viewer_done")
                    Spacer()
                    if onDelete != nil || allowDownloads {
                        Button(action: { showingActions = true }) {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.white)
                                .imageScale(.large)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("viewer_actions")
                        .accessibilityLabel("More actions")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                Spacer()
            }
        }
        .onChange(of: currentIndex) { _, newIndex in
            preloadAdjacent(around: newIndex)
            evictDistant(from: newIndex)
        }
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
            Button("Cancel", role: .cancel) { }
        }
        .alert("Export File?", isPresented: $showingExportConfirmation) {
            Button("Export") { exportFile() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will save the file outside the vault. It will no longer be protected.")
        }
        .alert("Delete File?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteFile() }
            Button("Cancel", role: .cancel) { }
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
    }

    // MARK: - Page Content

    @ViewBuilder
    private func photoPage(file: VaultFileItem) -> some View {
        if let image = images[file.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .containerRelativeFrame([.horizontal, .vertical])
        } else {
            ProgressView()
                .tint(.white)
                .containerRelativeFrame([.horizontal, .vertical])
                .task(id: file.id) {
                    await loadFullImage(for: file)
                }
        }
    }

    // MARK: - Drag to Dismiss

    private var dragToDissmissGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > 150 {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Image Loading

    private func loadFullImage(for file: VaultFileItem) async {
        guard let key = vaultKey, images[file.id] == nil else { return }
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
            try? VaultStorage.shared.deleteFile(id: file.id, with: key)
            await MainActor.run {
                onDelete?(file.id)
                dismiss()
            }
        }
    }
}
