import SwiftUI
import PhotosUI
import UIKit

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
        .onChange(of: appState.currentVaultKey) { _, newKey in
            // If the vault key is cleared, clear our files immediately
            if newKey == nil {
                files = []
                isLoading = false
            }
        }
        .onChange(of: showingSettings) { _, isShowing in
            // Reload files when returning from settings (in case of nuclear wipe)
            if !isShowing {
                files = []
                isLoading = true
                loadFiles()
            }
        }
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
            SecureImageViewer(
                file: file,
                vaultKey: appState.currentVaultKey,
                onDelete: { deletedId in
                    if let idx = files.firstIndex(where: { $0.id == deletedId }) {
                        files.remove(at: idx)
                    }
                    selectedFile = nil
                }
            )
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
        #if DEBUG
        print("📂 [VaultView] loadFiles() called")
        print("📂 [VaultView] currentVaultKey exists: \(appState.currentVaultKey != nil)")
        print("📂 [VaultView] isUnlocked: \(appState.isUnlocked)")
        if let key = appState.currentVaultKey {
            print("📂 [VaultView] Key hash: \(key.hashValue)")
        }
        #endif
        
        guard let key = appState.currentVaultKey else {
            #if DEBUG
            print("⚠️ [VaultView] No vault key available, stopping loadFiles")
            #endif
            isLoading = false
            return
        }

        Task {
            do {
                let fileEntries = try VaultStorage.shared.listFiles(with: key)
                #if DEBUG
                print("📂 [VaultView] Loaded \(fileEntries.count) files from storage")
                #endif
                
                let items = fileEntries.map { entry in
                    VaultFileItem(
                        id: entry.fileId,
                        size: entry.size,
                        thumbnailData: entry.thumbnailData,
                        mimeType: entry.mimeType,
                        filename: entry.filename
                    )
                }
                await MainActor.run {
                    files = items
                    isLoading = false
                }
            } catch {
                #if DEBUG
                print("❌ [VaultView] Error loading files: \(error)")
                #endif
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
                
                // Generate thumbnail
                let thumbnail = generateThumbnail(from: imageData)
                
                let fileId = try VaultStorage.shared.storeFile(
                    data: imageData,
                    filename: filename,
                    mimeType: "image/jpeg",
                    with: key,
                    thumbnailData: thumbnail
                )
                await MainActor.run {
                    files.append(VaultFileItem(
                        id: fileId,
                        size: imageData.count,
                        thumbnailData: thumbnail,
                        mimeType: "image/jpeg",
                        filename: filename
                    ))
                }
            } catch {
                // Handle error silently
            }
        }
    }

    private func handleSelectedImages(_ imagesData: [Data]) {
        #if DEBUG
        print("📸 [VaultView] handleSelectedImages called with \(imagesData.count) images")
        print("📸 [VaultView] currentVaultKey exists: \(appState.currentVaultKey != nil)")
        if let key = appState.currentVaultKey {
            print("📸 [VaultView] Key hash: \(key.hashValue)")
        }
        #endif
        
        guard let key = appState.currentVaultKey else {
            #if DEBUG
            print("❌ [VaultView] No vault key - cannot upload images!")
            #endif
            return
        }

        for (index, data) in imagesData.enumerated() {
            #if DEBUG
            print("📸 [VaultView] Processing image \(index + 1)/\(imagesData.count), size: \(data.count) bytes")
            #endif
            
            Task {
                do {
                    let filename = "IMG_\(Date().timeIntervalSince1970).jpg"
                    
                    // Generate thumbnail
                    let thumbnail = generateThumbnail(from: data)
                    #if DEBUG
                    print("📸 [VaultView] Generated thumbnail: \(thumbnail != nil)")
                    #endif
                    
                    let fileId = try VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: "image/jpeg",
                        with: key,
                        thumbnailData: thumbnail
                    )
                    #if DEBUG
                    print("✅ [VaultView] Image stored with ID: \(fileId)")
                    #endif
                    
                    await MainActor.run {
                        files.append(VaultFileItem(
                            id: fileId,
                            size: data.count,
                            thumbnailData: thumbnail,
                            mimeType: "image/jpeg",
                            filename: filename
                        ))
                        #if DEBUG
                        print("✅ [VaultView] Image added to files array. Total files: \(files.count)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("❌ [VaultView] Failed to add image \(index + 1): \(error)")
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
                    
                    // Generate thumbnail if it's an image
                    let thumbnail = mimeType.hasPrefix("image/") ? generateThumbnail(from: data) : nil
                    
                    if let fileId = try? VaultStorage.shared.storeFile(
                        data: data,
                        filename: filename,
                        mimeType: mimeType,
                        with: key,
                        thumbnailData: thumbnail
                    ) {
                        await MainActor.run {
                            files.append(VaultFileItem(
                                id: fileId,
                                size: data.count,
                                thumbnailData: thumbnail,
                                mimeType: mimeType,
                                filename: filename
                            ))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // Calculate thumbnail size (max 200x200, maintaining aspect ratio)
        let maxSize: CGFloat = 200
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        // Generate thumbnail
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Convert to JPEG with moderate compression
        return thumbnail.jpegData(compressionQuality: 0.7)
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
    let thumbnailData: Data?
    let mimeType: String?
    let filename: String?
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
            #if DEBUG
            print("🖼️ [PhotoPicker] Picker finished with \(results.count) results")
            #endif
            
            picker.dismiss(animated: true)
            
            guard !results.isEmpty else {
                #if DEBUG
                print("🖼️ [PhotoPicker] No results selected")
                #endif
                return
            }
            
            var imagesData: [Data] = []
            let group = DispatchGroup()
            
            // Process each result
            for (index, result) in results.enumerated() {
                let itemProvider = result.itemProvider
                
                #if DEBUG
                print("🖼️ [PhotoPicker] Processing result \(index + 1)/\(results.count)")
                print("🖼️ [PhotoPicker] Can load as UIImage: \(itemProvider.canLoadObject(ofClass: UIImage.self))")
                #endif
                
                // Load as image
                if itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        defer { group.leave() }
                        
                        if let error = error {
                            #if DEBUG
                            print("❌ [PhotoPicker] Error loading image \(index + 1): \(error)")
                            #endif
                            return
                        }
                        
                        guard let image = image as? UIImage,
                              let data = image.jpegData(compressionQuality: 0.8) else {
                            #if DEBUG
                            print("❌ [PhotoPicker] Failed to convert image \(index + 1) to data")
                            #endif
                            return
                        }
                        
                        #if DEBUG
                        print("✅ [PhotoPicker] Image \(index + 1) loaded, size: \(data.count) bytes")
                        #endif
                        imagesData.append(data)
                    }
                }
            }
            
            // When all images are loaded, call the callback
            group.notify(queue: .main) {
                #if DEBUG
                print("🖼️ [PhotoPicker] All images loaded. Total: \(imagesData.count)")
                print("🖼️ [PhotoPicker] Calling onImagesSelected callback")
                #endif
                self.onImagesSelected(imagesData)
            }
        }
    }
}

#Preview {
    VaultView()
        .environmentObject(AppState())
}
