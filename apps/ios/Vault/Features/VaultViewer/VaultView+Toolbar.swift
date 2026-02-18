import SwiftUI

// MARK: - Toolbar & Safe Area Insets

extension VaultView {

    @ToolbarContentBuilder
    var vaultToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { showingSettings = true }) {
                Image(systemName: "gear")
            }
            .accessibilityIdentifier("vault_settings_button")
            .accessibilityLabel("Settings")
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if !files.isEmpty && !subscriptionManager.isPremium {
                    StorageRingView(
                        fileCount: files.count,
                        maxFiles: SubscriptionManager.maxFreeFilesPerVault,
                        totalBytes: Int64(files.reduce(0) { $0 + $1.size })
                    )
                }

                Button(action: lockVault) {
                    Image(systemName: "lock.fill")
                }
                .accessibilityIdentifier("vault_lock_button")
                .accessibilityLabel("Lock vault")
            }
        }
    }

    // MARK: - Top Safe Area Inset

    func topSafeAreaContent(visible: VisibleFiles) -> some View {
        VStack(spacing: 8) {
            if !files.isEmpty && !showingSettings {
                HStack(spacing: 8) {
                    if isEditing {
                        editModeControls(visible: visible)
                    } else {
                        searchAndFilterControls
                    }
                }
                .padding(.horizontal)
            }
            if isSharedVault {
                sharedVaultBannerView
            }
            if appState.hasPendingImports {
                PendingImportBanner(
                    fileCount: appState.pendingImportCount,
                    onImport: { importPendingFiles() },
                    isImporting: $isImportingPendingFiles
                )
            }
        }
        .padding(.bottom, (!files.isEmpty && !showingSettings) ? 6 : 0)
        .background(Color.vaultBackground)
    }

    // MARK: - Edit Mode Controls

    private func editModeControls(visible: VisibleFiles) -> some View {
        let allVisible = visible.all
        return Group {
            // Select All / Deselect All button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if selectedIds.count == allVisible.count {
                        selectedIds.removeAll()
                    } else {
                        selectedIds = Set(allVisible.map(\.id))
                    }
                }
            } label: {
                Text(selectedIds.count == allVisible.count ? "Deselect All" : "Select All (\(allVisible.count))")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .vaultGlassBackground(cornerRadius: 12)
            }
            .accessibilityIdentifier("vault_select_all")

            // Done button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditing = false
                    selectedIds.removeAll()
                }
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .vaultGlassBackground(cornerRadius: 12)
            }
            .accessibilityIdentifier("vault_edit_done")
        }
    }

    // MARK: - Search & Filter Controls

    private var searchAndFilterControls: some View {
        Group {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.vaultSecondaryText)
                TextField("Search files", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("vault_search_field")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.vaultSecondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .vaultGlassBackground(cornerRadius: 12)

            // Filter & sort menu
            Menu {
                Section("Filter") {
                    ForEach(FileFilter.allCases) { filter in
                        Button {
                            fileFilter = filter
                        } label: {
                            if fileFilter == filter {
                                Label(filter.rawValue, systemImage: "checkmark")
                            } else {
                                Label(filter.rawValue, systemImage: filter.icon)
                            }
                        }
                    }
                }
                Section("Sort") {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: fileFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .fontWeight(.medium)
                    .padding(10)
                    .vaultGlassBackground(cornerRadius: 12)
            }
            .accessibilityIdentifier("vault_filter_menu")
            .accessibilityLabel("Filter and sort")

            // Select button (hidden for shared vaults)
            if !isSharedVault {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing = true
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .fontWeight(.medium)
                        .padding(10)
                        .vaultGlassBackground(cornerRadius: 12)
                }
                .accessibilityIdentifier("vault_select_button")
                .accessibilityLabel("Select files")
            }
        }
    }

    // MARK: - Bottom Edit Bar

    var bottomEditBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                showingBatchDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("vault_edit_delete")

            Button {
                batchExport()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .vaultProminentButtonStyle()
            .accessibilityIdentifier("vault_edit_export")
        }
        .padding(.horizontal)
        .vaultBarMaterial()
    }
}
