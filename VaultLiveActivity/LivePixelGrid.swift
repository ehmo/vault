import SwiftUI
import WidgetKit

/// App accent color hardcoded for widget extension (no access to main app's asset catalog).
private let vaultAccent = Color(red: 0.384, green: 0.275, blue: 0.918)

/// A 3x3 pixel grid for the Dynamic Island matching the in-app PixelAnimation.loading() preset.
///
/// The in-app version creates a trail via animation overlap (animationDuration 0.3s > timerInterval 0.1s),
/// so ~3 cells are visible at once with decreasing brightness as they fade out.
/// Since widget extensions don't support continuous implicit animations, we compute the trail explicitly:
/// the head cell at full opacity plus 3 trailing cells at decreasing opacity.
///
/// Animation is driven by `animationStep` from ContentState updates
/// because `TimelineView(.animation)` does not re-render in widget extensions.
struct LivePixelGrid: View {
    let animationStep: Int
    var size: CGFloat = 20
    var pixelSize: CGFloat = 4.5
    var spacing: CGFloat = 1

    /// Perimeter walk order: clockwise around the border, skipping center.
    /// Matches PixelAnimation.loading() pattern.
    private static let path = [1, 2, 3, 6, 9, 8, 7, 4]

    /// Trail length matching in-app animationDuration/timerInterval ratio (0.3/0.1 = 3 trailing cells).
    private static let trailOpacities: [Double] = [1.0, 0.55, 0.25, 0.08]

    var body: some View {
        let opacityMap = cellOpacities()

        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col + 1
                        let opacity = opacityMap[index] ?? 0
                        pixelCell(opacity: opacity)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// Compute opacity for each cell based on trail position.
    private func cellOpacities() -> [Int: Double] {
        let pathLen = Self.path.count
        let headIndex = animationStep % pathLen
        var map: [Int: Double] = [:]
        for (offset, opacity) in Self.trailOpacities.enumerated() {
            let pathIndex = (headIndex - offset + pathLen) % pathLen
            let cell = Self.path[pathIndex]
            // Head takes priority over trail (no double-assignment)
            if map[cell] == nil {
                map[cell] = opacity
            }
        }
        return map
    }

    /// Matches in-app PixelAnimationCell + PixelShadowStack:
    /// brightness 3 (3 stacked rectangles), shadowBrightness 2 (2 overlay shadow layers at radius 10).
    @ViewBuilder
    private func pixelCell(opacity: Double) -> some View {
        let isOn = opacity > 0
        let cellColor = isOn ? vaultAccent.opacity(opacity) : Color.clear
        let base = ZStack {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
            }
        }
        .foregroundStyle(cellColor)
        .frame(width: pixelSize, height: pixelSize)

        base.overlay {
            ForEach(0..<2, id: \.self) { _ in
                base.shadow(
                    color: isOn ? vaultAccent.opacity(opacity) : .clear,
                    radius: 10, x: 0, y: 0
                )
            }
        }
    }
}
