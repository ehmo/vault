import SwiftUI

// MARK: - Grid Content Views

extension VaultView {

    @ViewBuilder
    var fileGridContentView: some View {
        ScrollView {
            if let masterKey {
                if useDateGrouping {
                    dateGroupedContentView(masterKey: masterKey)
                } else {
                    flatContentView(split: splitFiles, masterKey: masterKey)
                }
            } else {
                ProgressView("Decrypting...")
            }
        }
    }

    @ViewBuilder
    func dateGroupedContentView(masterKey: Data) -> some View {
        let groups = groupFilesByDate(sortedFiles)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(groups) { group in
                Section {
                    Group {
                        if fileFilter == .media {
                            PhotosGridView(files: group.media, masterKey: masterKey, onSelect: { file, _ in
                                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                                let allMedia = sortedFiles.filter {
                                    let mime = $0.mimeType ?? ""
                                    return mime.hasPrefix("image/") || mime.hasPrefix("video/")
                                }
                                let globalIndex = allMedia.firstIndex(where: { $0.id == file.id }) ?? 0
                                selectedPhotoIndex = globalIndex
                            }, onDelete: isSharedVault ? nil : deleteFileById,
                               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                        } else {
                            FilesGridView(files: group.items, onSelect: { file in
                                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                                selectedFile = file
                            }, onDelete: isSharedVault ? nil : deleteFileById,
                               masterKey: masterKey,
                               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                        }
                    }
                    .padding(.top, 8)
                } header: {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.vaultSecondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    @ViewBuilder
    func flatContentView(split: (all: [VaultFileItem], media: [VaultFileItem], documents: [VaultFileItem]), masterKey: Data) -> some View {
        switch fileFilter {
        case .media:
            PhotosGridView(files: split.media, masterKey: masterKey, onSelect: { file, index in
                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedPhotoIndex = index
            }, onDelete: isSharedVault ? nil : deleteFileById,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
        default:
            FilesGridView(files: split.all, onSelect: { file in
                SentryManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedFile = file
            }, onDelete: isSharedVault ? nil : deleteFileById,
               masterKey: masterKey,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
        }
    }

    // MARK: - Skeleton Loading

    var skeletonGridContent: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<12, id: \.self) { _ in
                    Color.vaultSurface
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    // MARK: - Empty State

    var emptyStateContent: some View {
        VStack(spacing: 20) {
            if case .importing = transferManager.status {
                Spacer()
                importingProgressContent
                Spacer()
            } else if isSharedVault {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.vaultSecondaryText)
                    .accessibilityHidden(true)

                Text("Waiting for files")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("The vault owner hasn't added any files yet")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Spacer()

                // 3-step walkthrough
                VStack(spacing: 12) {
                    walkthroughCard(
                        icon: "plus.circle.fill",
                        title: "Add your files",
                        description: "Photos, videos, documents — anything you want to protect"
                    )
                    walkthroughCard(
                        icon: "lock.shield.fill",
                        title: "Encrypted instantly",
                        description: "Your files are scrambled with military-grade encryption"
                    )
                    walkthroughCard(
                        icon: "eye.slash.fill",
                        title: "Only you can access",
                        description: "Your pattern is the only key. Not even us."
                    )
                }

                Spacer()

                Button(action: {
                    if subscriptionManager.canAddFile(currentFileCount: files.count) {
                        showingImportOptions = true
                    } else {
                        showingPaywall = true
                    }
                }) {
                    Label("Protect Your First Files", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .vaultProminentButtonStyle()
                .accessibilityIdentifier("vault_first_files")
                .accessibilityHint("Import photos, videos, or files into the vault")
            }
        }
        .padding()
    }

    @ViewBuilder
    func walkthroughCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.vaultSecondaryText)
            }

            Spacer()
        }
        .padding(14)
        .vaultGlassBackground(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Import Progress

    var importingProgressContent: some View {
        VStack(spacing: 24) {
            PixelAnimation.loading(size: 60)

            Text("Downloading shared vault...")
                .font(.title3)
                .fontWeight(.medium)

            if transferManager.displayProgress > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(transferManager.displayProgress), total: 100)
                        .tint(.accentColor)
                        .padding(.horizontal, 40)

                    Text("\(transferManager.displayProgress)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.vaultSecondaryText)
                }
            }

            Text(transferManager.currentMessage)
                .font(.caption)
                .foregroundStyle(.vaultSecondaryText)
        }
        .accessibilityIdentifier("vault_import_progress")
    }

    // MARK: - Local Import Progress

    func localImportProgressContent(completed: Int, total: Int) -> some View {
        let percentage = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
        return VStack(spacing: 24) {
            PixelAnimation.loading(size: 60)

            Text(isDeleteInProgress ? "Deleting \(completed) of \(total)..." : "Importing \(completed) of \(total)...")
                .font(.title3)
                .fontWeight(.medium)

            VStack(spacing: 8) {
                ProgressView(value: Double(completed), total: Double(total))
                    .tint(.accentColor)
                    .padding(.horizontal, 40)

                Text("\(percentage)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.vaultSecondaryText)
            }
        }
    }
}
