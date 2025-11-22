import Foundation
import CoreLocation

/// Engine for looking up parking zones by coordinate
final class ZoneLookupEngine: ZoneLookupEngineProtocol {

    private let repository: ZoneRepository
    private var zones: [ParkingZone] = []
    private(set) var isReady = false

    /// Threshold in meters for boundary detection
    private let boundaryThreshold: Double = 10.0

    init(repository: ZoneRepository) {
        self.repository = repository
    }

    func reloadZones() async throws {
        zones = try await repository.getZones(for: .sanFrancisco)
        isReady = true
    }

    func findZone(at coordinate: CLLocationCoordinate2D) async -> ZoneLookupResult {
        // Ensure zones are loaded
        if !isReady {
            do {
                try await reloadZones()
            } catch {
                return .outsideCoverage(coordinate: coordinate)
            }
        }

        // Check if coordinate is within SF bounds
        guard CityIdentifier.sanFrancisco.contains(coordinate) else {
            return .outsideCoverage(coordinate: coordinate)
        }

        // Find all zones containing this point
        var matchingZones: [ParkingZone] = []
        var nearestDistance: Double = .infinity

        for zone in zones {
            // Check if point is inside ANY of the zone's boundaries (MultiPolygon)
            if isPointInsideZone(coordinate, zone: zone) {
                matchingZones.append(zone)
            }

            // Track distance to nearest boundary across all polygons
            let distance = distanceToZoneBoundary(coordinate, zone: zone)
            nearestDistance = min(nearestDistance, distance)
        }

        // No zones found
        if matchingZones.isEmpty {
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
        for boundary in zone.allBoundaryCoordinates {
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
}
