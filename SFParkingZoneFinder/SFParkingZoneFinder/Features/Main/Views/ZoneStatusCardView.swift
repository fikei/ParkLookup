import SwiftUI

/// Displays the zone name and permit validity status prominently
struct ZoneStatusCardView: View {
    let zoneName: String
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]

    /// Responsive card height based on screen size
    /// Calculated to show: zone card + map card (120pt) + rules header peek (~20pt)
    private var cardHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let safeAreaTop: CGFloat = 59  // Approximate for notch devices
        let safeAreaBottom: CGFloat = 34
        let padding: CGFloat = 32  // 16pt top + 16pt horizontal padding
        let mapCardHeight: CGFloat = 120
        let rulesHeaderPeek: CGFloat = 20  // Minimal peek of rules card
        let spacing: CGFloat = 32  // spacing between cards

        let availableHeight = screenHeight - safeAreaTop - safeAreaBottom - padding - mapCardHeight - rulesHeaderPeek - spacing
        // Clamp between reasonable min/max values
        return min(max(availableHeight, 300), 520)
    }

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

    /// Circle background color (system background on green, or status color otherwise)
    private var circleBackground: Color {
        isValidStyle ? Color(.systemBackground) : Color.forValidityStatus(validityStatus).opacity(0.15)
    }

    /// Text color for zone letter
    private var letterColor: Color {
        Color.forValidityStatus(validityStatus)
    }

    var body: some View {
        ZStack {
            // Zone Letter in Circle (truly centered)
            ZStack {
                Circle()
                    .fill(circleBackground)
                    .frame(width: 200, height: 200)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                Text(zoneCode)
                    .font(.system(size: 120, weight: .bold))
                    .foregroundColor(letterColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Zone \(zoneCode)")

            // Validity Badge (positioned at bottom)
            VStack {
                Spacer()
                ValidityBadgeView(
                    status: validityStatus,
                    permits: applicablePermits,
                    onColoredBackground: isValidStyle
                )
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
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
