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

        // Check for active street cleaning
        if blockface.hasActiveStreetCleaning() {
            // Red dashed line for active street cleaning
            strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
            lineWidth = 6
            lineDashPattern = [8, 4]
        } else if blockface.regulations.contains(where: { $0.type == "streetCleaning" }) {
            // Orange solid line for inactive street cleaning
            strokeColor = UIColor.systemOrange.withAlphaComponent(0.8)
            lineWidth = 5
        } else if let zone = blockface.permitZone {
            // Blue for permit zones
            strokeColor = permitZoneColor(zone).withAlphaComponent(0.7)
            lineWidth = 4
        } else {
            // Gray for other regulations
            strokeColor = UIColor.systemGray.withAlphaComponent(0.6)
            lineWidth = 3
        }
    }

    private func permitZoneColor(_ zone: String) -> UIColor {
        // Simple hash-based color for permit zones
        let hash = zone.hashValue
        let hue = CGFloat(abs(hash) % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
    }
}
