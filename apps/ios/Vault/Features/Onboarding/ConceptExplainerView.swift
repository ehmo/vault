import SwiftUI

/// A horizontally-paged explainer that introduces the six core Vaultaire concepts
/// right after the Welcome screen. Each page is visual-first with minimal text.
struct ConceptExplainerView: View {
    let onContinue: () -> Void

    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let totalPages = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                PatternEncryptionPage().tag(0)
                PlausibleDeniabilityPage().tag(1)
                DuressVaultPage().tag(2)
                EncryptedSharingPage().tag(3)
                EncryptedBackupPage().tag(4)
                HardwareSecurityPage().tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .easeInOut, value: currentPage)

            // Page dots
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(Color.accentColor.opacity(index == currentPage ? 1 : 0.25))
                        .frame(width: index == currentPage ? 20 : 6, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 12)

            // Continue button
            Button(action: {
                if currentPage < totalPages - 1 {
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        currentPage += 1
                    }
                } else {
                    onContinue()
                }
            }) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .vaultProminentButtonStyle()
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .accessibilityIdentifier("concepts_continue")
        }
        .background(Color.vaultBackground.ignoresSafeArea())
    }
}

// MARK: - Page 1: Pattern-Based Encryption

private struct PatternEncryptionPage: View {
    @State private var animatePattern = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Visual: 4x4 grid with highlighted path
            ZStack {
                // Glow behind grid
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 240, height: 240)

                PatternDemoGrid(animatePattern: animatePattern)
            }
            .frame(height: 260)
            .onAppear {
                guard !reduceMotion else {
                    animatePattern = true
                    return
                }
                withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                    animatePattern = true
                }
            }

            Spacer()

            // Text
            VStack(spacing: 10) {
                Text("Your Pattern Is Your Key")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Draw a pattern. It becomes an encryption key. Different pattern, different vault.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 120, alignment: .top)
        }
        .padding(.horizontal, 24)
    }
}

/// A 5x5 dot grid with an animated path showing a pattern being drawn.
private struct PatternDemoGrid: View {
    let animatePattern: Bool

    private let gridSize = 5
    private let dotSize: CGFloat = 10
    private let gridWidth: CGFloat = 200

    // Highlighted dots (row, col) representing the demo pattern path
    private let highlightedDots: [(Int, Int)] = [(0, 0), (1, 1), (2, 2), (3, 3), (3, 4), (4, 4)]

    var body: some View {
        ZStack {
            // Draw all dots
            ForEach(0..<gridSize, id: \.self) { row in
                ForEach(0..<gridSize, id: \.self) { col in
                    let isHighlighted = highlightedDots.contains { $0.0 == row && $0.1 == col }
                    Circle()
                        .fill(isHighlighted && animatePattern
                              ? Color.accentColor
                              : Color.vaultSecondaryText.opacity(0.3))
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(isHighlighted && animatePattern ? 1.4 : 1.0)
                        .shadow(color: isHighlighted && animatePattern
                                ? Color.accentColor.opacity(0.5) : .clear,
                                radius: 8)
                        .position(dotPosition(row: row, col: col))
                }
            }

            // Path lines
            if animatePattern {
                Path { path in
                    for (i, dot) in highlightedDots.enumerated() {
                        let pos = dotPosition(row: dot.0, col: dot.1)
                        if i == 0 {
                            path.move(to: pos)
                        } else {
                            path.addLine(to: pos)
                        }
                    }
                }
                .trim(from: 0, to: animatePattern ? 1 : 0)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // "Vault unlocked" badge at bottom
            if animatePattern {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    Text("Vault unlocked")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .vaultGlassBackground(cornerRadius: 10)
                .offset(y: gridWidth / 2 + 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: gridWidth, height: gridWidth)
    }

    private func dotPosition(row: Int, col: Int) -> CGPoint {
        let spacing = gridWidth / CGFloat(gridSize - 1)
        return CGPoint(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing)
    }
}

// MARK: - Page 2: Plausible Deniability

private struct PlausibleDeniabilityPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Visual: Two mini phones
            HStack(spacing: 20) {
                MiniPhoneView(label: "Your view", labelColor: .green) {
                    // 3x5 gallery grid resembling the vault file grid
                    let cols = 3
                    let rows = 5
                    let cellSize: CGFloat = 28
                    let gap: CGFloat = 4
                    VStack(spacing: gap) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(0..<cols, id: \.self) { col in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.accentColor.opacity(
                                            row < 3 ? 0.15 : 0.08
                                        ))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Color.accentColor.opacity(0.1), lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                    }
                }

                Text("=")
                    .font(.title)
                    .fontWeight(.light)
                    .foregroundStyle(.vaultSecondaryText)

                MiniPhoneView(label: "Their view", labelColor: .vaultSecondaryText) {
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.vaultSecondaryText.opacity(0.3))
                        Text("No vaults visible")
                            .font(.system(size: 9))
                            .foregroundStyle(.vaultSecondaryText.opacity(0.5))
                    }
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Text("Nothing to Find")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Without your pattern, there's no trace\nthat hidden vaults even exist.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No vault count. No file list. No metadata.")
                    .font(.caption)
                    .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(height: 120, alignment: .top)
        }
        .padding(.horizontal, 24)
    }
}

/// A small phone-shaped container used in the Plausible Deniability page.
private struct MiniPhoneView<Content: View>: View {
    let label: String
    let labelColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.vaultSurface)
                    .frame(width: 120, height: 190)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.vaultSecondaryText.opacity(0.1), lineWidth: 1)
                    )

                // Notch
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.vaultSecondaryText.opacity(0.1))
                    .frame(width: 36, height: 5)
                    .offset(y: -85)

                content
                    .frame(width: 100)
            }

            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(labelColor)
        }
    }
}

// MARK: - Page 3: Duress Vault

private struct DuressVaultPage: View {
    @State private var animatePulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Visual: 5x5 pattern grid with red duress path
            DuressPatternGrid(animatePulse: animatePulse)

            Spacer().frame(height: 24)

            // Vault rows showing wipe result
            VStack(spacing: 8) {
                DuressVaultRow(icon: "folder.fill", name: "Private Photos", status: "Destroyed", isWiped: true)
                DuressVaultRow(icon: "doc.fill", name: "Documents", status: "Destroyed", isWiped: true)
                DuressVaultRow(icon: "music.note", name: "Duress Vault", status: "Visible", isWiped: false)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Text("A Panic Button Disguised as a Pattern")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("If forced to unlock, the duress pattern silently wipes your real vaults.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 120, alignment: .top)
        }
        .padding(.horizontal, 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
}

/// A 5x5 dot grid with a red duress pattern path.
private struct DuressPatternGrid: View {
    let animatePulse: Bool

    private let gridSize = 5
    private let dotSize: CGFloat = 10
    private let gridWidth: CGFloat = 160

    // Duress pattern: Z-shape with direction changes
    private let highlightedDots: [(Int, Int)] = [(0, 0), (0, 2), (2, 2), (4, 0), (4, 2)]

    var body: some View {
        ZStack {
            // Glow behind grid
            Circle()
                .fill(Color.red.opacity(0.06))
                .frame(width: 200, height: 200)

            // Draw all dots
            ForEach(0..<gridSize, id: \.self) { row in
                ForEach(0..<gridSize, id: \.self) { col in
                    let isHighlighted = highlightedDots.contains { $0.0 == row && $0.1 == col }
                    Circle()
                        .fill(isHighlighted
                              ? Color.red
                              : Color.vaultSecondaryText.opacity(0.3))
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(isHighlighted ? 1.4 : 1.0)
                        .shadow(color: isHighlighted
                                ? Color.red.opacity(animatePulse ? 0.5 : 0.2) : .clear,
                                radius: isHighlighted ? 8 : 0)
                        .position(dotPosition(row: row, col: col))
                }
            }

            // Path lines connecting highlighted dots
            Path { path in
                for (i, dot) in highlightedDots.enumerated() {
                    let pos = dotPosition(row: dot.0, col: dot.1)
                    if i == 0 {
                        path.move(to: pos)
                    } else {
                        path.addLine(to: pos)
                    }
                }
            }
            .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: gridWidth, height: gridWidth)
    }

    private func dotPosition(row: Int, col: Int) -> CGPoint {
        let spacing = gridWidth / CGFloat(gridSize - 1)
        return CGPoint(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing)
    }
}

private struct DuressVaultRow: View {
    let icon: String
    let name: String
    let status: String
    let isWiped: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 20)

            Text(name)
                .font(.caption)
                .fontWeight(.medium)

            Spacer()

            Text(status)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(isWiped ? .red : .green)
        }
        .padding(10)
        .opacity(isWiped ? 0.5 : 1)
        .vaultGlassBackground(cornerRadius: 10)
    }
}

// MARK: - Page 4: Encrypted Sharing

private struct EncryptedSharingPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Visual: Two phones with encrypted tunnel
            HStack(spacing: 0) {
                // Left phone
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vaultSurface)
                    .frame(width: 64, height: 100)
                    .overlay(
                        Image(systemName: "iphone")
                            .font(.system(size: 28))
                            .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                    )

                // Encrypted tunnel
                ZStack {
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            AnimatedTunnelLine()
                        }
                    }

                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                        .background(Color.vaultBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.vaultSecondaryText.opacity(0.15))
                        )
                }
                .frame(width: 80)

                // Right phone
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vaultSurface)
                    .frame(width: 64, height: 100)
                    .overlay(
                        Image(systemName: "iphone")
                            .font(.system(size: 28))
                            .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                    )
            }

            Spacer().frame(height: 28)

            // Feature badges
            VStack(spacing: 8) {
                ShareBadgeRow(icon: "person.crop.circle.badge.xmark", label: "Accounts required", value: "None")
                ShareBadgeRow(icon: "person.fill.questionmark", label: "Identity shared", value: "None")
                ShareBadgeRow(icon: "lock.shield.fill", label: "Encryption", value: "End-to-end")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Text("Share Without a Trace")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Send encrypted vaults to anyone.\nNo accounts, no identity, no metadata trail.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 120, alignment: .top)
        }
        .padding(.horizontal, 24)
    }
}

private struct AnimatedTunnelLine: View {
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(
                LinearGradient(
                    colors: [.clear, Color.accentColor.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: animate ? geo.size.width : -geo.size.width * 0.6)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

private struct ShareBadgeRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)

            Text(label)
                .font(.caption)
                .foregroundStyle(.vaultSecondaryText)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        }
        .padding(10)
        .vaultGlassBackground(cornerRadius: 10)
    }
}

// MARK: - Page 5: Encrypted Backup

private struct EncryptedBackupPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Visual: Phone → Lock → Cloud
            VStack(spacing: 0) {
                // Phone icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.vaultSurface)
                        .frame(width: 64, height: 80)
                    Image(systemName: "iphone")
                        .font(.system(size: 28))
                        .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                }

                // Arrow with lock badge
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2, height: 50)

                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("AES-256")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.vaultBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.vaultSecondaryText.opacity(0.15))
                    )
                }
                .frame(height: 60)

                // Cloud icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.vaultSurface)
                        .frame(width: 80, height: 64)
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.vaultSecondaryText.opacity(0.6))
                }
            }

            Spacer().frame(height: 24)

            // Tags — vertical list
            VStack(alignment: .leading, spacing: 8) {
                BackupTagRow(text: "Encrypted locally first")
                BackupTagRow(text: "Pattern required to decrypt")
                BackupTagRow(text: "Apple can't read it")
                BackupTagRow(text: "We can't read it")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Text("Backed Up. Still Private.")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Encrypted on-device before it touches iCloud. Only your pattern can unlock it.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 120, alignment: .top)
        }
        .padding(.horizontal, 24)
    }
}

private struct BackupTagRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.green)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.vaultSecondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vaultGlassBackground(cornerRadius: 10)
    }
}

// MARK: - Page 6: Hardware Security

private struct HardwareSecurityPage: View {
    @State private var animateGlow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Visual: Chip with glow
            ZStack {
                // Pulsing glow
                Circle()
                    .fill(Color.accentColor.opacity(animateGlow ? 0.15 : 0.05))
                    .frame(width: 180, height: 180)
                    .scaleEffect(animateGlow ? 1.1 : 0.9)

                // Chip body
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.vaultSurface,
                                    Color.vaultSurface.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                                .padding(6)
                        )

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                }

                // Circuit traces
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) * 90.0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 2, height: 24)
                        .offset(y: -70)
                        .rotationEffect(.degrees(angle))
                }
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) * 90.0 + 45.0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 2, height: 18)
                        .offset(y: -66)
                        .rotationEffect(.degrees(angle))
                }
            }
            .frame(height: 200)

            Spacer().frame(height: 24)

            // Feature rows
            VStack(spacing: 8) {
                HardwareFeatureRow(icon: "key.fill", text: "Keys stored in Secure Enclave")
                HardwareFeatureRow(icon: "xmark.shield.fill", text: "Keys never leave the chip")
                HardwareFeatureRow(icon: "bolt.shield.fill", text: "Hardware-accelerated encryption")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Text("Protected by Your Device's Chip")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Encryption keys live in Apple's Secure Enclave. They can't be extracted — even by us.")
                    .font(.subheadline)
                    .foregroundStyle(.vaultSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 120, alignment: .top)
        }
        .padding(.horizontal, 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
        }
    }
}

private struct HardwareFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22)

            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary.opacity(0.8))

            Spacer()
        }
        .padding(10)
        .vaultGlassBackground(cornerRadius: 10)
    }
}

// MARK: - Previews

#Preview("Concept Explainer") {
    ConceptExplainerView(onContinue: {})
}
