import MapKit
import SwiftUI

/// Custom polyline that holds reference to blockface data
class BlockfacePolyline: MKPolyline {
    var blockface: Blockface?
}

/// Extension to add blockface rendering to existing map views
extension MKMapView {
    /// Add blockface overlays to the map
    func addBlockfaceOverlays(_ blockfaces: [Blockface]) {
        for blockface in blockfaces {
            let coordinates = blockface.geometry.locationCoordinates
            guard coordinates.count >= 2 else { continue }

            let polyline = BlockfacePolyline(
                coordinates: coordinates,
                count: coordinates.count
            )
            polyline.blockface = blockface

            addOverlay(polyline)
        }
    }

    /// Remove all blockface overlays
    func removeBlockfaceOverlays() {
        let blockfaceOverlays = overlays.compactMap { $0 as? BlockfacePolyline }
        removeOverlays(blockfaceOverlays)
    }
}

/// Renderer for blockface polylines
class BlockfacePolylineRenderer: MKPolylineRenderer {
    let blockface: Blockface?

    init(polyline: MKPolyline, blockface: Blockface) {
        self.blockface = blockface
        super.init(polyline: polyline)

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
            strokeColor = UIColor.systemGray.withAlphaComponent(0.5)
            lineWidth = 2
            return
        }

        // Priority order: street cleaning (active) > no parking > metered > time limit > permit > other
        // This ensures the most restrictive/important rules are visually prominent

        // 1. Active street cleaning - highest priority (can't park NOW)
        if blockface.hasActiveStreetCleaning() {
            strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
            lineWidth = 6
            lineDashPattern = [8, 4]  // Dashed to show urgency
            return
        }

        // 2. No parking zones
        if let noParkingReg = blockface.regulations.first(where: { $0.type == "noParking" }) {
            if noParkingReg.isInEffect() {
                strokeColor = UIColor.systemRed.withAlphaComponent(0.85)
                lineWidth = 5
                lineDashPattern = [4, 4]  // Shorter dashes
            } else {
                strokeColor = UIColor.systemPink.withAlphaComponent(0.6)
                lineWidth = 4
            }
            return
        }

        // 3. Tow-away zones
        if blockface.regulations.contains(where: { $0.type == "towAway" }) {
            strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
            lineWidth = 6
            lineDashPattern = [6, 3, 2, 3]  // Distinctive dash-dot pattern
            return
        }

        // 4. Loading zones (commercial hours)
        if let loadingReg = blockface.regulations.first(where: { $0.type == "loadingZone" }) {
            if loadingReg.isInEffect() {
                strokeColor = UIColor.systemPurple.withAlphaComponent(0.8)
                lineWidth = 5
                lineDashPattern = [10, 5]
            } else {
                strokeColor = UIColor.systemPurple.withAlphaComponent(0.5)
                lineWidth = 3
            }
            return
        }

        // 5. Metered parking
        if blockface.regulations.contains(where: { $0.type == "metered" }) {
            strokeColor = UIColor.systemGreen.withAlphaComponent(0.75)
            lineWidth = 5
            return
        }

        // 6. Inactive street cleaning (scheduled but not now)
        if blockface.regulations.contains(where: { $0.type == "streetCleaning" }) {
            strokeColor = UIColor.systemOrange.withAlphaComponent(0.8)
            lineWidth = 5
            return
        }

        // 7. Time limits
        if blockface.regulations.contains(where: { $0.type == "timeLimit" }) {
            strokeColor = UIColor.systemYellow.withAlphaComponent(0.8)
            lineWidth = 4
            return
        }

        // 8. Permit zones
        if let zone = blockface.permitZone {
            strokeColor = permitZoneColor(zone).withAlphaComponent(0.7)
            lineWidth = 4
            return
        }

        // Default - no specific regulation identified
        strokeColor = UIColor.systemGray.withAlphaComponent(0.6)
        lineWidth = 3
    }

    private func permitZoneColor(_ zone: String) -> UIColor {
        // Simple hash-based color for permit zones
        let hash = zone.hashValue
        let hue = CGFloat(abs(hash) % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
    }
}
