import SwiftUI
import WidgetKit

/// App accent color hardcoded for widget extension (no access to main app's asset catalog).
private let vaultAccent = Color(red: 0.384, green: 0.275, blue: 0.918)

/// A 3x3 pixel grid for the Dynamic Island matching the in-app PixelAnimation.loading() preset:
/// single cell perimeter walk, brightness 3, shadowBrightness 2, radius 10.
///
/// Animation is driven by `animationStep` from ContentState updates (~0.5s ticks)
/// because `TimelineView(.animation)` does not re-render in widget extensions.
struct LivePixelGrid: View {
    let animationStep: Int
    var size: CGFloat = 20
    var pixelSize: CGFloat = 4.5
    var spacing: CGFloat = 1

    /// Perimeter walk: single cell moves clockwise around the border.
    /// Matches PixelAnimation.loading() pattern: [[1, 2, 3, 6, 9, 8, 7, 4]]
    private let frames: [[Int]] = [[1], [2], [3], [6], [9], [8], [7], [4]]

    var body: some View {
        let frame = animationStep % frames.count
        let onSet = Set(frames[frame])

        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col + 1
                        let isOn = onSet.contains(index)
                        pixelCell(isOn: isOn)
                            .animation(.smooth(duration: 0.2), value: isOn)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// Matches in-app PixelAnimationCell + PixelShadowStack:
    /// brightness 3 (3 stacked rectangles), shadowBrightness 2 (2 overlay shadow layers at radius 10).
    @ViewBuilder
    private func pixelCell(isOn: Bool) -> some View {
        let base = ZStack {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
            }
        }
        .foregroundStyle(isOn ? vaultAccent : .clear)
        .frame(width: pixelSize, height: pixelSize)

        base.overlay {
            ForEach(0..<2, id: \.self) { _ in
                base.shadow(
                    color: isOn ? vaultAccent : .clear,
                    radius: 10, x: 0, y: 0
                )
            }
        }
    }
}
