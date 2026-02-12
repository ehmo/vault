import SwiftUI
import QuickLook

struct SecureImageViewer: View {
    let file: VaultFileItem
    let vaultKey: Data?
    var onDelete: ((UUID) -> Void)? = nil
    var allowDownloads: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var tempFileURL: URL?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingActions = false
    @State private var shareURL: URL?

    private var isImage: Bool { (file.mimeType ?? "").hasPrefix("image/") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(.white)
                Spacer()
                Button(action: { showingActions = true }) {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white)
                        .imageScale(.large)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.black)
            Divider()

            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let image = image {
                    imageView(image)
                } else if let url = tempFileURL {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else if let error = error {
                    errorView(error)
                }
            }
        }
        .task { loadFile() }
        .onDisappear(perform: cleanup)
        .alert("Export File?", isPresented: $showingExportConfirmation) {
            Button("Export", role: .destructive) { exportFile() }
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
        .confirmationDialog("Actions", isPresented: $showingActions, titleVisibility: .visible) {
            if allowDownloads {
                Button("Export") { showingExportConfirmation = true }
            }
            if onDelete != nil {
                Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
            }
            Button("Cancel", role: .cancel) { }
        }
        .onChange(of: shareURL) { _, url in
            guard let url else { return }
            ShareSheetHelper.present(items: [url]) {
                try? FileManager.default.removeItem(at: url)
                self.shareURL = nil
            }
        }
    }

    // MARK: - Image View

    private func imageView(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text("Unable to load file")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Actions

    private func loadFile() {
        guard let key = vaultKey else {
            error = "No vault key"
            isLoading = false
            return
        }

        Task {
            do {
                let (header, content) = try VaultStorage.shared.retrieveFile(id: file.id, with: key)

                // Images: display inline
                if header.mimeType.hasPrefix("image/"), let uiImage = UIImage(data: content) {
                    await MainActor.run {
                        self.image = uiImage
                        self.isLoading = false
                    }
                    return
                }

                // All other files: write to temp and present via Quick Look
                let filename = file.filename ?? "file_\(file.id.uuidString)"
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vault_preview", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempURL = tempDir.appendingPathComponent(filename)
                try content.write(to: tempURL)

                await MainActor.run {
                    self.tempFileURL = tempURL
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to decrypt file"
                    self.isLoading = false
                }
            }
        }
    }

    private func cleanup() {
        image = nil
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    private func exportFile() {
        guard let key = vaultKey else { return }

        Task {
            do {
                let (_, content) = try VaultStorage.shared.retrieveFile(id: file.id, with: key)
                let filename = file.filename ?? "Export_\(file.id.uuidString)"
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let url = tempDir.appendingPathComponent(filename)
                try content.write(to: url, options: [.atomic])
                await MainActor.run {
                    shareURL = url
                }
            } catch {
                // Ignore export errors
            }
        }
    }

    private func deleteFile() {
        guard let key = vaultKey else {
            onDelete?(file.id)
            dismiss()
            return
        }

        Task {
            do {
                try VaultStorage.shared.deleteFile(id: file.id, with: key)
            } catch {
                SentryManager.shared.captureError(error)
            }
            await MainActor.run {
                onDelete?(file.id)
                dismiss()
            }
        }
    }
}

// MARK: - Quick Look Preview

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        // Hide the default nav bar — our custom header handles Done/Actions
        controller.navigationItem.leftBarButtonItems = []
        controller.navigationItem.rightBarButtonItems = []
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

#Preview {
    SecureImageViewer(
        file: VaultFileItem(
            id: UUID(),
            size: 1024,
            encryptedThumbnail: nil,
            mimeType: "image/jpeg",
            filename: "preview.jpg"
        ),
        vaultKey: nil,
        onDelete: { _ in }
    )
}

// MARK: - Share Sheet Helper

/// Presents UIActivityViewController imperatively from the topmost view controller.
/// Avoids _UIReparentingView warnings caused by UIViewControllerRepresentable inside .sheet().
enum ShareSheetHelper {
    static func present(items: [Any], completion: (() -> Void)? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        presenter.present(activityVC, animated: true)
    }
}
