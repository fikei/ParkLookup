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
                // For geographic coordinates where north=+lat, east=+lon:
                // 90° clockwise (RIGHT turn): (dlat, dlon) → (+dlon, -dlat)
                // 90° counter-clockwise (LEFT turn): (dlat, dlon) → (-dlon, +dlat)
                if offsetToRight {
                    perpVector = (lat: forward.lon, lon: -forward.lat)
                } else {
                    perpVector = (lat: -forward.lon, lon: forward.lat)
                }

                if shouldDebug {
                    print("🔧 DEBUG: Perpendicular calculation for \(side) side (offsetToRight=\(offsetToRight))")
                    print("  Forward vector: dlat=\(forward.lat), dlon=\(forward.lon)")
                    print("  Perp vector: dlat=\(perpVector.lat), dlon=\(perpVector.lon)")
                }
            } else if i == centerline.count - 1 {
                // Last point - use direction from previous point
                let prev = centerline[i - 1]
                let forward = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)
                if offsetToRight {
                    perpVector = (lat: forward.lon, lon: -forward.lat)
                } else {
                    perpVector = (lat: -forward.lon, lon: forward.lat)
                }
            } else {
                // Middle point - average of incoming and outgoing directions
                let prev = centerline[i - 1]
                let next = centerline[i + 1]
                let forwardIn = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)
                let forwardOut = (lat: next.latitude - point.latitude, lon: next.longitude - point.longitude)
                let avgForward = (lat: (forwardIn.lat + forwardOut.lat) / 2, lon: (forwardIn.lon + forwardOut.lon) / 2)
                if offsetToRight {
                    perpVector = (lat: avgForward.lon, lon: -avgForward.lat)
                } else {
                    perpVector = (lat: -avgForward.lon, lon: avgForward.lat)
                }
            }

            // Normalize perpendicular vector
            let magnitude = sqrt(perpVector.lat * perpVector.lat + perpVector.lon * perpVector.lon)
            guard magnitude > 0 else { continue }
            let normalized = (lat: perpVector.lat / magnitude, lon: perpVector.lon / magnitude)

            // Create offset point
            // Don't scale - use raw offset since perpendicular is already in coordinate space
            let offsetPoint = CLLocationCoordinate2D(
                latitude: point.latitude + normalized.lat * widthDegrees,
                longitude: point.longitude + normalized.lon * widthDegrees
            )
            offsetSide.append(offsetPoint)

            if shouldDebug && i < 2 {
                print("  Point \(i): centerline=(\(point.latitude), \(point.longitude)), offset=(\(offsetPoint.latitude), \(offsetPoint.longitude))")
                print("    Offset applied: dlat=\(normalized.lat * widthDegrees), dlon=\(normalized.lon * widthDegrees)")
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
