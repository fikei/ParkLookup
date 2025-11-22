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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                // Zone Letter (very large, centered)
                Text(zoneCode)
                    .font(.system(size: 180, weight: .bold))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Zone \(zoneCode)")

                Spacer()

                // Validity Badge (at bottom)
                ValidityBadgeView(
                    status: validityStatus,
                    permits: applicablePermits
                )
                .padding(.bottom, 24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: UIScreen.main.bounds.height * 0.85)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            ZoneStatusCardView(
                zoneName: "Area Q",
                validityStatus: .valid,
                applicablePermits: [
                    ParkingPermit(type: .residential, area: "Q")
                ]
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
