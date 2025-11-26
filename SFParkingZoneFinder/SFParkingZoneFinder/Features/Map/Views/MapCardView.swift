import SwiftUI
import MapKit

/// Full-width map card showing user location and current zone
/// Note: Requires iOS 17+ for SwiftUI Map API
@available(iOS 17.0, *)
struct MapCardView: View {
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
                .mapControls { }  // Hide controls for cleaner look
                .disabled(true)
                .allowsHitTesting(false)

                // Expand hint overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2)
                            Text("Tap to expand")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
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
        .accessibilityLabel("Map showing your location in \(zoneName ?? "current zone"). Tap to expand.")
    }
}

// MARK: - Preview

#Preview {
    if #available(iOS 17.0, *) {
        ScrollView {
            VStack(spacing: 16) {
                MapCardView(
                    coordinate: CLLocationCoordinate2D(latitude: 37.7585, longitude: -122.4233),
                    zoneName: "Area Q",
                    onTap: {}
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    } else {
        Text("MapCardView requires iOS 17+")
    }
}
