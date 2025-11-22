import SwiftUI
import MapKit

/// MKMapView-based map with zone polygon overlays
/// Uses UIViewRepresentable to enable MKPolygonRenderer (not available in SwiftUI Map)
struct ZoneMapView: UIViewRepresentable {
    let zones: [ParkingZone]
    let currentZoneId: String?
    let userCoordinate: CLLocationCoordinate2D?
    let onZoneTapped: ((ParkingZone) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Set initial region (SF or user location)
        let center = userCoordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        mapView.setRegion(region, animated: false)

        // Add tap gesture for zone selection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update coordinator with current state
        context.coordinator.currentZoneId = currentZoneId
        context.coordinator.zones = zones
        context.coordinator.onZoneTapped = onZoneTapped

        // Remove existing overlays and annotations (except user location)
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        // Add zone polygons and labels
        for zone in zones {
            addZoneOverlays(zone, to: mapView, context: context)
        }

        // Re-center on user if location changed significantly
        if let coord = userCoordinate {
            let currentCenter = mapView.centerCoordinate
            let distance = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude))
            if distance > 500 { // Only re-center if moved > 500m
                let region = MKCoordinateRegion(
                    center: coord,
                    span: mapView.region.span
                )
                mapView.setRegion(region, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentZoneId: currentZoneId, zones: zones, onZoneTapped: onZoneTapped)
    }

    // MARK: - Private Helpers

    private func addZoneOverlays(_ zone: ParkingZone, to mapView: MKMapView, context: Context) {
        for boundary in zone.allBoundaryCoordinates {
            guard boundary.count >= 3 else { continue }

            // Create polygon overlay
            let polygon = ZonePolygon(coordinates: boundary, count: boundary.count)
            polygon.zoneId = zone.id
            polygon.zoneCode = zone.permitArea
            mapView.addOverlay(polygon, level: .aboveRoads)
        }

        // Add zone label annotation at centroid
        if let centroid = calculateCentroid(for: zone) {
            let annotation = ZoneLabelAnnotation(
                coordinate: centroid,
                zoneCode: zone.permitArea ?? zone.displayName,
                zoneId: zone.id
            )
            mapView.addAnnotation(annotation)
        }
    }

    private func calculateCentroid(for zone: ParkingZone) -> CLLocationCoordinate2D? {
        let allCoords = zone.allBoundaryCoordinates.flatMap { $0 }
        guard !allCoords.isEmpty else { return nil }

        let sumLat = allCoords.reduce(0.0) { $0 + $1.latitude }
        let sumLon = allCoords.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(
            latitude: sumLat / Double(allCoords.count),
            longitude: sumLon / Double(allCoords.count)
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var currentZoneId: String?
        var zones: [ParkingZone]
        var onZoneTapped: ((ParkingZone) -> Void)?

        init(currentZoneId: String?, zones: [ParkingZone], onZoneTapped: ((ParkingZone) -> Void)?) {
            self.currentZoneId = currentZoneId
            self.zones = zones
            self.onZoneTapped = onZoneTapped
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? ZonePolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            let isCurrentZone = polygon.zoneId == currentZoneId

            renderer.fillColor = ZoneColorProvider.fillColor(for: polygon.zoneCode, isCurrentZone: isCurrentZone)
            renderer.strokeColor = ZoneColorProvider.strokeColor(for: polygon.zoneCode, isCurrentZone: isCurrentZone)
            renderer.lineWidth = ZoneColorProvider.strokeWidth(isCurrentZone: isCurrentZone)

            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Skip user location annotation
            guard let zoneAnnotation = annotation as? ZoneLabelAnnotation else {
                return nil
            }

            let identifier = "ZoneLabel"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: zoneAnnotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
            } else {
                annotationView?.annotation = zoneAnnotation
            }

            // Create label view
            let isCurrentZone = zoneAnnotation.zoneId == currentZoneId
            let labelView = createZoneLabelView(
                code: zoneAnnotation.zoneCode,
                isCurrentZone: isCurrentZone
            )

            // Remove old subviews and add new label
            annotationView?.subviews.forEach { $0.removeFromSuperview() }
            annotationView?.addSubview(labelView)
            annotationView?.frame = labelView.frame
            annotationView?.centerOffset = CGPoint(x: 0, y: 0)

            return annotationView
        }

        private func createZoneLabelView(code: String, isCurrentZone: Bool) -> UIView {
            let label = UILabel()
            label.text = code
            label.font = .systemFont(ofSize: isCurrentZone ? 16 : 12, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center

            let size: CGFloat = isCurrentZone ? 32 : 24
            label.frame = CGRect(x: 0, y: 0, width: size, height: size)

            let containerView = UIView(frame: label.frame)
            containerView.backgroundColor = ZoneColorProvider.color(for: code)
            containerView.layer.cornerRadius = size / 2
            containerView.layer.borderWidth = isCurrentZone ? 2 : 1
            containerView.layer.borderColor = UIColor.white.cgColor
            containerView.layer.shadowColor = UIColor.black.cgColor
            containerView.layer.shadowOffset = CGSize(width: 0, height: 1)
            containerView.layer.shadowRadius = 2
            containerView.layer.shadowOpacity = 0.3

            containerView.addSubview(label)
            return containerView
        }

        // MARK: - Tap Handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            // Find which zone polygon contains this point
            for overlay in mapView.overlays {
                guard let polygon = overlay as? ZonePolygon,
                      let renderer = mapView.renderer(for: polygon) as? MKPolygonRenderer else {
                    continue
                }

                let mapPoint = MKMapPoint(coordinate)
                let polygonPoint = renderer.point(for: mapPoint)

                if renderer.path?.contains(polygonPoint) == true {
                    // Found the tapped zone
                    if let zone = zones.first(where: { $0.id == polygon.zoneId }) {
                        onZoneTapped?(zone)
                    }
                    return
                }
            }
        }
    }
}

// MARK: - Custom Overlay & Annotation Classes

/// MKPolygon subclass that carries zone metadata
class ZonePolygon: MKPolygon {
    var zoneId: String?
    var zoneCode: String?
}

/// Annotation for zone label display
class ZoneLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let zoneCode: String
    let zoneId: String

    init(coordinate: CLLocationCoordinate2D, zoneCode: String, zoneId: String) {
        self.coordinate = coordinate
        self.zoneCode = zoneCode
        self.zoneId = zoneId
        super.init()
    }
}

// MARK: - Preview

#Preview {
    ZoneMapView(
        zones: [],
        currentZoneId: nil,
        userCoordinate: CLLocationCoordinate2D(latitude: 37.7585, longitude: -122.4233),
        onZoneTapped: { zone in
            print("Tapped zone: \(zone.displayName)")
        }
    )
}
