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
    let onZoneTapped: ((ParkingZone) -> Void)?

    /// User's valid permit areas (uppercase codes like "Q", "AA")
    /// Zones matching these will be colored green, others orange
    var userPermitAreas: Set<String> = []

    /// Developer settings hash - when this changes, overlays reload with new simplification
    var devSettingsHash: Int = DeveloperSettings.shared.settingsHash

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

    /// Validates a coordinate to ensure it won't cause NaN errors
    private func isValidCoordinate(_ coord: CLLocationCoordinate2D?) -> Bool {
        guard let c = coord else { return false }
        return c.latitude.isFinite && c.longitude.isFinite &&
               c.latitude >= -90 && c.latitude <= 90 &&
               c.longitude >= -180 && c.longitude <= 180
    }

    func makeUIView(context: Context) -> MKMapView {
        logger.info("ZoneMapView init - \(self.zones.count) zones")

        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Set initial region centered on user (zoomed to ~10-15 blocks)
        // 0.006 degrees ≈ 670m ≈ 8-10 SF blocks, adjusted by zoom multiplier
        let defaultCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let userCenter = isValidCoordinate(userCoordinate) ? userCoordinate! : defaultCenter
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

        // Add tap gesture for zone selection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        // Load zone overlays in background, add to map on main thread
        let zonesToLoad = self.zones
        let devSettings = DeveloperSettings.shared

        DispatchQueue.global(qos: .userInitiated).async {

            var polygons: [ZonePolygon] = []
            var annotations: [ZoneLabelAnnotation] = []
            var totalBoundaries = 0
            var totalInputPoints = 0
            var totalOutputPoints = 0

            // Filter radius for visible zones
            let filterRadius = 0.03   // ~3.3km - visible area

            let minLat = center.latitude - filterRadius
            let maxLat = center.latitude + filterRadius
            let minLon = center.longitude - filterRadius
            let maxLon = center.longitude + filterRadius

            for zone in zonesToLoad {
                let zoneBoundaryCount = zone.allBoundaryCoordinates.count
                totalBoundaries += zoneBoundaryCount

                // Collect nearby boundaries
                var nearbyBoundaries: [[CLLocationCoordinate2D]] = []

                for boundary in zone.allBoundaryCoordinates {
                    totalInputPoints += boundary.count

                    // Check if any point of this boundary is within filter bounds
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
                    let displayBoundary = devSettings.isSimplificationEnabled
                        ? PolygonSimplifier.simplify(boundary, settings: devSettings)
                        : boundary

                    guard displayBoundary.count >= 3 else { continue }

                    let polygon = ZonePolygon(coordinates: displayBoundary, count: displayBoundary.count)
                    polygon.zoneId = zone.id
                    polygon.zoneCode = zone.permitArea
                    polygon.zoneType = zone.zoneType
                    polygon.originalVertexCount = boundary.count  // Store for debug display

                    // Check if this is a multi-permit boundary
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
                    totalOutputPoints += displayBoundary.count
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

            }

            // Apply overlap clipping if enabled (visual only)
            if devSettings.useOverlapClipping {
                polygons = Self.applyOverlapClipping(polygons, tolerance: devSettings.overlapTolerance)
            }

            // Apply polygon merging if enabled (visual only)
            if devSettings.mergeOverlappingSameZone || devSettings.useProximityMerging {
                polygons = Self.applyPolygonMerging(
                    polygons,
                    mergeOverlapping: devSettings.mergeOverlappingSameZone,
                    useProximity: devSettings.useProximityMerging,
                    proximityMeters: devSettings.proximityMergeDistance,
                    tolerance: devSettings.overlapTolerance
                )
            }

            // Remove near-duplicate polygons to prevent double-rendering
            polygons = Self.deduplicateOverlappingPolygons(polygons, overlapThreshold: devSettings.deduplicationThreshold)

            // Separate polygons by zone type and permit status for proper layering
            // Layer order (bottom to top): Metered → Non-Permitted RPP → Permitted RPP
            let meteredPolygons = polygons.filter { $0.zoneType == .metered }
            let nonPermittedPolygons = polygons.filter { polygon in
                guard polygon.zoneType != .metered else { return false }
                guard let zoneCode = polygon.zoneCode?.uppercased() else { return true }
                return !self.userPermitAreas.contains(zoneCode)
            }
            let permittedPolygons = polygons.filter { polygon in
                guard polygon.zoneType != .metered else { return false }
                guard let zoneCode = polygon.zoneCode?.uppercased() else { return false }
                return self.userPermitAreas.contains(zoneCode)
            }

            // Capture the coordinator, initial region, and showOverlays before async block
            let coordinator = context.coordinator
            let initialCenter = coordinator.initialCenter
            let initialSpan = coordinator.initialSpan
            let shouldShowOverlays = self.showOverlays

            // Add to map on main thread in batches to keep UI responsive
            DispatchQueue.main.async {

                // Mark setup done immediately so map is interactive
                coordinator.initialSetupDone = true
                coordinator.showOverlays = shouldShowOverlays

                // Re-apply the initial zoom first
                if let center = initialCenter, let span = initialSpan {
                    let region = MKCoordinateRegion(center: center, span: span)
                    mapView.setRegion(region, animated: false)
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

                // Add overlays in batches with proper layering:
                // Metered (bottom) → Non-Permitted RPP (middle) → Permitted RPP (top)
                let batchSize = 500

                // Ordered polygons: metered first, then non-permitted, then permitted (later additions render on top)
                let orderedPolygons = meteredPolygons + nonPermittedPolygons + permittedPolygons
                let totalPolygons = orderedPolygons.count

                func addBatch(startIndex: Int) {
                    let endIndex = min(startIndex + batchSize, totalPolygons)
                    let batch = Array(orderedPolygons[startIndex..<endIndex])

                    mapView.addOverlays(batch, level: .aboveRoads)

                    // Set alpha based on coordinator's CURRENT showOverlays value
                    // Coordinator is updated in updateUIView, so this reflects real-time state
                    if !coordinator.showOverlays {
                        logger.debug("⚠️ Adding overlays with alpha=0 (hidden) - showOverlays=false")
                        for overlay in batch {
                            if let renderer = mapView.renderer(for: overlay) {
                                renderer.alpha = 0
                            }
                        }
                    } else {
                        logger.debug("✅ Adding overlays with alpha=1 (visible) - showOverlays=true, batch size=\(batch.count)")
                    }

                    if endIndex < totalPolygons {
                        // Schedule next batch with tiny delay to let UI breathe
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            addBatch(startIndex: endIndex)
                        }
                    } else {
                        // Use coordinator's current showOverlays value
                        coordinator.overlaysCurrentlyVisible = coordinator.showOverlays
                        coordinator.overlaysLoaded = true
                        coordinator.isLoadingOverlays = false
                        coordinator.overlayLoadingMessage = ""
                        logger.info("Overlays loaded: \(totalPolygons) polygons, visible=\(coordinator.showOverlays)")
                    }
                }

                // Start adding batches
                if !orderedPolygons.isEmpty {
                    addBatch(startIndex: 0)
                } else {
                    // Use coordinator's current showOverlays value
                    coordinator.overlaysCurrentlyVisible = coordinator.showOverlays
                    coordinator.overlaysLoaded = true
                    coordinator.isLoadingOverlays = false
                    coordinator.overlayLoadingMessage = ""
                }
            }
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {

        // Update coordinator with current state
        context.coordinator.currentZoneId = currentZoneId
        context.coordinator.zones = zones
        context.coordinator.onZoneTapped = onZoneTapped
        context.coordinator.showOverlays = showOverlays
        context.coordinator.userPermitAreas = userPermitAreas

        // Handle searched location annotation
        updateSearchedAnnotation(mapView: mapView, context: context)

        // Check if reload trigger changed - force reload if so
        let currentReloadTrigger = DeveloperSettings.shared.reloadTrigger
        if context.coordinator.overlaysLoaded && currentReloadTrigger != context.coordinator.lastReloadTrigger {
            logger.info("🔄 Manual refresh triggered - reloading overlays")
            context.coordinator.lastReloadTrigger = currentReloadTrigger

            // Clear existing overlays and annotations (except user location and searched pin)
            let overlaysToRemove = mapView.overlays
            let annotationsToRemove = mapView.annotations.filter { annotation in
                !(annotation is MKUserLocation) && !(annotation is SearchedLocationAnnotation)
            }
            mapView.removeOverlays(overlaysToRemove)
            mapView.removeAnnotations(annotationsToRemove)

            // Reload overlays (keep overlaysLoaded=true to prevent race condition)
            context.coordinator.overlaysCurrentlyVisible = false
            loadOverlays(mapView: mapView, context: context)
            return
        }

        // Check if developer settings changed - reload overlays if so
        let currentSettingsHash = DeveloperSettings.shared.settingsHash
        if context.coordinator.overlaysLoaded && currentSettingsHash != context.coordinator.lastSettingsHash {
            logger.info("🔄 Developer settings changed - reloading overlays")
            context.coordinator.lastSettingsHash = currentSettingsHash

            // Clear existing overlays and annotations (except user location and searched pin)
            let overlaysToRemove = mapView.overlays
            let annotationsToRemove = mapView.annotations.filter { annotation in
                !(annotation is MKUserLocation) && !(annotation is SearchedLocationAnnotation)
            }
            mapView.removeOverlays(overlaysToRemove)
            mapView.removeAnnotations(annotationsToRemove)

            // Reload overlays (keep overlaysLoaded=true to prevent race condition)
            context.coordinator.overlaysCurrentlyVisible = false
            loadOverlays(mapView: mapView, context: context)
            return
        }

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
        Coordinator(currentZoneId: currentZoneId, zones: zones, onZoneTapped: onZoneTapped)
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
                    let displayBoundary = devSettings.isSimplificationEnabled
                        ? PolygonSimplifier.simplify(boundary, settings: devSettings)
                        : boundary

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
                polygons = Self.applyOverlapClipping(polygons, tolerance: devSettings.overlapTolerance)
            }

            // Apply polygon merging if enabled (visual only)
            if devSettings.mergeOverlappingSameZone || devSettings.useProximityMerging {
                polygons = Self.applyPolygonMerging(
                    polygons,
                    mergeOverlapping: devSettings.mergeOverlappingSameZone,
                    useProximity: devSettings.useProximityMerging,
                    proximityMeters: devSettings.proximityMergeDistance,
                    tolerance: devSettings.overlapTolerance
                )
            }

            // Remove near-duplicate polygons to prevent double-rendering
            polygons = Self.deduplicateOverlappingPolygons(polygons, overlapThreshold: devSettings.deduplicationThreshold)

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

                mapView.addAnnotations(annotations)

                // Set initial alpha based on coordinator's CURRENT showOverlays value
                // Coordinator is updated in updateUIView, so this reflects real-time state
                let initialAlpha: CGFloat = coordinator.showOverlays ? 1.0 : 0.0
                for annotation in annotations {
                    if let view = mapView.view(for: annotation) {
                        view.alpha = initialAlpha
                    }
                }

                let batchSize = 500
                // Ordered polygons: metered first, then non-permitted, then permitted (later additions render on top)
                let orderedPolygons = meteredPolygons + nonPermittedPolygons + permittedPolygons
                let totalPolygons = orderedPolygons.count

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
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var currentZoneId: String?
        var zones: [ParkingZone]
        var onZoneTapped: ((ParkingZone) -> Void)?
        var userPermitAreas: Set<String> = []

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
        var overlayLoadingMessage: String = ""  // Detailed message for developer view
        var lastVerticalBias: Double = 0.0

        // Track the searched location annotation
        weak var searchedAnnotation: SearchedLocationAnnotation?

        // Track developer settings hash to detect changes and refresh overlays
        var lastSettingsHash: Int = 0

        // Track reload trigger to detect manual refresh requests
        var lastReloadTrigger: Int = 0

        init(currentZoneId: String?, zones: [ParkingZone], onZoneTapped: ((ParkingZone) -> Void)?) {
            self.currentZoneId = currentZoneId
            self.zones = zones
            self.onZoneTapped = onZoneTapped
            self.lastSettingsHash = DeveloperSettings.shared.settingsHash
            self.lastReloadTrigger = DeveloperSettings.shared.reloadTrigger
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
            let devSettings = DeveloperSettings.shared

            // DEBUG: Log rendering details
            logger.debug("🎨 Rendering overlay #\(self.rendererCallCount): zoneId=\(polygon.zoneId ?? "nil"), zoneCode=\(polygon.zoneCode ?? "nil"), zoneType=\(String(describing: polygon.zoneType)), isMultiPermit=\(polygon.isMultiPermit), isCurrentZone=\(isCurrentZone)")

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

            // Multi-permit polygons get a dashed border if dash length is set
            // If user has permit for this multi-permit zone, use my permit zones color
            if polygon.isMultiPermit {
                // Apply dash pattern if dashLength > 0
                if devSettings.dashLength > 0 {
                    renderer.lineDashPattern = [NSNumber(value: devSettings.dashLength), NSNumber(value: devSettings.dashLength * 0.5)]
                }

                // Check if any of the multi-permit areas match user's permits
                if let multiPermitAreas = polygon.allValidPermitAreas {
                    let matchesUserPermit = multiPermitAreas.contains { userPermitAreas.contains($0.uppercased()) }
                    if matchesUserPermit {
                        // User has a valid permit for this multi-permit zone
                        let userColor = devSettings.myPermitZonesColor
                        let userFillOpacity = isCurrentZone ? devSettings.currentZoneFillOpacity : devSettings.myPermitZonesFillOpacity
                        let userStrokeOpacity = isCurrentZone ? devSettings.currentZoneStrokeOpacity : devSettings.myPermitZonesStrokeOpacity
                        renderer.fillColor = userColor.withAlphaComponent(CGFloat(userFillOpacity))
                        renderer.strokeColor = userColor.withAlphaComponent(CGFloat(userStrokeOpacity))
                    }
                }
            }

            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Skip user location annotation
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

            // Handle zone label annotation
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
    var originalVertexCount: Int = 0  // For debug: original vertex count before simplification

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

/// Annotation for searched address location (shows a blue pin)
class SearchedLocationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String? { nil }

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
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
