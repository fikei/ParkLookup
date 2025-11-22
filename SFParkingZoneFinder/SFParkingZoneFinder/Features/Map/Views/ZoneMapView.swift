import SwiftUI
import MapKit
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ZoneMapView")

// MARK: - Polygon Simplification (Douglas-Peucker Algorithm)

/// Simplifies a polygon by removing points that don't significantly affect the shape
/// Uses the Douglas-Peucker algorithm with the given tolerance (in degrees)
private func simplifyPolygon(_ coords: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
    guard coords.count > 4 else { return coords }  // Need at least 4 points for simplification

    func perpendicularDistance(_ point: CLLocationCoordinate2D, lineStart: CLLocationCoordinate2D, lineEnd: CLLocationCoordinate2D) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude

        if dx == 0 && dy == 0 {
            // Line start and end are the same point
            let pdx = point.longitude - lineStart.longitude
            let pdy = point.latitude - lineStart.latitude
            return sqrt(pdx * pdx + pdy * pdy)
        }

        let t = max(0, min(1, ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)))
        let projX = lineStart.longitude + t * dx
        let projY = lineStart.latitude + t * dy
        let pdx = point.longitude - projX
        let pdy = point.latitude - projY
        return sqrt(pdx * pdx + pdy * pdy)
    }

    func douglasPeucker(_ points: [CLLocationCoordinate2D], _ epsilon: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var maxDistance = 0.0
        var maxIndex = 0

        for i in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[i], lineStart: points[0], lineEnd: points[points.count - 1])
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        if maxDistance > epsilon {
            let left = douglasPeucker(Array(points[0...maxIndex]), epsilon)
            let right = douglasPeucker(Array(points[maxIndex...]), epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [points[0], points[points.count - 1]]
        }
    }

    let simplified = douglasPeucker(coords, tolerance)
    // Ensure polygon is closed
    if simplified.count >= 3 && (simplified.first!.latitude != simplified.last!.latitude || simplified.first!.longitude != simplified.last!.longitude) {
        return simplified + [simplified[0]]
    }
    return simplified
}

/// MKMapView-based map with zone polygon overlays
/// Uses UIViewRepresentable to enable MKPolygonRenderer (not available in SwiftUI Map)
struct ZoneMapView: UIViewRepresentable {
    let zones: [ParkingZone]
    let currentZoneId: String?
    let userCoordinate: CLLocationCoordinate2D?
    let onZoneTapped: ((ParkingZone) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("makeUIView START - zones count: \(self.zones.count), userCoord: \(userCoordinate != nil ? "present" : "nil")")

        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Set initial region centered on user (zoomed to ~10-15 blocks)
        // 0.006 degrees ≈ 670m ≈ 8-10 SF blocks
        let center = userCoordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let desiredSpan = MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        let region = MKCoordinateRegion(center: center, span: desiredSpan)
        mapView.setRegion(region, animated: false)

        // Store the desired region in coordinator so we can re-apply after overlays load
        context.coordinator.initialCenter = center
        context.coordinator.initialSpan = desiredSpan

        logger.debug("Map region set in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms - center: \(center.latitude), \(center.longitude)")

        // Add tap gesture for zone selection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        // Load zone overlays in background, add to map on main thread
        let zonesToLoad = self.zones
        let zoneCount = zonesToLoad.count
        logger.info("Starting background polygon prep for \(zoneCount) zones")

        DispatchQueue.global(qos: .userInitiated).async {
            let bgStartTime = CFAbsoluteTimeGetCurrent()
            logger.debug("Background thread START")

            // Prepare all polygon data in background
            // Filter to only include polygons near the user (performance optimization)
            // Apply simplification to reduce point count for smoother rendering
            var polygons: [ZonePolygon] = []
            var annotations: [ZoneLabelAnnotation] = []
            var totalBoundaries = 0
            var totalPoints = 0
            var simplifiedPoints = 0
            var filteredOut = 0

            // Two-tier filter: inner radius (full detail) and outer radius (simplified)
            let innerRadius = 0.008   // ~900m - full detail
            let outerRadius = 0.025   // ~2.8km - simplified polygons

            let innerMinLat = center.latitude - innerRadius
            let innerMaxLat = center.latitude + innerRadius
            let innerMinLon = center.longitude - innerRadius
            let innerMaxLon = center.longitude + innerRadius

            let outerMinLat = center.latitude - outerRadius
            let outerMaxLat = center.latitude + outerRadius
            let outerMinLon = center.longitude - outerRadius
            let outerMaxLon = center.longitude + outerRadius

            // Simplification tolerance (in degrees) - higher = more simplified
            let simplificationTolerance = 0.00005  // ~5m tolerance for outer polygons

            for (index, zone) in zonesToLoad.enumerated() {
                let zoneBoundaryCount = zone.allBoundaryCoordinates.count
                var zoneHasVisiblePolygon = false

                for boundary in zone.allBoundaryCoordinates {
                    guard boundary.count >= 3 else { continue }
                    totalBoundaries += 1
                    totalPoints += boundary.count

                    // Check if polygon is in inner radius (full detail)
                    let isInInnerRadius = boundary.contains { coord in
                        coord.latitude >= innerMinLat && coord.latitude <= innerMaxLat &&
                        coord.longitude >= innerMinLon && coord.longitude <= innerMaxLon
                    }

                    // Check if polygon is in outer radius (simplified)
                    let isInOuterRadius = boundary.contains { coord in
                        coord.latitude >= outerMinLat && coord.latitude <= outerMaxLat &&
                        coord.longitude >= outerMinLon && coord.longitude <= outerMaxLon
                    }

                    if isInInnerRadius {
                        // Full detail for nearby polygons
                        let polygon = ZonePolygon(coordinates: boundary, count: boundary.count)
                        polygon.zoneId = zone.id
                        polygon.zoneCode = zone.permitArea
                        polygons.append(polygon)
                        simplifiedPoints += boundary.count
                        zoneHasVisiblePolygon = true
                    } else if isInOuterRadius {
                        // Simplified for distant polygons
                        let simplified = simplifyPolygon(boundary, tolerance: simplificationTolerance)
                        if simplified.count >= 3 {
                            let polygon = ZonePolygon(coordinates: simplified, count: simplified.count)
                            polygon.zoneId = zone.id
                            polygon.zoneCode = zone.permitArea
                            polygons.append(polygon)
                            simplifiedPoints += simplified.count
                            zoneHasVisiblePolygon = true
                        }
                    } else {
                        filteredOut += 1
                    }
                }

                // Log zone info on first few
                if index < 3 {
                    logger.debug("Zone \(index): id=\(zone.id), permitArea=\(zone.permitArea ?? "nil"), boundaries=\(zoneBoundaryCount)")
                }

                // Only add annotation if zone has visible polygons near user
                if zoneHasVisiblePolygon {
                    let nearbyCoords = zone.allBoundaryCoordinates.flatMap { $0 }.filter { coord in
                        coord.latitude >= outerMinLat && coord.latitude <= outerMaxLat &&
                        coord.longitude >= outerMinLon && coord.longitude <= outerMaxLon
                    }
                    if !nearbyCoords.isEmpty {
                        let sumLat = nearbyCoords.reduce(0.0) { $0 + $1.latitude }
                        let sumLon = nearbyCoords.reduce(0.0) { $0 + $1.longitude }
                        let centroid = CLLocationCoordinate2D(
                            latitude: sumLat / Double(nearbyCoords.count),
                            longitude: sumLon / Double(nearbyCoords.count)
                        )
                        let annotation = ZoneLabelAnnotation(
                            coordinate: centroid,
                            zoneCode: zone.permitArea ?? zone.displayName,
                            zoneId: zone.id
                        )
                        annotations.append(annotation)
                    }
                }

                // Log progress every 10 zones
                if (index + 1) % 10 == 0 || index == zoneCount - 1 {
                    logger.debug("Processed \(index + 1)/\(zoneCount) zones")
                }
            }

            let bgElapsed = (CFAbsoluteTimeGetCurrent() - bgStartTime) * 1000
            logger.info("Background prep DONE in \(String(format: "%.1f", bgElapsed))ms - \(polygons.count) polygons (\(simplifiedPoints) points, filtered \(filteredOut)), \(totalBoundaries) total boundaries")

            // Capture the coordinator and initial region before async block
            let coordinator = context.coordinator
            let initialCenter = coordinator.initialCenter
            let initialSpan = coordinator.initialSpan

            // Add to map on main thread
            DispatchQueue.main.async {
                let mainStartTime = CFAbsoluteTimeGetCurrent()
                logger.debug("Main thread overlay add START - \(polygons.count) polygons")

                for polygon in polygons {
                    mapView.addOverlay(polygon, level: .aboveRoads)
                }
                let overlayElapsed = (CFAbsoluteTimeGetCurrent() - mainStartTime) * 1000
                logger.debug("Overlays added in \(String(format: "%.1f", overlayElapsed))ms")

                mapView.addAnnotations(annotations)

                // Re-apply the initial zoom after overlays are added to prevent MKMapView from auto-fitting
                if let center = initialCenter, let span = initialSpan {
                    let region = MKCoordinateRegion(center: center, span: span)
                    mapView.setRegion(region, animated: false)
                    logger.debug("Re-applied initial region after overlay load - center: \(center.latitude), \(center.longitude)")
                }

                // Mark initial setup as complete - now updateUIView can handle re-centering
                coordinator.initialSetupDone = true

                let totalMainElapsed = (CFAbsoluteTimeGetCurrent() - mainStartTime) * 1000
                logger.info("Main thread overlay add DONE in \(String(format: "%.1f", totalMainElapsed))ms - initialSetupDone")
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.info("makeUIView RETURN in \(String(format: "%.1f", elapsed))ms (background work continues)")
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        logger.debug("updateUIView called - overlays: \(mapView.overlays.count), annotations: \(mapView.annotations.count), initialSetupDone: \(context.coordinator.initialSetupDone)")

        // Update coordinator with current state
        context.coordinator.currentZoneId = currentZoneId
        context.coordinator.zones = zones
        context.coordinator.onZoneTapped = onZoneTapped

        // Skip re-centering during initial setup (overlays are loading async)
        guard context.coordinator.initialSetupDone else {
            logger.debug("Skipping re-center - initial setup not done")
            return
        }

        // Only re-center on user if location changed significantly
        // Don't re-add overlays on every update (expensive!)
        if let coord = userCoordinate {
            let currentCenter = mapView.centerCoordinate
            let distance = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude))
            if distance > 500 { // Only re-center if moved > 500m
                logger.debug("Re-centering map (moved \(String(format: "%.0f", distance))m)")
                // Use stored initial span to maintain zoom level
                let span = context.coordinator.initialSpan ?? mapView.region.span
                let region = MKCoordinateRegion(center: coord, span: span)
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

        // Store initial region to re-apply after overlays load
        var initialCenter: CLLocationCoordinate2D?
        var initialSpan: MKCoordinateSpan?

        // Flag to indicate initial overlay loading is complete
        var initialSetupDone = false

        init(currentZoneId: String?, zones: [ParkingZone], onZoneTapped: ((ParkingZone) -> Void)?) {
            self.currentZoneId = currentZoneId
            self.zones = zones
            self.onZoneTapped = onZoneTapped
        }

        // MARK: - MKMapViewDelegate

        private var rendererCallCount = 0

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? ZonePolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }

            rendererCallCount += 1
            let renderer = MKPolygonRenderer(polygon: polygon)
            let isCurrentZone = polygon.zoneId == currentZoneId

            let fillColor = ZoneColorProvider.fillColor(for: polygon.zoneCode, isCurrentZone: isCurrentZone)
            let strokeColor = ZoneColorProvider.strokeColor(for: polygon.zoneCode, isCurrentZone: isCurrentZone)

            renderer.fillColor = fillColor
            renderer.strokeColor = strokeColor
            renderer.lineWidth = ZoneColorProvider.strokeWidth(isCurrentZone: isCurrentZone)

            // Log first few and then every 1000th
            if rendererCallCount <= 5 || rendererCallCount % 1000 == 0 {
                logger.debug("Renderer #\(self.rendererCallCount) - zoneCode: \(polygon.zoneCode ?? "nil"), fill: \(fillColor.description), stroke: \(strokeColor.description)")
            }

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
