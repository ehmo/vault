import SwiftUI

struct SecureImageViewer: View {
    let file: VaultFileItem
    let vaultKey: Data?
    var onDelete: ((UUID) -> Void)? = nil
    var allowDownloads: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingActions = false
    @State private var shareURL: URL?
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
                } else if let error = error {
                    errorView(error)
                }
            }
        }
        .task { loadImage() }
        .onDisappear(perform: clearImage)
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
            Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
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

    private func loadImage() {
        guard let key = vaultKey else {
            error = "No vault key"
            isLoading = false
            return
        }

        Task {
            do {
                let (header, content) = try VaultStorage.shared.retrieveFile(id: file.id, with: key)

                // Only handle images for now
                if header.mimeType.hasPrefix("image/") {
                    if let uiImage = UIImage(data: content) {
                        await MainActor.run {
                            self.image = uiImage
                            self.isLoading = false
                        }
                        return
                    }
                }

                await MainActor.run {
                    self.error = "Unsupported file type"
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

    private func clearImage() {
        // Clear image from memory when view disappears
        image = nil
    }

    private func exportFile() {
        guard let image = image, let data = image.jpegData(compressionQuality: 0.95) else { return }

        // Write to a temporary location for sharing
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "Export_\(file.id.uuidString).jpg"
        let url = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: [.atomic])
            shareURL = url
        } catch {
            // Ignore share if we cannot write
        }
    }

    private func deleteFile() {
        guard let key = vaultKey else {
            // Even if key is missing, notify parent to refresh UI
            onDelete?(file.id)
            dismiss()
            return
        }

        Task {
            try? VaultStorage.shared.deleteFile(id: file.id, with: key)
            await MainActor.run {
                // Inform parent to remove this item from its list
                onDelete?(file.id)
                // Dismiss the viewer
                dismiss()
            }
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

