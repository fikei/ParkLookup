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
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition
    @State private var zones: [ParkingZone] = []
    @State private var isLoadingZones = true

    private let zoneService: ZoneServiceProtocol

    init(coordinate: CLLocationCoordinate2D?, zoneName: String?) {
        self.coordinate = coordinate
        self.zoneName = zoneName
        self.zoneService = DependencyContainer.shared.zoneService

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
                Map(position: $position) {
                    // Draw all RPP zone polygons
                    ForEach(zones) { zone in
                        ForEach(zone.allBoundaryCoordinates.indices, id: \.self) { boundaryIndex in
                            let coords = zone.allBoundaryCoordinates[boundaryIndex]
                            if coords.count >= 3 {
                                MapPolygon(coordinates: coords)
                                    .stroke(
                                        zone.permitArea == currentPermitArea ? Color.green : Color.blue,
                                        lineWidth: zone.permitArea == currentPermitArea ? 3 : 1
                                    )
                                    .foregroundStyle(
                                        zone.permitArea == currentPermitArea
                                            ? Color.green.opacity(0.3)
                                            : Color.blue.opacity(0.15)
                                    )
                            }
                        }
                    }

                    // User location
                    UserAnnotation()
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .ignoresSafeArea()

                // Zone info overlay
                VStack {
                    Spacer()
                    if let zoneName = zoneName {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Zone")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(zoneName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            Spacer()

                            // Legend
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 10, height: 10)
                                    Text("Your Zone")
                                        .font(.caption2)
                                }
                                HStack(spacing: 4) {
                                    Circle().fill(Color.blue.opacity(0.5)).frame(width: 10, height: 10)
                                    Text("Other Zones")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
                    }
                }

                // Loading indicator
                if isLoadingZones {
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

    private func loadZones() async {
        isLoadingZones = true
        do {
            zones = try await zoneService.getAllZones(for: .sanFrancisco)
        } catch {
            print("Failed to load zones for map: \(error)")
        }
        isLoadingZones = false
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
