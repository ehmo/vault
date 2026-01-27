import SwiftUI
import PhotosUI

struct VaultView: View {
    @EnvironmentObject var appState: AppState
    @State private var files: [VaultFileItem] = []
    @State private var selectedFile: VaultFileItem?
    @State private var showingImportOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingSettings = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading vault...")
                } else if files.isEmpty {
                    emptyStateView
                } else {
                    FileGridView(files: files, onSelect: { file in
                        selectedFile = file
                    })
                }
            }
            .navigationTitle("Vault")
            .toolbar {
                if !showingSettings {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: lockVault) {
                            Image(systemName: "lock.fill")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !files.isEmpty && !showingSettings {
                    Button(action: { showingImportOptions = true }) {
                        Label("Add Files", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .background(.thinMaterial)
                }
            }
        }
        .onAppear(perform: loadFiles)
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
        .sheet(item: $selectedFile) { file in
            SecureImageViewer(file: file, vaultKey: appState.currentVaultKey)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                VaultSettingsView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("This vault is empty")
                .font(.title2)
                .fontWeight(.medium)

            Text("Add photos, videos, or files to keep them secure")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingImportOptions = true }) {
                Label("Add Files", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
    }

    // MARK: - Actions

    private func lockVault() {
        appState.lockVault()
    }

    private func loadFiles() {
        guard let key = appState.currentVaultKey else {
            isLoading = false
            return
        }

        Task {
            do {
                let fileEntries = try VaultStorage.shared.listFiles(with: key)
                let items = fileEntries.map { entry in
                    VaultFileItem(id: entry.fileId, size: entry.size)
                }
                await MainActor.run {
                    files = items
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    files = []
                    isLoading = false
                }
            }
        }
    }

    private func handleCapturedImage(_ imageData: Data) {
        guard let key = appState.currentVaultKey else { return }

        Task {
            do {
                let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                let fileId = try VaultStorage.shared.storeFile(
                    data: imageData,
                    filename: filename,
                    mimeType: "image/jpeg",
                    with: key
                )
                await MainActor.run {
                    files.append(VaultFileItem(id: fileId, size: imageData.count))
                }
            } catch {
                // Handle error silently
            }
        }
    }

    private func handleSelectedImages(_ imagesData: [Data]) {
        guard let key = appState.currentVaultKey else { return }

        for data in imagesData {
            Task {
                do {
                    let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                    let fileId = try VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: "image/jpeg",
                        with: key
                    )
                    await MainActor.run {
                        files.append(VaultFileItem(id: fileId, size: data.count))
                        #if DEBUG
                        print("✅ Image added to vault: \(fileId)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("❌ Failed to add image: \(error)")
                    #endif
                }
            }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        guard let key = appState.currentVaultKey else { return }

        guard case .success(let urls) = result else { return }

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            Task {
                if let data = try? Data(contentsOf: url) {
                    let filename = url.lastPathComponent
                    let mimeType = mimeTypeForExtension(url.pathExtension)
                    if let fileId = try? VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: mimeType,
                        with: key
                    ) {
                        await MainActor.run {
                            files.append(VaultFileItem(id: fileId, size: data.count))
                        }
                    }
                }
            }
        }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Vault File Item

struct VaultFileItem: Identifiable {
    let id: UUID
    let size: Int
}

// MARK: - Photo Picker Wrapper

struct PhotoPicker: UIViewControllerRepresentable {
    let onImagesSelected: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0 // No limit
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
            
            var imagesData: [Data] = []
            let group = DispatchGroup()
            
            // Process each result
            for result in results {
                let itemProvider = result.itemProvider
                
                // Load as image
                if itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        defer { group.leave() }
                        
                        guard let image = image as? UIImage,
                              let data = image.jpegData(compressionQuality: 0.8) else { return }
                        
                        imagesData.append(data)
                    }
                }
            }
            
            // When all images are loaded, call the callback
            group.notify(queue: .main) {
                self.onImagesSelected(imagesData)
            }
        }
    }
}

#Preview {
    VaultView()
        .environmentObject(AppState())
}
