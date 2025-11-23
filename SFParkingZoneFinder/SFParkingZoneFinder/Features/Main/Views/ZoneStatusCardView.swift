import SwiftUI

/// Displays the zone name and permit validity status prominently
struct ZoneStatusCardView: View {
    let zoneName: String
    let zoneType: ZoneType
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let allValidPermitAreas: [String]  // All valid permits from overlapping zones

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

    /// Whether this is a metered/paid parking zone
    private var isMeteredZone: Bool {
        zoneType == .metered
    }

    /// Whether this is a multi-permit location (overlapping RPP zones)
    private var isMultiPermitLocation: Bool {
        allValidPermitAreas.count > 1
    }

    /// Extract just the zone letter/code (removes "Area " prefix)
    /// For metered zones, returns "$" symbol
    /// For multi-permit locations, returns combined codes like "A/B"
    private var zoneCode: String {
        if isMeteredZone {
            return "$"
        }
        // Show combined permit codes for multi-permit locations
        if isMultiPermitLocation {
            return allValidPermitAreas.joined(separator: "/")
        }
        if zoneName.hasPrefix("Area ") {
            return String(zoneName.dropFirst(5))
        }
        return zoneName
    }

    /// Display name shown below the zone code
    private var displaySubtitle: String? {
        if isMeteredZone {
            // For metered zones, show the street name from "Metered - Market St"
            if zoneName.hasPrefix("Metered - ") {
                return String(zoneName.dropFirst(10))
            }
            return "Paid Parking"
        }
        if isMultiPermitLocation {
            return "Multi-permit area"
        }
        return nil
    }

    /// Whether the card should use the "valid" green style
    private var isValidStyle: Bool {
        validityStatus == .valid || validityStatus == .multipleApply
    }

    /// Background color based on validity and zone type
    private var cardBackground: Color {
        if isMeteredZone {
            return Color(.systemBackground)  // Neutral background for metered zones
        }
        return isValidStyle ? Color.green : Color(.systemBackground)
    }

    /// Circle background color (system background on green, or status color otherwise)
    private var circleBackground: Color {
        if isMeteredZone {
            return Color.forZoneType(.metered).opacity(0.15)  // Green-tinted for metered
        }
        return isValidStyle ? Color(.systemBackground) : Color.forValidityStatus(validityStatus).opacity(0.15)
    }

    /// Text color for zone letter
    private var letterColor: Color {
        if isMeteredZone {
            return Color.forZoneType(.metered)  // Green for metered zones
        }
        return Color.forValidityStatus(validityStatus)
    }

    var body: some View {
        ZStack {
            // Zone Letter in Circle (truly centered)
            VStack(spacing: 8) {
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

                // Subtitle for metered zones (street name)
                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(isMeteredZone ? "Paid parking zone at \(displaySubtitle ?? "this location")" : "Zone \(zoneCode)")

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
            zoneType: .residentialPermit,
            validityStatus: .valid,
            applicablePermits: [
                ParkingPermit(type: .residential, area: "Q")
            ],
            allValidPermitAreas: ["Q"]
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Invalid Permit") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Area R",
            zoneType: .residentialPermit,
            validityStatus: .invalid,
            applicablePermits: [],
            allValidPermitAreas: ["R"]
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Multi-Permit Area") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Area A",
            zoneType: .residentialPermit,
            validityStatus: .valid,
            applicablePermits: [
                ParkingPermit(type: .residential, area: "A")
            ],
            allValidPermitAreas: ["A", "B"]
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Conditional") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Area U",
            zoneType: .residentialPermit,
            validityStatus: .conditional,
            applicablePermits: [],
            allValidPermitAreas: ["U"]
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Metered Zone") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Metered - Market St",
            zoneType: .metered,
            validityStatus: .noPermitRequired,
            applicablePermits: [],
            allValidPermitAreas: []
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
