import SwiftUI

struct SecureImageViewer: View {
    let file: VaultFileItem
    let vaultKey: Data?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(.white)
                Spacer()
                Menu {
                    Button(action: { showingExportConfirmation = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
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
        .onAppear(perform: loadImage)
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
        // Prevent screenshots
        .overlay {
            SecureContainerView()
        }
    }

    // MARK: - Image View

    private func imageView(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
            }
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
        // Export would save to Photos or Files
        // Implementation would use PHPhotoLibrary or UIActivityViewController
    }

    private func deleteFile() {
        guard let key = vaultKey else { return }

        Task {
            try? VaultStorage.shared.deleteFile(id: file.id, with: key)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Secure Container (Screenshot Prevention)

struct SecureContainerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let secureField = UITextField()
        secureField.isSecureTextEntry = true

        // The secure text field's layer is used to capture screenshots
        // Adding a child view to it makes that view also "secure"
        let containerView = UIView()
        containerView.backgroundColor = .clear

        if let secureLayer = secureField.layer.sublayers?.first {
            secureLayer.addSublayer(containerView.layer)
        }

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview {
    SecureImageViewer(
        file: VaultFileItem(id: UUID(), size: 1024),
        vaultKey: nil
    )
}

