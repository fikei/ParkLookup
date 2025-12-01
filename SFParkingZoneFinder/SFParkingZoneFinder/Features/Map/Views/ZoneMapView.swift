import SwiftUI
import MapKit
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ZoneMapView")

/// MKMapView-based map with zone polygon overlays
/// Uses UIViewRepresentable to enable MKPolygonRenderer (not available in SwiftUI Map)
struct ZoneMapView: UIViewRepresentable {
    let zones: [ParkingZone]
    let currentZoneId: String?
    let userCoordinate: CLLocationCoordinate2D?
    let onZoneTapped: ((ParkingZone, [String]?, CLLocationCoordinate2D) -> Void)?  // Pass zone, permit areas, and tap coordinate
    let onMapTapped: ((CLLocationCoordinate2D) -> Void)?  // Generic tap callback (fires for any tap on map)

    /// User's valid permit areas (uppercase codes like "Q", "AA")
    /// Zones matching these will be colored green, others orange
    var userPermitAreas: Set<String> = []

    /// Developer settings hash - when this changes, overlays reload with new simplification
    var devSettingsHash: Int = DeveloperSettings.shared.settingsHash

    /// Reload trigger - when this changes, overlays reload (used for overlay toggle changes)
    var reloadTrigger: Int = DeveloperSettings.shared.reloadTrigger

    /// Vertical bias for user location position (0.0 = center, positive = user appears lower on screen)
    /// A value of 0.25 means the user appears at 75% from top (25% from bottom)
    var verticalBias: Double = 0.0

    /// Whether to show zone polygon overlays (false = clean map with just user location)
    var showOverlays: Bool = true

    /// Zoom multiplier (1.0 = default, smaller = more zoomed in, larger = more zoomed out)
    /// 0.8 = 20% more zoomed in
    var zoomMultiplier: Double = 1.0

    /// Coordinate from address search (shows a pin when set)
    var searchedCoordinate: CLLocationCoordinate2D? = nil

    /// Coordinate where user tapped on map (shows a blue dot when set)
    var tappedCoordinate: CLLocationCoordinate2D? = nil

    /// Toggle to force map recenter (for when coordinate doesn't change but we want to recenter anyway)
    var recenterTrigger: Bool = false

    /// When true, shows an overview of all of San Francisco (ignores user coordinate)
    var showSFOverview: Bool = false

    /// Validates a coordinate to ensure it won't cause NaN errors
    private func isValidCoordinate(_ coord: CLLocationCoordinate2D?) -> Bool {
        guard let c = coord else { return false }
        return c.latitude.isFinite && c.longitude.isFinite &&
               c.latitude >= -90 && c.latitude <= 90 &&
               c.longitude >= -180 && c.longitude <= 180
    }

    func makeUIView(context: Context) -> MKMapView {
        logger.info("🚀 BUILD VERIFICATION: makeUIView called with \(self.zones.count) zones - DUPLICATE FIX ACTIVE")

        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Set initial region
        let defaultCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let center: CLLocationCoordinate2D
        let desiredSpan: MKCoordinateSpan

        if showSFOverview {
            // Show overview of all of San Francisco
            // SF bounds: ~37.7 to 37.8 latitude, ~-122.52 to -122.35 longitude
            center = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            desiredSpan = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        } else {
            // Normal view: centered on user (zoomed to ~10-15 blocks)
            // 0.006 degrees ≈ 670m ≈ 8-10 SF blocks, adjusted by zoom multiplier
            let userCenter = isValidCoordinate(userCoordinate) ? userCoordinate! : defaultCenter
            let baseSpan = 0.006
            let span = MKCoordinateSpan(
                latitudeDelta: baseSpan * zoomMultiplier,
                longitudeDelta: baseSpan * zoomMultiplier
            )

            // Apply vertical bias: offset center northward to push user location down on screen
            // verticalBias of 0.25 means user appears at 75% from top (halfway between center and bottom)
            let latOffset = span.latitudeDelta * verticalBias
            center = CLLocationCoordinate2D(
                latitude: userCenter.latitude + latOffset,
                longitude: userCenter.longitude
            )
            desiredSpan = span
        }

        let region = MKCoordinateRegion(center: center, span: desiredSpan)
        mapView.setRegion(region, animated: false)

        // Store the desired region in coordinator so we can re-apply after overlays load
        context.coordinator.initialCenter = center
        context.coordinator.initialSpan = desiredSpan

        // Add tap gesture for zone selection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        // Note: Overlay loading is handled in updateUIView via loadOverlays() to avoid duplication


        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {

        // Update coordinator with current state
        context.coordinator.currentZoneId = currentZoneId
        context.coordinator.zones = zones
        context.coordinator.onZoneTapped = onZoneTapped
        context.coordinator.onMapTapped = onMapTapped
        context.coordinator.showOverlays = showOverlays

        // Debug logging to track permit changes
        logger.debug("🔍 updateUIView called: overlaysLoaded=\(context.coordinator.overlaysLoaded), userPermitAreas=\(Array(userPermitAreas).sorted()), lastUserPermitAreas=\(Array(context.coordinator.lastUserPermitAreas).sorted())")

        // Check if user permits changed - reload overlays if so
        if context.coordinator.overlaysLoaded && userPermitAreas != context.coordinator.lastUserPermitAreas {
            logger.info("🔄 User permits changed - reloading overlays (permits: \(Array(userPermitAreas)))")
            context.coordinator.userPermitAreas = userPermitAreas
            context.coordinator.lastUserPermitAreas = userPermitAreas

            // Clear existing overlays and annotations (except user location, searched pin, and parking meters)
            let overlaysToRemove = mapView.overlays
            let annotationsToRemove = mapView.annotations.filter { annotation in
                !(annotation is MKUserLocation) &&
                !(annotation is SearchedLocationAnnotation) &&
                !(annotation is ParkingMeterAnnotation)
            }
            mapView.removeOverlays(overlaysToRemove)
            mapView.removeAnnotations(annotationsToRemove)

            // Reload overlays (keep overlaysLoaded=true to prevent race condition)
            context.coordinator.overlaysCurrentlyVisible = false
            loadOverlays(mapView: mapView, context: context)

            // Reload parking meters (respects toggle state)
            loadParkingMeterAnnotations(mapView: mapView)
            return
        } else {
            // Update coordinator's permit areas (no reload needed)
            if context.coordinator.userPermitAreas != userPermitAreas {
                logger.debug("🔍 Updating coordinator userPermitAreas: \(Array(context.coordinator.userPermitAreas).sorted()) -> \(Array(userPermitAreas).sorted())")
            }
            context.coordinator.userPermitAreas = userPermitAreas
        }

        // Handle searched location annotation
        updateSearchedAnnotation(mapView: mapView, context: context)

        // Handle tapped location annotation (blue dot)
        updateTappedAnnotation(mapView: mapView, context: context)

        // Handle SF overview mode (zoom out to show all of San Francisco)
        if showSFOverview != context.coordinator.lastShowSFOverview {
            context.coordinator.lastShowSFOverview = showSFOverview
            if showSFOverview {
                logger.info("🗺️ Showing SF overview - zooming out to show all of San Francisco")
                let sfCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                let sfSpan = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                let region = MKCoordinateRegion(center: sfCenter, span: sfSpan)
                mapView.setRegion(region, animated: true)
                return
            }
        }

        // Check if user coordinate changed - recenter map if user returned to GPS location
        let coordinateChanged: Bool
        if let prevCoord = context.coordinator.lastUserCoordinate, let newCoord = userCoordinate {
            // Compare coordinates with small tolerance for floating point differences
            let latDiff = abs(prevCoord.latitude - newCoord.latitude)
            let lonDiff = abs(prevCoord.longitude - newCoord.longitude)
            coordinateChanged = latDiff > 0.00001 || lonDiff > 0.00001
        } else {
            coordinateChanged = (context.coordinator.lastUserCoordinate == nil) != (userCoordinate == nil)
        }

        // Check if recenter was explicitly triggered (even if coordinate didn't change)
        let recenterTriggered = recenterTrigger != context.coordinator.lastRecenterTrigger

        if (coordinateChanged || recenterTriggered) && isValidCoordinate(userCoordinate) {
            if recenterTriggered {
                logger.info("📍 Recenter triggered - forcing map recenter to (\(userCoordinate!.latitude), \(userCoordinate!.longitude))")
            } else {
                logger.info("📍 User coordinate changed - recentering map to (\(userCoordinate!.latitude), \(userCoordinate!.longitude))")
            }
            context.coordinator.lastUserCoordinate = userCoordinate
            context.coordinator.lastRecenterTrigger = recenterTrigger

            // Recenter map with animation
            let baseSpan = 0.006
            let desiredSpan = MKCoordinateSpan(
                latitudeDelta: baseSpan * zoomMultiplier,
                longitudeDelta: baseSpan * zoomMultiplier
            )

            // Apply vertical bias
            let latOffset = desiredSpan.latitudeDelta * verticalBias
            let center = CLLocationCoordinate2D(
                latitude: userCoordinate!.latitude + latOffset,
                longitude: userCoordinate!.longitude
            )

            let region = MKCoordinateRegion(center: center, span: desiredSpan)
            mapView.setRegion(region, animated: true)
        } else if !coordinateChanged && context.coordinator.lastUserCoordinate == nil && isValidCoordinate(userCoordinate) {
            // First time setting coordinate
            context.coordinator.lastUserCoordinate = userCoordinate
        }

        // Check if reload trigger changed - force reload if so
        let currentReloadTrigger = DeveloperSettings.shared.reloadTrigger
        if context.coordinator.overlaysLoaded && currentReloadTrigger != context.coordinator.lastReloadTrigger {
            logger.info("🔄 Manual refresh triggered - reloading overlays")
            context.coordinator.lastReloadTrigger = currentReloadTrigger

            // Clear existing overlays and annotations (except user location, searched pin, and parking meters)
            let overlaysToRemove = mapView.overlays
            let annotationsToRemove = mapView.annotations.filter { annotation in
                !(annotation is MKUserLocation) &&
                !(annotation is SearchedLocationAnnotation) &&
                !(annotation is ParkingMeterAnnotation)
            }
            mapView.removeOverlays(overlaysToRemove)
            mapView.removeAnnotations(annotationsToRemove)

            // Reload overlays (keep overlaysLoaded=true to prevent race condition)
            context.coordinator.overlaysCurrentlyVisible = false
            loadOverlays(mapView: mapView, context: context)

            // Reload parking meters (respects toggle state)
            loadParkingMeterAnnotations(mapView: mapView)
            return
        }

        // NOTE: Developer settings changes NO LONGER trigger automatic reload
        // User must click "Apply" button to apply changes (which increments reloadTrigger)
        // This prevents unwanted refreshes while user is adjusting multiple settings

        // Load overlays if they haven't been loaded yet but zones are now available
        if !context.coordinator.overlaysLoaded && !zones.isEmpty {
            logger.info("🎬 Initial overlay load: \(zones.count) zones (overlaysLoaded=\(context.coordinator.overlaysLoaded))")
            loadOverlays(mapView: mapView, context: context)
            return
        }

        // Log if this is just a parameter update (no overlay reload needed)
        if context.coordinator.overlaysLoaded {
            logger.debug("✓ Overlay parameters updated (no reload needed)")
        }

        // Handle overlay visibility changes
        let overlaysVisible = context.coordinator.overlaysCurrentlyVisible
        logger.debug("🔍 Visibility check: showOverlays=\(showOverlays), overlaysVisible=\(overlaysVisible), overlays.count=\(mapView.overlays.count)")
        if showOverlays != overlaysVisible {
            if showOverlays {
                logger.info("👁️ Showing overlays with fade-in animation (1.6s total), overlay count=\(mapView.overlays.count)")
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
                } completion: { _ in
                    logger.info("✅ Fade-in animation complete - overlays should be visible")
                }
            } else {
                logger.info("🙈 Hiding overlays with fade-out animation")
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
        guard context.coordinator.initialSetupDone else { return }

        // Calculate current desired region (only if coordinate is valid)
        if let coord = userCoordinate, isValidCoordinate(coord) {
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
                let region = MKCoordinateRegion(center: biasedCenter, span: span)

                // Use slow animation (1.4s) for smooth transition when expanding/collapsing
                UIView.animate(withDuration: 1.4, delay: 0, options: [.curveEaseInOut]) {
                    mapView.setRegion(region, animated: false)
                }

                context.coordinator.lastVerticalBias = verticalBias
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentZoneId: currentZoneId, zones: zones, onZoneTapped: onZoneTapped, onMapTapped: onMapTapped)
    }

    // MARK: - Overlap Clipping

    /// Apply overlap clipping to polygons (visual only - doesn't affect zone lookup)
    /// Priority rules: Metered > RPP, Vertical (N-S) > Horizontal (E-W)
    private static func applyOverlapClipping(_ polygons: [ZonePolygon], tolerance: Double) -> [ZonePolygon] {
        guard polygons.count > 1 else { return polygons }

        // Build polygon info for priority comparison
        var polygonInfos: [(polygon: ZonePolygon, info: PolygonInfo, coords: [CLLocationCoordinate2D])] = []

        for polygon in polygons {
            let coords = polygon.coordinates.map { $0 }
            guard coords.count >= 3 else { continue }

            let info = PolygonInfo(
                coords: coords,
                zoneId: polygon.zoneId ?? "",
                zoneCode: polygon.zoneCode,
                isMetered: polygon.zoneType == .metered
            )
            polygonInfos.append((polygon, info, coords))
        }

        // Find overlapping pairs and clip lower-priority polygons
        var resultCoords: [[CLLocationCoordinate2D]] = polygonInfos.map { $0.coords }

        for i in 0..<polygonInfos.count {
            for j in (i + 1)..<polygonInfos.count {
                let info1 = polygonInfos[i].info
                let info2 = polygonInfos[j].info

                // Skip if same zone
                guard info1.zoneId != info2.zoneId else { continue }

                // Check if bounding boxes overlap
                guard PolygonClipper.boundingBoxesOverlap(resultCoords[i], resultCoords[j], tolerance: tolerance) else {
                    continue
                }

                // Determine which polygon has priority
                if PolygonClipper.hasPriority(polygon1: info1, over: info2) {
                    // Polygon 1 wins - clip polygon 2
                    let clippedResults = PolygonClipper.subtractPolygon(subject: resultCoords[j], minus: resultCoords[i])
                    if let firstClipped = clippedResults.first, firstClipped.count >= 3 {
                        resultCoords[j] = firstClipped
                    }
                } else {
                    // Polygon 2 wins - clip polygon 1
                    let clippedResults = PolygonClipper.subtractPolygon(subject: resultCoords[i], minus: resultCoords[j])
                    if let firstClipped = clippedResults.first, firstClipped.count >= 3 {
                        resultCoords[i] = firstClipped
                    }
                }
            }
        }

        // Create new polygons with clipped coordinates
        var result: [ZonePolygon] = []
        for (index, (original, _, _)) in polygonInfos.enumerated() {
            let clippedCoords = resultCoords[index]
            guard clippedCoords.count >= 3 else { continue }

            let newPolygon = ZonePolygon(coordinates: clippedCoords, count: clippedCoords.count)
            newPolygon.zoneId = original.zoneId
            newPolygon.zoneCode = original.zoneCode
            newPolygon.zoneType = original.zoneType
            newPolygon.isMultiPermit = original.isMultiPermit
            newPolygon.allValidPermitAreas = original.allValidPermitAreas
            newPolygon.originalVertexCount = original.originalVertexCount

            result.append(newPolygon)
        }

        return result
    }

    /// Apply polygon merging for same-zone polygons (visual only)
    private static func applyPolygonMerging(
        _ polygons: [ZonePolygon],
        mergeOverlapping: Bool,
        useProximity: Bool,
        proximityMeters: Double,
        tolerance: Double
    ) -> [ZonePolygon] {
        guard polygons.count > 1 else { return polygons }

        // Group polygons by zone code for merging
        var byZoneCode: [String: [ZonePolygon]] = [:]
        for polygon in polygons {
            let key = polygon.zoneCode ?? polygon.zoneId ?? "unknown"
            if byZoneCode[key] == nil {
                byZoneCode[key] = []
            }
            byZoneCode[key]?.append(polygon)
        }

        var result: [ZonePolygon] = []

        for (_, zonePolygons) in byZoneCode {
            // If only one polygon in this zone, no merging needed
            guard zonePolygons.count > 1 else {
                result.append(contentsOf: zonePolygons)
                continue
            }

            // Build info for merging
            let polygonInfos: [(coords: [CLLocationCoordinate2D], zoneCode: String?, zoneId: String)] =
                zonePolygons.map { (coords: $0.coordinates, zoneCode: $0.zoneCode, zoneId: $0.zoneId ?? "") }

            var mergedCoords: [[CLLocationCoordinate2D]]

            if useProximity {
                // Use proximity-based merging
                mergedCoords = PolygonClipper.mergeByProximity(polygonInfos, distanceMeters: proximityMeters)
            } else if mergeOverlapping {
                // Use overlap-based merging
                mergedCoords = PolygonClipper.mergeOverlappingSameZone(polygonInfos, tolerance: tolerance)
            } else {
                // No merging - keep original
                result.append(contentsOf: zonePolygons)
                continue
            }

            // Create new polygons from merged coordinates
            // Use the first original polygon as a template for metadata
            let template = zonePolygons[0]

            for coords in mergedCoords {
                guard coords.count >= 3 else { continue }

                let newPolygon = ZonePolygon(coordinates: coords, count: coords.count)
                newPolygon.zoneId = template.zoneId
                newPolygon.zoneCode = template.zoneCode
                newPolygon.zoneType = template.zoneType
                newPolygon.isMultiPermit = template.isMultiPermit
                newPolygon.allValidPermitAreas = template.allValidPermitAreas
                newPolygon.originalVertexCount = coords.count

                result.append(newPolygon)
            }
        }

        return result
    }

    /// Buffer polygon to clean up self-intersecting edges and remove points that are too close together
    /// This helps fix triangulation failures caused by invalid geometry
    private static func bufferPolygon(
        _ coordinates: [CLLocationCoordinate2D],
        bufferDistance: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3 else { return coordinates }

        var cleaned: [CLLocationCoordinate2D] = []
        var previous: CLLocationCoordinate2D? = nil

        for coord in coordinates {
            // Skip points that are too close to the previous point
            if let prev = previous {
                let latDiff = abs(coord.latitude - prev.latitude)
                let lonDiff = abs(coord.longitude - prev.longitude)
                let distance = sqrt(latDiff * latDiff + lonDiff * lonDiff)

                // Only add if distance is greater than buffer distance
                if distance >= bufferDistance {
                    cleaned.append(coord)
                    previous = coord
                }
            } else {
                // Always add first point
                cleaned.append(coord)
                previous = coord
            }
        }

        // Ensure we have at least 3 points for a valid polygon
        return cleaned.count >= 3 ? cleaned : coordinates
    }

    /// Remove near-duplicate polygons that have high overlap (e.g., 95%+)
    /// Prevents double-rendering of essentially the same polygon
    private static func deduplicateOverlappingPolygons(
        _ polygons: [ZonePolygon],
        overlapThreshold: Double = 0.95
    ) -> [ZonePolygon] {
        guard polygons.count > 1 else { return polygons }

        var result: [ZonePolygon] = []
        var toRemove = Set<Int>()

        // Check each pair of polygons for high overlap
        for i in 0..<polygons.count {
            guard !toRemove.contains(i) else { continue }

            let poly1 = polygons[i]
            let coords1 = poly1.coordinates
            guard coords1.count >= 3 else { continue }

            for j in (i + 1)..<polygons.count {
                guard !toRemove.contains(j) else { continue }

                let poly2 = polygons[j]
                let coords2 = poly2.coordinates
                guard coords2.count >= 3 else { continue }

                // Only check polygons from the same zone
                guard poly1.zoneId == poly2.zoneId || poly1.zoneCode == poly2.zoneCode else {
                    continue
                }

                // Calculate bounding box overlap as a fast approximation
                let box1 = PolygonClipper.boundingBox(of: coords1)
                let box2 = PolygonClipper.boundingBox(of: coords2)

                // Calculate overlap area (intersection of bounding boxes)
                let overlapMinLat = max(box1.minLat, box2.minLat)
                let overlapMaxLat = min(box1.maxLat, box2.maxLat)
                let overlapMinLon = max(box1.minLon, box2.minLon)
                let overlapMaxLon = min(box1.maxLon, box2.maxLon)

                // Check if bounding boxes overlap
                guard overlapMinLat < overlapMaxLat && overlapMinLon < overlapMaxLon else {
                    continue
                }

                // Calculate areas
                let overlapArea = (overlapMaxLat - overlapMinLat) * (overlapMaxLon - overlapMinLon)
                let area1 = (box1.maxLat - box1.minLat) * (box1.maxLon - box1.minLon)
                let area2 = (box2.maxLat - box2.minLat) * (box2.maxLon - box2.minLon)
                let minArea = min(area1, area2)

                // If overlap is >= threshold of the smaller polygon, mark as duplicate
                if minArea > 0 && (overlapArea / minArea) >= overlapThreshold {
                    // Keep the one with fewer vertices (more simplified) or smaller area
                    if coords2.count < coords1.count || area2 < area1 {
                        toRemove.insert(i)
                        break  // poly1 is marked for removal, move to next i
                    } else {
                        toRemove.insert(j)
                    }
                }
            }
        }

        // Build result excluding removed polygons
        for i in 0..<polygons.count {
            if !toRemove.contains(i) {
                result.append(polygons[i])
            }
        }

        let removedCount = polygons.count - result.count
        if removedCount > 0 {
            logger.info("🔍 Removed \(removedCount) near-duplicate polygon(s) (≥\(Int(overlapThreshold * 100))% overlap)")
        }

        return result
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

    /// Updates the searched location annotation based on searchedCoordinate
    private func updateSearchedAnnotation(mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Remove existing searched annotation if coordinate changed or cleared
        if let existingAnnotation = coordinator.searchedAnnotation {
            // Check if we need to remove it (coordinate cleared or changed)
            if searchedCoordinate == nil {
                mapView.removeAnnotation(existingAnnotation)
                coordinator.searchedAnnotation = nil
            } else if let newCoord = searchedCoordinate,
                      abs(existingAnnotation.coordinate.latitude - newCoord.latitude) > 0.000001 ||
                      abs(existingAnnotation.coordinate.longitude - newCoord.longitude) > 0.000001 {
                // Coordinate changed - remove old annotation
                mapView.removeAnnotation(existingAnnotation)
                coordinator.searchedAnnotation = nil
            } else {
                // Same coordinate, nothing to do
                return
            }
        }

        // Add new annotation if we have a searched coordinate
        if let coord = searchedCoordinate, isValidCoordinate(coord) {
            let annotation = SearchedLocationAnnotation(coordinate: coord)
            mapView.addAnnotation(annotation)
            coordinator.searchedAnnotation = annotation
            logger.info("📍 Added searched location pin at (\(coord.latitude), \(coord.longitude))")
        }
    }

    private func updateTappedAnnotation(mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Remove existing tapped annotation if coordinate changed or cleared
        if let existingAnnotation = coordinator.tappedAnnotation {
            // Check if we need to remove it (coordinate cleared or changed)
            if tappedCoordinate == nil {
                mapView.removeAnnotation(existingAnnotation)
                coordinator.tappedAnnotation = nil
            } else if let newCoord = tappedCoordinate,
                      abs(existingAnnotation.coordinate.latitude - newCoord.latitude) > 0.000001 ||
                      abs(existingAnnotation.coordinate.longitude - newCoord.longitude) > 0.000001 {
                // Coordinate changed - remove old annotation
                mapView.removeAnnotation(existingAnnotation)
                coordinator.tappedAnnotation = nil
            } else {
                // Same coordinate, nothing to do
                return
            }
        }

        // Add new annotation if we have a tapped coordinate
        if let coord = tappedCoordinate, isValidCoordinate(coord) {
            let annotation = TappedLocationAnnotation(coordinate: coord)
            mapView.addAnnotation(annotation)
            coordinator.tappedAnnotation = annotation
            logger.info("📍 Added tapped location dot at (\(coord.latitude), \(coord.longitude))")
        }
    }

    // MARK: - Overlay Loading

    private func loadOverlays(mapView: MKMapView, context: Context) {
        let zonesToLoad = self.zones
        let shouldShowOverlays = self.showOverlays
        let coordinator = context.coordinator
        let devSettings = DeveloperSettings.shared

        logger.debug("🔧 loadOverlays called with shouldShowOverlays=\(shouldShowOverlays)")

        // Mark as loading started
        coordinator.isLoadingOverlays = true
        coordinator.overlayLoadingMessage = "Processing \(zonesToLoad.count) zones..."

        // Mark as loaded immediately to prevent race condition (multiple simultaneous loads)
        coordinator.overlaysLoaded = true
        coordinator.lastUserPermitAreas = userPermitAreas  // Initialize permit tracking
        logger.debug("🔧 loadOverlays: initialized lastUserPermitAreas=\(Array(userPermitAreas).sorted())")

        let defaultCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let userCenter = isValidCoordinate(userCoordinate) ? userCoordinate! : defaultCenter

        DispatchQueue.global(qos: .userInitiated).async {
            var polygons: [ZonePolygon] = []
            var annotations: [ZoneLabelAnnotation] = []
            var totalBoundaries = 0
            var totalInputPoints = 0
            var totalOutputPoints = 0

            // Filter radius for visible zones
            let filterRadius = 0.03   // ~3.3km - visible area
            let center = userCenter
            let minLat = center.latitude - filterRadius
            let maxLat = center.latitude + filterRadius
            let minLon = center.longitude - filterRadius
            let maxLon = center.longitude + filterRadius

            for zone in zonesToLoad {
                let zoneBoundaryCount = zone.allBoundaryCoordinates.count
                totalBoundaries += zoneBoundaryCount

                var nearbyBoundaries: [[CLLocationCoordinate2D]] = []

                for boundary in zone.allBoundaryCoordinates {
                    totalInputPoints += boundary.count

                    let hasNearbyPoint = boundary.contains { coord in
                        coord.latitude >= minLat && coord.latitude <= maxLat &&
                        coord.longitude >= minLon && coord.longitude <= maxLon
                    }

                    if hasNearbyPoint {
                        nearbyBoundaries.append(boundary)
                    }
                }

                // Apply simplification pipeline based on DeveloperSettings
                let multiPermitIndices = zone.multiPermitBoundaryIndices
                let allBoundaries = zone.allBoundaryCoordinates

                for boundary in nearbyBoundaries {
                    guard boundary.count >= 3 else { continue }

                    // Apply simplification if enabled
                    var displayBoundary = devSettings.isSimplificationEnabled
                        ? PolygonSimplifier.simplify(boundary, settings: devSettings)
                        : boundary

                    // Apply polygon buffering if enabled (cleans up self-intersections)
                    if devSettings.usePolygonBuffering {
                        displayBoundary = Self.bufferPolygon(displayBoundary, bufferDistance: devSettings.polygonBufferDistance)
                    }

                    guard displayBoundary.count >= 3 else { continue }

                    let polygon = ZonePolygon(coordinates: displayBoundary, count: displayBoundary.count)
                    polygon.zoneId = zone.id
                    polygon.zoneCode = zone.permitArea
                    polygon.zoneType = zone.zoneType
                    polygon.originalVertexCount = boundary.count

                    // Check if this boundary is multi-permit
                    if let firstCoord = boundary.first {
                        for (originalIndex, originalBoundary) in allBoundaries.enumerated() {
                            if let origFirst = originalBoundary.first,
                               abs(origFirst.latitude - firstCoord.latitude) < 0.000001 &&
                               abs(origFirst.longitude - firstCoord.longitude) < 0.000001 &&
                               multiPermitIndices.contains(originalIndex) {
                                polygon.isMultiPermit = true
                                polygon.allValidPermitAreas = zone.validPermitAreas(for: originalIndex)
                                logger.debug("  🎯 Multi-permit boundary matched: zone=\(zone.permitArea ?? "nil"), boundaryIndex=\(originalIndex), validAreas=\(polygon.allValidPermitAreas?.description ?? "nil")")
                                break
                            }
                        }
                    }

                    polygons.append(polygon)
                    totalOutputPoints += displayBoundary.count
                }

                // Create zone label annotation at centroid
                if !nearbyBoundaries.isEmpty {
                    let allNearbyPoints = nearbyBoundaries.flatMap { $0 }
                    if !allNearbyPoints.isEmpty {
                        let sumLat = allNearbyPoints.reduce(0.0) { $0 + $1.latitude }
                        let sumLon = allNearbyPoints.reduce(0.0) { $0 + $1.longitude }
                        let centroid = CLLocationCoordinate2D(
                            latitude: sumLat / Double(allNearbyPoints.count),
                            longitude: sumLon / Double(allNearbyPoints.count)
                        )
                        let annotation = ZoneLabelAnnotation(
                            coordinate: centroid,
                            zoneCode: zone.permitArea ?? zone.displayName,
                            zoneId: zone.id
                        )
                        annotations.append(annotation)
                    }
                }

            }

            // Log simplification stats if enabled
            if devSettings.logSimplificationStats && devSettings.isSimplificationEnabled {
                let reduction = totalInputPoints > 0 ? Double(totalInputPoints - totalOutputPoints) / Double(totalInputPoints) * 100 : 0
                logger.info("📐 Simplification: \(totalInputPoints) → \(totalOutputPoints) vertices (\(String(format: "%.1f", reduction))% reduction)")
            }

            // Apply overlap clipping if enabled (visual only)
            if devSettings.useOverlapClipping {
                let beforeCount = polygons.count
                polygons = Self.applyOverlapClipping(polygons, tolerance: devSettings.overlapTolerance)
                let afterCount = polygons.count
                let removed = beforeCount - afterCount
                if removed > 0 {
                    logger.info("🔪 Overlap clipping: \(beforeCount) → \(afterCount) polygons (\(removed) removed)")
                }
                DispatchQueue.main.async {
                    devSettings.polygonsRemovedByClipping = removed
                }
            } else {
                DispatchQueue.main.async {
                    devSettings.polygonsRemovedByClipping = 0
                }
            }

            // Apply polygon merging if enabled (visual only)
            if devSettings.mergeOverlappingSameZone || devSettings.useProximityMerging {
                let beforeCount = polygons.count
                polygons = Self.applyPolygonMerging(
                    polygons,
                    mergeOverlapping: devSettings.mergeOverlappingSameZone,
                    useProximity: devSettings.useProximityMerging,
                    proximityMeters: devSettings.proximityMergeDistance,
                    tolerance: devSettings.overlapTolerance
                )
                let afterCount = polygons.count
                let removed = beforeCount - afterCount
                if removed > 0 {
                    logger.info("🔗 Polygon merging: \(beforeCount) → \(afterCount) polygons (\(removed) merged)")
                }
                DispatchQueue.main.async {
                    devSettings.polygonsRemovedByMerging = removed
                }
            } else {
                DispatchQueue.main.async {
                    devSettings.polygonsRemovedByMerging = 0
                }
            }

            // Remove near-duplicate polygons to prevent double-rendering (if enabled)
            if devSettings.useDeduplication {
                let beforeDedup = polygons.count
                polygons = Self.deduplicateOverlappingPolygons(polygons, overlapThreshold: devSettings.deduplicationThreshold)
                let afterDedup = polygons.count
                let dedupRemoved = beforeDedup - afterDedup
                if dedupRemoved > 0 {
                    logger.info("🗑️ Deduplication: \(beforeDedup) → \(afterDedup) polygons (\(dedupRemoved) removed)")
                }
                DispatchQueue.main.async {
                    devSettings.polygonsRemovedByDeduplication = dedupRemoved
                    devSettings.totalZonesLoaded = zonesToLoad.count
                }
            } else {
                DispatchQueue.main.async {
                    devSettings.polygonsRemovedByDeduplication = 0
                    devSettings.totalZonesLoaded = zonesToLoad.count
                }
            }

            // Separate polygons by zone type and permit status for proper layering
            // Layer order (bottom to top): Metered → Non-Permitted RPP → Permitted RPP
            let meteredPolygons = polygons.filter { $0.zoneType == .metered }
            let nonPermittedPolygons = polygons.filter { polygon in
                guard polygon.zoneType != .metered else { return false }
                guard let zoneCode = polygon.zoneCode?.uppercased() else { return true }
                return !userPermitAreas.contains(zoneCode)
            }
            let permittedPolygons = polygons.filter { polygon in
                guard polygon.zoneType != .metered else { return false }
                guard let zoneCode = polygon.zoneCode?.uppercased() else { return false }
                return userPermitAreas.contains(zoneCode)
            }

            DispatchQueue.main.async {

                // Check if zone polygons should be shown (user setting)
                let showZonePolygons = devSettings.showZonePolygons

                // Set initial alpha based on coordinator's CURRENT showOverlays value
                // Coordinator is updated in updateUIView, so this reflects real-time state
                let initialAlpha: CGFloat = coordinator.showOverlays ? 1.0 : 0.0

                // Deduplicate annotations by zoneId to prevent duplicate pins
                logger.info("🔍 Deduplication: Total annotations before: \(annotations.count)")
                var seenZoneIds = Set<String>()
                let uniqueAnnotations = annotations.filter { annotation in
                    let zoneId = annotation.zoneId
                    if seenZoneIds.contains(zoneId) {
                        logger.info("  ❌ Duplicate zoneId=\(zoneId), skipping")
                        return false
                    }
                    seenZoneIds.insert(zoneId)
                    return true
                }
                logger.info("✅ Deduplication: Unique annotations after: \(uniqueAnnotations.count), removed \(annotations.count - uniqueAnnotations.count) duplicates")

                // Conditionally add annotations based on zone polygon visibility
                if showZonePolygons {
                    mapView.addAnnotations(uniqueAnnotations)

                    for annotation in uniqueAnnotations {
                        if let view = mapView.view(for: annotation) {
                            view.alpha = initialAlpha
                        }
                    }
                }

                let batchSize = 500
                // Ordered polygons: metered first, then non-permitted, then permitted (later additions render on top)
                // Only add zone polygons if user has enabled them in settings
                let orderedPolygons = showZonePolygons ? (meteredPolygons + nonPermittedPolygons + permittedPolygons) : []
                let totalPolygons = orderedPolygons.count

                if !showZonePolygons {
                    logger.info("📍 Zone polygons hidden (user setting)")
                }

                func addBatch(startIndex: Int) {
                    let endIndex = min(startIndex + batchSize, totalPolygons)
                    let batch = Array(orderedPolygons[startIndex..<endIndex])

                    mapView.addOverlays(batch, level: .aboveRoads)

                    // Set initial alpha
                    for overlay in batch {
                        if let renderer = mapView.renderer(for: overlay) {
                            renderer.alpha = initialAlpha
                        }
                    }

                    if endIndex < totalPolygons {
                        // Update loading progress for developer view
                        coordinator.overlayLoadingMessage = "Rendering overlays \(endIndex)/\(totalPolygons)..."

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            addBatch(startIndex: endIndex)
                        }
                    } else {
                        // Use coordinator's current showOverlays value
                        coordinator.overlaysCurrentlyVisible = coordinator.showOverlays
                        coordinator.overlaysLoaded = true
                        coordinator.isLoadingOverlays = false
                        coordinator.overlayLoadingMessage = ""
                        logger.info("Deferred overlays loaded: \(totalPolygons) polygons, visible=\(coordinator.showOverlays)")
                        // Update stats
                        devSettings.totalPolygonsRendered = totalPolygons
                    }
                }

                if !orderedPolygons.isEmpty {
                    addBatch(startIndex: 0)
                } else {
                    // Use coordinator's current showOverlays value
                    coordinator.overlaysCurrentlyVisible = coordinator.showOverlays
                    coordinator.overlaysLoaded = true
                    coordinator.isLoadingOverlays = false
                    coordinator.overlayLoadingMessage = ""
                }

                // Load blockface data and add overlays
                loadBlockfaceOverlays(mapView: mapView, isInitialLoad: true)

                // Load parking meter annotations
                loadParkingMeterAnnotations(mapView: mapView)
            }
        }
    }

    /// Load and render blockface data overlays (OPTIMIZED)
    /// - Parameters:
    ///   - mapView: The map view to add overlays to
    ///   - isInitialLoad: Whether this is the first load
    ///   - centerCoordinate: Optional center coordinate (uses map center if nil)
    private func loadBlockfaceOverlays(mapView: MKMapView, isInitialLoad: Bool = false, centerCoordinate: CLLocationCoordinate2D? = nil) {
        // Check feature flag - only load if enabled in developer settings
        let devSettings = DeveloperSettings.shared
        guard devSettings.showBlockfaceOverlays else {
            logger.debug("📍 Blockface overlays disabled (feature flag off)")
            return
        }

        // Determine center coordinate
        let loadCenter: CLLocationCoordinate2D
        if let center = centerCoordinate {
            loadCenter = center
        } else if isValidCoordinate(userCoordinate) {
            loadCenter = userCoordinate!
        } else {
            loadCenter = mapView.region.center
        }

        // Zoom to user location on initial load (or test area if no location)
        if isInitialLoad {
            logger.info("📍 Initial load with blockface overlays enabled - centering on user location")
            DispatchQueue.main.async {
                let blockfaceSpan = MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.008) // Larger initial view
                let blockfaceRegion = MKCoordinateRegion(center: loadCenter, span: blockfaceSpan)
                mapView.setRegion(blockfaceRegion, animated: true)
            }
        }

        // Load blockfaces asynchronously near the center coordinate
        Task {
            do {
                let startTime = Date()
                // Large radius for full viewport coverage
                let blockfaces = try await BlockfaceLoader.shared.loadBlockfacesNear(
                    coordinate: loadCenter,
                    radiusMeters: 3000,  // 3km radius for full viewport coverage
                    maxCount: 800       // Increased for dense areas
                )
                let elapsed = Date().timeIntervalSince(startTime)
                logger.info("📍 Loaded \(blockfaces.count) nearby blockfaces in \(String(format: "%.3f", elapsed))s")

                // Add blockface overlays to map on main thread
                await MainActor.run {
                    // Reset renderer counts before adding new overlays
                    if let coordinator = mapView.delegate as? Coordinator {
                        coordinator.blockfacePolygonCount = 0
                        coordinator.blockfacePolylineCount = 0
                    }

                    mapView.addBlockfaceOverlays(blockfaces)
                    logger.info("✅ Added \(blockfaces.count) blockface overlays to map")

                    // Log renderer count summary after a brief delay (renderers are created lazily)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if let coordinator = mapView.delegate as? Coordinator {
                            if coordinator.blockfacePolygonCount > 0 || coordinator.blockfacePolylineCount > 0 {
                                logger.info("📍 Created \(coordinator.blockfacePolygonCount) polygon renderers + \(coordinator.blockfacePolylineCount) polyline renderers")
                            }
                        }
                    }

                    // Update coordinator's last load center to prevent immediate reload
                    if let coordinator = mapView.delegate as? Coordinator {
                        coordinator.lastBlockfaceLoadCenter = loadCenter
                    }
                }
            } catch {
                logger.error("❌ Failed to load blockfaces: \(error.localizedDescription)")
            }
        }
    }

    /// Load and render parking meter annotations
    private func loadParkingMeterAnnotations(mapView: MKMapView) {
        // Check feature flag - only load if enabled in developer settings
        let devSettings = DeveloperSettings.shared
        guard devSettings.showParkingMeters else {
            logger.debug("🅿️ Parking meters disabled (feature flag off)")

            // Remove any existing parking meter annotations
            let existingMeters = mapView.annotations.compactMap { $0 as? ParkingMeterAnnotation }
            if !existingMeters.isEmpty {
                mapView.removeAnnotations(existingMeters)
                logger.info("🅿️ Removed \(existingMeters.count) parking meter annotations")
            }
            return
        }

        // Remove existing parking meter annotations first
        let existingMeters = mapView.annotations.compactMap { $0 as? ParkingMeterAnnotation }
        if !existingMeters.isEmpty {
            mapView.removeAnnotations(existingMeters)
        }

        do {
            let meters = try ParkingMeterLoader.shared.loadParkingMeters()
            logger.info("🅿️ Loaded \(meters.count) parking meters from dataset")

            // Filter meters within the current visible region to avoid overwhelming the map
            let visibleRegion = mapView.region
            let visibleMeters = meters.filter { meter in
                let coord = meter.coordinate
                let latDelta = abs(coord.latitude - visibleRegion.center.latitude)
                let lonDelta = abs(coord.longitude - visibleRegion.center.longitude)
                return latDelta <= visibleRegion.span.latitudeDelta / 2 &&
                       lonDelta <= visibleRegion.span.longitudeDelta / 2
            }

            // Create annotations for visible meters
            let annotations = visibleMeters.map { meter in
                ParkingMeterAnnotation(coordinate: meter.coordinate, meter: meter)
            }

            mapView.addAnnotations(annotations)
            logger.info("✅ Added \(annotations.count) parking meter annotations (filtered from \(meters.count) total)")
        } catch {
            logger.error("❌ Failed to load parking meters: \(error.localizedDescription)")
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var currentZoneId: String?
        var zones: [ParkingZone]
        var onZoneTapped: ((ParkingZone, [String]?, CLLocationCoordinate2D) -> Void)?
        var onMapTapped: ((CLLocationCoordinate2D) -> Void)?
        var userPermitAreas: Set<String> = []
        var lastUserPermitAreas: Set<String> = []  // Track previous permits to detect changes

        // Store initial region to re-apply after overlays load
        var initialCenter: CLLocationCoordinate2D?
        var initialSpan: MKCoordinateSpan?

        // Flag to indicate initial overlay loading is complete
        var initialSetupDone = false

        // Track overlay visibility state
        var showOverlays: Bool = true
        var overlaysCurrentlyVisible: Bool = false  // Start hidden, will be set true after initial load if showOverlays is true
        var overlaysLoaded: Bool = false  // Track whether overlays have been loaded
        var isLoadingOverlays: Bool = false  // Track whether overlays are currently being loaded/rendered

        // Blockface renderer counters for logging summary
        var blockfacePolygonCount: Int = 0
        var blockfacePolylineCount: Int = 0
        var overlayLoadingMessage: String = ""  // Detailed message for developer view
        var lastVerticalBias: Double = 0.0

        // Track the searched location annotation
        weak var searchedAnnotation: SearchedLocationAnnotation?

        // Track the tapped location annotation
        weak var tappedAnnotation: TappedLocationAnnotation?

        // Track developer settings hash to detect changes and refresh overlays
        var lastSettingsHash: Int = 0

        // Track reload trigger to detect manual refresh requests
        var lastReloadTrigger: Int = 0

        // Track last user coordinate to detect when user returns to GPS location
        var lastUserCoordinate: CLLocationCoordinate2D?

        // Track recenter trigger to force recentering even when coordinate doesn't change
        var lastRecenterTrigger: Bool = false

        // Track SF overview mode to detect changes
        var lastShowSFOverview: Bool = false

        // Track blockface overlay state to zoom to sample location when enabled
        var lastBlockfaceOverlaysEnabled: Bool = false

        // Track blockface loading for dynamic region updates
        var lastBlockfaceLoadCenter: CLLocationCoordinate2D?
        var isLoadingBlockfaces: Bool = false

        init(currentZoneId: String?, zones: [ParkingZone], onZoneTapped: ((ParkingZone, [String]?, CLLocationCoordinate2D) -> Void)?, onMapTapped: ((CLLocationCoordinate2D) -> Void)?) {
            self.currentZoneId = currentZoneId
            self.zones = zones
            self.onZoneTapped = onZoneTapped
            self.onMapTapped = onMapTapped
            self.lastSettingsHash = DeveloperSettings.shared.settingsHash
            self.lastReloadTrigger = DeveloperSettings.shared.reloadTrigger
            self.lastBlockfaceOverlaysEnabled = DeveloperSettings.shared.showBlockfaceOverlays
        }

        // MARK: - MKMapViewDelegate

        private var rendererCallCount = 0

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Handle perpendicular direction markers (debug visualization)
            if overlay is PerpendicularMarker {
                return PerpendicularMarkerRenderer(overlay: overlay)
            }

            // Handle blockface centerline polylines (debug visualization)
            if let blockfacePolyline = overlay as? BlockfacePolyline {
                blockfacePolylineCount += 1
                return BlockfacePolylineRenderer(polyline: blockfacePolyline, blockface: blockfacePolyline.blockface)
            }

            // Handle blockface polygons - check before ZonePolygon since BlockfacePolygon is also MKPolygon
            if let blockfacePolygon = overlay as? BlockfacePolygon,
               let blockface = blockfacePolygon.blockface {
                blockfacePolygonCount += 1
                return BlockfacePolygonRenderer(polygon: blockfacePolygon, blockface: blockface)
            }

            guard let polygon = overlay as? ZonePolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }

            rendererCallCount += 1
            polygon.overlayNumber = rendererCallCount  // Store overlay number for debug display

            // Validate polygon before rendering
            let pointCount = polygon.pointCount
            if pointCount < 3 {
                logger.warning("⚠️ Skipping invalid polygon (< 3 points): zoneId=\(polygon.zoneId ?? "nil"), points=\(pointCount)")
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            let isCurrentZone = polygon.zoneId == currentZoneId
            let devSettings = DeveloperSettings.shared

            // DEBUG: Log rendering details
            logger.debug("🎨 Rendering overlay #\(self.rendererCallCount): zoneId=\(polygon.zoneId ?? "nil"), zoneCode=\(polygon.zoneCode ?? "nil"), zoneType=\(String(describing: polygon.zoneType)), isMultiPermit=\(polygon.isMultiPermit), points=\(pointCount), isCurrentZone=\(isCurrentZone)")

            // Determine zone category and get appropriate color/opacity
            var baseColor: UIColor
            var fillOpacity: Double
            var strokeOpacity: Double
            let zoneType = polygon.zoneType ?? .residentialPermit

            if zoneType == .metered {
                // Paid Zones (metered parking)
                baseColor = devSettings.paidZonesColor
                fillOpacity = devSettings.paidZonesFillOpacity
                strokeOpacity = devSettings.paidZonesStrokeOpacity
                logger.debug("  → Category: Paid Zone, color=\(devSettings.paidZonesColorHex), fillOpacity=\(fillOpacity), strokeOpacity=\(strokeOpacity)")
            } else if let zoneCode = polygon.zoneCode?.uppercased(),
                      userPermitAreas.contains(zoneCode) {
                // My Permit Zones (user has permit)
                baseColor = devSettings.myPermitZonesColor
                fillOpacity = devSettings.myPermitZonesFillOpacity
                strokeOpacity = devSettings.myPermitZonesStrokeOpacity
                logger.debug("  → Category: My Permit Zone, color=\(devSettings.myPermitZonesColorHex), fillOpacity=\(fillOpacity), strokeOpacity=\(strokeOpacity)")
            } else if zoneType == .residentialPermit {
                // Free Timed Zones (RPP zones without permit)
                baseColor = devSettings.freeTimedZonesColor
                fillOpacity = devSettings.freeTimedZonesFillOpacity
                strokeOpacity = devSettings.freeTimedZonesStrokeOpacity
                logger.debug("  → Category: Free Timed Zone, color=\(devSettings.freeTimedZonesColorHex), fillOpacity=\(fillOpacity), strokeOpacity=\(strokeOpacity)")
            } else {
                // Fallback
                baseColor = ZoneColorProvider.color(for: zoneType)
                fillOpacity = 0.20
                strokeOpacity = 0.6
                logger.debug("  → Category: Fallback, fillOpacity=\(fillOpacity), strokeOpacity=\(strokeOpacity)")
            }

            // Override opacity if this is the current zone (user is inside)
            if isCurrentZone {
                fillOpacity = devSettings.currentZoneFillOpacity
                strokeOpacity = devSettings.currentZoneStrokeOpacity
                logger.debug("  → Current Zone Override: fillOpacity=\(fillOpacity), strokeOpacity=\(strokeOpacity)")
            }

            // Apply fill and stroke colors with opacity
            renderer.fillColor = baseColor.withAlphaComponent(CGFloat(fillOpacity))
            renderer.strokeColor = baseColor.withAlphaComponent(CGFloat(strokeOpacity))
            renderer.lineWidth = CGFloat(devSettings.strokeWidth)

            // Multi-permit polygons: Always apply dashed border and set color based on permit match
            if polygon.isMultiPermit {
                // ALWAYS apply dash pattern to multi-permit zones (user can control density with dashLength)
                let dashLength = max(devSettings.dashLength, 5.0) // Minimum dash length of 5 if not set
                renderer.lineDashPattern = [NSNumber(value: dashLength), NSNumber(value: dashLength * 0.5)]

                // Check if any of the multi-permit areas match user's permits
                var matchesUserPermit = false
                if let multiPermitAreas = polygon.allValidPermitAreas {
                    logger.debug("  🔍 Multi-Permit Check: zone=\(polygon.zoneCode ?? "nil"), multiPermitAreas=\(multiPermitAreas), userPermitAreas=\(Array(self.userPermitAreas))")
                    matchesUserPermit = multiPermitAreas.contains { self.userPermitAreas.contains($0.uppercased()) }
                } else {
                    logger.debug("  🔍 Multi-Permit Check: zone=\(polygon.zoneCode ?? "nil"), allValidPermitAreas=nil, userPermitAreas=\(Array(self.userPermitAreas))")
                }

                if matchesUserPermit {
                    // User has a valid permit for this multi-permit zone → GREEN
                    let userColor = devSettings.myPermitZonesColor
                    let userFillOpacity = isCurrentZone ? devSettings.currentZoneFillOpacity : devSettings.myPermitZonesFillOpacity
                    let userStrokeOpacity = isCurrentZone ? devSettings.currentZoneStrokeOpacity : devSettings.myPermitZonesStrokeOpacity
                    renderer.fillColor = userColor.withAlphaComponent(CGFloat(userFillOpacity))
                    renderer.strokeColor = userColor.withAlphaComponent(CGFloat(userStrokeOpacity))
                    logger.debug("  → Multi-Permit Zone (WITH user permit): GREEN, dashed")
                } else {
                    // User does NOT have a valid permit for this multi-permit zone → ORANGE
                    let orangeColor = devSettings.freeTimedZonesColor
                    let orangeFillOpacity = isCurrentZone ? devSettings.currentZoneFillOpacity : devSettings.freeTimedZonesFillOpacity
                    let orangeStrokeOpacity = isCurrentZone ? devSettings.currentZoneStrokeOpacity : devSettings.freeTimedZonesStrokeOpacity
                    renderer.fillColor = orangeColor.withAlphaComponent(CGFloat(orangeFillOpacity))
                    renderer.strokeColor = orangeColor.withAlphaComponent(CGFloat(orangeStrokeOpacity))
                    logger.debug("  → Multi-Permit Zone (WITHOUT user permit): ORANGE, dashed")
                }
            }

            // Override with purple color if showing lookup boundaries
            if devSettings.showLookupBoundaries {
                let purpleColor = UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0)  // Purple
                let opacity = CGFloat(devSettings.lookupBoundaryOpacity)
                renderer.fillColor = purpleColor.withAlphaComponent(opacity * 0.5)  // Lighter fill
                renderer.strokeColor = purpleColor.withAlphaComponent(opacity)  // Stronger stroke
                renderer.lineWidth = 2.0  // Thicker line for visibility
                logger.debug("  → Lookup Boundary Override: PURPLE, opacity=\(devSettings.lookupBoundaryOpacity)")
            }

            // Set renderer alpha based on current visibility state
            // This ensures overlays respect the showOverlays state when rendered
            renderer.alpha = showOverlays ? 1.0 : 0.0

            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Use default MKUserLocation view (blue pulsing dot)
            if annotation is MKUserLocation {
                return nil
            }

            // Handle searched location annotation (blue pin, no label)
            if let searchedAnnotation = annotation as? SearchedLocationAnnotation {
                let identifier = "SearchedLocation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: searchedAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                    annotationView?.markerTintColor = .systemBlue
                    annotationView?.glyphImage = UIImage(systemName: "mappin")
                    annotationView?.titleVisibility = .hidden
                    annotationView?.displayPriority = .required
                } else {
                    annotationView?.annotation = searchedAnnotation
                }

                return annotationView
            }

            // Handle tapped location annotation (blue dot, smaller than pin)
            if let tappedAnnotation = annotation as? TappedLocationAnnotation {
                let identifier = "TappedLocation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: tappedAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                    annotationView?.markerTintColor = .systemBlue
                    annotationView?.glyphImage = nil  // No glyph, just a solid dot
                    annotationView?.titleVisibility = .hidden
                    annotationView?.displayPriority = .required
                } else {
                    annotationView?.annotation = tappedAnnotation
                }

                return annotationView
            }

            // Handle parking meter annotation
            if let meterAnnotation = annotation as? ParkingMeterAnnotation {
                let identifier = "ParkingMeter"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

                // Only show callout in developer mode
                let showCallout = DeveloperSettings.shared.developerModeUnlocked

                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: meterAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = showCallout
                    annotationView?.markerTintColor = meterAnnotation.meter.isActive ? .systemGreen : .systemGray
                    annotationView?.glyphImage = UIImage(systemName: "parkingsign.circle.fill")
                    annotationView?.displayPriority = .defaultLow
                    annotationView?.glyphTintColor = .white
                } else {
                    annotationView?.annotation = meterAnnotation
                    annotationView?.canShowCallout = showCallout
                    annotationView?.markerTintColor = meterAnnotation.meter.isActive ? .systemGreen : .systemGray
                }

                return annotationView
            }

            // Handle blockface label annotation (colored pin, no text)
            if let blockfaceAnnotation = annotation as? BlockfaceLabelAnnotation {
                let identifier = "BlockfaceLabel"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: blockfaceAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false  // Never show callout
                    annotationView?.markerTintColor = blockfaceAnnotation.pinColor
                    annotationView?.glyphImage = nil  // No glyph, just colored pin
                    annotationView?.displayPriority = .required
                } else {
                    annotationView?.annotation = blockfaceAnnotation
                    annotationView?.markerTintColor = blockfaceAnnotation.pinColor
                }

                return annotationView
            }

            // Handle zone label annotation - HIDDEN for now
            if annotation is ZoneLabelAnnotation {
                return nil  // Don't display zone circles
            }

            return nil
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

        /// Calculate blockface pin color based on regulations (matches BlockfacePolygonRenderer logic)
        private func colorForBlockface(_ blockface: Blockface) -> UIColor {
            if blockface.regulations.isEmpty {
                // No restrictions = free parking → Green
                return UIColor.systemGreen
            }

            // Check regulation types to determine color (priority order)
            var hasActiveStreetCleaning = false
            var hasMetered = false
            var hasRPP = false
            var hasTimeLimit = false
            var hasNoParking = false

            let now = Date()
            let calendar = Calendar.current
            // Check within next 2 hours for "park until" window
            let parkUntilWindow = calendar.date(byAdding: .hour, value: 2, to: now) ?? now

            for reg in blockface.regulations {
                let regType = reg.type.lowercased()

                if regType == "noparking" || regType == "no parking" {
                    hasNoParking = true
                }
                if regType == "streetcleaning" || regType == "street cleaning" {
                    // Only consider street cleaning if active NOW or within park-until window
                    if isStreetCleaningActiveForColor(regulation: reg, at: now, untilDate: parkUntilWindow) {
                        hasActiveStreetCleaning = true
                    }
                }
                if regType == "metered" || regType == "meter" {
                    hasMetered = true
                }
                if let permitZone = reg.permitZone, !permitZone.isEmpty {
                    hasRPP = true
                }
                if regType == "timelimit" || regType == "time limit" {
                    hasTimeLimit = true
                }
            }

            // Priority: No Parking > Active Street Cleaning > Metered > Time Limited/RPP
            if hasNoParking {
                return UIColor.systemRed
            } else if hasActiveStreetCleaning {
                return UIColor.systemRed
            } else if hasMetered {
                return UIColor.systemGray
            } else if hasTimeLimit || hasRPP {
                return UIColor.systemOrange
            } else {
                return UIColor.systemGreen
            }
        }

        /// Check if street cleaning is active now or will be active within the park-until window
        private func isStreetCleaningActiveForColor(regulation: BlockfaceRegulation, at date: Date, untilDate: Date) -> Bool {
            guard let daysStr = regulation.enforcementDays,
                  let startStr = regulation.enforcementStart,
                  let endStr = regulation.enforcementEnd else {
                return false
            }

            // Parse time strings (HH:MM format)
            func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
                let components = timeStr.split(separator: ":").compactMap { Int($0) }
                guard components.count == 2 else { return nil }
                return (hour: components[0], minute: components[1])
            }

            guard let startTime = parseTime(startStr),
                  let endTime = parseTime(endStr) else {
                return false
            }

            // Convert string days to check
            let cleaningDays = daysStr.compactMap { dayStr -> Int? in
                let dayLower = dayStr.lowercased()
                switch dayLower {
                case "sunday", "sun": return 1
                case "monday", "mon": return 2
                case "tuesday", "tue", "tues": return 3
                case "wednesday", "wed": return 4
                case "thursday", "thu", "thurs": return 5
                case "friday", "fri": return 6
                case "saturday", "sat": return 7
                default: return nil
                }
            }

            let calendar = Calendar.current

            // Check if active on current date
            let currentWeekday = calendar.component(.weekday, from: date)
            if cleaningDays.contains(currentWeekday) {
                // Check time range
                guard let todayStart = calendar.date(bySettingHour: startTime.hour, minute: startTime.minute, second: 0, of: date),
                      let todayEnd = calendar.date(bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: date) else {
                    return false
                }

                if date >= todayStart && date <= todayEnd {
                    return true  // Active right now
                }

                // Check if will be active before untilDate
                if untilDate > todayStart && date < todayStart {
                    return true  // Will be active soon
                }
            }

            // Check next day if within untilDate window
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: date) {
                let nextWeekday = calendar.component(.weekday, from: nextDay)
                if cleaningDays.contains(nextWeekday) {
                    guard let nextStart = calendar.date(bySettingHour: startTime.hour, minute: startTime.minute, second: 0, of: nextDay) else {
                        return false
                    }

                    if nextStart <= untilDate {
                        return true  // Will be active tomorrow within window
                    }
                }
            }

            return false
        }

        private func createBlockfaceCalloutView(for blockface: Blockface) -> UIView {
            let containerView = UIView()
            containerView.translatesAutoresizingMaskIntoConstraints = false

            // Street name (bold)
            let streetLabel = UILabel()
            streetLabel.text = blockface.street
            streetLabel.font = .systemFont(ofSize: 16, weight: .bold)
            streetLabel.translatesAutoresizingMaskIntoConstraints = false

            // Segment info (from → to)
            let segmentLabel = UILabel()
            if let from = blockface.fromStreet, let to = blockface.toStreet {
                segmentLabel.text = "\(from) → \(to)"
            } else {
                segmentLabel.text = "Unknown segment"
            }
            segmentLabel.font = .systemFont(ofSize: 14)
            segmentLabel.textColor = .secondaryLabel
            segmentLabel.translatesAutoresizingMaskIntoConstraints = false

            // Side info
            let sideLabel = UILabel()
            let sideName: String
            switch blockface.side {
            case "EVEN":
                sideName = "West side"
            case "ODD":
                sideName = "East side"
            case "NORTH":
                sideName = "North side"
            case "SOUTH":
                sideName = "South side"
            default:
                sideName = "\(blockface.side) side"
            }
            sideLabel.text = sideName
            sideLabel.font = .systemFont(ofSize: 14)
            sideLabel.textColor = .secondaryLabel
            sideLabel.translatesAutoresizingMaskIntoConstraints = false

            // Regulations (if any)
            let regulationsStack = UIStackView()
            regulationsStack.axis = .vertical
            regulationsStack.spacing = 4
            regulationsStack.translatesAutoresizingMaskIntoConstraints = false

            if !blockface.regulations.isEmpty {
                // Regulations header
                let regHeader = UILabel()
                regHeader.text = "Regulations:"
                regHeader.font = .systemFont(ofSize: 14, weight: .semibold)
                regHeader.translatesAutoresizingMaskIntoConstraints = false
                regulationsStack.addArrangedSubview(regHeader)

                // Add each regulation
                for reg in blockface.regulations {
                    let regLabel = UILabel()
                    regLabel.text = "• \(reg.description)"
                    regLabel.font = .systemFont(ofSize: 13)
                    regLabel.numberOfLines = 0  // Allow wrapping
                    regLabel.translatesAutoresizingMaskIntoConstraints = false
                    regulationsStack.addArrangedSubview(regLabel)
                }
            } else {
                let noRegLabel = UILabel()
                noRegLabel.text = "No parking regulations"
                noRegLabel.font = .systemFont(ofSize: 13)
                noRegLabel.textColor = .tertiaryLabel
                noRegLabel.translatesAutoresizingMaskIntoConstraints = false
                regulationsStack.addArrangedSubview(noRegLabel)
            }

            // Add all subviews
            containerView.addSubview(streetLabel)
            containerView.addSubview(segmentLabel)
            containerView.addSubview(sideLabel)
            containerView.addSubview(regulationsStack)

            // Layout constraints
            NSLayoutConstraint.activate([
                // Street label
                streetLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
                streetLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
                streetLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

                // Segment label
                segmentLabel.topAnchor.constraint(equalTo: streetLabel.bottomAnchor, constant: 2),
                segmentLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
                segmentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

                // Side label
                sideLabel.topAnchor.constraint(equalTo: segmentLabel.bottomAnchor, constant: 2),
                sideLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
                sideLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

                // Regulations stack
                regulationsStack.topAnchor.constraint(equalTo: sideLabel.bottomAnchor, constant: 8),
                regulationsStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
                regulationsStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
                regulationsStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),

                // Container width
                containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
                containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
            ])

            return containerView
        }

        // MARK: - Tap Handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            // Check blockface polygons first (higher priority when blockface mode is active)
            for overlay in mapView.overlays {
                if let blockfacePolygon = overlay as? BlockfacePolygon,
                   let blockface = blockfacePolygon.blockface,
                   let renderer = mapView.renderer(for: blockfacePolygon) as? MKPolygonRenderer {

                    let mapPoint = MKMapPoint(coordinate)
                    let polygonPoint = renderer.point(for: mapPoint)

                    if renderer.path?.contains(polygonPoint) == true {
                        // Found tapped blockface
                        // Build detailed label with street, side, and regulations
                        var labelLines: [String] = []

                        // Line 1: Street name and segment
                        let streetLine = "\(blockface.street)"
                        let segmentLine = "(\(blockface.fromStreet ?? "?") to \(blockface.toStreet ?? "?"))"
                        labelLines.append(streetLine)
                        labelLines.append(segmentLine)

                        // Line 2: Side
                        let sideName: String
                        switch blockface.side {
                        case "EVEN":
                            sideName = "West side"
                        case "ODD":
                            sideName = "East side"
                        case "NORTH":
                            sideName = "North side"
                        case "SOUTH":
                            sideName = "South side"
                        default:
                            sideName = "\(blockface.side) side"
                        }
                        labelLines.append(sideName)

                        // Lines 3+: Regulations
                        if !blockface.regulations.isEmpty {
                            labelLines.append("") // Blank line separator
                            for reg in blockface.regulations {
                                labelLines.append("• \(reg.description)")
                            }
                        } else {
                            labelLines.append("")
                            labelLines.append("No parking regulations")
                        }

                        let label = labelLines.joined(separator: "\n")
                        logger.info("📍 Tapped blockface: \(blockface.street) \(sideName)")

                        // Only show annotation in developer mode
                        if DeveloperSettings.shared.developerModeUnlocked {
                            // Calculate color for pin
                            let pinColor = colorForBlockface(blockface)

                            // Add temporary annotation to show blockface info
                            let annotation = BlockfaceLabelAnnotation(
                                coordinate: coordinate,
                                label: label,
                                blockface: blockface,
                                pinColor: pinColor
                            )

                            // Remove any existing blockface label annotations
                            let existingLabels = mapView.annotations.compactMap { $0 as? BlockfaceLabelAnnotation }
                            mapView.removeAnnotations(existingLabels)

                            // Add new annotation
                            mapView.addAnnotation(annotation)
                        }

                        // Trigger generic map tap callback (updates spot card)
                        onMapTapped?(coordinate)

                        return
                    }
                }
            }

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
                        // Pass the zone, permit areas, and tap coordinate
                        onZoneTapped?(zone, polygon.allValidPermitAreas, coordinate)

                        // Trigger generic map tap callback (updates spot card)
                        onMapTapped?(coordinate)
                    }

                    // Store overlay debug info if developer mode is active
                    let devSettings = DeveloperSettings.shared
                    if devSettings.developerModeUnlocked {
                        devSettings.tappedOverlayNumber = polygon.overlayNumber
                        devSettings.tappedZoneId = polygon.zoneId ?? ""
                        devSettings.tappedZoneCode = polygon.zoneCode ?? ""
                        devSettings.tappedIsMultiPermit = polygon.isMultiPermit
                        devSettings.tappedVertexCount = polygon.pointCount
                        logger.debug("📍 Tapped overlay #\(polygon.overlayNumber): zone=\(polygon.zoneCode ?? "nil"), vertices=\(polygon.pointCount), multiPermit=\(polygon.isMultiPermit)")
                    }

                    return
                }
            }

            // If blockface mode is enabled and no direct hit, find nearest blockface
            if DeveloperSettings.shared.showBlockfaceOverlays {
                var nearestBlockface: (blockface: Blockface, distance: Double)?
                let tappedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

                for overlay in mapView.overlays {
                    if let blockfacePolygon = overlay as? BlockfacePolygon,
                       let blockface = blockfacePolygon.blockface {

                        // Calculate distance to blockface centerline
                        let coords = blockface.geometry.locationCoordinates
                        guard !coords.isEmpty else { continue }

                        // Find minimum distance to any point on the blockface
                        var minDistance = Double.infinity
                        for coord in coords {
                            let blockfacePoint = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                            let distance = tappedLocation.distance(from: blockfacePoint)
                            if distance < minDistance {
                                minDistance = distance
                            }
                        }

                        // Track nearest blockface (within 100m radius)
                        if minDistance <= 100 {
                            if nearestBlockface == nil || minDistance < nearestBlockface!.distance {
                                nearestBlockface = (blockface, minDistance)
                            }
                        }
                    }
                }

                // If found a nearby blockface, highlight it
                if let nearest = nearestBlockface {
                    // Build label for nearest blockface
                    var labelLines: [String] = []

                    let streetLine = "\(nearest.blockface.street)"
                    let segmentLine = "(\(nearest.blockface.fromStreet ?? "?") to \(nearest.blockface.toStreet ?? "?"))"
                    labelLines.append(streetLine)
                    labelLines.append(segmentLine)

                    let sideName: String
                    switch nearest.blockface.side {
                    case "EVEN":
                        sideName = "West side"
                    case "ODD":
                        sideName = "East side"
                    case "NORTH":
                        sideName = "North side"
                    case "SOUTH":
                        sideName = "South side"
                    default:
                        sideName = "\(nearest.blockface.side) side"
                    }
                    labelLines.append(sideName)
                    labelLines.append("(\(Int(nearest.distance))m away)")

                    if !nearest.blockface.regulations.isEmpty {
                        labelLines.append("")
                        for reg in nearest.blockface.regulations {
                            labelLines.append("• \(reg.description)")
                        }
                    } else {
                        labelLines.append("")
                        labelLines.append("No parking regulations")
                    }

                    let label = labelLines.joined(separator: "\n")
                    logger.info("📍 Tapped near blockface: \(nearest.blockface.street) \(sideName) (\(Int(nearest.distance))m)")

                    // Only show annotation in developer mode
                    if DeveloperSettings.shared.developerModeUnlocked {
                        // Use the blockface's center point for the annotation (not tap point)
                        let coords = nearest.blockface.geometry.locationCoordinates
                        let centerIndex = coords.count / 2
                        let blockfaceCenter = coords[centerIndex]

                        // Calculate color for pin
                        let pinColor = colorForBlockface(nearest.blockface)

                        let annotation = BlockfaceLabelAnnotation(
                            coordinate: blockfaceCenter,
                            label: label,
                            blockface: nearest.blockface,
                            pinColor: pinColor
                        )

                        // Remove existing blockface labels
                        let existingLabels = mapView.annotations.compactMap { $0 as? BlockfaceLabelAnnotation }
                        mapView.removeAnnotations(existingLabels)

                        // Add annotation at blockface center
                        mapView.addAnnotation(annotation)
                    }

                    // Trigger map tap callback (updates spot card)
                    onMapTapped?(coordinate)

                    return
                }
            }

            // No zone or blockface found - still trigger callback to show tapped location
            onMapTapped?(coordinate)
        }

        // MARK: - Region Change Handling

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Check if blockface overlays are enabled
            guard DeveloperSettings.shared.showBlockfaceOverlays else { return }

            // Don't reload if already loading
            guard !isLoadingBlockfaces else { return }

            let currentCenter = mapView.region.center

            // Check if we should reload blockfaces (user has moved significantly)
            var shouldReload = false

            if let lastCenter = lastBlockfaceLoadCenter {
                // Calculate distance from last load center
                let lastLocation = CLLocation(latitude: lastCenter.latitude, longitude: lastCenter.longitude)
                let currentLocation = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                let distance = lastLocation.distance(from: currentLocation)

                // Reload if moved more than 1km from last load (larger threshold to reduce reloads)
                if distance > 1000 {
                    shouldReload = true
                }
            } else {
                // No previous load, should load
                shouldReload = true
            }

            guard shouldReload else { return }

            // Mark as loading and update last center
            isLoadingBlockfaces = true
            lastBlockfaceLoadCenter = currentCenter

            // Load blockfaces for new region (async)
            Task { @MainActor in
                do {
                    let blockfaces = try await BlockfaceLoader.shared.loadBlockfacesNear(
                        coordinate: currentCenter,
                        radiusMeters: 3000,  // Same as initial load
                        maxCount: 800
                    )

                    // Remove existing blockface overlays
                    let existingBlockfaces = mapView.overlays.compactMap { $0 as? BlockfacePolygon }
                    let existingPolylines = mapView.overlays.compactMap { $0 as? BlockfacePolyline }
                    mapView.removeOverlays(existingBlockfaces)
                    mapView.removeOverlays(existingPolylines)

                    // Add new blockfaces
                    mapView.addBlockfaceOverlays(blockfaces)

                    print("🔄 Dynamically loaded \(blockfaces.count) blockfaces for new region")
                } catch {
                    print("❌ Failed to load blockfaces for new region: \(error)")
                }

                // Mark as done loading
                isLoadingBlockfaces = false
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
    var originalVertexCount: Int = 0  // For debug: original vertex count before simplification
    var overlayNumber: Int = 0  // For debug: rendering order number (overlay #)

    /// Extract coordinates from polygon points
    var coordinates: [CLLocationCoordinate2D] {
        let points = self.points()
        return (0..<pointCount).map { index in
            MKMapPoint(x: points[index].x, y: points[index].y).coordinate
        }
    }
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

/// Annotation for searched address location (shows a pin)
class SearchedLocationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String? { nil }

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

/// Annotation for tapped location (shows a blue dot)
class TappedLocationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String? { nil }

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

/// Annotation for tapped blockface (shows a label)
class BlockfaceLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let label: String
    let blockface: Blockface
    let pinColor: UIColor
    var title: String? { nil }  // Hide title to prevent text annotations

    init(coordinate: CLLocationCoordinate2D, label: String, blockface: Blockface, pinColor: UIColor) {
        self.coordinate = coordinate
        self.label = label
        self.blockface = blockface
        self.pinColor = pinColor
        super.init()
    }
}

/// Annotation for parking meters
class ParkingMeterAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let meter: ParkingMeter
    var title: String? { meter.displayName }

    init(coordinate: CLLocationCoordinate2D, meter: ParkingMeter) {
        self.coordinate = coordinate
        self.meter = meter
        super.init()
    }
}

// MARK: - Preview

#Preview {
    ZoneMapView(
        zones: [],
        currentZoneId: nil,
        userCoordinate: CLLocationCoordinate2D(latitude: 37.7585, longitude: -122.4233),
        onZoneTapped: { zone, permitAreas, coordinate in
            print("Tapped zone: \(zone.displayName), permits: \(permitAreas?.description ?? "nil"), at: \(coordinate.latitude),\(coordinate.longitude)")
        },
        onMapTapped: { coordinate in
            print("Tapped map at: \(coordinate.latitude),\(coordinate.longitude)")
        }
    )
}
