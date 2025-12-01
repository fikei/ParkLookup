import MapKit
import SwiftUI
import CoreLocation

/// Custom polygon that holds reference to blockface data
class BlockfacePolygon: MKPolygon {
    var blockface: Blockface?
    /// True if this blockface has both metered parking AND user has a valid permit for the zone
    /// These blockfaces are colored green but require users to check street signs
    var isMeteredWithPermit: Bool = false
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

        // Priority-based color coding:
        // 1. Red: No Parking, Active street cleaning
        // 2. Green: Your zone where park until is >24 hours
        // 3. Grey: Paid Parking currently enforced
        // 4. Orange: Time Limited & enforced <24 hours, Your zone where park until is <24 hours
        // 5. Blue: No restrictions (excluding street cleaning)
        let baseColor: UIColor
        let opacity: Double

        if let bf = blockface {
            if bf.regulations.isEmpty {
                // No restrictions = free parking → Blue
                baseColor = UIColor.systemBlue
                opacity = devSettings.blockfaceOpacity
            } else {
                let now = Date()
                _ = Calendar.current

                // Get user permits
                let userPermits = getUserPermits()
                let userPermitSet = Set(userPermits.map { $0.uppercased() })

                // Analyze regulations
                var hasNoParking = false
                var hasActiveStreetCleaning = false
                var hasMeteredEnforced = false
                var isUserZone = false
                var parkUntilHours: Double?

                // Debug logging for Zone i
                let isDebugStreet = bf.street.contains("Buchanan") || bf.street.contains("Pine")
                if isDebugStreet {
                    print("🔍 DEBUG POLYGON - Street: \(bf.street), Side: \(bf.side)")
                    print("  User permits: \(userPermits) → uppercased: \(userPermitSet)")
                }

                // Check each regulation
                for reg in bf.regulations {
                    let regType = reg.type.lowercased()

                    // 1. No parking (highest priority)
                    if regType == "noparking" {
                        hasNoParking = true
                    }

                    // 2. Active street cleaning
                    if regType == "streetcleaning" {
                        if isRegulationCurrentlyActive(reg, at: now) {
                            hasActiveStreetCleaning = true
                        }
                    }

                    // 3. Metered and currently enforced
                    if regType == "metered" {
                        if isRegulationCurrentlyActive(reg, at: now) {
                            hasMeteredEnforced = true
                        }
                    }

                    // Check if this is user's zone (RPP)
                    if regType == "residentialpermit" {
                        if isDebugStreet {
                            print("  RPP regulation found:")
                            print("    permitZone: \(reg.permitZone ?? "nil")")
                            print("    allPermitZones: \(reg.allPermitZones)")
                        }
                        if let permitZone = reg.permitZone, userPermitSet.contains(permitZone.uppercased()) {
                            isUserZone = true
                            if isDebugStreet {
                                print("    ✅ MATCH via permitZone!")
                            }
                        }
                        // Also check allPermitZones for multi-RPP
                        for zone in reg.allPermitZones {
                            if userPermitSet.contains(zone.uppercased()) {
                                isUserZone = true
                                if isDebugStreet {
                                    print("    ✅ MATCH via allPermitZones!")
                                }
                                break
                            }
                        }
                    }
                }

                // Calculate park until time for this blockface
                // Include street cleaning so blocks turn orange when cleaning is within 24 hours
                if isUserZone || bf.regulations.contains(where: {
                    let type = $0.type.lowercased()
                    return type == "timelimit" || type == "streetcleaning"
                }) {
                    parkUntilHours = calculateParkUntilHours(blockface: bf, userPermitZones: userPermitSet, at: now)
                    if isDebugStreet {
                        print("  parkUntilHours: \(parkUntilHours ?? -1)")
                    }
                }

                // Apply priority-based coloring
                // IMPORTANT: Permit zones trump metered parking - permit holders get unlimited parking in their zone
                if hasNoParking || hasActiveStreetCleaning {
                    // Priority 1: Red for no parking or active street cleaning (affects everyone)
                    baseColor = UIColor.systemRed
                    opacity = devSettings.blockfaceOpacity
                    if isDebugStreet {
                        print("  → Color: RED (no parking or street cleaning)")
                    }
                } else if isUserZone {
                    // Priority 2: Green for user's permit zone (unlimited parking for permit holders)
                    // This takes precedence over metered enforcement - permit holders don't pay meters in their zone
                    baseColor = UIColor.systemGreen
                    opacity = devSettings.blockfaceOpacity
                    if isDebugStreet {
                        print("  → Color: GREEN (user zone - permit holder has unlimited parking)")
                    }
                } else if hasMeteredEnforced {
                    // Priority 3: Grey for metered parking currently enforced (non-permit holders)
                    baseColor = UIColor.systemGray
                    opacity = devSettings.blockfaceOpacity
                    if isDebugStreet {
                        print("  → Color: GREY (metered enforced, no permit)")
                    }
                } else if let hours = parkUntilHours, hours <= 24 {
                    // Priority 4: Orange for time limited <24 hours
                    baseColor = UIColor.systemOrange
                    opacity = devSettings.blockfaceOpacity
                    if isDebugStreet {
                        print("  → Color: ORANGE (time limited ≤24h)")
                    }
                } else {
                    // Priority 5: Blue for no restrictions
                    baseColor = UIColor.systemBlue
                    opacity = devSettings.blockfaceOpacity
                    if isDebugStreet {
                        print("  → Color: BLUE (no restrictions)")
                    }
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

    /// Get user permits from UserDefaults
    private func getUserPermits() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: "user_parking_permits") else {
            return []
        }

        do {
            let permits = try JSONDecoder().decode([ParkingPermit].self, from: data)
            return permits.map { $0.area }
        } catch {
            return []
        }
    }

    /// Check if a regulation is currently in effect
    private func isRegulationCurrentlyActive(_ regulation: BlockfaceRegulation, at time: Date) -> Bool {
        guard let startStr = regulation.enforcementStart,
              let endStr = regulation.enforcementEnd else {
            return false
        }

        // Parse time strings
        func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
            let components = timeStr.split(separator: ":").compactMap { Int($0) }
            guard components.count == 2 else { return nil }
            return (hour: components[0], minute: components[1])
        }

        guard let startTime = parseTime(startStr),
              let endTime = parseTime(endStr) else {
            return false
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: time)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.hour * 60 + startTime.minute
        let endMinutes = endTime.hour * 60 + endTime.minute

        // Check day of week if enforcement days specified
        if let enforcementDays = regulation.enforcementDays, !enforcementDays.isEmpty {
            guard let weekday = components.weekday else { return false }

            // Map day strings to weekday numbers
            let activeDays = enforcementDays.compactMap { dayStr -> Int? in
                switch dayStr.lowercased() {
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

            guard activeDays.contains(weekday) else { return false }
        }

        // Check time window
        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    /// Calculate park until time in hours for a blockface
    private func calculateParkUntilHours(blockface: Blockface, userPermitZones: Set<String>, at time: Date) -> Double? {
        var earliestRestrictionDate: Date?
        _ = Calendar.current

        for reg in blockface.regulations {
            let regType = reg.type.lowercased()

            // Skip if this is a permit zone and user has the permit (unlimited parking)
            if regType == "residentialpermit" {
                if let permitZone = reg.permitZone, userPermitZones.contains(permitZone.uppercased()) {
                    // User has permit for single-zone RPP
                    continue
                }
                // Check multi-RPP
                var hasPermit = false
                for zone in reg.allPermitZones {
                    if userPermitZones.contains(zone.uppercased()) {
                        hasPermit = true
                        break
                    }
                }
                if hasPermit {
                    continue
                }
            }

            // Calculate restriction date for this regulation
            if regType == "timelimit" || regType == "residentialpermit" {
                if let timeLimit = reg.timeLimit {
                    let expirationDate = time.addingTimeInterval(TimeInterval(timeLimit * 60))
                    if earliestRestrictionDate == nil || expirationDate < earliestRestrictionDate! {
                        earliestRestrictionDate = expirationDate
                    }
                }
            }

            if regType == "streetcleaning" {
                if let nextCleaning = findNextStreetCleaningDate(regulation: reg, from: time) {
                    if earliestRestrictionDate == nil || nextCleaning < earliestRestrictionDate! {
                        earliestRestrictionDate = nextCleaning
                    }
                }
            }
        }

        // Convert to hours
        if let restrictionDate = earliestRestrictionDate {
            let interval = restrictionDate.timeIntervalSince(time)
            return interval / 3600.0  // Convert seconds to hours
        }

        // No restrictions found - unlimited parking (return very large number)
        return 9999.0
    }

    /// Find next street cleaning date
    private func findNextStreetCleaningDate(regulation: BlockfaceRegulation, from date: Date) -> Date? {
        guard let daysStr = regulation.enforcementDays,
              let startStr = regulation.enforcementStart else {
            return nil
        }

        // Parse time strings
        func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
            let components = timeStr.split(separator: ":").compactMap { Int($0) }
            guard components.count == 2 else { return nil }
            return (hour: components[0], minute: components[1])
        }

        guard let startTime = parseTime(startStr) else { return nil }

        let cleaningDays = daysStr.compactMap { dayStr -> Int? in
            switch dayStr.lowercased() {
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

        guard !cleaningDays.isEmpty else { return nil }

        let calendar = Calendar.current

        // Check next 7 days
        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: checkDate)

            if cleaningDays.contains(weekday) {
                if let cleaningStart = calendar.date(
                    bySettingHour: startTime.hour,
                    minute: startTime.minute,
                    second: 0,
                    of: checkDate
                ) {
                    if cleaningStart > date {
                        return cleaningStart
                    }
                }
            }
        }

        return nil
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
        // Use same priority-based color coding as polygon renderer
        // 1. Red: No Parking, Active street cleaning
        // 2. Green: Your zone where park until is >24 hours
        // 3. Grey: Paid Parking currently enforced
        // 4. Orange: Time Limited & enforced <24 hours, Your zone where park until is <24 hours
        // 5. Blue: No restrictions (excluding street cleaning)
        let baseColor: UIColor

        if let bf = blockface {
            if bf.regulations.isEmpty {
                // No restrictions = free parking → Blue
                baseColor = UIColor.systemBlue
            } else {
                let now = Date()

                // Get user permits
                let userPermits = getPolylineUserPermits()
                let userPermitSet = Set(userPermits.map { $0.uppercased() })

                // Analyze regulations
                var hasNoParking = false
                var hasActiveStreetCleaning = false
                var hasMeteredEnforced = false
                var isUserZone = false
                var parkUntilHours: Double?

                // Debug logging for Zone i
                let isDebugStreet = bf.street.contains("Buchanan") || bf.street.contains("Pine")
                if isDebugStreet {
                    print("🔍 DEBUG POLYLINE - Street: \(bf.street), Side: \(bf.side)")
                    print("  User permits: \(userPermits) → uppercased: \(userPermitSet)")
                }

                // Check each regulation
                for reg in bf.regulations {
                    let regType = reg.type.lowercased()

                    // 1. No parking (highest priority)
                    if regType == "noparking" {
                        hasNoParking = true
                    }

                    // 2. Active street cleaning
                    if regType == "streetcleaning" {
                        if isPolylineRegulationActive(reg, at: now) {
                            hasActiveStreetCleaning = true
                        }
                    }

                    // 3. Metered and currently enforced
                    if regType == "metered" {
                        if isPolylineRegulationActive(reg, at: now) {
                            hasMeteredEnforced = true
                        }
                    }

                    // Check if this is user's zone (RPP)
                    if regType == "residentialpermit" {
                        if isDebugStreet {
                            print("  RPP regulation found:")
                            print("    permitZone: \(reg.permitZone ?? "nil")")
                            print("    allPermitZones: \(reg.allPermitZones)")
                        }
                        if let permitZone = reg.permitZone, userPermitSet.contains(permitZone.uppercased()) {
                            isUserZone = true
                            if isDebugStreet {
                                print("    ✅ MATCH via permitZone!")
                            }
                        }
                        // Also check allPermitZones for multi-RPP
                        for zone in reg.allPermitZones {
                            if userPermitSet.contains(zone.uppercased()) {
                                isUserZone = true
                                if isDebugStreet {
                                    print("    ✅ MATCH via allPermitZones!")
                                }
                                break
                            }
                        }
                    }
                }

                // Calculate park until time for this blockface
                // Include street cleaning so blocks turn orange when cleaning is within 24 hours
                if isUserZone || bf.regulations.contains(where: {
                    let type = $0.type.lowercased()
                    return type == "timelimit" || type == "streetcleaning"
                }) {
                    parkUntilHours = calculatePolylineParkUntilHours(blockface: bf, userPermitZones: userPermitSet, at: now)
                    if isDebugStreet {
                        print("  parkUntilHours: \(parkUntilHours ?? -1)")
                    }
                }

                // Apply priority-based coloring
                // IMPORTANT: Permit zones trump metered parking - permit holders get unlimited parking in their zone
                if hasNoParking || hasActiveStreetCleaning {
                    // Priority 1: Red for no parking or active street cleaning (affects everyone)
                    baseColor = UIColor.systemRed
                    if isDebugStreet {
                        print("  → Color: RED (no parking or street cleaning)")
                    }
                } else if isUserZone {
                    // Priority 2: Green for user's permit zone (unlimited parking for permit holders)
                    // This takes precedence over metered enforcement - permit holders don't pay meters in their zone
                    baseColor = UIColor.systemGreen
                    if isDebugStreet {
                        print("  → Color: GREEN (user zone - permit holder has unlimited parking)")
                    }
                } else if hasMeteredEnforced {
                    // Priority 3: Grey for metered parking currently enforced (non-permit holders)
                    baseColor = UIColor.systemGray
                    if isDebugStreet {
                        print("  → Color: GREY (metered enforced, no permit)")
                    }
                } else if let hours = parkUntilHours, hours <= 24 {
                    // Priority 4: Orange for time limited <24 hours
                    baseColor = UIColor.systemOrange
                    if isDebugStreet {
                        print("  → Color: ORANGE (time limited ≤24h)")
                    }
                } else {
                    // Priority 5: Blue for no restrictions
                    baseColor = UIColor.systemBlue
                    if isDebugStreet {
                        print("  → Color: BLUE (no restrictions)")
                    }
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

    /// Check if a regulation is currently in effect (for polyline)
    private func isPolylineRegulationActive(_ regulation: BlockfaceRegulation, at time: Date) -> Bool {
        guard let startStr = regulation.enforcementStart,
              let endStr = regulation.enforcementEnd else {
            return false
        }

        // Parse time strings
        func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
            let components = timeStr.split(separator: ":").compactMap { Int($0) }
            guard components.count == 2 else { return nil }
            return (hour: components[0], minute: components[1])
        }

        guard let startTime = parseTime(startStr),
              let endTime = parseTime(endStr) else {
            return false
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: time)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.hour * 60 + startTime.minute
        let endMinutes = endTime.hour * 60 + endTime.minute

        // Check day of week if enforcement days specified
        if let enforcementDays = regulation.enforcementDays, !enforcementDays.isEmpty {
            guard let weekday = components.weekday else { return false }

            // Map day strings to weekday numbers
            let activeDays = enforcementDays.compactMap { dayStr -> Int? in
                switch dayStr.lowercased() {
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

            guard activeDays.contains(weekday) else { return false }
        }

        // Check time window
        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    /// Calculate park until time in hours for a blockface (for polyline)
    private func calculatePolylineParkUntilHours(blockface: Blockface, userPermitZones: Set<String>, at time: Date) -> Double? {
        var earliestRestrictionDate: Date?

        for reg in blockface.regulations {
            let regType = reg.type.lowercased()

            // Skip if this is a permit zone and user has the permit (unlimited parking)
            if regType == "residentialpermit" {
                if let permitZone = reg.permitZone, userPermitZones.contains(permitZone.uppercased()) {
                    continue
                }
                var hasPermit = false
                for zone in reg.allPermitZones {
                    if userPermitZones.contains(zone.uppercased()) {
                        hasPermit = true
                        break
                    }
                }
                if hasPermit {
                    continue
                }
            }

            // Calculate restriction date for this regulation
            if regType == "timelimit" || regType == "residentialpermit" {
                if let timeLimit = reg.timeLimit {
                    let expirationDate = time.addingTimeInterval(TimeInterval(timeLimit * 60))
                    if earliestRestrictionDate == nil || expirationDate < earliestRestrictionDate! {
                        earliestRestrictionDate = expirationDate
                    }
                }
            }

            if regType == "streetcleaning" {
                if let nextCleaning = findPolylineNextStreetCleaningDate(regulation: reg, from: time) {
                    if earliestRestrictionDate == nil || nextCleaning < earliestRestrictionDate! {
                        earliestRestrictionDate = nextCleaning
                    }
                }
            }
        }

        // Convert to hours
        if let restrictionDate = earliestRestrictionDate {
            let interval = restrictionDate.timeIntervalSince(time)
            return interval / 3600.0  // Convert seconds to hours
        }

        // No restrictions found - unlimited parking (return very large number)
        return 9999.0
    }

    /// Find next street cleaning date (for polyline)
    private func findPolylineNextStreetCleaningDate(regulation: BlockfaceRegulation, from date: Date) -> Date? {
        guard let daysStr = regulation.enforcementDays,
              let startStr = regulation.enforcementStart else {
            return nil
        }

        // Parse time strings
        func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
            let components = timeStr.split(separator: ":").compactMap { Int($0) }
            guard components.count == 2 else { return nil }
            return (hour: components[0], minute: components[1])
        }

        guard let startTime = parseTime(startStr) else { return nil }

        let cleaningDays = daysStr.compactMap { dayStr -> Int? in
            switch dayStr.lowercased() {
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

        guard !cleaningDays.isEmpty else { return nil }

        let calendar = Calendar.current

        // Check next 7 days
        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: checkDate)

            if cleaningDays.contains(weekday) {
                if let cleaningStart = calendar.date(
                    bySettingHour: startTime.hour,
                    minute: startTime.minute,
                    second: 0,
                    of: checkDate
                ) {
                    if cleaningStart > date {
                        return cleaningStart
                    }
                }
            }
        }

        return nil
    }

    /// Get user permits from UserDefaults (for polyline)
    private func getPolylineUserPermits() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: "user_parking_permits") else {
            return []
        }

        do {
            let permits = try JSONDecoder().decode([ParkingPermit].self, from: data)
            return permits.map { $0.area }
        } catch {
            return []
        }
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
