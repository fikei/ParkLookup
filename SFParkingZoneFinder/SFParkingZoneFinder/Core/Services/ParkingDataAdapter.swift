import Foundation
import CoreLocation

// MARK: - Data Structures

/// Unified parking lookup result that works for both zones and blockfaces
struct ParkingLookupResult {
    /// Display name - Zone code ("Zone Q") or street name ("Mission St")
    let locationName: String

    /// Detailed location description (optional)
    let locationDetail: String?

    /// Primary regulation type affecting parking
    let primaryRegulationType: RegulationType

    /// Permit zones that apply (if RPP)
    let permitAreas: [String]?

    /// Time limit in minutes (if any)
    let timeLimitMinutes: Int?

    /// All regulations (for detail view)
    let allRegulations: [RegulationInfo]

    /// Next restriction that will end parking window
    let nextRestriction: RestrictionWindow?

    /// Source data for adapter-specific logic
    let sourceData: SourceData

    enum RegulationType {
        case free              // No restrictions
        case timeLimited       // Time limit only
        case residentialPermit // RPP zone
        case metered           // Paid parking
        case noParking         // No parking allowed
        case streetCleaning    // Street cleaning active
    }

    enum SourceData {
        case zone(ParkingZone)
        case blockface(Blockface)
    }
}

/// Detailed regulation information
struct RegulationInfo: Identifiable {
    let id = UUID()
    let type: ParkingLookupResult.RegulationType
    let description: String
    let enforcementDays: [DayOfWeek]?
    let enforcementStart: String?  // "08:00"
    let enforcementEnd: String?    // "18:00"
    let permitZone: String?
    let timeLimit: Int?  // minutes
}

/// Time window when parking is restricted
struct RestrictionWindow {
    let type: ParkingLookupResult.RegulationType
    let startsAt: Date
    let endsAt: Date
    let description: String
}

/// Result of park-until time calculation
struct ParkUntilResult {
    /// Time when user must move car
    let parkUntilTime: Date

    /// Reason for this time limit
    let reason: String

    /// Type of restriction causing the limit
    let restrictionType: ParkingLookupResult.RegulationType
}

// MARK: - Protocol

/// Unified interface for parking data lookup (zones or blockfaces)
protocol ParkingDataAdapterProtocol {
    /// Find parking information at a given coordinate
    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult?

    /// Calculate when user needs to move car
    func calculateParkUntil(
        for result: ParkingLookupResult,
        userPermits: Set<String>,
        parkingStartTime: Date
    ) -> ParkUntilResult?

    /// Check if user can park at this location
    func canPark(
        at result: ParkingLookupResult,
        userPermits: Set<String>,
        at time: Date
    ) -> Bool
}

// MARK: - Adapter Factory

/// Factory that returns the appropriate adapter based on feature flag
class ParkingDataAdapter {
    static var shared: ParkingDataAdapterProtocol {
        if DeveloperSettings.shared.useBlockfaceForFeatures {
            return BlockfaceDataAdapter()
        } else {
            return ZoneDataAdapter()
        }
    }
}

// MARK: - Zone-Based Adapter (Legacy System)

/// Adapter for legacy zone-based parking lookup
class ZoneDataAdapter: ParkingDataAdapterProtocol {
    private let zoneLookupEngine = ZoneLookupEngine()

    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult? {
        // Use existing zone lookup logic
        guard let result = zoneLookupEngine.lookup(coordinate: coordinate) else {
            return nil
        }

        // Convert zone result to unified format
        let primaryType: ParkingLookupResult.RegulationType
        if result.isInZone {
            if result.currentZone?.zoneType == .metered {
                primaryType = .metered
            } else if result.currentZone?.zoneType == .residentialPermit {
                primaryType = .residentialPermit
            } else if result.currentZone?.zoneType == .timeLimited {
                primaryType = .timeLimited
            } else {
                primaryType = .free
            }
        } else {
            primaryType = .free
        }

        // Extract permit areas
        let permitAreas: [String]?
        if let zone = result.currentZone, zone.zoneType == .residentialPermit {
            permitAreas = [zone.permitArea].compactMap { $0 }
        } else {
            permitAreas = nil
        }

        // Extract time limit
        let timeLimit = result.currentZone?.rules.first(where: { $0.ruleType == .timeLimit })?.timeLimit

        // Build regulations list
        var regulations: [RegulationInfo] = []
        if let zone = result.currentZone {
            for rule in zone.rules {
                let regType: ParkingLookupResult.RegulationType = {
                    switch rule.ruleType {
                    case .timeLimit: return .timeLimited
                    case .residential: return .residentialPermit
                    default: return .free
                    }
                }()

                regulations.append(RegulationInfo(
                    type: regType,
                    description: rule.displayString,
                    enforcementDays: rule.enforcementDays,
                    enforcementStart: rule.enforcementStartTime?.formatted,
                    enforcementEnd: rule.enforcementEndTime?.formatted,
                    permitZone: zone.zoneType == .residentialPermit ? zone.permitArea : nil,
                    timeLimit: rule.timeLimit
                ))
            }
        }

        // Determine next restriction (zones don't have street cleaning)
        let nextRestriction: RestrictionWindow? = nil

        return ParkingLookupResult(
            locationName: result.currentZone?.displayName ?? "No Zone",
            locationDetail: result.currentZone?.permitArea != nil ? "Zone \(result.currentZone!.permitArea!)" : nil,
            primaryRegulationType: primaryType,
            permitAreas: permitAreas,
            timeLimitMinutes: timeLimit,
            allRegulations: regulations,
            nextRestriction: nextRestriction,
            sourceData: result.currentZone.map { .zone($0) } ?? .zone(ParkingZone(
                id: "unknown",
                zoneType: .publicParking,
                geometry: ZoneGeometry(type: "Polygon", coordinates: []),
                rules: [],
                permitArea: nil,
                displayName: "Unknown"
            ))
        )
    }

    func calculateParkUntil(
        for result: ParkingLookupResult,
        userPermits: Set<String>,
        parkingStartTime: Date
    ) -> ParkUntilResult? {
        // Use existing time limit logic
        guard let timeLimit = result.timeLimitMinutes else {
            return nil
        }

        let parkUntilTime = parkingStartTime.addingTimeInterval(TimeInterval(timeLimit * 60))

        return ParkUntilResult(
            parkUntilTime: parkUntilTime,
            reason: "\(timeLimit) minute time limit",
            restrictionType: .timeLimited
        )
    }

    func canPark(
        at result: ParkingLookupResult,
        userPermits: Set<String>,
        at time: Date
    ) -> Bool {
        // Zone-based permission logic
        switch result.primaryRegulationType {
        case .free:
            return true
        case .residentialPermit:
            if let permitAreas = result.permitAreas {
                return !userPermits.isDisjoint(with: Set(permitAreas))
            }
            return false
        case .metered, .timeLimited:
            return true  // Can park but with restrictions
        case .noParking, .streetCleaning:
            return false
        }
    }
}

// MARK: - Blockface-Based Adapter (New System)

/// Adapter for blockface-based parking lookup
class BlockfaceDataAdapter: ParkingDataAdapterProtocol {
    // Track last selected blockface for sticky preference
    private var lastSelectedBlockface: Blockface?

    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult? {
        do {
            // Find nearby blockfaces (50m radius for precision)
            let nearbyBlockfaces = try await BlockfaceLoader.shared.loadBlockfacesNear(
                coordinate: coordinate,
                radiusMeters: 50,
                maxCount: 20  // Only need closest few
            )

            guard !nearbyBlockfaces.isEmpty else {
                return nil
            }

            // Find closest blockface with smart selection
            let selectedBlockface = selectBestBlockface(
                from: nearbyBlockfaces,
                userCoordinate: coordinate
            )

            // Store for sticky preference
            lastSelectedBlockface = selectedBlockface

            // Convert blockface to unified result
            return convertBlockfaceToResult(selectedBlockface)

        } catch {
            print("❌ BlockfaceDataAdapter lookup failed: \(error)")
            return nil
        }
    }

    func calculateParkUntil(
        for result: ParkingLookupResult,
        userPermits: Set<String>,
        parkingStartTime: Date
    ) -> ParkUntilResult? {
        guard case .blockface(let blockface) = result.sourceData else {
            return nil
        }

        let calendar = Calendar.current
        var earliestEndTime: Date?
        var earliestReason: String?
        var earliestType: ParkingLookupResult.RegulationType?

        // Check each regulation for time limits
        for regulation in blockface.regulations {
            switch regulation.type {
            case "timeLimit":
                // Time limit: parking start + limit duration
                if let limitMins = regulation.timeLimit {
                    let endTime = parkingStartTime.addingTimeInterval(TimeInterval(limitMins * 60))
                    if earliestEndTime == nil || endTime < earliestEndTime! {
                        earliestEndTime = endTime
                        earliestReason = "\(limitMins) minute time limit"
                        earliestType = .timeLimited
                    }
                }

            case "streetCleaning":
                // Street cleaning: check if it will occur during parking
                if let nextCleaningWindow = findNextStreetCleaningWindow(
                    regulation: regulation,
                    from: parkingStartTime
                ) {
                    if earliestEndTime == nil || nextCleaningWindow.start < earliestEndTime! {
                        earliestEndTime = nextCleaningWindow.start
                        earliestReason = "Street cleaning starts"
                        earliestType = .streetCleaning
                    }
                }

            case "metered":
                // Check meter enforcement hours
                if let enforcementEnd = findMeterEnforcementEnd(
                    regulation: regulation,
                    from: parkingStartTime
                ) {
                    // Note: Meter end doesn't necessarily mean you must move,
                    // but it's when you stop paying. Only use if no other limits.
                    if earliestEndTime == nil {
                        earliestEndTime = enforcementEnd
                        earliestReason = "Meter enforcement ends"
                        earliestType = .metered
                    }
                }

            case "residentialPermit":
                // RPP time limit for non-permit holders
                if let limitMins = regulation.timeLimit,
                   !hasMatchingPermit(regulation: regulation, userPermits: userPermits) {
                    let endTime = parkingStartTime.addingTimeInterval(TimeInterval(limitMins * 60))
                    if earliestEndTime == nil || endTime < earliestEndTime! {
                        earliestEndTime = endTime
                        earliestReason = "\(limitMins) min limit (no permit)"
                        earliestType = .timeLimited
                    }
                }

            default:
                break
            }
        }

        guard let endTime = earliestEndTime,
              let reason = earliestReason,
              let type = earliestType else {
            return nil  // No time limit
        }

        return ParkUntilResult(
            parkUntilTime: endTime,
            reason: reason,
            restrictionType: type
        )
    }

    func canPark(
        at result: ParkingLookupResult,
        userPermits: Set<String>,
        at time: Date
    ) -> Bool {
        guard case .blockface(let blockface) = result.sourceData else {
            return false
        }

        // Check each regulation
        for regulation in blockface.regulations {
            // Street cleaning overrides everything
            if regulation.type == "streetCleaning" {
                if isRegulationActive(regulation, at: time) {
                    return false  // No parking during street cleaning
                }
            }

            // No parking zones
            if regulation.type == "noParking" {
                if isRegulationActive(regulation, at: time) {
                    return false
                }
            }
        }

        // Check permit requirements
        let hasRPP = blockface.regulations.contains { $0.type == "residentialPermit" }
        if hasRPP {
            // Check if user has matching permit
            let hasPermit = blockface.regulations.contains { regulation in
                regulation.type == "residentialPermit" &&
                hasMatchingPermit(regulation: regulation, userPermits: userPermits)
            }

            if hasPermit {
                // Permit exempts from meter in this zone
                return true
            } else {
                // Can still park but with time limit restrictions
                return true
            }
        }

        // Metered or time-limited parking
        return true
    }

    // MARK: - Private Helpers

    /// Select best blockface using PM-specified logic
    private func selectBestBlockface(
        from blockfaces: [Blockface],
        userCoordinate: CLLocationCoordinate2D
    ) -> Blockface {
        // Sticky preference: if last blockface is still in list, prefer it
        if let last = lastSelectedBlockface,
           blockfaces.contains(where: { $0.id == last.id }) {
            return last
        }

        // Calculate distances and find closest
        let userLocation = CLLocation(
            latitude: userCoordinate.latitude,
            longitude: userCoordinate.longitude
        )

        let scored = blockfaces.map { blockface -> (blockface: Blockface, distance: Double, sameSide: Bool) in
            // Calculate distance to blockface centerline
            let coords = blockface.geometry.locationCoordinates
            let minDistance = coords.map { coord in
                CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: userLocation)
            }.min() ?? Double.infinity

            // TODO: Determine if user is on same side of street
            // For now, assume side check based on proximity
            let sameSide = minDistance < 15  // Within 15m = probably same side

            return (blockface, minDistance, sameSide)
        }

        // Sort: same side first, then by distance
        let sorted = scored.sorted { a, b in
            if a.sameSide != b.sameSide {
                return a.sameSide  // Prefer same side
            }
            return a.distance < b.distance  // Then closest
        }

        return sorted.first!.blockface
    }

    /// Convert blockface to unified parking result
    private func convertBlockfaceToResult(_ blockface: Blockface) -> ParkingLookupResult {
        // Determine primary regulation type
        let primaryType = determinePrimaryType(blockface: blockface)

        // Extract permit zones
        let permitAreas = blockface.regulations
            .filter { $0.type == "residentialPermit" }
            .compactMap { $0.permitZone }

        // Extract time limit
        let timeLimit = blockface.regulations
            .first(where: { $0.timeLimit != nil })?
            .timeLimit

        // Build all regulations list
        let allRegulations = blockface.regulations.map { reg in
            RegulationInfo(
                type: regulationTypeMapping(reg.type),
                description: reg.description,
                enforcementDays: reg.enforcementDays,
                enforcementStart: reg.enforcementStart,
                enforcementEnd: reg.enforcementEnd,
                permitZone: reg.permitZone,
                timeLimit: reg.timeLimit
            )
        }

        // Find next restriction
        let nextRestriction = findNextRestriction(blockface: blockface)

        // Location name: hide blockface details per PM requirements
        let locationName: String
        if let permitZone = permitAreas.first {
            locationName = "Zone \(permitZone)"
        } else if primaryType == .metered {
            locationName = "Metered Parking"
        } else {
            locationName = blockface.street
        }

        return ParkingLookupResult(
            locationName: locationName,
            locationDetail: nil,  // Hide street details
            primaryRegulationType: primaryType,
            permitAreas: permitAreas.isEmpty ? nil : permitAreas,
            timeLimitMinutes: timeLimit,
            allRegulations: allRegulations,
            nextRestriction: nextRestriction,
            sourceData: .blockface(blockface)
        )
    }

    /// Determine primary regulation type (what shows on card)
    private func determinePrimaryType(blockface: Blockface) -> ParkingLookupResult.RegulationType {
        // Priority order per PM requirements
        if blockface.regulations.contains(where: { $0.type == "noParking" }) {
            return .noParking
        }
        if blockface.regulations.contains(where: { $0.type == "streetCleaning" && isRegulationActive($0, at: Date()) }) {
            return .streetCleaning
        }
        if blockface.regulations.contains(where: { $0.type == "metered" }) {
            return .metered
        }
        if blockface.regulations.contains(where: { $0.type == "residentialPermit" }) {
            return .residentialPermit
        }
        if blockface.regulations.contains(where: { $0.type == "timeLimit" }) {
            return .timeLimited
        }
        return .free
    }

    /// Map blockface regulation type to unified type
    private func regulationTypeMapping(_ type: String) -> ParkingLookupResult.RegulationType {
        switch type {
        case "streetCleaning": return .streetCleaning
        case "timeLimit": return .timeLimited
        case "residentialPermit": return .residentialPermit
        case "metered": return .metered
        case "noParking": return .noParking
        default: return .free
        }
    }

    /// Find next restriction that will end parking window
    private func findNextRestriction(blockface: Blockface) -> RestrictionWindow? {
        let now = Date()
        var nextWindow: (start: Date, end: Date, type: ParkingLookupResult.RegulationType, desc: String)?

        for regulation in blockface.regulations {
            if regulation.type == "streetCleaning",
               let window = findNextStreetCleaningWindow(regulation: regulation, from: now) {
                if nextWindow == nil || window.start < nextWindow!.start {
                    nextWindow = (window.start, window.end, .streetCleaning, "Street cleaning")
                }
            }
        }

        guard let window = nextWindow else {
            return nil
        }

        return RestrictionWindow(
            type: window.type,
            startsAt: window.start,
            endsAt: window.end,
            description: window.desc
        )
    }

    /// Check if regulation is active at given time
    private func isRegulationActive(_ regulation: BlockfaceRegulation, at time: Date) -> Bool {
        return regulation.isInEffect(at: time)
    }

    /// Check if user has matching permit
    private func hasMatchingPermit(regulation: BlockfaceRegulation, userPermits: Set<String>) -> Bool {
        guard let permitZone = regulation.permitZone else {
            return false
        }
        return userPermits.contains(permitZone)
    }

    /// Find next street cleaning window
    private func findNextStreetCleaningWindow(
        regulation: BlockfaceRegulation,
        from startTime: Date
    ) -> (start: Date, end: Date)? {
        guard let days = regulation.enforcementDays,
              let startStr = regulation.enforcementStart,
              let endStr = regulation.enforcementEnd,
              let startTime = TimeOfDay.parse(startStr),
              let endTime = TimeOfDay.parse(endStr) else {
            return nil
        }

        let calendar = Calendar.current

        // Check next 7 days for street cleaning
        for dayOffset in 0..<7 {
            let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: from)!
            let weekday = calendar.component(.weekday, from: checkDate)
            let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday)

            if days.contains(dayOfWeek) {
                // Found a street cleaning day
                let cleaningStart = calendar.date(
                    bySettingHour: startTime.hour,
                    minute: startTime.minute,
                    second: 0,
                    of: checkDate
                )!

                let cleaningEnd = calendar.date(
                    bySettingHour: endTime.hour,
                    minute: endTime.minute,
                    second: 0,
                    of: checkDate
                )!

                if cleaningStart > from {
                    return (cleaningStart, cleaningEnd)
                }
            }
        }

        return nil
    }

    /// Find meter enforcement end time
    private func findMeterEnforcementEnd(
        regulation: BlockfaceRegulation,
        from startTime: Date
    ) -> Date? {
        guard let endStr = regulation.enforcementEnd,
              let endTime = TimeOfDay.parse(endStr) else {
            return nil
        }

        let calendar = Calendar.current
        let endDate = calendar.date(
            bySettingHour: endTime.hour,
            minute: endTime.minute,
            second: 0,
            of: startTime
        )!

        return endDate > startTime ? endDate : nil
    }
}

// MARK: - Extensions

extension TimeOfDay {
    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
