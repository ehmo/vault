import SwiftUI

// MARK: - Grid Content Views

extension VaultView {

    @ViewBuilder
    func fileGridContentView(visible: VisibleFiles) -> some View {
        ScrollView {
            if let masterKey {
                if useDateGrouping {
                    dateGroupedContentView(visible: visible, masterKey: masterKey.rawBytes)
                } else {
                    flatContentView(visible: visible, masterKey: masterKey.rawBytes)
                }
            } else {
                ProgressView("Decrypting...")
            }
        }
    }

    @ViewBuilder
    func dateGroupedContentView(visible: VisibleFiles, masterKey: Data) -> some View {
        let groups = groupFilesByDate(visible.all, newestFirst: sortOrder == .dateNewest)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    Group {
                        if fileFilter == .media {
                            PhotosGridView(files: group.media, masterKey: masterKey, onSelect: { file, _ in
                                EmbraceManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                                let globalIndex = visible.mediaIndexById[file.id] ?? 0
                                selectedPhotoIndex = globalIndex
                            }, onDelete: isSharedVault ? nil : deleteFileById,
                               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                        } else {
                            FilesGridView(files: group.items, onSelect: { file in
                                EmbraceManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                                selectedFile = file
                            }, onDelete: isSharedVault ? nil : deleteFileById,
                               masterKey: masterKey,
                               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
                        }
                    }
                    .padding(.top, 4)
                } header: {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(.vaultSecondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.top, index > 0 ? 12 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.vaultBackground)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    @ViewBuilder
    func flatContentView(visible: VisibleFiles, masterKey: Data) -> some View {
        if fileFilter == .media {
            PhotosGridView(files: visible.media, masterKey: masterKey, onSelect: { file, index in
                EmbraceManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
                selectedPhotoIndex = index
            }, onDelete: isSharedVault ? nil : deleteFileById,
               isEditing: isEditing, selectedIds: selectedIds, onToggleSelect: toggleSelection)
        } else {
            FilesGridView(files: visible.all, onSelect: { file in
                EmbraceManager.shared.addBreadcrumb(category: "file.selected", data: ["mimeType": file.mimeType ?? "unknown"])
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("vault_empty_state_container")
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
        .background(Color.vaultSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Import Progress

    var importingProgressContent: some View {
        let progress = max(0, min(transferManager.displayProgress, 100))
        return VStack(spacing: 20) {
            VaultSyncIndicator(style: .loading, message: "Downloading shared vault...")

            VStack(spacing: 8) {
                ProgressView(value: Double(progress), total: 100)
                    .tint(.accentColor)

                Text("\(progress)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.vaultSecondaryText)
            }

            Text(transferManager.currentMessage)
                .font(.subheadline)
                .foregroundStyle(.vaultSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .vaultGlassBackground(cornerRadius: 16)
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
