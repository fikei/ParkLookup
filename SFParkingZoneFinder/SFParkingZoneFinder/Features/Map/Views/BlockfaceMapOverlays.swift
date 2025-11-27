import MapKit
import SwiftUI
import CoreLocation

/// Custom polygon that holds reference to blockface data
class BlockfacePolygon: MKPolygon {
    var blockface: Blockface?
}

/// Extension to add blockface rendering to existing map views
extension MKMapView {
    /// Add blockface overlays to the map as polygons with actual width
    func addBlockfaceOverlays(_ blockfaces: [Blockface]) {
        for blockface in blockfaces {
            let centerline = blockface.geometry.locationCoordinates
            guard centerline.count >= 2 else { continue }

            // Create a parking lane polygon by offsetting the centerline perpendicular to the street
            // Width represents ~8 feet parking lane (approximately 0.00002 degrees latitude ≈ 2.4m)
            let laneWidthDegrees = 0.00002

            guard let polygonCoords = createParkingLanePolygon(
                centerline: centerline,
                widthDegrees: laneWidthDegrees
            ) else { continue }

            let polygon = BlockfacePolygon(
                coordinates: polygonCoords,
                count: polygonCoords.count
            )
            polygon.blockface = blockface

            addOverlay(polygon)
        }
    }

    /// Remove all blockface overlays
    func removeBlockfaceOverlays() {
        let blockfaceOverlays = overlays.compactMap { $0 as? BlockfacePolygon }
        removeOverlays(blockfaceOverlays)
    }

    /// Create a polygon representing a parking lane by offsetting a centerline
    private func createParkingLanePolygon(
        centerline: [CLLocationCoordinate2D],
        widthDegrees: Double
    ) -> [CLLocationCoordinate2D]? {
        guard centerline.count >= 2 else { return nil }

        var leftSide: [CLLocationCoordinate2D] = []
        var rightSide: [CLLocationCoordinate2D] = []

        for i in 0..<centerline.count {
            let point = centerline[i]

            // Calculate perpendicular offset direction
            var perpVector: (lat: Double, lon: Double)

            if i == 0 {
                // First point - use direction to next point
                let next = centerline[i + 1]
                let forward = (lat: next.latitude - point.latitude, lon: next.longitude - point.longitude)
                perpVector = (lat: -forward.lon, lon: forward.lat)
            } else if i == centerline.count - 1 {
                // Last point - use direction from previous point
                let prev = centerline[i - 1]
                let forward = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)
                perpVector = (lat: -forward.lon, lon: forward.lat)
            } else {
                // Middle point - average of incoming and outgoing directions
                let prev = centerline[i - 1]
                let next = centerline[i + 1]
                let forwardIn = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)
                let forwardOut = (lat: next.latitude - point.latitude, lon: next.longitude - point.longitude)
                let avgForward = (lat: (forwardIn.lat + forwardOut.lat) / 2, lon: (forwardIn.lon + forwardOut.lon) / 2)
                perpVector = (lat: -avgForward.lon, lon: avgForward.lat)
            }

            // Normalize perpendicular vector
            let magnitude = sqrt(perpVector.lat * perpVector.lat + perpVector.lon * perpVector.lon)
            guard magnitude > 0 else { continue }
            let normalized = (lat: perpVector.lat / magnitude, lon: perpVector.lon / magnitude)

            // Create offset points on both sides
            let offset = widthDegrees / 2  // Half width on each side
            leftSide.append(CLLocationCoordinate2D(
                latitude: point.latitude + normalized.lat * offset,
                longitude: point.longitude + normalized.lon * offset
            ))
            rightSide.append(CLLocationCoordinate2D(
                latitude: point.latitude - normalized.lat * offset,
                longitude: point.longitude - normalized.lon * offset
            ))
        }

        // Build polygon: left side forward + right side reversed to close the shape
        var polygonCoords = leftSide
        polygonCoords.append(contentsOf: rightSide.reversed())

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
        guard let blockface = blockface else {
            // Default style if no blockface data
            fillColor = UIColor.systemGray.withAlphaComponent(0.3)
            strokeColor = UIColor.systemGray.withAlphaComponent(0.6)
            lineWidth = 1
            return
        }

        // Priority order: street cleaning (active) > no parking > metered > time limit > permit > other
        // This ensures the most restrictive/important rules are visually prominent

        // 1. Active street cleaning - highest priority (can't park NOW)
        if blockface.hasActiveStreetCleaning() {
            fillColor = UIColor.systemRed.withAlphaComponent(0.6)
            strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
            lineWidth = 2
            lineDashPattern = [8, 4]  // Dashed border to show urgency
            return
        }

        // 2. No parking zones
        if let noParkingReg = blockface.regulations.first(where: { $0.type == "noParking" }) {
            if noParkingReg.isInEffect() {
                fillColor = UIColor.systemRed.withAlphaComponent(0.5)
                strokeColor = UIColor.systemRed.withAlphaComponent(0.85)
                lineWidth = 2
                lineDashPattern = [4, 4]  // Shorter dashes
            } else {
                fillColor = UIColor.systemPink.withAlphaComponent(0.3)
                strokeColor = UIColor.systemPink.withAlphaComponent(0.6)
                lineWidth = 1
            }
            return
        }

        // 3. Tow-away zones
        if blockface.regulations.contains(where: { $0.type == "towAway" }) {
            fillColor = UIColor.systemRed.withAlphaComponent(0.6)
            strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
            lineWidth = 2
            lineDashPattern = [6, 3, 2, 3]  // Distinctive dash-dot pattern
            return
        }

        // 4. Loading zones (commercial hours)
        if let loadingReg = blockface.regulations.first(where: { $0.type == "loadingZone" }) {
            if loadingReg.isInEffect() {
                fillColor = UIColor.systemPurple.withAlphaComponent(0.5)
                strokeColor = UIColor.systemPurple.withAlphaComponent(0.8)
                lineWidth = 2
                lineDashPattern = [10, 5]
            } else {
                fillColor = UIColor.systemPurple.withAlphaComponent(0.2)
                strokeColor = UIColor.systemPurple.withAlphaComponent(0.5)
                lineWidth = 1
            }
            return
        }

        // 5. Metered parking
        if blockface.regulations.contains(where: { $0.type == "metered" }) {
            fillColor = UIColor.systemGreen.withAlphaComponent(0.4)
            strokeColor = UIColor.systemGreen.withAlphaComponent(0.75)
            lineWidth = 1.5
            return
        }

        // 6. Inactive street cleaning (scheduled but not now)
        if blockface.regulations.contains(where: { $0.type == "streetCleaning" }) {
            fillColor = UIColor.systemOrange.withAlphaComponent(0.4)
            strokeColor = UIColor.systemOrange.withAlphaComponent(0.8)
            lineWidth = 1.5
            return
        }

        // 7. Time limits
        if blockface.regulations.contains(where: { $0.type == "timeLimit" }) {
            fillColor = UIColor.systemYellow.withAlphaComponent(0.4)
            strokeColor = UIColor.systemYellow.withAlphaComponent(0.8)
            lineWidth = 1.5
            return
        }

        // 8. Permit zones
        if let zone = blockface.permitZone {
            let color = permitZoneColor(zone)
            fillColor = color.withAlphaComponent(0.35)
            strokeColor = color.withAlphaComponent(0.7)
            lineWidth = 1.5
            return
        }

        // Default - no specific regulation identified
        fillColor = UIColor.systemGray.withAlphaComponent(0.3)
        strokeColor = UIColor.systemGray.withAlphaComponent(0.6)
        lineWidth = 1
    }

    private func permitZoneColor(_ zone: String) -> UIColor {
        // Simple hash-based color for permit zones
        let hash = zone.hashValue
        let hue = CGFloat(abs(hash) % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
    }
}
