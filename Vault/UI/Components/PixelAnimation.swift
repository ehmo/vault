import SwiftUI
import Combine

// MARK: - PixelAnimation

/// A 3x3 pixel grid that animates cells on/off in configurable patterns with glow effects.
/// Ported from Pixel view, restyled for Vault's theme.
///
/// The trail effect (matching the Dynamic Island's LivePixelGrid) is produced by animation overlap:
/// `animationDuration > timerInterval` means ~3 cells are visible at once as they fade out.
/// This requires Timer.publish + onReceive — TimelineView re-evaluates its body on each tick,
/// which disrupts in-flight implicit animations and breaks the trail.
struct PixelAnimation: View {
    var brightness: Int = 2
    var shadowBrightness: Int = 2
    var color: Color = .accentColor
    var rotation: CGFloat = 0
    var tileSize: CGFloat = 64
    var pixelSize: CGFloat = 10
    var spacing: CGFloat = 0
    var timerInterval: Double = 0.1
    var animationDuration: Double = 0.25
    var pattern: [[Int]] = [[1, 2, 3, 6, 9, 8, 7, 4]]

    @State private var step: Int = 0

    private var timer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: timerInterval, on: .main, in: .common).autoconnect()
    }

    private var frames: [[Int]] {
        guard let first = pattern.first else { return [] }
        if pattern.count == 1 { return first.map { [$0] } }
        let allSingles = pattern.allSatisfy { $0.count == 1 }
        if allSingles {
            let merged = pattern.compactMap(\.first)
            return [merged, []]
        }
        return pattern
    }

    var body: some View {
        let onSet = Set(frames.isEmpty ? [] : frames[step])
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col + 1
                        PixelAnimationCell(
                            isOn: onSet.contains(index),
                            size: pixelSize,
                            color: color,
                            brightness: brightness,
                            shadowBrightness: shadowBrightness
                        )
                        .rotationEffect(.degrees(rotation))
                    }
                }
            }
        }
        .frame(width: tileSize, height: tileSize)
        .onReceive(timer) { _ in
            guard !frames.isEmpty else { return }
            withAnimation(.smooth(duration: animationDuration)) {
                step = (step + 1) % frames.count
            }
        }
        .onChange(of: frames.count) { _, _ in
            if step >= frames.count { step = 0 }
        }
    }
}

// MARK: - PixelAnimationCell

private struct PixelAnimationCell: View {
    let isOn: Bool
    let size: CGFloat
    let color: Color
    var brightness: Int = 2
    var shadowBrightness: Int = 2

    var body: some View {
        ZStack {
            ForEach(0..<brightness, id: \.self) { _ in
                Rectangle()
            }
        }
        .foregroundStyle(isOn ? color : .clear)
        .frame(width: size, height: size)
        .modifier(PixelShadowStack(
            enabled: isOn,
            color: color,
            count: shadowBrightness
        ))
    }
}

// MARK: - PixelShadowStack

private struct PixelShadowStack: ViewModifier {
    let enabled: Bool
    let color: Color
    let count: Int

    func body(content: Content) -> some View {
        content
            .overlay {
                ForEach(0..<count, id: \.self) { _ in
                    content.shadow(
                        color: enabled ? color : .clear,
                        radius: 10, x: 0, y: 0
                    )
                }
            }
    }
}

// MARK: - Factory Methods

extension PixelAnimation {
    /// Upload/sync: wave left-to-right pattern, accent color
    static func uploading(size: CGFloat = 40) -> PixelAnimation {
        let scale = size / 64
        return PixelAnimation(
            brightness: 2,
            shadowBrightness: 1,
            color: .accentColor,
            tileSize: size,
            pixelSize: 14 * scale,
            timerInterval: 0.17,
            animationDuration: 0.2,
            pattern: [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
        )
    }

    /// Download: wave right-to-left pattern, accent color
    static func downloading(size: CGFloat = 40) -> PixelAnimation {
        let scale = size / 64
        return PixelAnimation(
            brightness: 2,
            shadowBrightness: 1,
            color: .accentColor,
            tileSize: size,
            pixelSize: 14 * scale,
            timerInterval: 0.17,
            animationDuration: 0.2,
            pattern: [[3, 6, 9], [2, 5, 8], [1, 4, 7]]
        )
    }

    /// Sync badge: plus/cross pattern pulse
    static func syncing(size: CGFloat = 24) -> PixelAnimation {
        let scale = size / 64
        return PixelAnimation(
            brightness: 1,
            shadowBrightness: 1,
            color: .accentColor,
            tileSize: size,
            pixelSize: 14 * scale,
            timerInterval: 0.3,
            animationDuration: 0.2,
            pattern: [[2], [4], [6], [8]]
        )
    }

    /// Generic loading: frame rotation pattern (unlock screen).
    /// Trail effect: animationDuration (0.3s) > timerInterval (0.1s) → ~3 cells visible at once,
    /// matching the Dynamic Island's LivePixelGrid explicit trail computation.
    static func loading(size: CGFloat = 60) -> PixelAnimation {
        let scale = size / 80
        return PixelAnimation(
            brightness: 3,
            shadowBrightness: 2,
            color: .accentColor,
            tileSize: size,
            pixelSize: 14 * scale,
            timerInterval: 0.1,
            animationDuration: 0.3,
            pattern: [[1, 2, 3, 6, 9, 8, 7, 4]]
        )
    }
}

#Preview("Uploading") {
    PixelAnimation.uploading()
        .padding()
        .background(.black)
}

#Preview("Loading") {
    PixelAnimation.loading(size: 80)
        .padding()
        .background(.black)
}
