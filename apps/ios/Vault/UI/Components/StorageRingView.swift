import SwiftUI

struct StorageRingView: View {
    let fileCount: Int
    let maxFiles: Int?
    let totalBytes: Int64

    @State private var showingDetail = false

    private var progress: Double {
        guard let max = maxFiles, max > 0 else {
            return min(Double(fileCount) / 200.0, 1.0)
        }
        return min(Double(fileCount) / Double(max), 1.0)
    }

    private var ringColor: Color {
        progress >= 0.8 ? .vaultHighlight : .accentColor
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(fileCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fileCount) files, \(formattedBytes) used")
        .popover(isPresented: $showingDetail) {
            VStack(spacing: 8) {
                Text("\(fileCount) files")
                    .font(.headline)
                Text("\(formattedBytes) used")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let max = maxFiles {
                    Text("\(fileCount) of \(max) file limit")
                        .font(.caption)
                        .foregroundStyle(.vaultSecondaryText)
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
