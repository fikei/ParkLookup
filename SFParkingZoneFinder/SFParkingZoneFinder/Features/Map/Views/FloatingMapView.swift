import SwiftUI
import MapKit

/// Floating mini-map showing user location and current zone
struct FloatingMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let zoneName: String?
    let onTap: () -> Void

    @State private var region: MKCoordinateRegion

    init(
        coordinate: CLLocationCoordinate2D?,
        zoneName: String?,
        onTap: @escaping () -> Void
    ) {
        self.coordinate = coordinate
        self.zoneName = zoneName
        self.onTap = onTap

        // Initialize region with coordinate or SF default
        let center = coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Map
                Map(coordinateRegion: .constant(region), showsUserLocation: true)
                    .disabled(true) // Prevent interaction, tap opens expanded view
                    .allowsHitTesting(false)

                // Zone label overlay
                if let zoneName = zoneName {
                    VStack {
                        Spacer()
                        HStack {
                            Text(zoneName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(8)
                    }
                }

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
                    region.center = coord
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

    @State private var region: MKCoordinateRegion

    init(coordinate: CLLocationCoordinate2D?, zoneName: String?) {
        self.coordinate = coordinate
        self.zoneName = zoneName

        let center = coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $region, showsUserLocation: true)
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
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
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
        }
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
