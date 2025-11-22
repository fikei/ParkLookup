import SwiftUI

/// Displays the zone name and permit validity status prominently
struct ZoneStatusCardView: View {
    let zoneName: String
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]

    /// Extract just the zone letter/code (removes "Area " prefix)
    private var zoneCode: String {
        if zoneName.hasPrefix("Area ") {
            return String(zoneName.dropFirst(5))
        }
        return zoneName
    }

    /// Whether the card should use the "valid" green style
    private var isValidStyle: Bool {
        validityStatus == .valid || validityStatus == .multipleApply
    }

    /// Background color based on validity
    private var cardBackground: Color {
        isValidStyle ? Color.green : Color(.systemBackground)
    }

    /// Text color based on validity (white on green, primary otherwise)
    private var textColor: Color {
        isValidStyle ? .white : .primary
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                // Zone Letter (very large, centered)
                Text(zoneCode)
                    .font(.system(size: 180, weight: .bold))
                    .foregroundColor(textColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Zone \(zoneCode)")

                Spacer()

                // Validity Badge (at bottom)
                ValidityBadgeView(
                    status: validityStatus,
                    permits: applicablePermits,
                    onColoredBackground: isValidStyle
                )
                .padding(.bottom, 24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: UIScreen.main.bounds.height * 0.85)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Preview

#Preview("Valid Permit") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Area Q",
            validityStatus: .valid,
            applicablePermits: [
                ParkingPermit(type: .residential, area: "Q")
            ]
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Invalid Permit") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Area R",
            validityStatus: .invalid,
            applicablePermits: []
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Conditional") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Area U",
            validityStatus: .conditional,
            applicablePermits: []
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
