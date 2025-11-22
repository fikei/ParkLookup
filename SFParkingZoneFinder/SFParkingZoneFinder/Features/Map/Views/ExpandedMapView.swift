import SwiftUI
import MapKit
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ExpandedMapView")

// MARK: - Expanded Map View

struct ExpandedMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let zoneName: String?
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let zones: [ParkingZone]
    let currentZoneId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedZone: ParkingZone?

    init(
        coordinate: CLLocationCoordinate2D?,
        zoneName: String?,
        validityStatus: PermitValidityStatus = .noPermitRequired,
        applicablePermits: [ParkingPermit] = [],
        zones: [ParkingZone] = [],
        currentZoneId: String? = nil
    ) {
        self.coordinate = coordinate
        self.zoneName = zoneName
        self.validityStatus = validityStatus
        self.applicablePermits = applicablePermits
        self.zones = zones
        self.currentZoneId = currentZoneId

        let totalBoundaries = zones.reduce(0) { $0 + $1.boundaries.count }
        let totalPoints = zones.reduce(0) { $0 + $1.boundaries.reduce(0) { $0 + $1.count } }
        logger.info("ExpandedMapView init - zones: \(zones.count), boundaries: \(totalBoundaries), points: \(totalPoints)")
    }

    /// Extract permit area code from zone name (e.g., "Area Q" -> "Q")
    private var currentPermitArea: String? {
        guard let zoneName = zoneName, zoneName.hasPrefix("Area ") else {
            return zoneName
        }
        return String(zoneName.dropFirst(5))
    }

    var body: some View {
        let _ = logger.debug("ExpandedMapView body evaluated - zones: \(zones.count)")

        NavigationView {
            ZStack {
                // Zone map with polygons
                ZoneMapView(
                    zones: zones,
                    currentZoneId: currentZoneId,
                    userCoordinate: coordinate,
                    onZoneTapped: { zone in
                        selectedZone = zone
                    }
                )
                .ignoresSafeArea()

                // Zone info overlay
                VStack {
                    // Current zone card at top
                    MiniZoneCard(
                        zoneName: zoneName,
                        zoneCode: currentPermitArea,
                        validityStatus: validityStatus,
                        applicablePermits: applicablePermits
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()

                    // Tapped zone info card at bottom
                    if let selected = selectedZone {
                        TappedZoneCard(zone: selected) {
                            selectedZone = nil
                        }
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedZone?.id)
            }
            .navigationTitle("Zone Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tapped Zone Card

private struct TappedZoneCard: View {
    let zone: ParkingZone
    let onDismiss: () -> Void

    private var zoneCode: String {
        zone.permitArea ?? zone.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with dismiss button
            HStack {
                HStack(spacing: 12) {
                    // Zone circle with color
                    ZStack {
                        Circle()
                            .fill(ZoneColorProvider.swiftUIColor(for: zone.permitArea))
                            .frame(width: 44, height: 44)

                        Text(zoneCode)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(zone.displayName)
                            .font(.headline)
                        Text(zone.zoneType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            // Rules summary
            if let ruleDesc = zone.primaryRuleDescription {
                Text(ruleDesc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Enforcement hours
            if let hours = zone.enforcementHours {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(hours)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Mini Zone Card (matches main ZoneStatusCardView style)

private struct MiniZoneCard: View {
    let zoneName: String?
    let zoneCode: String?
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]

    /// Whether to use the "valid" green style
    private var isValidStyle: Bool {
        validityStatus == .valid || validityStatus == .multipleApply
    }

    /// Card background color based on validity
    private var cardBackground: Color {
        isValidStyle ? Color.green : Color(.systemBackground)
    }

    /// Circle background color - uses zone color
    private var circleBackground: Color {
        ZoneColorProvider.swiftUIColor(for: zoneCode)
    }

    /// Text color for zone letter - white on zone color background
    private var letterColor: Color {
        .white
    }

    var body: some View {
        HStack(spacing: 16) {
            zoneCircle
            zoneInfo
            Spacer()
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    private var zoneCircle: some View {
        ZStack {
            Circle()
                .fill(circleBackground)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(zoneCode ?? "?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(letterColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private var zoneInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(zoneName ?? "Unknown Zone")
                .font(.headline)
                .foregroundColor(isValidStyle ? .white : .primary)

            // Validity badge inline
            HStack(spacing: 6) {
                Image(systemName: validityStatus.iconName)
                    .font(.caption)
                Text(validityStatus.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isValidStyle ? .white.opacity(0.9) : Color.forValidityStatus(validityStatus))
        }
    }
}

// MARK: - Preview

#Preview {
    ExpandedMapView(
        coordinate: CLLocationCoordinate2D(latitude: 37.7585, longitude: -122.4233),
        zoneName: "Area Q",
        validityStatus: .valid,
        zones: []
    )
}
