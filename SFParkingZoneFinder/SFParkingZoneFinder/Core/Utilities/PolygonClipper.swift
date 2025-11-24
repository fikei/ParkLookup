import Foundation
import CoreLocation

/// Utility for clipping overlapping polygons for visual display
/// Uses priority rules to determine which polygon "wins" in overlap regions
enum PolygonClipper {

    // MARK: - Polygon Orientation

    /// Determines if a polygon is primarily vertical (N-S oriented) or horizontal (E-W oriented)
    /// Based on the bounding box aspect ratio
    static func orientation(of coords: [CLLocationCoordinate2D]) -> PolygonOrientation {
        guard coords.count >= 3 else { return .unknown }

        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }

        let latSpan = (lats.max() ?? 0) - (lats.min() ?? 0)
        let lonSpan = (lons.max() ?? 0) - (lons.min() ?? 0)

        // Account for longitude compression at SF latitude (~37.7°)
        // 1° longitude ≈ 0.79° latitude equivalent at this latitude
        let adjustedLonSpan = lonSpan * 0.79

        if latSpan > adjustedLonSpan * 1.2 {
            return .vertical  // N-S oriented (taller than wide)
        } else if adjustedLonSpan > latSpan * 1.2 {
            return .horizontal  // E-W oriented (wider than tall)
        } else {
            return .square  // Roughly square
        }
    }

    // MARK: - Overlap Detection

    /// Check if two polygons potentially overlap using bounding box test
    static func boundingBoxesOverlap(
        _ coords1: [CLLocationCoordinate2D],
        _ coords2: [CLLocationCoordinate2D],
        tolerance: Double = 0.00001
    ) -> Bool {
        guard coords1.count >= 3, coords2.count >= 3 else { return false }

        let box1 = boundingBox(of: coords1)
        let box2 = boundingBox(of: coords2)

        // Check if bounding boxes overlap (with tolerance)
        return !(box1.maxLat + tolerance < box2.minLat ||
                 box2.maxLat + tolerance < box1.minLat ||
                 box1.maxLon + tolerance < box2.minLon ||
                 box2.maxLon + tolerance < box1.minLon)
    }

    /// Get bounding box for coordinates
    static func boundingBox(of coords: [CLLocationCoordinate2D]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        return (
            minLat: lats.min() ?? 0,
            maxLat: lats.max() ?? 0,
            minLon: lons.min() ?? 0,
            maxLon: lons.max() ?? 0
        )
    }

    // MARK: - Sutherland-Hodgman Clipping

    /// Clip subject polygon against clip polygon using Sutherland-Hodgman algorithm
    /// Returns the portion of subject that is INSIDE clip polygon
    static func clipPolygon(
        subject: [CLLocationCoordinate2D],
        against clip: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard subject.count >= 3, clip.count >= 3 else { return subject }

        var output = subject

        // For each edge of the clipping polygon
        for i in 0..<clip.count {
            guard output.count >= 3 else { return [] }

            let edgeStart = clip[i]
            let edgeEnd = clip[(i + 1) % clip.count]

            var newOutput: [CLLocationCoordinate2D] = []

            for j in 0..<output.count {
                let current = output[j]
                let previous = output[(j + output.count - 1) % output.count]

                let currentInside = isLeft(of: edgeStart, to: edgeEnd, point: current)
                let previousInside = isLeft(of: edgeStart, to: edgeEnd, point: previous)

                if currentInside {
                    if !previousInside {
                        // Entering - add intersection point
                        if let intersection = lineIntersection(
                            p1: previous, p2: current,
                            p3: edgeStart, p4: edgeEnd
                        ) {
                            newOutput.append(intersection)
                        }
                    }
                    newOutput.append(current)
                } else if previousInside {
                    // Leaving - add intersection point
                    if let intersection = lineIntersection(
                        p1: previous, p2: current,
                        p3: edgeStart, p4: edgeEnd
                    ) {
                        newOutput.append(intersection)
                    }
                }
            }

            output = newOutput
        }

        return output
    }

    /// Subtract clip polygon from subject polygon
    /// Returns the portion of subject that is OUTSIDE clip polygon
    /// This is an approximation - for complex cases, returns the original subject
    static func subtractPolygon(
        subject: [CLLocationCoordinate2D],
        minus clip: [CLLocationCoordinate2D]
    ) -> [[CLLocationCoordinate2D]] {
        guard subject.count >= 3, clip.count >= 3 else { return [subject] }

        // Check if they actually overlap
        guard boundingBoxesOverlap(subject, clip) else { return [subject] }

        // Find the intersection region
        let intersection = clipPolygon(subject: subject, against: clip)

        // If no intersection, return original
        guard intersection.count >= 3 else { return [subject] }

        // For visual overlay purposes, we'll use a simplified approach:
        // Clip the subject polygon along the edges of the intersection
        // This works well for rectangular SF street blocks

        let clippedResults = clipAlongIntersectionEdges(subject: subject, intersection: intersection)

        return clippedResults.isEmpty ? [subject] : clippedResults
    }

    /// Clip subject polygon along intersection edges
    /// Returns multiple result polygons representing the non-overlapping portions
    private static func clipAlongIntersectionEdges(
        subject: [CLLocationCoordinate2D],
        intersection: [CLLocationCoordinate2D]
    ) -> [[CLLocationCoordinate2D]] {
        // For SF's grid layout, most overlaps are rectangular
        // We can clip by finding the primary axis of overlap and splitting

        let subjectBox = boundingBox(of: subject)
        let intersectBox = boundingBox(of: intersection)

        // Determine the dominant overlap direction
        let latOverlap = min(subjectBox.maxLat, intersectBox.maxLat) - max(subjectBox.minLat, intersectBox.minLat)
        let lonOverlap = min(subjectBox.maxLon, intersectBox.maxLon) - max(subjectBox.minLon, intersectBox.minLon)

        var results: [[CLLocationCoordinate2D]] = []

        // Create clipped portions based on which side has less overlap
        if latOverlap < lonOverlap {
            // Split horizontally (keep top and bottom portions)
            if intersectBox.minLat > subjectBox.minLat {
                // Keep bottom portion
                let bottom = clipToLatRange(subject, minLat: subjectBox.minLat, maxLat: intersectBox.minLat)
                if bottom.count >= 3 { results.append(bottom) }
            }
            if intersectBox.maxLat < subjectBox.maxLat {
                // Keep top portion
                let top = clipToLatRange(subject, minLat: intersectBox.maxLat, maxLat: subjectBox.maxLat)
                if top.count >= 3 { results.append(top) }
            }
        } else {
            // Split vertically (keep left and right portions)
            if intersectBox.minLon > subjectBox.minLon {
                // Keep left portion
                let left = clipToLonRange(subject, minLon: subjectBox.minLon, maxLon: intersectBox.minLon)
                if left.count >= 3 { results.append(left) }
            }
            if intersectBox.maxLon < subjectBox.maxLon {
                // Keep right portion
                let right = clipToLonRange(subject, minLon: intersectBox.maxLon, maxLon: subjectBox.maxLon)
                if right.count >= 3 { results.append(right) }
            }
        }

        return results
    }

    /// Clip polygon to a latitude range
    private static func clipToLatRange(_ coords: [CLLocationCoordinate2D], minLat: Double, maxLat: Double) -> [CLLocationCoordinate2D] {
        // Create a clipping rectangle
        let box = boundingBox(of: coords)
        let clipRect = [
            CLLocationCoordinate2D(latitude: minLat, longitude: box.minLon - 0.001),
            CLLocationCoordinate2D(latitude: maxLat, longitude: box.minLon - 0.001),
            CLLocationCoordinate2D(latitude: maxLat, longitude: box.maxLon + 0.001),
            CLLocationCoordinate2D(latitude: minLat, longitude: box.maxLon + 0.001)
        ]
        return clipPolygon(subject: coords, against: clipRect)
    }

    /// Clip polygon to a longitude range
    private static func clipToLonRange(_ coords: [CLLocationCoordinate2D], minLon: Double, maxLon: Double) -> [CLLocationCoordinate2D] {
        // Create a clipping rectangle
        let box = boundingBox(of: coords)
        let clipRect = [
            CLLocationCoordinate2D(latitude: box.minLat - 0.001, longitude: minLon),
            CLLocationCoordinate2D(latitude: box.maxLat + 0.001, longitude: minLon),
            CLLocationCoordinate2D(latitude: box.maxLat + 0.001, longitude: maxLon),
            CLLocationCoordinate2D(latitude: box.minLat - 0.001, longitude: maxLon)
        ]
        return clipPolygon(subject: coords, against: clipRect)
    }

    // MARK: - Geometry Helpers

    /// Check if point is to the left of directed line from p1 to p2
    private static func isLeft(of p1: CLLocationCoordinate2D, to p2: CLLocationCoordinate2D, point: CLLocationCoordinate2D) -> Bool {
        return (p2.longitude - p1.longitude) * (point.latitude - p1.latitude) -
               (p2.latitude - p1.latitude) * (point.longitude - p1.longitude) >= 0
    }

    /// Find intersection point of two line segments
    private static func lineIntersection(
        p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D,
        p3: CLLocationCoordinate2D, p4: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D? {
        let d1 = (p2.longitude - p1.longitude, p2.latitude - p1.latitude)
        let d2 = (p4.longitude - p3.longitude, p4.latitude - p3.latitude)

        let cross = d1.0 * d2.1 - d1.1 * d2.0

        // Lines are parallel
        guard abs(cross) > 1e-10 else { return nil }

        let d3 = (p3.longitude - p1.longitude, p3.latitude - p1.latitude)
        let t = (d3.0 * d2.1 - d3.1 * d2.0) / cross

        return CLLocationCoordinate2D(
            latitude: p1.latitude + t * d1.1,
            longitude: p1.longitude + t * d1.0
        )
    }

    // MARK: - Priority Rules

    /// Determine which polygon has priority in overlap regions
    /// Returns true if polygon1 should be rendered on top (polygon2 clipped)
    static func hasPriority(
        polygon1: PolygonInfo,
        over polygon2: PolygonInfo
    ) -> Bool {
        // Rule 1: Metered zones always win
        if polygon1.isMetered && !polygon2.isMetered {
            return true
        }
        if polygon2.isMetered && !polygon1.isMetered {
            return false
        }

        // Rule 2: Vertical (N-S) polygons win over horizontal (E-W)
        if polygon1.orientation == .vertical && polygon2.orientation == .horizontal {
            return true
        }
        if polygon2.orientation == .vertical && polygon1.orientation == .horizontal {
            return false
        }

        // Rule 3: For same orientation, smaller area wins (more specific zone)
        return polygon1.area < polygon2.area
    }

    /// Calculate approximate area of polygon
    static func area(of coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 3 else { return 0 }

        var sum = 0.0
        for i in 0..<coords.count {
            let j = (i + 1) % coords.count
            sum += coords[i].longitude * coords[j].latitude
            sum -= coords[j].longitude * coords[i].latitude
        }
        return abs(sum) / 2.0
    }
}

// MARK: - Supporting Types

enum PolygonOrientation {
    case vertical    // N-S oriented (taller than wide)
    case horizontal  // E-W oriented (wider than tall)
    case square      // Roughly equal dimensions
    case unknown
}

struct PolygonInfo {
    let coords: [CLLocationCoordinate2D]
    let zoneId: String
    let zoneCode: String?
    let isMetered: Bool
    let orientation: PolygonOrientation
    let area: Double

    init(coords: [CLLocationCoordinate2D], zoneId: String, zoneCode: String?, isMetered: Bool) {
        self.coords = coords
        self.zoneId = zoneId
        self.zoneCode = zoneCode
        self.isMetered = isMetered
        self.orientation = PolygonClipper.orientation(of: coords)
        self.area = PolygonClipper.area(of: coords)
    }
}
