import Foundation
import CoreLocation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ZoneLookup")

/// Engine for looking up parking zones by coordinate
final class ZoneLookupEngine: ZoneLookupEngineProtocol {

    private let repository: ZoneRepository
    private var zones: [ParkingZone] = []
    private(set) var isReady = false

    /// All loaded zones (for map display)
    var allZones: [ParkingZone] { zones }

    /// Threshold in meters for boundary detection
    private let boundaryThreshold: Double = 10.0

    init(repository: ZoneRepository) {
        self.repository = repository
    }

    func reloadZones() async throws {
        zones = try await repository.getZones(for: .sanFrancisco)
        isReady = true

        // Log zone breakdown by type
        let rppCount = zones.filter { $0.zoneType == .residentialPermit }.count
        let meteredCount = zones.filter { $0.zoneType == .metered }.count
        let otherCount = zones.count - rppCount - meteredCount
        logger.info("✅ Loaded \(self.zones.count) zones: \(rppCount) RPP, \(meteredCount) metered, \(otherCount) other")
    }

    func findZone(at coordinate: CLLocationCoordinate2D) async -> ZoneLookupResult {

        // Ensure zones are loaded
        if !isReady {
            do {
                try await reloadZones()
            } catch let error as DataSourceError {
                let zoneError = convertToZoneDataError(error)
                logger.error("Failed to load zones: \(zoneError.localizedDescription)")
                return .dataLoadError(zoneError, coordinate: coordinate)
            } catch {
                logger.error("Failed to load zones: \(error.localizedDescription)")
                return .dataLoadError(.unknown(message: error.localizedDescription), coordinate: coordinate)
            }
        }

        // Check if zones were actually loaded
        if zones.isEmpty {
            logger.error("No zones loaded")
            return .dataLoadError(.noZonesLoaded, coordinate: coordinate)
        }

        // Check if coordinate is within SF bounds
        guard CityIdentifier.sanFrancisco.contains(coordinate) else {
            return .outsideCoverage(coordinate: coordinate)
        }

        // Find all zones containing this point
        var matchingZones: [ParkingZone] = []
        var nearestDistance: Double = .infinity
        var nearestZone: ParkingZone?

        for zone in zones {
            // Check if point is inside ANY of the zone's boundaries (MultiPolygon)
            if isPointInsideZone(coordinate, zone: zone) {
                matchingZones.append(zone)
            }

            // Track distance to nearest boundary across all polygons
            let distance = distanceToZoneBoundary(coordinate, zone: zone)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestZone = zone
            }
        }

        // No zones found - check if we're very close to a zone (handles gaps in metered zones)
        if matchingZones.isEmpty {
            // If within 75 meters of a zone, use it with low confidence
            // This handles gaps in metered zone polygons where meters don't exist
            if let nearest = nearestZone, nearestDistance < 75 {
                logger.info("📍 No exact match, using nearest zone '\(nearest.displayName)' at \(Int(nearestDistance))m")
                return ZoneLookupResult(
                    primaryZone: nearest,
                    overlappingZones: [nearest],
                    confidence: .low,
                    coordinate: coordinate,
                    nearestBoundaryDistance: nearestDistance
                )
            }

            logger.warning("⚠️ No zone found at (\(coordinate.latitude), \(coordinate.longitude)) - returning unknownArea")
            return .unknownArea(coordinate: coordinate)
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

        logger.info("Returning result with primary zone: \(matchingZones.first?.permitArea ?? "none"), confidence: \(String(describing: confidence))")

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
        for boundary in boundaries {
            if isPoint(point, insidePolygon: boundary) {
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
        guard polygon.count >= 3 else { return false }

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
