import ActivityKit
import SwiftUI
import WidgetKit

/// App accent color hardcoded for widget extension (no access to main app's asset catalog).
private let vaultAccent = Color(red: 0.384, green: 0.275, blue: 0.918)
private let livePixelTickInterval: TimeInterval = 0.1

struct TransferLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransferActivityAttributes.self) { context in
            // Lock Screen / banner view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    animatedPixelGrid(size: 36, pixelSize: 8, spacing: 2)
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    } else if context.state.isFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            if context.state.activeUploadCount > 1 {
                                Text("\(context.state.activeUploadCount) uploads")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            progressText(context: context)
                                .font(.title3.monospacedDigit())
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(context.state.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !context.state.isComplete && !context.state.isFailed && context.state.total > 0 {
                            ProgressView(
                                value: Double(context.state.progress),
                                total: Double(context.state.total)
                            )
                            .tint(vaultAccent)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                animatedPixelGrid(size: 20, pixelSize: 4.5, spacing: 1)
            } compactTrailing: {
                if context.state.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if context.state.isFailed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                } else if context.state.total > 0 {
                    if context.state.activeUploadCount > 1 {
                        Text("\(context.state.activeUploadCount)x \(context.state.progress)%")
                            .foregroundStyle(.white)
                            .font(.caption2.monospacedDigit())
                    } else {
                        Text("\(context.state.progress)%")
                            .foregroundStyle(.white)
                            .font(.caption2.monospacedDigit())
                            .contentTransition(.numericText())
                            .animation(.default, value: context.state.progress)
                    }
                } else {
                    Text("...")
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                animatedPixelGrid(size: 16, pixelSize: 3.5, spacing: 0.5)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TransferActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            animatedPixelGrid(size: 36, pixelSize: 8, spacing: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                if context.state.isComplete {
                    Text("Complete")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if context.state.isFailed {
                    Text("Failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if context.state.total > 0 {
                    ProgressView(
                        value: Double(context.state.progress),
                        total: Double(context.state.total)
                    )
                    .tint(vaultAccent)

                    if context.state.activeUploadCount > 1 {
                        Text("\(context.state.activeUploadCount) uploads running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !context.state.isComplete && !context.state.isFailed {
                progressText(context: context)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.8))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func progressText(context: ActivityViewContext<TransferActivityAttributes>) -> some View {
        if context.state.total > 0 {
            Text("\(context.state.progress)%")
                .contentTransition(.numericText())
                .animation(.default, value: context.state.progress)
        } else {
            ProgressView()
        }
    }

    /// Keep the loader animating continuously even when ActivityKit coalesces
    /// ContentState updates while progress is unchanged.
    @ViewBuilder
    private func animatedPixelGrid(size: CGFloat, pixelSize: CGFloat, spacing: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: livePixelTickInterval, paused: false)) { timeline in
            let timelineStep = Int(
                (timeline.date.timeIntervalSinceReferenceDate / livePixelTickInterval)
                    .rounded(.down)
            )
            LivePixelGrid(
                animationStep: timelineStep,
                size: size,
                pixelSize: pixelSize,
                spacing: spacing
            )
        }
    }
}
