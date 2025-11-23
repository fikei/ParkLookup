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
    let allValidPermitAreas: [String]  // All valid permits in current location
    let zones: [ParkingZone]
    let currentZoneId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedZone: ParkingZone?

    init(
        coordinate: CLLocationCoordinate2D?,
        zoneName: String?,
        validityStatus: PermitValidityStatus = .noPermitRequired,
        applicablePermits: [ParkingPermit] = [],
        allValidPermitAreas: [String] = [],
        zones: [ParkingZone] = [],
        currentZoneId: String? = nil
    ) {
        self.coordinate = coordinate
        self.zoneName = zoneName
        self.validityStatus = validityStatus
        self.applicablePermits = applicablePermits
        self.allValidPermitAreas = allValidPermitAreas
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
                        applicablePermits: applicablePermits,
                        allValidPermitAreas: allValidPermitAreas
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

    @State private var animationIndex: Int = 0

    private var zoneCode: String {
        zone.permitArea ?? zone.displayName
    }

    /// Whether this zone accepts multiple permits
    private var isMultiPermitZone: Bool {
        zone.validPermitAreas.count > 1 && zone.zoneType == .residentialPermit
    }

    /// All valid permit areas for multi-permit zones
    private var allPermitAreas: [String] {
        zone.validPermitAreas.isEmpty ? [zone.permitArea ?? zoneCode] : zone.validPermitAreas
    }

    /// Combined zone code for multi-permit (e.g., "A/B")
    private var combinedZoneCode: String {
        if isMultiPermitZone {
            return allPermitAreas.joined(separator: "/")
        }
        return zoneCode
    }

    /// Currently highlighted area for multi-permit zones
    private var currentSelectedArea: String {
        guard isMultiPermitZone, animationIndex < allPermitAreas.count else {
            return zoneCode
        }
        return allPermitAreas[animationIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with dismiss button
            HStack {
                HStack(spacing: 12) {
                    // Zone circle(s) - overlapping for multi-permit
                    if isMultiPermitZone {
                        MultiPermitCircleView(
                            permitAreas: allPermitAreas,
                            animationIndex: animationIndex,
                            size: 44
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                animationIndex = (animationIndex + 1) % allPermitAreas.count
                            }
                        }
                    } else {
                        // Single zone circle
                        ZStack {
                            Circle()
                                .fill(ZoneColorProvider.swiftUIColor(for: zone.permitArea))
                                .frame(width: 44, height: 44)

                            Text(zoneCode)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if isMultiPermitZone {
                            // Show currently selected area
                            Text("Zone \(currentSelectedArea)")
                                .font(.headline)
                                .animation(.easeInOut(duration: 0.2), value: animationIndex)
                            Text("Multi Permit Zone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(zone.displayName)
                                .font(.headline)
                            Text(zone.zoneType.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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

// MARK: - Multi-Permit Circle View

/// Displays overlapping circles for multi-permit zones with animation
private struct MultiPermitCircleView: View {
    let permitAreas: [String]
    let animationIndex: Int
    let size: CGFloat

    /// Offset between circles for overlap effect
    private var offset: CGFloat {
        size * 0.25
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
        ZStack(alignment: .leading) {
            ForEach(reorderedAreas, id: \.index) { item in
                let isActive = item.index == animationIndex

                ZStack {
                    Circle()
                        .fill(ZoneColorProvider.swiftUIColor(for: item.area))
                        .frame(width: size, height: size)
                        .shadow(color: isActive ? .black.opacity(0.3) : .black.opacity(0.1),
                                radius: isActive ? 4 : 2,
                                x: 0, y: isActive ? 2 : 1)

                    Text(item.area)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
                .offset(x: CGFloat(item.index) * offset)
                .scaleEffect(isActive ? 1.1 : 1.0)
                .zIndex(isActive ? 1 : 0)
            }
        }
        .frame(width: totalWidth, height: size * 1.1)
    }
}

// MARK: - Mini Zone Card (matches main ZoneStatusCardView style)

private struct MiniZoneCard: View {
    let zoneName: String?
    let zoneCode: String?
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let allValidPermitAreas: [String]

    @State private var animationIndex: Int = 0

    /// Whether this is a multi-permit location
    private var isMultiPermitLocation: Bool {
        allValidPermitAreas.count > 1
    }

    /// Permit areas ordered with user's permit first
    private var orderedPermitAreas: [String] {
        guard isMultiPermitLocation else {
            return [zoneCode ?? "?"]
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

    @ViewBuilder
    private var zoneCircle: some View {
        if isMultiPermitLocation {
            MultiPermitCircleView(
                permitAreas: orderedPermitAreas,
                animationIndex: animationIndex,
                size: 56
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationIndex = (animationIndex + 1) % orderedPermitAreas.count
                }
            }
        } else {
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
    }

    /// Currently highlighted area for multi-permit locations
    private var currentSelectedArea: String {
        guard isMultiPermitLocation, animationIndex < orderedPermitAreas.count else {
            return zoneCode ?? "?"
        }
        return orderedPermitAreas[animationIndex]
    }

    private var zoneInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isMultiPermitLocation {
                // Show currently selected area name
                Text("Zone \(currentSelectedArea)")
                    .font(.headline)
                    .foregroundColor(isValidStyle ? .white : .primary)
                    .animation(.easeInOut(duration: 0.2), value: animationIndex)
                Text("Multi Permit Zone")
                    .font(.caption)
                    .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
            } else {
                Text(zoneName ?? "Unknown Zone")
                    .font(.headline)
                    .foregroundColor(isValidStyle ? .white : .primary)
            }

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
