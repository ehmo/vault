import SwiftUI
import Combine

// MARK: - PixelLoader

/// Unified pixel loader with trailing snake animation.
/// 
/// Features:
/// - Left-to-right snake pattern (row-major: 1→2→3→4→5→6→7→8→9)
/// - Explicit trailing cells with decreasing opacity (head + 2 trailing)
/// - Stronger colors for better visibility in both light and dark modes
/// - Single unified appearance across the entire app
///
/// The animation creates a "snake" effect where the head pixel is brightest,
/// followed by 2 trailing pixels at 66% and 33% opacity.
struct PixelLoader: View {
    var size: CGFloat = 60
    var color: Color = .accentColor

    // Animation state
    @State private var step: Int = 0

    // Row-major order: left to right, top to bottom
    private static let path = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    // Trail opacities: head + 2 trailing cells
    private static let trailOpacities: [Double] = [1.0, 0.66, 0.33]

    // Timer for animation
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let opacityMap = cellOpacities()
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
                            color: effectiveColor,
                            shadowRadius: size / 6
                        )
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .onReceive(timer) { _ in
            withAnimation(.smooth(duration: 0.25)) {
                step = (step + 1) % Self.path.count
            }
        }
    }

    /// Compute opacity for each cell based on trail position.
    private func cellOpacities() -> [Int: Double] {
        let pathLen = Self.path.count
        let headIndex = step % pathLen
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

    /// Enhanced color for better visibility in dark mode.
    private var effectiveColor: Color {
        guard colorScheme == .dark else { return color }
        // Lighten more aggressively for better visibility in dark mode
        return Color(UIColor(color).lighter(by: 0.45))
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
        // Stack multiple rectangles for stronger glow
        ZStack {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle()
                    .foregroundStyle(isOn ? color.opacity(opacity) : .clear)
                    .frame(width: size, height: size)
            }
        }
        // Shadow overlay for glow effect
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
}

// MARK: - UIColor Helper

private extension UIColor {
    func lighter(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(
            hue: h,
            saturation: max(s * (1 - amount), 0),
            brightness: min(b + amount, 1.0),
            alpha: a
        )
    }
}

// MARK: - Previews

#Preview("Standard - Light") {
    PixelLoader.standard(size: 80)
        .padding()
        .background(Color.vaultBackground)
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
        .background(Color.vaultBackground)
}
