import SwiftUI

/// Displays the zone name and permit validity status prominently
struct ZoneStatusCardView: View {
    let zoneName: String
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]

    var body: some View {
        VStack(spacing: 16) {
            // Zone Name (large, prominent)
            Text(zoneName)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)

            // Validity Badge
            ValidityBadgeView(
                status: validityStatus,
                permits: applicablePermits
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ZoneStatusCardView(
            zoneName: "Area Q",
            validityStatus: .valid,
            applicablePermits: [
                ParkingPermit(type: .residential, area: "Q")
            ]
        )

        ZoneStatusCardView(
            zoneName: "Area R",
            validityStatus: .invalid,
            applicablePermits: []
        )

        ZoneStatusCardView(
            zoneName: "Downtown Metered",
            validityStatus: .noPermitRequired,
            applicablePermits: []
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
