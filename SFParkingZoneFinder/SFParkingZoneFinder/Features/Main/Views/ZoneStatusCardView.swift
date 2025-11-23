import SwiftUI

/// Displays the zone name and permit validity status prominently
struct ZoneStatusCardView: View {
    let zoneName: String
    let zoneType: ZoneType
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let allValidPermitAreas: [String]  // All valid permits from overlapping zones
    let meteredSubtitle: String?  // For metered zones: "$2/hr • 2hr max"

    @State private var animationIndex: Int = 0
    private let animationTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

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

    /// Permit areas ordered with user's permit first
    private var orderedPermitAreas: [String] {
        guard isMultiPermitLocation else {
            return allValidPermitAreas.isEmpty ? [singleZoneCode] : allValidPermitAreas
        }
        var areas = allValidPermitAreas
        // Move user's permit to front if they have one
        if let userPermitArea = applicablePermits.first?.area,
           let index = areas.firstIndex(of: userPermitArea) {
            areas.remove(at: index)
            areas.insert(userPermitArea, at: 0)
        }
        return areas
    }

    /// Single zone code for non-multi-permit locations
    private var singleZoneCode: String {
        if isMeteredZone {
            return "$"
        }
        if zoneName.hasPrefix("Area ") {
            return String(zoneName.dropFirst(5))
        }
        if zoneName.hasPrefix("Zone ") {
            return String(zoneName.dropFirst(5))
        }
        return zoneName
    }

    /// Display name shown below the zone code
    private var displaySubtitle: String? {
        if isMeteredZone {
            // Show hourly cost & max time for metered zones
            return meteredSubtitle ?? "$2/hr • 2hr max"
        }
        if isMultiPermitLocation {
            return "Tap to cycle • Valid: \(allValidPermitAreas.joined(separator: ", "))"
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
                if isMultiPermitLocation {
                    // Multi-permit: overlapping circles with animation
                    LargeMultiPermitCircleView(
                        permitAreas: orderedPermitAreas,
                        animationIndex: animationIndex,
                        size: 160
                    )
                    .onReceive(animationTimer) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            animationIndex = (animationIndex + 1) % orderedPermitAreas.count
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            animationIndex = (animationIndex + 1) % orderedPermitAreas.count
                        }
                    }
                } else {
                    // Single zone circle
                    ZStack {
                        Circle()
                            .fill(circleBackground)
                            .frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                        Text(singleZoneCode)
                            .font(.system(size: 120, weight: .bold))
                            .foregroundColor(letterColor)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                }

                // Subtitle for metered zones or multi-permit
                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundColor(isValidStyle ? .white.opacity(0.9) : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(isMeteredZone ? "Paid parking zone at \(displaySubtitle ?? "this location")" : "Zone \(singleZoneCode)")

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

// MARK: - Large Multi-Permit Circle View

/// Displays large overlapping circles for multi-permit zones with animation
private struct LargeMultiPermitCircleView: View {
    let permitAreas: [String]
    let animationIndex: Int
    let size: CGFloat

    /// Offset between circles for overlap effect
    private var offset: CGFloat {
        size * 0.35
    }

    /// Total width needed for overlapping circles
    private var totalWidth: CGFloat {
        size + (CGFloat(permitAreas.count - 1) * offset)
    }

    /// Reorder permit areas to put the current animated one on top
    private var reorderedAreas: [(area: String, index: Int)] {
        var areas = permitAreas.enumerated().map { (area: $1, index: $0) }
        // Move the animated index to the end so it renders on top
        if let animatedItem = areas.first(where: { $0.index == animationIndex }) {
            areas.removeAll { $0.index == animationIndex }
            areas.append(animatedItem)
        }
        return areas
    }

    var body: some View {
        ZStack(alignment: .center) {
            ForEach(reorderedAreas, id: \.index) { item in
                let isActive = item.index == animationIndex
                let xOffset = CGFloat(item.index) * offset - (totalWidth - size) / 2

                ZStack {
                    Circle()
                        .fill(ZoneColorProvider.swiftUIColor(for: item.area))
                        .frame(width: size, height: size)
                        .shadow(color: isActive ? .black.opacity(0.3) : .black.opacity(0.15),
                                radius: isActive ? 8 : 4,
                                x: 0, y: isActive ? 4 : 2)

                    Text(item.area)
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
                .offset(x: xOffset)
                .scaleEffect(isActive ? 1.15 : 1.0)
                .zIndex(isActive ? 1 : 0)
            }
        }
        .frame(width: totalWidth, height: size * 1.2)
    }
}

// MARK: - Preview

#Preview("Valid Permit") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Zone Q",
            zoneType: .residentialPermit,
            validityStatus: .valid,
            applicablePermits: [
                ParkingPermit(type: .residential, area: "Q")
            ],
            allValidPermitAreas: ["Q"],
            meteredSubtitle: nil
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Invalid Permit") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Zone R",
            zoneType: .residentialPermit,
            validityStatus: .invalid,
            applicablePermits: [],
            allValidPermitAreas: ["R"],
            meteredSubtitle: nil
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Multi-Permit Zone") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Zone A",
            zoneType: .residentialPermit,
            validityStatus: .valid,
            applicablePermits: [
                ParkingPermit(type: .residential, area: "A")
            ],
            allValidPermitAreas: ["A", "B"],
            meteredSubtitle: nil
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Conditional") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Zone U",
            zoneType: .residentialPermit,
            validityStatus: .conditional,
            applicablePermits: [],
            allValidPermitAreas: ["U"],
            meteredSubtitle: nil
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Paid Parking") {
    ScrollView {
        ZoneStatusCardView(
            zoneName: "Paid Parking",
            zoneType: .metered,
            validityStatus: .noPermitRequired,
            applicablePermits: [],
            allValidPermitAreas: [],
            meteredSubtitle: "$3/hr • 2hr max"
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
