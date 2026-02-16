import SwiftUI

/// Shared validation feedback view for pattern creation screens.
/// Displays errors (red, blocking), warnings (yellow, informational),
/// and pattern complexity/strength score.
///
/// Used by: PatternSetupView, ChangePatternView, JoinVaultView, SharedVaultInviteView
struct PatternValidationFeedbackView: View {
    let result: PatternValidationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Errors
            ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.vaultHighlight)
                    Text(error.message)
                        .font(.caption)
                }
            }

            // Warnings and complexity score (only if no errors)
            if result.errors.isEmpty {
                ForEach(Array(result.warnings.prefix(2).enumerated()), id: \.offset) { _, warning in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.vaultHighlight)
                        Text(warning.rawValue)
                            .font(.caption)
                    }
                }

                // Complexity score
                let description = PatternValidator.shared.complexityDescription(for: result.metrics.complexityScore)
                HStack {
                    Image(systemName: "shield.fill")
                        .foregroundStyle(result.metrics.complexityScore >= 30 ? .green : .orange)
                    Text("Strength: \(description)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .vaultGlassBackground(cornerRadius: 12)
    }
}
