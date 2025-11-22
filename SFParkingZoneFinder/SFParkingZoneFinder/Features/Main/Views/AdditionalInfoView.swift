import SwiftUI

/// Shows address, last updated time, and action buttons
struct AdditionalInfoView: View {
    let address: String
    let lastUpdated: Date?
    let confidence: LookupConfidence
    let onRefresh: () -> Void
    let onReportIssue: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Address row
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                Text(address)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer()

                // Confidence indicator
                if confidence != .high {
                    ConfidenceIndicator(confidence: confidence)
                }
            }

            // Last updated
            if let lastUpdated = lastUpdated {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text("Updated \(lastUpdated.relativeTimeString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                // Refresh button
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)

                Spacer()

                // Report issue button
                Button(action: onReportIssue) {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Settings button
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Confidence Indicator

struct ConfidenceIndicator: View {
    let confidence: LookupConfidence

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
            Text(confidence.displayText)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private var iconName: String {
        switch confidence {
        case .high: return "checkmark.circle.fill"
        case .medium: return "questionmark.circle"
        case .low: return "exclamationmark.triangle"
        case .outsideCoverage: return "xmark.circle"
        }
    }

    private var color: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        case .outsideCoverage: return .gray
        }
    }
}

// MARK: - Date Extension

extension Date {
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AdditionalInfoView(
            address: "123 Main St, San Francisco",
            lastUpdated: Date().addingTimeInterval(-120),
            confidence: .high,
            onRefresh: {},
            onReportIssue: {},
            onSettings: {}
        )

        AdditionalInfoView(
            address: "Near Market & 5th",
            lastUpdated: Date().addingTimeInterval(-3600),
            confidence: .medium,
            onRefresh: {},
            onReportIssue: {},
            onSettings: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
