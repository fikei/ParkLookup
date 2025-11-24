import Foundation
import CoreLocation

/// Utility for simplifying polygon boundaries for map display
/// Supports multiple algorithms that can be combined in a pipeline
enum PolygonSimplifier {

    // MARK: - Main Pipeline

    /// Apply the simplification pipeline based on DeveloperSettings
    /// Order: Curve-aware D-P → Grid Snap → Convex Hull (if enabled)
    static func simplify(
        _ coords: [CLLocationCoordinate2D],
        settings: DeveloperSettings = .shared
    ) -> [CLLocationCoordinate2D] {
        guard coords.count >= 3 else { return coords }

        var result = coords

        // Step 1: Douglas-Peucker simplification (curve-aware if enabled)
        if settings.useDouglasPeucker {
            if settings.preserveCurves {
                result = curveAwareDouglasPeucker(
                    result,
                    tolerance: settings.douglasPeuckerTolerance,
                    curveThreshold: settings.curveAngleThreshold
                )
            } else {
                result = douglasPeucker(result, tolerance: settings.douglasPeuckerTolerance)
            }
        }

        // Step 2: Grid snapping
        if settings.useGridSnapping {
            result = gridSnap(result, gridSize: settings.gridSnapSize)
        }

        // Step 3: Convex hull (most aggressive - loses interior detail)
        if settings.useConvexHull {
            result = convexHull(result)
        }

        // Step 4: Corner rounding (creates smooth arcs at corners)
        if settings.useCornerRounding {
            result = roundCorners(result, radius: settings.cornerRoundingRadius)
        }

        // Ensure polygon is closed
        if result.count >= 3 && !coordsEqual(result.first!, result.last!) {
            result.append(result[0])
        }

        return result
    }

    // MARK: - Douglas-Peucker Algorithm

    /// Standard Douglas-Peucker simplification
    /// Removes points that are within `tolerance` distance of the line between endpoints
    static func douglasPeucker(
        _ coords: [CLLocationCoordinate2D],
        tolerance: Double
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }

        var maxDistance = 0.0
        var maxIndex = 0

        // Find the point with maximum perpendicular distance
        for i in 1..<(coords.count - 1) {
            let distance = perpendicularDistance(
                coords[i],
                lineStart: coords[0],
                lineEnd: coords[coords.count - 1]
            )
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        // If max distance exceeds tolerance, recursively simplify
        if maxDistance > tolerance {
            let left = douglasPeucker(Array(coords[0...maxIndex]), tolerance: tolerance)
            let right = douglasPeucker(Array(coords[maxIndex...]), tolerance: tolerance)
            return Array(left.dropLast()) + right
        } else {
            return [coords[0], coords[coords.count - 1]]
        }
    }

    /// Curve-aware Douglas-Peucker simplification
    /// Preserves points where the angle between segments exceeds the curve threshold
    static func curveAwareDouglasPeucker(
        _ coords: [CLLocationCoordinate2D],
        tolerance: Double,
        curveThreshold: Double
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }

        // First, identify curve points that must be preserved
        var curvePoints = Set<Int>()
        for i in 1..<(coords.count - 1) {
            let angle = angleBetweenSegments(
                coords[i - 1],
                coords[i],
                coords[i + 1]
            )
            // If angle deviation from straight (180°) exceeds threshold, preserve this point
            if abs(180 - angle) > curveThreshold {
                curvePoints.insert(i)
            }
        }

        // Run D-P but preserve curve points
        return douglasPeuckerPreserving(
            coords,
            tolerance: tolerance,
            preserveIndices: curvePoints
        )
    }

    /// Douglas-Peucker that preserves specific indices
    private static func douglasPeuckerPreserving(
        _ coords: [CLLocationCoordinate2D],
        tolerance: Double,
        preserveIndices: Set<Int>,
        offset: Int = 0
    ) -> [CLLocationCoordinate2D] {
        // Base case: can't simplify further
        guard coords.count > 2 else { return coords }

        var maxDistance = 0.0
        var maxIndex = 1  // Start at 1, not 0, to avoid infinite recursion

        // Find the point with maximum perpendicular distance
        for i in 1..<(coords.count - 1) {
            let distance = perpendicularDistance(
                coords[i],
                lineStart: coords[0],
                lineEnd: coords[coords.count - 1]
            )
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        // Check if we need to split (max distance exceeds tolerance OR split point must be preserved)
        let absoluteMaxIndex = offset + maxIndex
        let mustPreserve = preserveIndices.contains(absoluteMaxIndex)

        // Also check if any preserved points exist in the ranges we're about to simplify
        let leftPreserved = preserveIndices.contains { $0 > offset && $0 < absoluteMaxIndex }
        let rightPreserved = preserveIndices.contains { $0 > absoluteMaxIndex && $0 < offset + coords.count - 1 }

        if maxDistance > tolerance || mustPreserve || leftPreserved || rightPreserved {
            // Ensure we're actually making progress (arrays must be smaller)
            let leftArray = Array(coords[0...maxIndex])
            let rightArray = Array(coords[maxIndex...])

            // Safety check: avoid infinite recursion
            guard leftArray.count < coords.count && rightArray.count < coords.count else {
                return [coords[0], coords[coords.count - 1]]
            }

            let left = douglasPeuckerPreserving(
                leftArray,
                tolerance: tolerance,
                preserveIndices: preserveIndices,
                offset: offset
            )
            let right = douglasPeuckerPreserving(
                rightArray,
                tolerance: tolerance,
                preserveIndices: preserveIndices,
                offset: offset + maxIndex
            )
            return Array(left.dropLast()) + right
        }

        return [coords[0], coords[coords.count - 1]]
    }

    // MARK: - Grid Snapping

    /// Snap coordinates to a regular grid
    /// Useful for straightening block-aligned edges
    static func gridSnap(
        _ coords: [CLLocationCoordinate2D],
        gridSize: Double
    ) -> [CLLocationCoordinate2D] {
        guard gridSize > 0 else { return coords }

        var snapped = coords.map { coord in
            CLLocationCoordinate2D(
                latitude: round(coord.latitude / gridSize) * gridSize,
                longitude: round(coord.longitude / gridSize) * gridSize
            )
        }

        // Remove consecutive duplicates (snapping can create them)
        snapped = removeConsecutiveDuplicates(snapped)

        return snapped
    }

    /// Selective grid snapping - only snap points that are "nearly aligned" to grid
    /// Preserves curved sections while cleaning up straight sections
    static func selectiveGridSnap(
        _ coords: [CLLocationCoordinate2D],
        gridSize: Double,
        alignmentThreshold: Double  // Max distance from grid line to snap (in degrees)
    ) -> [CLLocationCoordinate2D] {
        guard gridSize > 0 else { return coords }

        let snapped = coords.map { coord -> CLLocationCoordinate2D in
            let snappedLat = round(coord.latitude / gridSize) * gridSize
            let snappedLon = round(coord.longitude / gridSize) * gridSize

            let latDiff = abs(coord.latitude - snappedLat)
            let lonDiff = abs(coord.longitude - snappedLon)

            // Only snap if close to grid line
            let newLat = latDiff < alignmentThreshold ? snappedLat : coord.latitude
            let newLon = lonDiff < alignmentThreshold ? snappedLon : coord.longitude

            return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        }

        return removeConsecutiveDuplicates(snapped)
    }

    // MARK: - Convex Hull (Graham Scan)

    /// Compute the convex hull of a set of points
    /// Most aggressive simplification - loses all interior detail
    static func convexHull(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
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
            let distA = pow(a.latitude - pivot.latitude, 2) + pow(a.longitude - pivot.longitude, 2)
            let distB = pow(b.latitude - pivot.latitude, 2) + pow(b.longitude - pivot.longitude, 2)
            return distA < distB
        }

        // Build hull using cross product to determine turn direction
        var hull: [CLLocationCoordinate2D] = []
        for point in sorted {
            while hull.count >= 2 && crossProduct(hull[hull.count - 2], hull[hull.count - 1], point) <= 0 {
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

    // MARK: - Corner Rounding

    /// Round corners of a polygon by replacing sharp vertices with arc segments
    /// - Parameters:
    ///   - coords: The input polygon coordinates
    ///   - radius: The radius of the corner rounding (in degrees, ~0.00001 ≈ 1.1m)
    ///   - segments: Number of points to generate for each arc
    /// - Returns: A new polygon with rounded corners
    static func roundCorners(
        _ coords: [CLLocationCoordinate2D],
        radius: Double,
        segments: Int = 8
    ) -> [CLLocationCoordinate2D] {
        guard coords.count >= 3 && radius > 0 else { return coords }

        // Remove closing point if present (we'll add it back at the end)
        var points = coords
        if points.count > 1 && coordsEqual(points.first!, points.last!) {
            points.removeLast()
        }

        guard points.count >= 3 else { return coords }

        var result: [CLLocationCoordinate2D] = []

        for i in 0..<points.count {
            let prev = points[(i - 1 + points.count) % points.count]
            let curr = points[i]
            let next = points[(i + 1) % points.count]

            // Calculate vectors from current point to previous and next
            let toPrev = (prev.longitude - curr.longitude, prev.latitude - curr.latitude)
            let toNext = (next.longitude - curr.longitude, next.latitude - curr.latitude)

            // Calculate lengths
            let lenPrev = sqrt(toPrev.0 * toPrev.0 + toPrev.1 * toPrev.1)
            let lenNext = sqrt(toNext.0 * toNext.0 + toNext.1 * toNext.1)

            // Skip if edges are too short for rounding
            let minLen = min(lenPrev, lenNext)
            if minLen < radius * 2 {
                result.append(curr)
                continue
            }

            // Normalize vectors
            let unitPrev = (toPrev.0 / lenPrev, toPrev.1 / lenPrev)
            let unitNext = (toNext.0 / lenNext, toNext.1 / lenNext)

            // Calculate the angle between the two edges
            let dot = unitPrev.0 * unitNext.0 + unitPrev.1 * unitNext.1
            let angle = acos(max(-1, min(1, dot)))

            // If angle is very close to 180° (straight line), skip rounding
            if angle > .pi - 0.01 {
                result.append(curr)
                continue
            }

            // If angle is very sharp (close to 0°), skip rounding
            if angle < 0.1 {
                result.append(curr)
                continue
            }

            // Calculate the distance from corner to tangent points
            // For a circular arc tangent to both edges: d = radius / tan(angle/2)
            let halfAngle = angle / 2
            let tangentDist = min(radius / tan(halfAngle), minLen * 0.4)

            // Calculate tangent points on each edge
            let tangentPrev = CLLocationCoordinate2D(
                latitude: curr.latitude + unitPrev.1 * tangentDist,
                longitude: curr.longitude + unitPrev.0 * tangentDist
            )
            let tangentNext = CLLocationCoordinate2D(
                latitude: curr.latitude + unitNext.1 * tangentDist,
                longitude: curr.longitude + unitNext.0 * tangentDist
            )

            // Calculate the center of the arc
            // The center is along the angle bisector, at distance radius/sin(angle/2) from corner
            let bisectorX = unitPrev.0 + unitNext.0
            let bisectorY = unitPrev.1 + unitNext.1
            let bisectorLen = sqrt(bisectorX * bisectorX + bisectorY * bisectorY)

            if bisectorLen < 0.0000001 {
                // Degenerate case - just keep the corner
                result.append(curr)
                continue
            }

            let unitBisector = (bisectorX / bisectorLen, bisectorY / bisectorLen)
            let centerDist = tangentDist / sin(halfAngle)
            let center = CLLocationCoordinate2D(
                latitude: curr.latitude + unitBisector.1 * centerDist,
                longitude: curr.longitude + unitBisector.0 * centerDist
            )

            // Calculate actual arc radius (distance from center to tangent points)
            let arcRadius = sqrt(
                pow(tangentPrev.longitude - center.longitude, 2) +
                pow(tangentPrev.latitude - center.latitude, 2)
            )

            // Calculate start and end angles for the arc
            let startAngle = atan2(
                tangentPrev.latitude - center.latitude,
                tangentPrev.longitude - center.longitude
            )
            let endAngle = atan2(
                tangentNext.latitude - center.latitude,
                tangentNext.longitude - center.longitude
            )

            // Determine arc direction (we want the shorter arc on the outside of the corner)
            var arcAngle = endAngle - startAngle

            // Normalize to -π to π
            while arcAngle > .pi { arcAngle -= 2 * .pi }
            while arcAngle < -.pi { arcAngle += 2 * .pi }

            // Generate arc points
            result.append(tangentPrev)
            for j in 1..<segments {
                let t = Double(j) / Double(segments)
                let currentAngle = startAngle + arcAngle * t
                let arcPoint = CLLocationCoordinate2D(
                    latitude: center.latitude + arcRadius * sin(currentAngle),
                    longitude: center.longitude + arcRadius * cos(currentAngle)
                )
                result.append(arcPoint)
            }
            result.append(tangentNext)
        }

        // Close the polygon
        if result.count >= 3 && !coordsEqual(result.first!, result.last!) {
            result.append(result[0])
        }

        return result
    }

    // MARK: - Geometry Helpers

    /// Calculate perpendicular distance from a point to a line segment
    private static func perpendicularDistance(
        _ point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude

        if dx == 0 && dy == 0 {
            // Line start and end are the same point
            let pdx = point.longitude - lineStart.longitude
            let pdy = point.latitude - lineStart.latitude
            return sqrt(pdx * pdx + pdy * pdy)
        }

        // Project point onto line
        let t = max(0, min(1, ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)))
        let projX = lineStart.longitude + t * dx
        let projY = lineStart.latitude + t * dy
        let pdx = point.longitude - projX
        let pdy = point.latitude - projY
        return sqrt(pdx * pdx + pdy * pdy)
    }

    /// Calculate angle between two line segments at a shared point (in degrees)
    /// Returns angle at point B in the sequence A → B → C
    private static func angleBetweenSegments(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        _ c: CLLocationCoordinate2D
    ) -> Double {
        let v1 = (a.longitude - b.longitude, a.latitude - b.latitude)
        let v2 = (c.longitude - b.longitude, c.latitude - b.latitude)

        let dot = v1.0 * v2.0 + v1.1 * v2.1
        let mag1 = sqrt(v1.0 * v1.0 + v1.1 * v1.1)
        let mag2 = sqrt(v2.0 * v2.0 + v2.1 * v2.1)

        guard mag1 > 0 && mag2 > 0 else { return 180 }

        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        return acos(cosAngle) * 180 / .pi
    }

    /// Cross product of vectors OA and OB (for convex hull)
    private static func crossProduct(
        _ o: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        return (a.longitude - o.longitude) * (b.latitude - o.latitude) -
               (a.latitude - o.latitude) * (b.longitude - o.longitude)
    }

    /// Check if two coordinates are equal (within floating point tolerance)
    private static func coordsEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        return abs(a.latitude - b.latitude) < 0.0000001 &&
               abs(a.longitude - b.longitude) < 0.0000001
    }

    /// Remove consecutive duplicate coordinates
    private static func removeConsecutiveDuplicates(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coords.count > 1 else { return coords }

        var result = [coords[0]]
        for i in 1..<coords.count {
            if !coordsEqual(coords[i], result.last!) {
                result.append(coords[i])
            }
        }
        return result
    }
}
