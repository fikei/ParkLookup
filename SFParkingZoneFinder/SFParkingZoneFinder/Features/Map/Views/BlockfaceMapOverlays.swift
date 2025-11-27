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

        for blockface in blockfaces {
            let centerline = blockface.geometry.locationCoordinates
            guard centerline.count >= 2 else { continue }

            // Add polygons if enabled
            if devSettings.showBlockfacePolygons {
                // Use developer-configured polygon width
                let laneWidthDegrees = devSettings.blockfacePolygonWidth

                guard let polygonCoords = createParkingLanePolygon(
                    centerline: centerline,
                    widthDegrees: laneWidthDegrees,
                    side: blockface.side
                ) else { continue }

                let polygon = BlockfacePolygon(
                    coordinates: polygonCoords,
                    count: polygonCoords.count
                )
                polygon.blockface = blockface

                addOverlay(polygon)
            }

            // Add centerline polylines if enabled
            if devSettings.showBlockfaceCenterlines {
                let polyline = BlockfacePolyline(
                    coordinates: centerline,
                    count: centerline.count
                )
                polyline.blockface = blockface
                addOverlay(polyline)
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

        for i in 0..<centerline.count {
            let point = centerline[i]

            // Calculate perpendicular offset direction
            var perpVector: (lat: Double, lon: Double)

            if i == 0 {
                // First point - use direction to next point
                let next = centerline[i + 1]
                let forward = (lat: next.latitude - point.latitude, lon: next.longitude - point.longitude)
                // Right perpendicular: (forward.lon, -forward.lat)
                // Left perpendicular: (-forward.lon, forward.lat)
                if offsetToRight {
                    perpVector = (lat: forward.lon, lon: -forward.lat)
                } else {
                    perpVector = (lat: -forward.lon, lon: forward.lat)
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
            offsetSide.append(CLLocationCoordinate2D(
                latitude: point.latitude + normalized.lat * widthDegrees,
                longitude: point.longitude + normalized.lon * widthDegrees
            ))
        }

        // Build polygon: centerline forward + offset side reversed to close the shape
        // This creates a polygon between the curb (centerline) and the street edge (offset)
        var polygonCoords = centerline
        polygonCoords.append(contentsOf: offsetSide.reversed())

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

    required init?(coder aDecoder: NSCoder) {
        self.blockface = nil
        super.init(coder: aDecoder)
    }

    private func configureStyle() {
        let devSettings = DeveloperSettings.shared

        // Use developer-configured color and opacity
        let baseColor = UIColor(hex: devSettings.blockfaceColorHex) ?? UIColor.systemOrange
        let opacity = devSettings.blockfaceOpacity

        fillColor = baseColor.withAlphaComponent(opacity)
        strokeColor = baseColor.withAlphaComponent(min(opacity + 0.3, 1.0))  // Slightly more opaque stroke
        lineWidth = devSettings.blockfaceStrokeWidth
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

    required init?(coder aDecoder: NSCoder) {
        self.blockface = nil
        super.init(coder: aDecoder)
    }

    private func configureStyle() {
        // Simple black centerline for debugging
        strokeColor = UIColor.black.withAlphaComponent(0.7)
        lineWidth = 2
        lineDashPattern = [2, 2]  // Dashed to distinguish from polygon borders
    }
}
