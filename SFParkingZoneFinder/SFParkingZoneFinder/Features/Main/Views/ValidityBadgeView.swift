import SwiftUI

/// Color-coded badge showing permit validity status
/// Uses shapes + text for color-blind accessibility
struct ValidityBadgeView: View {
    let status: PermitValidityStatus
    let permits: [ParkingPermit]
    /// When true, uses white styling for display on colored backgrounds
    var onColoredBackground: Bool = false
    /// Time limit in minutes for non-permit holders (for "Park until" display)
    var timeLimitMinutes: Int? = nil

    /// Calculate "Park until" time based on current time + time limit
    /// Shows for both .invalid (wrong permit) and .noPermitSet (no permit configured)
    private var parkUntilText: String? {
        guard (status == .invalid || status == .noPermitSet), let limit = timeLimitMinutes else { return nil }

        let parkUntil = Date().addingTimeInterval(TimeInterval(limit * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "PARK UNTIL \(formatter.string(from: parkUntil))"
    }

    /// Display text - shows "Park until" for invalid status when time limit available
    private var displayText: String {
        if let parkUntil = parkUntilText {
            return parkUntil
        }
        return status.displayText
    }

    var body: some View {
        HStack(spacing: 12) {
            // Shape indicator (accessibility: not color-only)
            // Show clock icon when displaying "Park until" time
            Image(systemName: parkUntilText != nil ? "clock" : status.iconName)
                .font(.system(size: 20, weight: .semibold))

            // Text
            Text(displayText)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(badgeBackground)
        .foregroundColor(badgeForeground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeBorder, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Badge Colors

    private var badgeBackground: Color {
        if onColoredBackground {
            // White semi-transparent background on green card
            return Color.white.opacity(0.25)
        }
        return statusColor.opacity(0.15)
    }

    private var badgeForeground: Color {
        if onColoredBackground {
            return .white
        }
        return statusColor
    }

    private var badgeBorder: Color {
        if onColoredBackground {
            return Color.white.opacity(0.5)
        }
        return statusColor
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        Color.forValidityStatus(status)
    }

    private var accessibilityText: String {
        switch status {
        case .valid:
            let permitAreas = permits.map { $0.area }.joined(separator: ", ")
            return "Permit status: Valid. Your Area \(permitAreas) permit is valid at this location."
        case .invalid:
            return "Permit status: Not valid. Your permit is not valid at this location."
        case .conditional:
            return "Permit status: Conditional. Check the rules below for restrictions."
        case .noPermitRequired:
            return "No permit required. Anyone can park here within posted limits."
        case .multipleApply:
            let permitAreas = permits.map { $0.area }.joined(separator: ", ")
            return "Multiple permits valid. Your permits for Areas \(permitAreas) are all valid here."
        case .noPermitSet:
            return "Permit required. Add a permit in settings to check validity."
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ValidityBadgeView(status: .valid, permits: [
            ParkingPermit(type: .residential, area: "Q")
        ])

        ValidityBadgeView(status: .invalid, permits: [])

        ValidityBadgeView(status: .conditional, permits: [])

        ValidityBadgeView(status: .noPermitRequired, permits: [])

        ValidityBadgeView(status: .multipleApply, permits: [
            ParkingPermit(type: .residential, area: "Q"),
            ParkingPermit(type: .residential, area: "R")
        ])
    }
    .padding()
}
