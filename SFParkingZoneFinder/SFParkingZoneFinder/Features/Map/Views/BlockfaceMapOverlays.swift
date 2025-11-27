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

/// Custom polyline for perpendicular direction markers (debug visualization)
class PerpendicularMarker: MKPolyline {
    // Just a marker class to distinguish from centerlines
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

        // Convert width from degrees to meters (approximate at SF latitude)
        // At 37.75°N: 1° latitude ≈ 111km, 1° longitude ≈ 87.7km
        // Using average for width: ~99km per degree
        let widthMeters = widthDegrees * 99_000.0

        // Determine offset direction based on side
        // EVEN = right side, ODD = left side (SF standard)
        let offsetToRight = side.uppercased() == "EVEN"

        var offsetSide: [CLLocationCoordinate2D] = []

        // Debug logging for ALL blockfaces to help diagnose rotation issues
        let shouldDebug = true
        let devSettings = DeveloperSettings.shared

        // Convert centerline to map points (Mercator projection coordinates in meters)
        let centerlineMapPoints = centerline.map { MKMapPoint($0) }

        if shouldDebug {
            print("\n🔧 DEBUG: Perpendicular calculation")
            print("  Side: \(side) (offsetToRight=\(offsetToRight))")
            print("  Width: \(widthDegrees)° ≈ \(widthMeters)m")
            print("  First coord: lat=\(centerline[0].latitude), lon=\(centerline[0].longitude)")
            print("  First map point: x=\(centerlineMapPoints[0].x)m, y=\(centerlineMapPoints[0].y)m")
        }

        for i in 0..<centerlineMapPoints.count {
            let point = centerlineMapPoints[i]

            // Calculate perpendicular offset direction in map point space
            var perpVector: (x: Double, y: Double)

            if i == 0 {
                // First point - use direction to next point
                let next = centerlineMapPoints[i + 1]
                let forward = (x: next.x - point.x, y: next.y - point.y)

                // Calculate perpendicular in map point space (already in meters, Mercator-projected)
                // MKMapPoint: x=east (right), y=south (DOWN - inverted from normal Cartesian!)
                // For a vector pointing north (dy<0), rotating 90° clockwise should point east (dx>0)
                // Formula: 90° clockwise (RIGHT): (dx, dy) → (-dy, dx)
                // Formula: 90° counter-clockwise (LEFT): (dx, dy) → (dy, -dx)
                if offsetToRight {
                    perpVector = (x: -forward.y, y: forward.x)
                } else {
                    perpVector = (x: forward.y, y: -forward.x)
                }

                if shouldDebug && i == 0 {
                    // Calculate angles for debugging
                    let forwardAngle = atan2(forward.y, forward.x) * 180 / .pi
                    let perpAngle = atan2(perpVector.y, perpVector.x) * 180 / .pi
                    let angleDiff = perpAngle - forwardAngle

                    print("  Point 0:")
                    print("    Forward vector: dx=\(String(format: "%.2f", forward.x))m, dy=\(String(format: "%.2f", forward.y))m")
                    print("    Forward angle: \(String(format: "%.1f", forwardAngle))° (0°=east, 90°=south, -90°=north)")
                    print("    Perp vector (raw): dx=\(String(format: "%.2f", perpVector.x))m, dy=\(String(format: "%.2f", perpVector.y))m")
                    print("    Perp angle: \(String(format: "%.1f", perpAngle))°")
                    print("    Angle difference: \(String(format: "%.1f", angleDiff))° (should be ±90°)")
                }
            } else if i == centerlineMapPoints.count - 1 {
                // Last point - use direction from previous point
                let prev = centerlineMapPoints[i - 1]
                let forward = (x: point.x - prev.x, y: point.y - prev.y)

                if offsetToRight {
                    perpVector = (x: -forward.y, y: forward.x)
                } else {
                    perpVector = (x: forward.y, y: -forward.x)
                }
            } else {
                // Middle point - average of incoming and outgoing directions
                let prev = centerlineMapPoints[i - 1]
                let next = centerlineMapPoints[i + 1]
                let forwardIn = (x: point.x - prev.x, y: point.y - prev.y)
                let forwardOut = (x: next.x - point.x, y: next.y - point.y)
                let avgForward = (x: (forwardIn.x + forwardOut.x) / 2, y: (forwardIn.y + forwardOut.y) / 2)

                if offsetToRight {
                    perpVector = (x: -avgForward.y, y: avgForward.x)
                } else {
                    perpVector = (x: avgForward.y, y: -avgForward.x)
                }
            }

            // Normalize the perpendicular vector
            let magnitude = sqrt(perpVector.x * perpVector.x + perpVector.y * perpVector.y)
            guard magnitude > 0 else { continue }
            let normalized = (x: perpVector.x / magnitude, y: perpVector.y / magnitude)

            // Create offset point in map point space
            let offsetMapPoint = MKMapPoint(
                x: point.x + normalized.x * widthMeters,
                y: point.y + normalized.y * widthMeters
            )

            // Convert back to geographic coordinates
            let offsetCoord = offsetMapPoint.coordinate
            offsetSide.append(offsetCoord)

            if shouldDebug && i < 2 {
                print("  Point \(i) offset:")
                print("    Normalized perp: dx=\(String(format: "%.3f", normalized.x)), dy=\(String(format: "%.3f", normalized.y))")
                print("    Offset distance: \(String(format: "%.1f", widthMeters))m")
                print("    Center coord: (\(String(format: "%.6f", centerline[i].latitude)), \(String(format: "%.6f", centerline[i].longitude)))")
                print("    Offset coord: (\(String(format: "%.6f", offsetCoord.latitude)), \(String(format: "%.6f", offsetCoord.longitude)))")
                let latDiff = offsetCoord.latitude - centerline[i].latitude
                let lonDiff = offsetCoord.longitude - centerline[i].longitude
                print("    Coord delta: dlat=\(String(format: "%.8f", latDiff)), dlon=\(String(format: "%.8f", lonDiff))")
            }

            // Add visual debug markers: short perpendicular lines at each point
            if devSettings.showBlockfaceCenterlines && i < centerlineMapPoints.count {
                let debugLength = widthMeters * 0.3  // 30% of width for visibility
                let debugEndpoint = MKMapPoint(
                    x: point.x + normalized.x * debugLength,
                    y: point.y + normalized.y * debugLength
                )
                let marker = PerpendicularMarker(coordinates: [centerline[i], debugEndpoint.coordinate], count: 2)
                addOverlay(marker)
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

/// Renderer for perpendicular direction markers (debug visualization)
class PerpendicularMarkerRenderer: MKPolylineRenderer {
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        configureStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
        // Bright red arrows showing perpendicular offset direction
        strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
        lineWidth = 3
        // Solid line to distinguish from dashed centerline
    }
}
