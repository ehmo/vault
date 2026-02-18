import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                    Button {
                        appState.setAppearanceMode(mode)
                    } label: {
                        HStack {
                            Text(mode.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appState.appearanceMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityIdentifier("appearance_\(mode.rawValue)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
