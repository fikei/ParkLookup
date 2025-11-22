import SwiftUI
import MapKit

/// Floating mini-map showing user location and current zone
struct FloatingMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let zoneName: String?
    let onTap: () -> Void

    @State private var position: MapCameraPosition

    init(
        coordinate: CLLocationCoordinate2D?,
        zoneName: String?,
        onTap: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.zoneName = zoneName
        self.onTap = onTap

        // Initialize camera position with coordinate or SF default (2x zoom)
        let center = coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
        )))
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Map (iOS 17+ API)
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapControls { }
                .disabled(true)
                .allowsHitTesting(false)

                // Expand hint
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .frame(width: 120, height: 120)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .onChange(of: coordinate?.latitude) { _, _ in
            if let coord = coordinate {
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
                    ))
                }
            }
        }
    }
}

// MARK: - Expanded Map View

struct ExpandedMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let zoneName: String?
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]

    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition
    @State private var zones: [ParkingZone] = []
    @State private var isLoadingZones = true

    init(
        coordinate: CLLocationCoordinate2D?,
        zoneName: String?,
        validityStatus: PermitValidityStatus = .noPermitRequired,
        applicablePermits: [ParkingPermit] = []
    ) {
        self.coordinate = coordinate
        self.zoneName = zoneName
        self.validityStatus = validityStatus
        self.applicablePermits = applicablePermits

        let center = coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )))
    }

    /// Extract permit area code from zone name (e.g., "Area Q" -> "Q")
    private var currentPermitArea: String? {
        guard let zoneName = zoneName, zoneName.hasPrefix("Area ") else {
            return zoneName
        }
        return String(zoneName.dropFirst(5))
    }

    var body: some View {
        NavigationView {
            ZStack {
                mapContent
                    .ignoresSafeArea()

                // Zone info overlay - Mini Zone Card matching main view style
                VStack {
                    Spacer()
                    MiniZoneCard(
                        zoneName: zoneName,
                        zoneCode: currentPermitArea,
                        validityStatus: validityStatus,
                        applicablePermits: applicablePermits
                    )
                    .padding()
                }

                // Loading indicator
                if isLoadingZones {
                    loadingIndicator
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadZones()
            }
        }
    }

    // MARK: - Subviews (broken out for type-checker)

    @ViewBuilder
    private var mapContent: some View {
        Map(position: $position) {
            // Draw zone polygons
            ForEach(zones) { zone in
                zonePolygons(for: zone)
            }
            // User location
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    @MapContentBuilder
    private func zonePolygons(for zone: ParkingZone) -> some MapContent {
        let isCurrentZone = zone.permitArea == currentPermitArea
        let strokeColor: Color = isCurrentZone ? .green : .blue
        let fillColor: Color = isCurrentZone ? .green.opacity(0.3) : .blue.opacity(0.15)
        let lineWidth: CGFloat = isCurrentZone ? 3 : 1

        ForEach(zone.allBoundaryCoordinates.indices, id: \.self) { idx in
            let coords = zone.allBoundaryCoordinates[idx]
            if coords.count >= 3 {
                MapPolygon(coordinates: coords)
                    .stroke(strokeColor, lineWidth: lineWidth)
                    .foregroundStyle(fillColor)
            }
        }
    }

    private var loadingIndicator: some View {
        VStack {
            HStack {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                Spacer()
            }
            .padding()
            Spacer()
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadZones() async {
        isLoadingZones = true
        do {
            let service = DependencyContainer.shared.zoneService
            zones = try await service.getAllZones(for: .sanFrancisco)
        } catch {
            print("Failed to load zones for map: \(error)")
        }
        isLoadingZones = false
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

    /// Circle background color
    private var circleBackground: Color {
        isValidStyle ? Color(.systemBackground) : Color.forValidityStatus(validityStatus).opacity(0.15)
    }

    /// Text color for zone letter
    private var letterColor: Color {
        Color.forValidityStatus(validityStatus)
    }

    var body: some View {
        HStack(spacing: 16) {
            zoneCircle
            zoneInfo
            Spacer()
            legend
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

    private var legend: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Your Zone")
                    .font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.blue.opacity(0.5)).frame(width: 8, height: 8)
                Text("Other Zones")
                    .font(.caption2)
            }
        }
        .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        FloatingMapView(
            coordinate: CLLocationCoordinate2D(latitude: 37.7585, longitude: -122.4233),
            zoneName: "Area Q",
            onTap: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
