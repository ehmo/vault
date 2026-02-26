import SwiftUI
import UIKit

// MARK: - PixelLoader

/// Unified pixel loader with trailing snake animation.
///
/// Features:
/// - Counter-clockwise snake around cube perimeter (1→2→3→6→9→8→7→4)
/// - Explicit trailing cells with decreasing opacity (head + 2 trailing)
/// - Stronger colors for better visibility in both light and dark modes
/// - Single unified appearance across the entire app
///
/// Uses `TimelineView` instead of `Timer.publish` so the animation only runs
/// while the view is on-screen, eliminating idle CPU cost.
struct PixelLoader: View {
    var size: CGFloat = 60
    var color: Color = .accentColor

    // Counter-clockwise perimeter walk: around the border skipping center
    // 1→2→3→6→9→8→7→4 (skipping center 5)
    private static let path = [1, 2, 3, 6, 9, 8, 7, 4]

    // Trail opacities: head + 2 trailing cells
    private static let trailOpacities: [Double] = [1.0, 0.66, 0.33]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let step = Self.step(for: context.date)
            let opacityMap = Self.cellOpacities(step: step)
            let pixelSize = size / 4.5
            let spacing = size / 20

            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col + 1
                            let opacity = opacityMap[index] ?? 0
                            PixelCell(
                                opacity: opacity,
                                size: pixelSize,
                                color: color,
                                shadowRadius: size / 6
                            )
                        }
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }

    /// Derive the animation step from wall-clock time so all loaders stay in sync.
    private static func step(for date: Date) -> Int {
        let interval = date.timeIntervalSinceReferenceDate
        return Int(interval * 10) % path.count
    }

    /// Compute opacity for each cell based on trail position.
    private static func cellOpacities(step: Int) -> [Int: Double] {
        let pathLen = path.count
        guard pathLen > 0 else { return [:] }

        let headIndex = step % pathLen
        var map: [Int: Double] = [:]

        for (offset, opacity) in trailOpacities.enumerated() {
            let pathIndex = (headIndex - offset + pathLen) % pathLen
            let cell = path[pathIndex]
            if map[cell] == nil {
                map[cell] = opacity
            }
        }
        return map
    }
}

// MARK: - PixelCell

private struct PixelCell: View {
    let opacity: Double
    let size: CGFloat
    let color: Color
    let shadowRadius: CGFloat

    private var isOn: Bool { opacity > 0 }

    var body: some View {
        Rectangle()
            .foregroundStyle(isOn ? color.opacity(opacity) : .clear)
            .frame(width: size, height: size)
            .shadow(
                color: isOn ? color.opacity(opacity * 0.9) : .clear,
                radius: shadowRadius,
                x: 0,
                y: 0
            )
    }
}

// MARK: - Factory Methods

extension PixelLoader {
    /// The unified standard loader used everywhere in the app.
    ///
    /// - Parameter size: Total size of the loader (default 60pt)
    /// - Returns: A configured PixelLoader with trailing snake animation
    static func standard(size: CGFloat = 60) -> PixelLoader {
        PixelLoader(size: size)
    }

    /// Compact variant for small badges/indicators.
    /// Same appearance as standard(), just smaller.
    static func compact(size: CGFloat = 24) -> PixelLoader {
        PixelLoader(size: size)
    }

    /// Returns a new PixelLoader with the specified color.
    /// - Parameter color: The color to use for the pixels
    /// - Returns: A new PixelLoader instance with the updated color
    func color(_ newColor: Color) -> some View {
        PixelLoader(size: size, color: newColor)
            .id("pixel-loader-\(size)-\(newColor.hashValue)")
    }
}

// MARK: - Previews

#Preview("Standard - Light") {
    PixelLoader.standard(size: 80)
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("Standard - Dark") {
    PixelLoader.standard(size: 80)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Compact") {
    PixelLoader.compact(size: 24)
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("Custom Color") {
    PixelLoader.standard(size: 60)
        .color(.red)
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("Multiple Colors") {
    HStack(spacing: 20) {
        PixelLoader.standard(size: 40)
            .color(.accentColor)
        PixelLoader.standard(size: 40)
            .color(.red)
        PixelLoader.standard(size: 40)
            .color(.green)
        PixelLoader.standard(size: 40)
            .color(.white)
    }
    .padding()
    .background(Color.black)
}
