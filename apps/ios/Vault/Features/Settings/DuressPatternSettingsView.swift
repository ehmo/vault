import SwiftUI

struct DuressPatternSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasDuressVault = false
    @State private var showingSetupSheet = false

    var body: some View {
        List {
            Section {
                if hasDuressVault {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Duress vault configured")
                    }

                    Button("Change duress vault") {
                        showingSetupSheet = true
                    }

                    Button("Remove duress vault", role: .destructive) {
                        Task {
                            await DuressHandler.shared.clearDuressVault()
                            await MainActor.run {
                                hasDuressVault = false
                            }
                        }
                    }
                } else {
                    Text("No duress vault configured")
                        .foregroundStyle(.vaultSecondaryText)

                    Button("Set up duress vault") {
                        showingSetupSheet = true
                    }
                }
            } header: {
                Text("Duress Vault")
            } footer: {
                Text("When you enter the duress pattern, all other vaults are silently destroyed while showing this vault's content.")
            }

            Section("How It Works") {
                Label("Enter duress pattern under coercion", systemImage: "1.circle")
                Label("All other vaults are permanently destroyed", systemImage: "2.circle")
                Label("Duress vault content is shown normally", systemImage: "3.circle")
                Label("No visible indication that anything happened", systemImage: "4.circle")
            }
            .font(.subheadline)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationTitle("Duress Pattern")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            hasDuressVault = await DuressHandler.shared.hasDuressVault
        }
        .fullScreenCover(isPresented: $showingSetupSheet) {
            DuressSetupSheet()
        }
    }
}

struct DuressSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.vaultHighlight)

                Text("Set Up Duress Vault")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose which vault to keep accessible when under duress. All other vaults will be destroyed when this pattern is entered.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Text("Enter the pattern for the vault you want to use as your duress vault.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)

                // Pattern input would go here
                // For now, placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vaultSurface)
                    .frame(height: 200)
                    .overlay {
                        Text("Pattern input")
                            .foregroundStyle(.vaultSecondaryText)
                    }

                Spacer()
            }
            .padding()
            .navigationTitle("Duress Vault")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.vaultBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
