import SwiftUI
import WidgetKit

/// A 3x3 pixel grid for the Dynamic Island that animates using TimelineView.
/// Mirrors the main app's PixelAnimation wave patterns.
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
                            Rectangle()
                                .fill(onSet.contains(index) ? Color.accentColor : Color.accentColor.opacity(0.15))
                                .frame(width: pixelSize, height: pixelSize)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func frameIndex(for date: Date) -> Int {
        let interval = date.timeIntervalSinceReferenceDate
        let step = Int(interval / 0.17)
        return step % columnOrder.count
    }
}
