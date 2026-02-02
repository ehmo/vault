import ActivityKit
import SwiftUI
import WidgetKit

/// App accent color hardcoded for widget extension (no access to main app's asset catalog).
private let vaultAccent = Color(red: 0.384, green: 0.275, blue: 0.918)

struct TransferLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransferActivityAttributes.self) { context in
            // Lock Screen / banner view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    LivePixelGrid(
                        transferType: context.attributes.transferType,
                        animationStep: context.state.animationStep,
                        size: 36,
                        pixelSize: 8,
                        spacing: 2
                    )
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
                        progressText(context: context)
                            .font(.title3.monospacedDigit())
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
                LivePixelGrid(
                    transferType: context.attributes.transferType,
                    animationStep: context.state.animationStep,
                    size: 20,
                    pixelSize: 4.5,
                    spacing: 1
                )
            } compactTrailing: {
                if context.state.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if context.state.isFailed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                } else if context.state.total > 0 {
                    Text("\(context.state.progress)%")
                        .foregroundStyle(.white)
                        .font(.caption2.monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.default, value: context.state.progress)
                } else {
                    Text("...")
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                LivePixelGrid(
                    transferType: context.attributes.transferType,
                    animationStep: context.state.animationStep,
                    size: 16,
                    pixelSize: 3.5,
                    spacing: 0.5
                )
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TransferActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            LivePixelGrid(
                transferType: context.attributes.transferType,
                animationStep: context.state.animationStep,
                size: 36,
                pixelSize: 8,
                spacing: 2
            )

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
}
