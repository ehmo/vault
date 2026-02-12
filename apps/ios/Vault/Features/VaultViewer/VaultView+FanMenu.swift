import SwiftUI

// MARK: - Fan Menu

extension VaultView {

    struct FanItem {
        let icon: String
        let label: String
        var accessibilityId: String? = nil
        let action: () -> Void
    }

    var fanMenuContent: some View {
        let items = [
            FanItem(icon: "camera.fill", label: "Camera", accessibilityId: "vault_add_camera") {
                showingFanMenu = false
                showingCamera = true
            },
            FanItem(icon: "photo.on.rectangle", label: "Library", accessibilityId: "vault_add_library") {
                showingFanMenu = false
                showingPhotoPicker = true
            },
            FanItem(icon: "doc.fill", label: "Files", accessibilityId: "vault_add_files") {
                showingFanMenu = false
                showingFilePicker = true
            },
        ]

        // Fan spreads upward-left from the + button in a quarter-circle
        let fanRadius: CGFloat = 80
        let startAngle: Double = 180 // straight left (camera aligned with + button)
        let endAngle: Double = 270   // straight up (documents aligned with + button)

        return ZStack(alignment: .bottomTrailing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let angle: Double = items.count == 1
                    ? startAngle
                    : startAngle + (endAngle - startAngle) * Double(index) / Double(items.count - 1)
                let radians = angle * .pi / 180

                Button {
                    item.action()
                } label: {
                    Image(systemName: item.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                .accessibilityLabel(item.label)
                .accessibilityIdentifier(item.accessibilityId ?? item.label)
                .offset(
                    x: showingFanMenu ? cos(radians) * fanRadius : 0,
                    y: showingFanMenu ? sin(radians) * fanRadius : 0
                )
                .scaleEffect(showingFanMenu ? 1 : 0.3)
                .opacity(showingFanMenu ? 1 : 0)
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.7)
                        .delay(showingFanMenu ? Double(index) * 0.05 : 0),
                    value: showingFanMenu
                )
            }
            // Invisible spacer so ZStack matches button size for alignment
            Color.clear.frame(width: 52, height: 52)
        }
    }

    var mainPlusButtonView: some View {
        Button {
            if subscriptionManager.canAddFile(currentFileCount: files.count) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showingFanMenu.toggle()
                }
            } else {
                showingPaywall = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(showingFanMenu ? Color(.systemGray) : Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .rotationEffect(.degrees(showingFanMenu ? 45 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vault_add_button")
        .accessibilityLabel(showingFanMenu ? "Close menu" : "Add files")
    }
}
