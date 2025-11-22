import SwiftUI

/// Displays parking rules as bullet points with expandable full rules
struct RulesSummaryView: View {
    let summaryLines: [String]
    let warnings: [ParkingWarning]
    let onViewFullRules: () -> Void

    @State private var showFullRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Parking Rules")
                .font(.headline)
                .foregroundColor(.primary)

            // Warnings (if any)
            ForEach(warnings) { warning in
                WarningBanner(warning: warning)
            }

            // Rules as bullet points
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(summaryLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(line)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.body)
                }
            }

            // View full rules button
            Button(action: onViewFullRules) {
                HStack {
                    Text("View Full Rules")
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Warning Banner

struct WarningBanner: View {
    let warning: ParkingWarning

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.body)

            Text(warning.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(textColor)

            Spacer()
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(8)
    }

    private var iconName: String {
        switch warning.severity {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch warning.severity {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    private var textColor: Color {
        switch warning.severity {
        case .high: return .red
        case .medium: return .orange
        case .low: return .primary
        }
    }

    private var backgroundColor: Color {
        switch warning.severity {
        case .high: return .red.opacity(0.1)
        case .medium: return .orange.opacity(0.1)
        case .low: return .blue.opacity(0.1)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        RulesSummaryView(
            summaryLines: [
                "Residential Permit Area Q only",
                "2-hour limit for non-permit holders",
                "Enforced Mon-Sat, 8 AM - 6 PM"
            ],
            warnings: [
                ParkingWarning(
                    type: .streetCleaning,
                    message: "Street cleaning in effect!",
                    severity: .high
                )
            ],
            onViewFullRules: {}
        )

        RulesSummaryView(
            summaryLines: [
                "Metered parking - $3.00/hour",
                "2-hour max",
                "Free on Sundays"
            ],
            warnings: [],
            onViewFullRules: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
