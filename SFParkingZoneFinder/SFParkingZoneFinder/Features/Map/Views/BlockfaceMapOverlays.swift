import MapKit
import SwiftUI
import CoreLocation

/// Custom polygon that holds reference to blockface data
class BlockfacePolygon: MKPolygon {
    var blockface: Blockface?
}

/// Custom polyline for blockface centerlines (debug visualization)
class BlockfacePolyline: MKPolyline {
    var blockface: Blockface?
}

/// Extension to add blockface rendering to existing map views
extension MKMapView {
    /// Add blockface overlays to the map as polygons with actual width
    func addBlockfaceOverlays(_ blockfaces: [Blockface]) {
        let devSettings = DeveloperSettings.shared

        print("🔧 DEBUG: Adding \(blockfaces.count) blockface overlays")

        for (index, blockface) in blockfaces.enumerated() {
            let centerline = blockface.geometry.locationCoordinates
            guard centerline.count >= 2 else { continue }

            if index < 3 {  // Log first 3 blockfaces for debugging
                print("🔧 DEBUG: Blockface \(index) (\(blockface.street), \(blockface.side) side)")
                print("  Centerline points: \(centerline.count)")
                print("  First point: lat=\(centerline[0].latitude), lon=\(centerline[0].longitude)")
                print("  Second point: lat=\(centerline[1].latitude), lon=\(centerline[1].longitude)")
                let dlat = centerline[1].latitude - centerline[0].latitude
                let dlon = centerline[1].longitude - centerline[0].longitude
                print("  Direction: dlat=\(dlat), dlon=\(dlon)")
            }

            // Add polygons if enabled
            if devSettings.showBlockfacePolygons {
                // TESTING: Force large width to rule out thin polygon rendering artifacts
                let laneWidthDegrees = 0.0003  // ~36m / 118 feet - should be very visible

                guard let polygonCoords = createParkingLanePolygon(
                    centerline: centerline,
                    widthDegrees: laneWidthDegrees,
                    side: blockface.side
                ) else { continue }

                if index < 3 {
                    print("  Created polygon with \(polygonCoords.count) points")
                    print("  Width setting: \(laneWidthDegrees) degrees (TESTING: forced large)")
                }

                let polygon = BlockfacePolygon(
                    coordinates: polygonCoords,
                    count: polygonCoords.count
                )
                polygon.blockface = blockface

                if index < 3 {
                    print("  ✅ Adding polygon overlay to map")
                }
                addOverlay(polygon)
            } else if index < 3 {
                print("  ⚠️ SKIPPING polygon - showBlockfacePolygons is OFF")
            }

            // Add centerline polylines if enabled
            if devSettings.showBlockfaceCenterlines {
                let polyline = BlockfacePolyline(
                    coordinates: centerline,
                    count: centerline.count
                )
                polyline.blockface = blockface
                if index < 3 {
                    print("  ✅ Adding centerline polyline overlay to map")
                }
                addOverlay(polyline)
            } else if index < 3 {
                print("  ⚠️ SKIPPING centerline - showBlockfaceCenterlines is OFF")
            }

            // DIAGNOSTIC: Add direction arrow at start of each blockface
            if devSettings.showBlockfaceCenterlines && centerline.count >= 2 {
                let start = centerline[0]
                let next = centerline[1]
                let arrowLength = 0.00015  // Small arrow in degrees
                let dx = next.longitude - start.longitude
                let dy = next.latitude - start.latitude
                let len = sqrt(dx*dx + dy*dy)
                let endPoint = CLLocationCoordinate2D(
                    latitude: start.latitude + (dy/len) * arrowLength,
                    longitude: start.longitude + (dx/len) * arrowLength
                )
                let arrow = MKPolyline(coordinates: [start, endPoint], count: 2)
                addOverlay(arrow)
            }
        }
    }

    /// Remove all blockface overlays
    func removeBlockfaceOverlays() {
        let blockfaceOverlays = overlays.compactMap { $0 as? BlockfacePolygon }
        removeOverlays(blockfaceOverlays)
    }

    /// Create a polygon representing a parking lane by offsetting a centerline
    /// Offsets to the appropriate side based on SF addressing convention:
    /// - EVEN addresses = RIGHT side of street (when traveling in line direction)
    /// - ODD addresses = LEFT side of street (when traveling in line direction)
    private func createParkingLanePolygon(
        centerline: [CLLocationCoordinate2D],
        widthDegrees: Double,
        side: String
    ) -> [CLLocationCoordinate2D]? {
        guard centerline.count >= 2 else { return nil }

        // Determine offset direction based on side
        // EVEN = right side, ODD = left side (SF standard)
        let offsetToRight = side.uppercased() == "EVEN"

        var offsetSide: [CLLocationCoordinate2D] = []

        // Debug logging for first blockface
        let shouldDebug = centerline.count >= 2 &&
                         abs(centerline[0].latitude - 37.7564) < 0.001 &&
                         abs(centerline[0].longitude - (-122.4193)) < 0.001

        for i in 0..<centerline.count {
            let point = centerline[i]

            // Calculate perpendicular offset direction
            var perpVector: (lat: Double, lon: Double)

            if i == 0 {
                // First point - use direction to next point
                let next = centerline[i + 1]
                let forward = (lat: next.latitude - point.latitude, lon: next.longitude - point.longitude)

                // Account for latitude/longitude scaling
                // At higher latitudes, longitude degrees are "shorter" than latitude degrees
                // 1° lon = 1° lat × cos(latitude) in ground distance
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians)

                // Scale longitude to metric space where 1° lon = 1° lat in actual distance
                let forwardMetric = (lat: forward.lat, lon: forward.lon * lonScaleFactor)

                // Calculate perpendicular in metric space
                // 90° clockwise (RIGHT): (dlat, dlon) → (+dlon, -dlat)
                // 90° counter-clockwise (LEFT): (dlat, dlon) → (-dlon, +dlat)
                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                } else {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                }

                // Normalize in metric space (where lat and lon have same scale)
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                // Convert back to geographic space by unscaling longitude
                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon / lonScaleFactor)

                if shouldDebug {
                    print("🔧 DEBUG: Perpendicular calculation for \(side) side (offsetToRight=\(offsetToRight))")
                    print("  Latitude: \(point.latitude)°, lonScaleFactor: \(lonScaleFactor)")
                    print("  Forward vector: dlat=\(forward.lat), dlon=\(forward.lon)")

                    // Diagnose forward direction
                    let fwdDir = describeDirection(dlat: forward.lat, dlon: forward.lon)
                    print("  Forward points: \(fwdDir)")

                    print("  Forward (metric): dlat=\(forwardMetric.lat), dlon=\(forwardMetric.lon)")
                    print("  Perp (metric): dlat=\(perpMetric.lat), dlon=\(perpMetric.lon)")
                    print("  Perp (geographic): dlat=\(perpVector.lat), dlon=\(perpVector.lon)")

                    // Diagnose perpendicular direction
                    let perpDir = describeDirection(dlat: perpVector.lat, dlon: perpVector.lon)
                    print("  Perpendicular points: \(perpDir)")

                    // Determine if this is a left or right turn
                    let turn = determineTurn(forward: (forward.lat, forward.lon), perp: (perpVector.lat, perpVector.lon))
                    print("  Turn direction: \(turn) (expected: \(offsetToRight ? "RIGHT" : "LEFT"))")
                }
            } else if i == centerline.count - 1 {
                // Last point - use direction from previous point
                let prev = centerline[i - 1]
                let forward = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)

                // Account for latitude/longitude scaling
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians)
                let forwardMetric = (lat: forward.lat, lon: forward.lon * lonScaleFactor)

                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                } else {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                }

                // Normalize in metric space
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon / lonScaleFactor)
            } else {
                // Middle point - average of incoming and outgoing directions
                let prev = centerline[i - 1]
                let next = centerline[i + 1]
                let forwardIn = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)
                let forwardOut = (lat: next.latitude - point.latitude, lon: next.longitude - point.longitude)
                let avgForward = (lat: (forwardIn.lat + forwardOut.lat) / 2, lon: (forwardIn.lon + forwardOut.lon) / 2)

                // Account for latitude/longitude scaling
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians)
                let forwardMetric = (lat: avgForward.lat, lon: avgForward.lon * lonScaleFactor)

                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                } else {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                }

                // Normalize in metric space
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon / lonScaleFactor)
            }

            // perpVector is already normalized from metric space calculation above
            // Create offset point by scaling the normalized perpVector by desired width
            let offsetPoint = CLLocationCoordinate2D(
                latitude: point.latitude + perpVector.lat * widthDegrees,
                longitude: point.longitude + perpVector.lon * widthDegrees
            )
            offsetSide.append(offsetPoint)

            if shouldDebug && i < 2 {
                let dlat = offsetPoint.latitude - point.latitude
                let dlon = offsetPoint.longitude - point.longitude
                print("  Point \(i): centerline=(\(point.latitude), \(point.longitude)), offset=(\(offsetPoint.latitude), \(offsetPoint.longitude))")
                print("    Offset applied: dlat=\(dlat), dlon=\(dlon)")
            }
        }

        // Build polygon: centerline forward + offset side reversed to close the shape
        // This creates a polygon between the curb (centerline) and the street edge (offset)
        var polygonCoords = centerline
        polygonCoords.append(contentsOf: offsetSide.reversed())

        // Debug: Print all polygon vertices
        if shouldDebug {
            print("  🔷 COMPLETE POLYGON - Total vertices: " + String(polygonCoords.count))
            for (idx, coord) in polygonCoords.enumerated() {
                let label = idx < centerline.count ? "CENTER" : "OFFSET"
                print("    [\(idx)] \(label): lat=\(coord.latitude), lon=\(coord.longitude)")
            }
        }

        return polygonCoords.count >= 3 ? polygonCoords : nil
    }
}

/// Renderer for blockface polygons with actual width/dimension
class BlockfacePolygonRenderer: MKPolygonRenderer {
    let blockface: Blockface?

    init(polygon: MKPolygon, blockface: Blockface) {
        self.blockface = blockface
        super.init(polygon: polygon)

        // Configure rendering based on blockface properties
        configureStyle()
    }

    // Required initializers - not used in our implementation
    override init(overlay: MKOverlay) {
        self.blockface = nil
        super.init(overlay: overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
        let devSettings = DeveloperSettings.shared

        // TESTING: Force full opacity and bright color to rule out visibility issues
        let baseColor = UIColor.systemOrange
        let opacity = 1.0  // 100% opacity for testing

        fillColor = baseColor.withAlphaComponent(opacity)

        // Disable stroke for thin polygons - the stroke creates visible diagonal lines
        // between centerline and offset that look wrong on the map
        strokeColor = nil
        lineWidth = 0

        // Debug: Log rendering configuration for first few polygons
        if let bf = blockface {
            print("  🎨 Renderer config for \(bf.street) \(bf.side): fillOpacity=\(opacity) (TESTING: forced), stroke=DISABLED, color=ORANGE (forced)")
        }
    }
}

/// Renderer for blockface centerline polylines (debug visualization)
class BlockfacePolylineRenderer: MKPolylineRenderer {
    let blockface: Blockface?

    init(polyline: MKPolyline, blockface: Blockface?) {
        self.blockface = blockface
        super.init(polyline: polyline)
        configureStyle()
    }

    override init(overlay: MKOverlay) {
        self.blockface = nil
        super.init(overlay: overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
        // Simple black centerline for debugging
        strokeColor = UIColor.black.withAlphaComponent(0.7)
        lineWidth = 2
        lineDashPattern = [2, 2]  // Dashed to distinguish from polygon borders
    }
}

// MARK: - Diagnostic Helpers

/// Describe the compass direction of a vector
private func describeDirection(dlat: Double, dlon: Double) -> String {
    let threshold = 0.3  // Ratio threshold for "mostly" one direction
    let latAbs = abs(dlat)
    let lonAbs = abs(dlon)
    let total = latAbs + lonAbs

    if total == 0 { return "ZERO" }

    let latRatio = latAbs / total
    let lonRatio = lonAbs / total

    var parts: [String] = []

    if latRatio > threshold {
        parts.append(dlat > 0 ? "NORTH" : "SOUTH")
    }
    if lonRatio > threshold {
        parts.append(dlon > 0 ? "EAST" : "WEST")
    }

    return parts.isEmpty ? "UNCLEAR" : parts.joined(separator: "-")
}

/// Determine if perpendicular is a LEFT or RIGHT turn from forward
/// Uses cross product: forward × perp > 0 → left turn, < 0 → right turn
private func determineTurn(forward: (lat: Double, lon: Double), perp: (lat: Double, lon: Double)) -> String {
    // In lat/lon space: lat=y, lon=x
    // Cross product z-component: forward.x * perp.y - forward.y * perp.x
    let cross = forward.lon * perp.lat - forward.lat * perp.lon

    if abs(cross) < 1e-10 { return "PARALLEL/OPPOSITE" }
    return cross > 0 ? "LEFT" : "RIGHT"
}
