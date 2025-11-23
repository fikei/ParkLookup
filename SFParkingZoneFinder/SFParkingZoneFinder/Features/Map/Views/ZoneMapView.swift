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

// MARK: - Convex Hull Algorithm (Graham Scan)

/// Computes the convex hull of a set of points using Graham scan algorithm
/// Returns points in counter-clockwise order forming the hull
private func convexHull(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
    guard points.count >= 3 else { return points }

    // Find the bottom-most point (or left-most in case of tie)
    var sorted = points
    let pivot = sorted.min { a, b in
        if a.latitude != b.latitude {
            return a.latitude < b.latitude
        }
        return a.longitude < b.longitude
    }!

    // Sort points by polar angle with respect to pivot
    sorted.sort { a, b in
        let angleA = atan2(a.latitude - pivot.latitude, a.longitude - pivot.longitude)
        let angleB = atan2(b.latitude - pivot.latitude, b.longitude - pivot.longitude)
        if angleA != angleB {
            return angleA < angleB
        }
        // If same angle, closer point first
        let distA = (a.latitude - pivot.latitude) * (a.latitude - pivot.latitude) +
                    (a.longitude - pivot.longitude) * (a.longitude - pivot.longitude)
        let distB = (b.latitude - pivot.latitude) * (b.latitude - pivot.latitude) +
                    (b.longitude - pivot.longitude) * (b.longitude - pivot.longitude)
        return distA < distB
    }

    // Cross product to determine turn direction
    func cross(_ o: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
               (a.latitude - o.latitude) * (b.longitude - o.longitude)
    }

    // Build hull
    var hull: [CLLocationCoordinate2D] = []
    for point in sorted {
        while hull.count >= 2 && cross(hull[hull.count - 2], hull[hull.count - 1], point) <= 0 {
            hull.removeLast()
        }
        hull.append(point)
    }

    // Close the hull
    if hull.count >= 3 {
        hull.append(hull[0])
    }

    return hull
}

/// MKMapView-based map with zone polygon overlays
/// Uses UIViewRepresentable to enable MKPolygonRenderer (not available in SwiftUI Map)
struct ZoneMapView: UIViewRepresentable {
    let zones: [ParkingZone]
    let currentZoneId: String?
    let userCoordinate: CLLocationCoordinate2D?
    let onZoneTapped: ((ParkingZone) -> Void)?

    /// Vertical bias for user location position (0.0 = center, positive = user appears lower on screen)
    /// A value of 0.25 means the user appears at 75% from top (25% from bottom)
    var verticalBias: Double = 0.0

    /// Whether to show zone polygon overlays (false = clean map with just user location)
    var showOverlays: Bool = true

    /// Zoom multiplier (1.0 = default, smaller = more zoomed in, larger = more zoomed out)
    /// 0.8 = 20% more zoomed in
    var zoomMultiplier: Double = 1.0

    /// When true, uses convex hull (smoothed envelope). When false, uses actual block boundaries.
    /// Set to false to see the preprocessed polygon data as-is.
    static var useConvexHull: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("makeUIView START - zones count: \(self.zones.count), userCoord: \(userCoordinate != nil ? "present" : "nil")")

        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Set initial region centered on user (zoomed to ~10-15 blocks)
        // 0.006 degrees ≈ 670m ≈ 8-10 SF blocks, adjusted by zoom multiplier
        let userCenter = userCoordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let baseSpan = 0.006
        let desiredSpan = MKCoordinateSpan(
            latitudeDelta: baseSpan * zoomMultiplier,
            longitudeDelta: baseSpan * zoomMultiplier
        )

        // Apply vertical bias: offset center northward to push user location down on screen
        // verticalBias of 0.25 means user appears at 75% from top (halfway between center and bottom)
        let latOffset = desiredSpan.latitudeDelta * verticalBias
        let center = CLLocationCoordinate2D(
            latitude: userCenter.latitude + latOffset,
            longitude: userCenter.longitude
        )

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

        let useConvexHull = ZoneMapView.useConvexHull
        DispatchQueue.global(qos: .userInitiated).async {
            let bgStartTime = CFAbsoluteTimeGetCurrent()
            logger.info("Background thread START - useConvexHull: \(useConvexHull)")

            var polygons: [ZonePolygon] = []
            var annotations: [ZoneLabelAnnotation] = []
            var totalBoundaries = 0
            var totalPoints = 0
            var outputPoints = 0

            // Filter radius for visible zones
            let filterRadius = 0.03   // ~3.3km - visible area

            let minLat = center.latitude - filterRadius
            let maxLat = center.latitude + filterRadius
            let minLon = center.longitude - filterRadius
            let maxLon = center.longitude + filterRadius

            for (index, zone) in zonesToLoad.enumerated() {
                let zoneBoundaryCount = zone.allBoundaryCoordinates.count
                totalBoundaries += zoneBoundaryCount

                // Collect nearby boundaries
                var nearbyBoundaries: [[CLLocationCoordinate2D]] = []

                for boundary in zone.allBoundaryCoordinates {
                    totalPoints += boundary.count

                    // Check if any point of this boundary is within filter bounds
                    let hasNearbyPoint = boundary.contains { coord in
                        coord.latitude >= minLat && coord.latitude <= maxLat &&
                        coord.longitude >= minLon && coord.longitude <= maxLon
                    }

                    if hasNearbyPoint {
                        nearbyBoundaries.append(boundary)
                    }
                }

                // Log zone info on first few
                if index < 3 {
                    let pointCounts = nearbyBoundaries.map { $0.count }
                    logger.info("Zone \(index): id=\(zone.id), permitArea=\(zone.permitArea ?? "nil"), boundaries=\(zoneBoundaryCount), nearbyBoundaries=\(nearbyBoundaries.count), pointsPerBoundary=\(pointCounts.prefix(5))")
                }

                if useConvexHull {
                    // CONVEX HULL MODE: Create single smoothed envelope per zone
                    let allNearbyPoints = nearbyBoundaries.flatMap { $0 }
                    if allNearbyPoints.count >= 3 {
                        let hull = convexHull(allNearbyPoints)
                        if hull.count >= 3 {
                            let polygon = ZonePolygon(coordinates: hull, count: hull.count)
                            polygon.zoneId = zone.id
                            polygon.zoneCode = zone.permitArea
                            polygon.zoneType = zone.zoneType
                            polygons.append(polygon)
                            outputPoints += hull.count
                        }
                    }
                } else {
                    // ACTUAL BOUNDARIES MODE: Use preprocessed block polygons as-is
                    // Get multi-permit boundary indices for this zone
                    let multiPermitIndices = zone.multiPermitBoundaryIndices

                    // Build a lookup from boundary coordinate count to original indices
                    // for matching nearbyBoundaries back to original indices
                    let allBoundaries = zone.allBoundaryCoordinates

                    for boundary in nearbyBoundaries {
                        guard boundary.count >= 3 else { continue }
                        let polygon = ZonePolygon(coordinates: boundary, count: boundary.count)
                        polygon.zoneId = zone.id
                        polygon.zoneCode = zone.permitArea
                        polygon.zoneType = zone.zoneType

                        // Check if this is a multi-permit boundary by matching coordinates
                        // Find the original index by comparing first coordinate (unique enough for matching)
                        if let firstCoord = boundary.first {
                            for (originalIndex, originalBoundary) in allBoundaries.enumerated() {
                                if let origFirst = originalBoundary.first,
                                   abs(origFirst.latitude - firstCoord.latitude) < 0.000001 &&
                                   abs(origFirst.longitude - firstCoord.longitude) < 0.000001 &&
                                   multiPermitIndices.contains(originalIndex) {
                                    polygon.isMultiPermit = true
                                    polygon.allValidPermitAreas = zone.validPermitAreas(for: originalIndex)
                                    break
                                }
                            }
                        }

                        polygons.append(polygon)
                        outputPoints += boundary.count
                    }
                }

                // Add annotation at zone centroid (from all nearby boundaries)
                let allNearbyPoints = nearbyBoundaries.flatMap { $0 }
                if !allNearbyPoints.isEmpty {
                    let sumLat = allNearbyPoints.reduce(0.0) { $0 + $1.latitude }
                    let sumLon = allNearbyPoints.reduce(0.0) { $0 + $1.longitude }
                    let centroid = CLLocationCoordinate2D(
                        latitude: sumLat / Double(allNearbyPoints.count),
                        longitude: sumLon / Double(allNearbyPoints.count)
                    )
                    // For metered zones, use "$" symbol; for RPP use permit area code
                    let labelCode = zone.zoneType == .metered ? "$" : (zone.permitArea ?? zone.displayName)
                    let annotation = ZoneLabelAnnotation(
                        coordinate: centroid,
                        zoneCode: labelCode,
                        zoneId: zone.id,
                        zoneType: zone.zoneType
                    )
                    annotations.append(annotation)
                }

                // Log progress every 10 zones
                if (index + 1) % 10 == 0 || index == zoneCount - 1 {
                    logger.debug("Processed \(index + 1)/\(zoneCount) zones, polygons so far: \(polygons.count)")
                }
            }

            let bgElapsed = (CFAbsoluteTimeGetCurrent() - bgStartTime) * 1000
            let modeStr = useConvexHull ? "convex hull" : "actual boundaries"
            logger.info("Background prep DONE in \(String(format: "%.1f", bgElapsed))ms - mode: \(modeStr), \(polygons.count) polygons (\(outputPoints) points from \(totalPoints) original), \(totalBoundaries) total boundaries")

            // Separate polygons by zone type - metered zones render below RPP zones
            let meteredPolygons = polygons.filter { $0.zoneType == .metered }
            let rppPolygons = polygons.filter { $0.zoneType != .metered }
            logger.info("Zone layering: \(meteredPolygons.count) metered (bottom), \(rppPolygons.count) RPP (top)")

            // Capture the coordinator, initial region, and showOverlays before async block
            let coordinator = context.coordinator
            let initialCenter = coordinator.initialCenter
            let initialSpan = coordinator.initialSpan
            let shouldShowOverlays = self.showOverlays

            // Add to map on main thread in batches to keep UI responsive
            DispatchQueue.main.async {
                let mainStartTime = CFAbsoluteTimeGetCurrent()
                logger.info("Main thread overlay add START - \(polygons.count) polygons, \(annotations.count) annotations, showOverlays: \(shouldShowOverlays)")

                // Mark setup done immediately so map is interactive
                coordinator.initialSetupDone = true
                coordinator.showOverlays = shouldShowOverlays

                // Re-apply the initial zoom first
                if let center = initialCenter, let span = initialSpan {
                    let region = MKCoordinateRegion(center: center, span: span)
                    mapView.setRegion(region, animated: false)
                    logger.debug("Applied initial region - center: \(center.latitude), \(center.longitude)")
                }

                // Add annotations immediately (they're lightweight)
                mapView.addAnnotations(annotations)

                // Hide annotations if overlays should be hidden
                if !shouldShowOverlays {
                    for annotation in annotations {
                        if let view = mapView.view(for: annotation) {
                            view.alpha = 0
                        }
                    }
                }

                // Add overlays in batches - metered zones first (bottom layer), then RPP zones (top layer)
                let batchSize = 500

                // Ordered polygons: metered first, then RPP (later additions render on top)
                let orderedPolygons = meteredPolygons + rppPolygons
                let totalPolygons = orderedPolygons.count

                func addBatch(startIndex: Int) {
                    let endIndex = min(startIndex + batchSize, totalPolygons)
                    let batch = Array(orderedPolygons[startIndex..<endIndex])

                    mapView.addOverlays(batch, level: .aboveRoads)

                    // Hide overlays if showOverlays is false
                    if !shouldShowOverlays {
                        for overlay in batch {
                            if let renderer = mapView.renderer(for: overlay) {
                                renderer.alpha = 0
                            }
                        }
                    }

                    if endIndex < totalPolygons {
                        // Schedule next batch with tiny delay to let UI breathe
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            addBatch(startIndex: endIndex)
                        }
                    } else {
                        let totalElapsed = (CFAbsoluteTimeGetCurrent() - mainStartTime) * 1000
                        logger.info("All \(totalPolygons) overlays added in \(String(format: "%.1f", totalElapsed))ms")
                        // Mark overlays as visible/hidden based on initial state
                        coordinator.overlaysCurrentlyVisible = shouldShowOverlays
                    }
                }

                // Start adding batches
                if !orderedPolygons.isEmpty {
                    addBatch(startIndex: 0)
                } else {
                    coordinator.overlaysCurrentlyVisible = shouldShowOverlays
                }

                let setupElapsed = (CFAbsoluteTimeGetCurrent() - mainStartTime) * 1000
                logger.info("Initial setup done in \(String(format: "%.1f", setupElapsed))ms - overlay batching started")
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
        context.coordinator.showOverlays = showOverlays

        // Handle overlay visibility changes
        let overlaysVisible = context.coordinator.overlaysCurrentlyVisible
        if showOverlays != overlaysVisible {
            if showOverlays {
                // Show overlays with slow fade animation when maximizing
                for overlay in mapView.overlays {
                    if let renderer = mapView.renderer(for: overlay) {
                        renderer.alpha = 0
                    }
                }
                for annotation in mapView.annotations where annotation is ZoneLabelAnnotation {
                    if let view = mapView.view(for: annotation) {
                        view.alpha = 0
                    }
                }
                // Slower fade in: 1.2s duration with 0.4s delay for smooth appearance
                UIView.animate(withDuration: 1.2, delay: 0.4, options: [.curveEaseOut]) {
                    for overlay in mapView.overlays {
                        if let renderer = mapView.renderer(for: overlay) {
                            renderer.alpha = 1
                        }
                    }
                    for annotation in mapView.annotations where annotation is ZoneLabelAnnotation {
                        if let view = mapView.view(for: annotation) {
                            view.alpha = 1
                        }
                    }
                }
            } else {
                // Hide overlays with fade out
                UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseIn]) {
                    for overlay in mapView.overlays {
                        if let renderer = mapView.renderer(for: overlay) {
                            renderer.alpha = 0
                        }
                    }
                    for annotation in mapView.annotations where annotation is ZoneLabelAnnotation {
                        if let view = mapView.view(for: annotation) {
                            view.alpha = 0
                        }
                    }
                }
            }
            context.coordinator.overlaysCurrentlyVisible = showOverlays
        }

        // Skip re-centering during initial setup (overlays are loading async)
        guard context.coordinator.initialSetupDone else {
            logger.debug("Skipping re-center - initial setup not done")
            return
        }

        // Calculate current desired region
        if let coord = userCoordinate {
            let baseSpan = 0.006
            let span = MKCoordinateSpan(
                latitudeDelta: baseSpan * zoomMultiplier,
                longitudeDelta: baseSpan * zoomMultiplier
            )
            let latOffset = span.latitudeDelta * verticalBias
            let biasedCenter = CLLocationCoordinate2D(
                latitude: coord.latitude + latOffset,
                longitude: coord.longitude
            )

            // Check if we need to update region (zoom/bias changed or moved significantly)
            let currentSpan = mapView.region.span
            let currentCenter = mapView.centerCoordinate
            let spanChanged = abs(currentSpan.latitudeDelta - span.latitudeDelta) > 0.0001
            let biasChanged = abs(context.coordinator.lastVerticalBias - verticalBias) > 0.01
            let distance = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                .distance(from: CLLocation(latitude: currentCenter.latitude - (currentSpan.latitudeDelta * context.coordinator.lastVerticalBias), longitude: currentCenter.longitude))

            if spanChanged || biasChanged || distance > 500 {
                logger.debug("Updating map region - spanChanged: \(spanChanged), biasChanged: \(biasChanged), distance: \(String(format: "%.0f", distance))m")
                let region = MKCoordinateRegion(center: biasedCenter, span: span)

                // Use slower animation (0.8s) for smooth transition when expanding/collapsing
                UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseInOut]) {
                    mapView.setRegion(region, animated: false)
                }

                context.coordinator.lastVerticalBias = verticalBias
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
            polygon.zoneType = zone.zoneType
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

        // Track overlay visibility state
        var showOverlays: Bool = true
        var overlaysCurrentlyVisible: Bool = false  // Start hidden, will be set true after initial load if showOverlays is true
        var lastVerticalBias: Double = 0.0

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

            // Use zone type-aware coloring for metered zones
            var fillColor: UIColor
            var strokeColor: UIColor
            if let zoneType = polygon.zoneType, zoneType == .metered {
                fillColor = ZoneColorProvider.fillColor(for: zoneType, isCurrentZone: isCurrentZone)
                strokeColor = ZoneColorProvider.strokeColor(for: zoneType, isCurrentZone: isCurrentZone)
            } else {
                fillColor = ZoneColorProvider.fillColor(for: polygon.zoneCode, isCurrentZone: isCurrentZone)
                strokeColor = ZoneColorProvider.strokeColor(for: polygon.zoneCode, isCurrentZone: isCurrentZone)
            }

            renderer.fillColor = fillColor
            renderer.strokeColor = strokeColor
            renderer.lineWidth = ZoneColorProvider.strokeWidth(isCurrentZone: isCurrentZone)

            // Multi-permit polygons get a dashed border and slightly different fill
            if polygon.isMultiPermit {
                renderer.lineDashPattern = [8, 4]  // Dashed line pattern
                renderer.lineWidth = isCurrentZone ? 4.0 : 2.5  // Thicker border
                // Slightly more saturated fill for multi-permit areas
                renderer.fillColor = fillColor.withAlphaComponent(0.35)
            }

            // Log first few and then every 1000th
            if rendererCallCount <= 5 || rendererCallCount % 1000 == 0 {
                let typeStr = polygon.zoneType?.rawValue ?? "rpp"
                let mpStr = polygon.isMultiPermit ? " [multi-permit]" : ""
                logger.debug("Renderer #\(self.rendererCallCount) - zoneCode: \(polygon.zoneCode ?? "nil"), type: \(typeStr)\(mpStr)")
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
                zoneType: zoneAnnotation.zoneType,
                isCurrentZone: isCurrentZone
            )

            // Remove old subviews and add new label
            annotationView?.subviews.forEach { $0.removeFromSuperview() }
            annotationView?.addSubview(labelView)
            annotationView?.frame = labelView.frame
            annotationView?.centerOffset = CGPoint(x: 0, y: 0)

            return annotationView
        }

        private func createZoneLabelView(code: String, zoneType: ZoneType?, isCurrentZone: Bool) -> UIView {
            let label = UILabel()
            label.text = code
            label.font = .systemFont(ofSize: isCurrentZone ? 16 : 12, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center

            let size: CGFloat = isCurrentZone ? 32 : 24
            label.frame = CGRect(x: 0, y: 0, width: size, height: size)

            let containerView = UIView(frame: label.frame)
            // Use zone type-aware coloring for metered zones
            if let zType = zoneType, zType == .metered {
                containerView.backgroundColor = ZoneColorProvider.color(for: zType)
            } else {
                containerView.backgroundColor = ZoneColorProvider.color(for: code)
            }
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
    var zoneType: ZoneType?
    var isMultiPermit: Bool = false  // True if this polygon accepts multiple permits
    var allValidPermitAreas: [String]?  // All valid permit areas for multi-permit polygons
}

/// Annotation for zone label display
class ZoneLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let zoneCode: String
    let zoneId: String
    let zoneType: ZoneType?

    init(coordinate: CLLocationCoordinate2D, zoneCode: String, zoneId: String, zoneType: ZoneType? = nil) {
        self.coordinate = coordinate
        self.zoneCode = zoneCode
        self.zoneId = zoneId
        self.zoneType = zoneType
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
