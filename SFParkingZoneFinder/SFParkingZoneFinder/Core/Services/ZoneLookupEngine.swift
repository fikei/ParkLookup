import Foundation
import CoreLocation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ZoneLookup")

/// Engine for looking up parking zones by coordinate
final class ZoneLookupEngine: ZoneLookupEngineProtocol {

    private let repository: ZoneRepository
    private var zones: [ParkingZone] = []
    private(set) var isReady = false

    /// Threshold in meters for boundary detection
    private let boundaryThreshold: Double = 10.0

    init(repository: ZoneRepository) {
        self.repository = repository
        logger.info("ZoneLookupEngine initialized")
    }

    func reloadZones() async throws {
        logger.info("Reloading zones...")
        zones = try await repository.getZones(for: .sanFrancisco)
        isReady = true
        logger.info("✅ Loaded \(self.zones.count) zones, isReady=\(self.isReady)")

        // Log summary of loaded zones
        var totalBoundaries = 0
        for zone in zones {
            totalBoundaries += zone.boundaries.count
        }
        logger.info("Total boundaries across all zones: \(totalBoundaries)")
    }

    func findZone(at coordinate: CLLocationCoordinate2D) async -> ZoneLookupResult {
        logger.info("🔍 Finding zone at: (\(coordinate.latitude), \(coordinate.longitude))")

        // Ensure zones are loaded
        if !isReady {
            logger.info("Zones not ready, loading...")
            do {
                try await reloadZones()
            } catch let error as DataSourceError {
                let zoneError = convertToZoneDataError(error)
                logger.error("❌ Failed to load zones: \(zoneError.localizedDescription)")
                return .dataLoadError(zoneError, coordinate: coordinate)
            } catch {
                logger.error("❌ Failed to load zones: \(error.localizedDescription)")
                return .dataLoadError(.unknown(message: error.localizedDescription), coordinate: coordinate)
            }
        }

        // Check if zones were actually loaded
        if zones.isEmpty {
            logger.error("❌ No zones loaded - returning data error")
            return .dataLoadError(.noZonesLoaded, coordinate: coordinate)
        }

        logger.info("Have \(self.zones.count) zones loaded")

        // Check if coordinate is within SF bounds
        guard CityIdentifier.sanFrancisco.contains(coordinate) else {
            logger.warning("⚠️ Coordinate outside SF bounds")
            return .outsideCoverage(coordinate: coordinate)
        }

        logger.info("✓ Coordinate is within SF bounds")

        // Find all zones containing this point
        var matchingZones: [ParkingZone] = []
        var nearestDistance: Double = .infinity

        for zone in zones {
            let boundaryCount = zone.allBoundaryCoordinates.count
            logger.debug("Checking zone \(zone.permitArea ?? zone.id) with \(boundaryCount) boundaries")

            // Check if point is inside ANY of the zone's boundaries (MultiPolygon)
            if isPointInsideZone(coordinate, zone: zone) {
                logger.info("✅ MATCH: Point is inside zone \(zone.permitArea ?? zone.id)")
                matchingZones.append(zone)
            }

            // Track distance to nearest boundary across all polygons
            let distance = distanceToZoneBoundary(coordinate, zone: zone)
            nearestDistance = min(nearestDistance, distance)
        }

        logger.info("Found \(matchingZones.count) matching zones, nearest boundary: \(nearestDistance)m")

        // No zones found
        if matchingZones.isEmpty {
            logger.warning("⚠️ No matching zones found - returning outsideCoverage")
            return .outsideCoverage(coordinate: coordinate)
        }

        // Sort by restrictiveness (most restrictive first)
        matchingZones.sort { $0.restrictiveness > $1.restrictiveness }

        // Determine confidence
        let confidence: LookupConfidence
        if matchingZones.count > 1 {
            confidence = .medium // Multiple overlapping zones
        } else if nearestDistance < boundaryThreshold {
            confidence = .medium // Near a boundary
        } else {
            confidence = .high
        }

        logger.info("✅ Returning result with primary zone: \(matchingZones.first?.permitArea ?? "none"), confidence: \(String(describing: confidence))")

        return ZoneLookupResult(
            primaryZone: matchingZones.first,
            overlappingZones: matchingZones,
            confidence: confidence,
            coordinate: coordinate,
            nearestBoundaryDistance: nearestDistance
        )
    }

    // MARK: - MultiPolygon Zone Checks

    /// Check if point is inside ANY of the zone's boundary polygons
    private func isPointInsideZone(
        _ point: CLLocationCoordinate2D,
        zone: ParkingZone
    ) -> Bool {
        let boundaries = zone.allBoundaryCoordinates
        for (index, boundary) in boundaries.enumerated() {
            if isPoint(point, insidePolygon: boundary) {
                logger.debug("Point is inside boundary \(index) of zone \(zone.permitArea ?? zone.id)")
                return true
            }
        }
        return false
    }

    /// Get minimum distance to any boundary polygon in the zone
    private func distanceToZoneBoundary(
        _ point: CLLocationCoordinate2D,
        zone: ParkingZone
    ) -> Double {
        var minDistance: Double = .infinity
        for boundary in zone.allBoundaryCoordinates {
            let distance = distanceToPolygonBoundary(point, polygon: boundary)
            minDistance = min(minDistance, distance)
        }
        return minDistance
    }

    // MARK: - Point in Polygon (Ray Casting)

    private func isPoint(
        _ point: CLLocationCoordinate2D,
        insidePolygon polygon: [CLLocationCoordinate2D]
    ) -> Bool {
        guard polygon.count >= 3 else {
            logger.debug("Polygon has \(polygon.count) points (needs >= 3)")
            return false
        }

        var isInside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let xi = polygon[i].longitude
            let yi = polygon[i].latitude
            let xj = polygon[j].longitude
            let yj = polygon[j].latitude

            if ((yi > point.latitude) != (yj > point.latitude)) &&
               (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi) {
                isInside.toggle()
            }
            j = i
        }

        return isInside
    }

    // MARK: - Distance to Boundary

    private func distanceToPolygonBoundary(
        _ point: CLLocationCoordinate2D,
        polygon: [CLLocationCoordinate2D]
    ) -> Double {
        guard polygon.count >= 2 else { return .infinity }

        var minDistance: Double = .infinity

        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            let segmentDistance = distanceToLineSegment(
                point: point,
                lineStart: polygon[i],
                lineEnd: polygon[j]
            )
            minDistance = min(minDistance, segmentDistance)
        }

        return minDistance
    }

    private func distanceToLineSegment(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let start = CLLocation(latitude: lineStart.latitude, longitude: lineStart.longitude)
        let end = CLLocation(latitude: lineEnd.latitude, longitude: lineEnd.longitude)

        // Simplified: just check distance to both endpoints
        // A more accurate implementation would project onto the line segment
        let distToStart = location.distance(from: start)
        let distToEnd = location.distance(from: end)

        return min(distToStart, distToEnd)
    }

    // MARK: - Error Conversion

    /// Convert DataSourceError to ZoneDataError for user-facing error reporting
    private func convertToZoneDataError(_ error: DataSourceError) -> ZoneDataError {
        switch error {
        case .fileNotFound(let filename):
            return .fileNotFound(filename: filename)
        case .parsingFailed(let reason):
            return .decodingFailed(details: reason)
        case .invalidData(let reason):
            return .decodingFailed(details: reason)
        case .cityNotSupported(let city):
            return .unknown(message: "City '\(city)' is not supported")
        }
    }
}
