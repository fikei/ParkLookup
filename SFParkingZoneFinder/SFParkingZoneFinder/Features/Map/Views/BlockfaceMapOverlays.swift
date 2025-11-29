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

        for blockface in blockfaces {
            let centerline = blockface.geometry.locationCoordinates
            guard centerline.count >= 2 else { continue }

            // Add polygons if enabled
            if devSettings.showBlockfacePolygons {
                // 6 meters width at SF latitude (37.75°N)
                // 1 degree latitude ≈ 111km, so 6m ≈ 0.000054 degrees
                let laneWidthDegrees = 0.000054

                guard var polygonCoords = createParkingLanePolygon(
                    centerline: centerline,
                    widthDegrees: laneWidthDegrees,
                    side: blockface.side
                ) else { continue }

                let polygon = BlockfacePolygon(
                    coordinates: &polygonCoords,
                    count: polygonCoords.count
                )
                polygon.blockface = blockface
                addOverlay(polygon)
            }

            // Add centerline polylines if enabled (for debugging)
            if devSettings.showBlockfaceCenterlines {
                var mutableCenterline = centerline
                let polyline = BlockfacePolyline(
                    coordinates: &mutableCenterline,
                    count: mutableCenterline.count
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

                // Account for latitude/longitude scaling
                // At higher latitudes, longitude degrees are "shorter" than latitude degrees
                // 1° lon = 1° lat × cos(latitude) in ground distance
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians)

                // Scale longitude to metric space where 1° lon = 1° lat in actual distance
                // Since 1° lon is shorter, we DIVIDE by cos(lat) to scale it UP
                let forwardMetric = (lat: forward.lat, lon: forward.lon / lonScaleFactor)

                // Calculate perpendicular in metric space
                // In metric space where coordinates are (lat, lon) representing (y, x):
                // 90° clockwise RIGHT turn: (y, x) → (-x, y) → (lat: -lon, lon: lat)
                // 90° counter-clockwise LEFT turn: (y, x) → (x, -y) → (lat: lon, lon: -lat)
                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                } else {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                }

                // Normalize in metric space (where lat and lon have same scale)
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                // Convert back to geographic space by scaling longitude back DOWN
                // Since we divided by cos(lat) to go TO metric, we multiply to go back
                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon * lonScaleFactor)
            } else if i == centerline.count - 1 {
                // Last point - use direction from previous point
                let prev = centerline[i - 1]
                let forward = (lat: point.latitude - prev.latitude, lon: point.longitude - prev.longitude)

                // Account for latitude/longitude scaling
                let latRadians = point.latitude * .pi / 180
                let lonScaleFactor = cos(latRadians)
                let forwardMetric = (lat: forward.lat, lon: forward.lon / lonScaleFactor)

                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                } else {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                }

                // Normalize in metric space
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon * lonScaleFactor)
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
                let forwardMetric = (lat: avgForward.lat, lon: avgForward.lon / lonScaleFactor)

                var perpMetric: (lat: Double, lon: Double)
                if offsetToRight {
                    perpMetric = (lat: -forwardMetric.lon, lon: forwardMetric.lat)
                } else {
                    perpMetric = (lat: forwardMetric.lon, lon: -forwardMetric.lat)
                }

                // Normalize in metric space
                let magnitudeMetric = sqrt(perpMetric.lat * perpMetric.lat + perpMetric.lon * perpMetric.lon)
                guard magnitudeMetric > 0 else { continue }
                let normalizedMetric = (lat: perpMetric.lat / magnitudeMetric, lon: perpMetric.lon / magnitudeMetric)

                perpVector = (lat: normalizedMetric.lat, lon: normalizedMetric.lon * lonScaleFactor)
            }

            // perpVector is already normalized from metric space calculation above
            // Create offset point by scaling the normalized perpVector by desired width
            let offsetPoint = CLLocationCoordinate2D(
                latitude: point.latitude + perpVector.lat * widthDegrees,
                longitude: point.longitude + perpVector.lon * widthDegrees
            )
            offsetSide.append(offsetPoint)
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureStyle() {
        let devSettings = DeveloperSettings.shared

        // Updated color coding based on regulation type:
        // 1. No parking → Red
        // 2. Street cleaning (when ACTIVE or within park-until window) → Red
        // 3. Metered/Paid → Grey
        // 4. Time Limited → Orange
        // 5. RPP (residential permit) → Orange
        // 6. No restrictions (free parking) → Green
        let baseColor: UIColor
        let opacity: Double

        if let bf = blockface {
            if bf.regulations.isEmpty {
                // No restrictions = free parking → Green
                baseColor = UIColor.systemGreen
                opacity = devSettings.blockfaceOpacity
            } else {
                // Check regulation types to determine color (priority order)
                var hasActiveStreetCleaning = false
                var hasMetered = false
                var hasRPP = false
                var hasTimeLimit = false
                var hasNoParking = false

                let now = Date()
                let calendar = Calendar.current
                // Check within next 2 hours for "park until" window
                let parkUntilWindow = calendar.date(byAdding: .hour, value: 2, to: now) ?? now

                for reg in bf.regulations {
                    let regType = reg.type.lowercased()

                    if regType == "noparking" || regType == "no parking" {
                        hasNoParking = true
                    }
                    if regType == "streetcleaning" || regType == "street cleaning" {
                        // Only consider street cleaning if active NOW or within park-until window
                        if isStreetCleaningActive(regulation: reg, at: now, untilDate: parkUntilWindow) {
                            hasActiveStreetCleaning = true
                        }
                    }
                    if regType == "metered" || regType == "meter" {
                        hasMetered = true
                    }
                    if let permitZone = reg.permitZone, !permitZone.isEmpty {
                        hasRPP = true
                    }
                    if regType == "timelimit" || regType == "time limit" {
                        hasTimeLimit = true
                    }

                    // Debug: Log first regulation type for this blockface
                    if bf.regulations.first === reg {
                        print("📍 DEBUG: First regulation type for \(bf.street): '\(reg.type)'")
                    }
                }

                // Priority: No Parking > Active Street Cleaning > Metered > Time Limited/RPP
                if hasNoParking {
                    baseColor = UIColor.systemRed
                    opacity = devSettings.blockfaceOpacity
                } else if hasActiveStreetCleaning {
                    baseColor = UIColor.systemRed
                    opacity = devSettings.blockfaceOpacity
                } else if hasMetered {
                    // Metered/Paid parking → Grey
                    baseColor = UIColor.systemGray
                    opacity = devSettings.blockfaceOpacity
                } else if hasTimeLimit || hasRPP {
                    // Timed zones and RPP → Orange
                    baseColor = UIColor.systemOrange
                    opacity = devSettings.blockfaceOpacity
                } else {
                    // Default to green for unknown types (free parking)
                    print("⚠️ DEBUG: Unknown regulation types for \(bf.street), defaulting to green")
                    baseColor = UIColor.systemGreen
                    opacity = devSettings.blockfaceOpacity
                }
            }

            fillColor = baseColor.withAlphaComponent(opacity)
        } else {
            // No blockface info - shouldn't happen
            fillColor = UIColor.clear
        }

        // Disable stroke for thin polygons - the stroke creates visible diagonal lines
        // between centerline and offset that look wrong on the map
        strokeColor = nil
        lineWidth = 0
    }

    /// Check if street cleaning is active now or will be active within the park-until window
    private func isStreetCleaningActive(regulation: BlockfaceRegulation, at date: Date, untilDate: Date) -> Bool {
        guard let daysStr = regulation.enforcementDays,
              let startStr = regulation.enforcementStart,
              let endStr = regulation.enforcementEnd else {
            return false
        }

        // Parse time strings (HH:MM format)
        func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
            let components = timeStr.split(separator: ":").compactMap { Int($0) }
            guard components.count == 2 else { return nil }
            return (hour: components[0], minute: components[1])
        }

        guard let startTime = parseTime(startStr),
              let endTime = parseTime(endStr) else {
            return false
        }

        // Convert string days to check
        let cleaningDays = daysStr.compactMap { dayStr -> Int? in
            // Map day strings to Calendar weekday values (1=Sunday, 2=Monday, etc.)
            let dayLower = dayStr.lowercased()
            switch dayLower {
            case "sunday", "sun": return 1
            case "monday", "mon": return 2
            case "tuesday", "tue", "tues": return 3
            case "wednesday", "wed": return 4
            case "thursday", "thu", "thurs": return 5
            case "friday", "fri": return 6
            case "saturday", "sat": return 7
            default: return nil
            }
        }

        guard !cleaningDays.isEmpty else { return false }

        let calendar = Calendar.current

        // Check only next 3 days (enough for 2-hour park-until window)
        for dayOffset in 0..<3 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: checkDate)

            if cleaningDays.contains(weekday) {
                // This day has street cleaning, check if the time window overlaps
                guard let cleaningStart = calendar.date(
                    bySettingHour: startTime.hour,
                    minute: startTime.minute,
                    second: 0,
                    of: checkDate
                ),
                let cleaningEnd = calendar.date(
                    bySettingHour: endTime.hour,
                    minute: endTime.minute,
                    second: 0,
                    of: checkDate
                ) else {
                    continue
                }

                // Check if this cleaning window overlaps with our date-untilDate window
                if cleaningEnd > date && cleaningStart <= untilDate {
                    return true
                }
            }
        }

        return false
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
        let devSettings = DeveloperSettings.shared

        // Use zone color scheme for consistency with parking zone overlays
        let baseColor: UIColor

        if let bf = blockface {
            if bf.regulations.isEmpty {
                // No restrictions = free parking → My Permit Zones color (Green)
                baseColor = devSettings.myPermitZonesColor
            } else {
                // Check regulation types to determine color (priority order)
                var hasStreetCleaning = false
                var hasMetered = false
                var hasRPP = false
                var hasTimeLimit = false
                var hasNoParking = false

                for reg in bf.regulations {
                    if reg.type == "streetCleaning" {
                        hasStreetCleaning = true
                    }
                    if reg.type == "metered" {
                        hasMetered = true
                    }
                    if let permitZone = reg.permitZone, !permitZone.isEmpty {
                        hasRPP = true
                    }
                    if reg.type == "timeLimit" {
                        hasTimeLimit = true
                    }
                    if reg.type == "noParking" {
                        hasNoParking = true
                    }
                }

                // Priority: No Parking > Street Cleaning > Metered > RPP > Time Limited
                // Use zone color scheme:
                // - Metered = Paid Zones (grey)
                // - RPP = Free Timed Zones (orange)
                // - Free/Time Limited = My Permit Zones (green)
                // - Restrictions (no parking/street cleaning) = Red (safety)
                if hasNoParking {
                    baseColor = UIColor.systemRed
                } else if hasStreetCleaning {
                    baseColor = UIColor.systemRed
                } else if hasMetered {
                    // Paid/Metered parking → Paid Zones color (grey)
                    baseColor = devSettings.paidZonesColor
                } else if hasRPP {
                    // RPP without user permit → Free Timed Zones color (orange)
                    baseColor = devSettings.freeTimedZonesColor
                } else if hasTimeLimit {
                    // Time limited free parking → My Permit Zones color (green)
                    baseColor = devSettings.myPermitZonesColor
                } else {
                    // Fallback for unknown regulation types
                    baseColor = UIColor.systemBlue
                }
            }
        } else {
            // No blockface info - fallback
            baseColor = UIColor.systemBlue
        }

        // Styling optimized for visibility:
        // - 2pt stroke width (visible but not overwhelming)
        // - Rounded line caps and joins (smooth, professional appearance)
        // - 75% opacity for subtle overlay effect
        // - Solid line (no dash pattern for cleaner look)
        strokeColor = baseColor.withAlphaComponent(0.75)
        lineWidth = 2.0
        lineCap = .round
        lineJoin = .round
        lineDashPattern = nil
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
