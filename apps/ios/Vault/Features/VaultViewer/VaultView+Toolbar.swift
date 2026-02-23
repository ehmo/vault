import SwiftUI

// MARK: - Toolbar Header & Safe Area Insets

extension VaultView {

    // MARK: - Custom Toolbar Header

    /// Pure SwiftUI header that replaces NavigationStack toolbar items.
    /// Avoids UIKit navigation bar insertion animation that causes toolbar
    /// icons to jump positions on initial appearance.
    var toolbarHeaderView: some View {
        ZStack {
            // Title centered on screen (independent of button widths)
            // Constrained width to prevent overlap with toolbar buttons (44pt each side + padding)
            Text(appState.vaultName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200)

            // Buttons on the edges
            HStack {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .vaultGlassBackground(cornerRadius: 22)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vault_settings_button")
                .accessibilityLabel("Settings")

                Spacer()

                HStack(spacing: 12) {
                    if !viewModel.files.isEmpty && !subscriptionManager.isPremium {
                        StorageRingView(
                            fileCount: viewModel.files.count,
                            maxFiles: SubscriptionManager.maxFreeFilesPerVault,
                            totalBytes: Int64(viewModel.files.reduce(0) { $0 + $1.size })
                        )
                    }

                    Button(action: lockVault) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 44, height: 44)
                            .vaultGlassBackground(cornerRadius: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vault_lock_button")
                    .accessibilityLabel("Lock vault")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Top Safe Area Inset

    func topSafeAreaContent(visible: VisibleFiles) -> some View {
        VStack(spacing: 8) {
            if !showingSettings {
                toolbarHeaderView
            }

            VStack(spacing: 8) {
                if !viewModel.files.isEmpty && !showingSettings {
                    HStack(spacing: 8) {
                        if viewModel.isEditing {
                            editModeControls(visible: visible)
                        } else {
                            searchAndFilterControls
                        }
                    }
                    .padding(.horizontal)
                }
                if viewModel.isSharedVault {
                    sharedVaultBannerView
                }
                if appState.hasPendingImports {
                    PendingImportBanner(
                        fileCount: appState.pendingImportCount,
                        onImport: { viewModel.importPendingFiles() },
                        isImporting: Binding(
                            get: { viewModel.isImportingPendingFiles },
                            set: { viewModel.isImportingPendingFiles = $0 }
                        )
                    )
                }
            }
        }
        .padding(.bottom, (!viewModel.files.isEmpty && !showingSettings) ? 6 : 0)
        .background(Color.vaultBackground)
    }

    // MARK: - Edit Mode Controls

    private func editModeControls(visible: VisibleFiles) -> some View {
        let allVisible = visible.all
        return Group {
            // Select All / Deselect All button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if viewModel.selectedIds.count == allVisible.count {
                        viewModel.selectedIds.removeAll()
                    } else {
                        viewModel.selectedIds = Set(allVisible.map(\.id))
                    }
                }
            } label: {
                Text(viewModel.selectedIds.count == allVisible.count ? "Deselect All" : "Select All (\(allVisible.count))")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .vaultGlassBackground(cornerRadius: 12)
            }
            .accessibilityIdentifier("vault_select_all")

            // Done button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isEditing = false
                    viewModel.selectedIds.removeAll()
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
                TextField("Search files", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit {
                        // Dismiss keyboard when Done is tapped
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("vault_search_field")
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
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
                            viewModel.setFileFilter(filter)
                            EmbraceManager.shared.addBreadcrumb(category: "filter.changed")
                        } label: {
                            if viewModel.fileFilter == filter {
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
                            viewModel.sortOrder = order
                        } label: {
                            if viewModel.sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: viewModel.fileFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .fontWeight(.medium)
                    .padding(10)
                    .vaultGlassBackground(cornerRadius: 12)
            }
            .accessibilityIdentifier("vault_filter_menu")
            .accessibilityLabel("Filter and sort")

            // Select button (shown for regular vaults and shared vaults that allow downloads)
            let canSelect = !viewModel.isSharedVault || (viewModel.sharePolicy?.allowDownloads ?? true)
            if canSelect {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isEditing = true
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
            // Delete button only for regular vaults (not shared vaults)
            if !viewModel.isSharedVault {
                Button(role: .destructive) {
                    viewModel.showingBatchDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("vault_edit_delete")
            }

            // Export button (shown for all vaults, but especially important for shared vaults with allowDownloads)
            Button {
                viewModel.batchExport()
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
