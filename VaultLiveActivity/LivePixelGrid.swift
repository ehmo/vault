import SwiftUI
import WidgetKit

/// App accent color hardcoded for widget extension (no access to main app's asset catalog).
private let vaultAccent = Color(red: 0.384, green: 0.275, blue: 0.918)

/// A 3x3 pixel grid for the Dynamic Island that animates column-sweep patterns
/// with smooth crossfade transitions, matching the in-app PixelAnimation style.
struct LivePixelGrid: View {
    let transferType: TransferActivityAttributes.TransferType
    var size: CGFloat = 20
    var pixelSize: CGFloat = 4.5
    var spacing: CGFloat = 1

    /// Upload: L→R columns; Download: R→L columns
    private var columnOrder: [[Int]] {
        switch transferType {
        case .uploading:
            return [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
        case .downloading:
            return [[3, 6, 9], [2, 5, 8], [1, 4, 7]]
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.17)) { timeline in
            let frame = frameIndex(for: timeline.date)
            let onSet = Set(columnOrder[frame])

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

    private func frameIndex(for date: Date) -> Int {
        let interval = date.timeIntervalSinceReferenceDate
        let step = Int(interval / 0.17)
        return step % columnOrder.count
    }
}
