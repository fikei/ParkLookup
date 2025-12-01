import Foundation
import CoreLocation
import os.log

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
        case outsideCoverage   // Outside supported city bounds
        case unknownArea       // Inside city but no data available
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
        // Always use BlockfaceDataAdapter for now
        // ZoneDataAdapter disabled due to compilation issues - needs refactoring
        return BlockfaceDataAdapter()
    }
}

// MARK: - Zone-Based Adapter (Legacy System) - DISABLED

// TODO: Re-enable ZoneDataAdapter after fixing compilation issues
// Issues: ZoneLookupEngine initialization, ZoneType enum cases, ParkingZone initializer
/*
/// Adapter for legacy zone-based parking lookup
class ZoneDataAdapter: ParkingDataAdapterProtocol {
    // ... implementation disabled ...
}
*/

// MARK: - Blockface-Based Adapter (New System)

/// Adapter for blockface-based parking lookup
class BlockfaceDataAdapter: ParkingDataAdapterProtocol {
    private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "BlockfaceDataAdapter")

    // Track last selected blockface for sticky preference
    private var lastSelectedBlockface: Blockface?

    func lookupParking(at coordinate: CLLocationCoordinate2D) async -> ParkingLookupResult? {
        logger.info("🔍 ParkingDataAdapter.lookupParking at (\(coordinate.latitude), \(coordinate.longitude))")

        // Check if coordinate is within supported city bounds
        guard CityIdentifier.sanFrancisco.contains(coordinate) else {
            logger.warning("  ⚠️ Coordinate outside San Francisco bounds - returning outsideCoverage")
            return createOutsideCoverageResult(coordinate: coordinate)
        }

        do {
            // Find nearby blockfaces (50m radius for precision)
            let nearbyBlockfaces = try await BlockfaceLoader.shared.loadBlockfacesNear(
                coordinate: coordinate,
                radiusMeters: 50,
                maxCount: 20  // Only need closest few
            )

            logger.info("  Found \(nearbyBlockfaces.count) blockfaces within 50m")

            guard !nearbyBlockfaces.isEmpty else {
                logger.warning("  ⚠️ No blockfaces found within 50m, trying larger radius...")

                // Try larger radius as fallback
                let nearbyFallback = try await BlockfaceLoader.shared.loadBlockfacesNear(
                    coordinate: coordinate,
                    radiusMeters: 150,
                    maxCount: 20
                )

                logger.info("  Found \(nearbyFallback.count) blockfaces within 150m")

                guard !nearbyFallback.isEmpty else {
                    logger.warning("  ⚠️ No blockfaces found even within 150m - returning unknownArea")
                    return createUnknownAreaResult(coordinate: coordinate)
                }

                // Use fallback blockfaces
                let selectedBlockface = selectBestBlockface(
                    from: nearbyFallback,
                    userCoordinate: coordinate
                )
                lastSelectedBlockface = selectedBlockface
                logger.info("  ✅ Selected blockface: \(selectedBlockface.street) (\(selectedBlockface.side))")
                return convertBlockfaceToResult(selectedBlockface)
            }

            // Find closest blockface with smart selection
            let selectedBlockface = selectBestBlockface(
                from: nearbyBlockfaces,
                userCoordinate: coordinate
            )

            // Store for sticky preference
            lastSelectedBlockface = selectedBlockface

            logger.info("  ✅ Selected blockface: \(selectedBlockface.street) (\(selectedBlockface.side)), regulations: \(selectedBlockface.regulations.count)")

            // Convert blockface to unified result
            return convertBlockfaceToResult(selectedBlockface)

        } catch {
            logger.error("❌ BlockfaceDataAdapter lookup failed: \(error.localizedDescription)")
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

    /// Create result for location outside coverage area
    private func createOutsideCoverageResult(coordinate: CLLocationCoordinate2D) -> ParkingLookupResult {
        return ParkingLookupResult(
            locationName: "Outside Coverage",
            locationDetail: "San Francisco only",
            primaryRegulationType: .outsideCoverage,
            permitAreas: nil,
            timeLimitMinutes: nil,
            allRegulations: [],
            nextRestriction: nil,
            sourceData: .blockface(Blockface(
                id: "outside-coverage",
                street: "Outside Coverage",
                fromStreet: nil,
                toStreet: nil,
                side: "UNKNOWN",
                geometry: LineStringGeometry(type: "LineString", coordinates: []),
                regulations: []
            ))
        )
    }

    /// Create result for location inside city but no blockface data
    private func createUnknownAreaResult(coordinate: CLLocationCoordinate2D) -> ParkingLookupResult {
        return ParkingLookupResult(
            locationName: "Unknown Area",
            locationDetail: "No parking data available",
            primaryRegulationType: .unknownArea,
            permitAreas: nil,
            timeLimitMinutes: nil,
            allRegulations: [],
            nextRestriction: nil,
            sourceData: .blockface(Blockface(
                id: "unknown-area",
                street: "Unknown Area",
                fromStreet: nil,
                toStreet: nil,
                side: "UNKNOWN",
                geometry: LineStringGeometry(type: "LineString", coordinates: []),
                regulations: []
            ))
        )
    }

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

        // Extract permit zones (use multi-RPP allPermitZones)
        let permitAreas = blockface.regulations
            .filter { $0.type == "residentialPermit" }
            .flatMap { $0.allPermitZones }

        // Extract time limit
        let timeLimit = blockface.regulations
            .first(where: { $0.timeLimit != nil })?
            .timeLimit

        // Build all regulations list
        logger.info("🔍 Building regulations from blockface: \(blockface.street), regulationCount=\(blockface.regulations.count)")
        let allRegulations = blockface.regulations.map { reg in
            logger.info("  Blockface regulation: type=\(reg.type), desc=\(reg.description)")

            // Convert String days to DayOfWeek
            let days: [DayOfWeek]? = reg.enforcementDays?.compactMap { dayStr in
                DayOfWeek.allCases.first { $0.rawValue.lowercased() == dayStr.lowercased() }
            }

            return RegulationInfo(
                type: regulationTypeMapping(reg.type),
                description: reg.description,
                enforcementDays: days,
                enforcementStart: reg.enforcementStart,
                enforcementEnd: reg.enforcementEnd,
                permitZone: reg.permitZone,
                timeLimit: reg.timeLimit
            )
        }
        logger.info("✅ Built \(allRegulations.count) regulations for ParkingLookupResult")

        // Find next restriction
        let nextRestriction = findNextRestriction(blockface: blockface)

        // Location name: hide blockface details per PM requirements
        let locationName: String
        if !permitAreas.isEmpty {
            // Residential permit zone(s)
            if permitAreas.count == 1 {
                locationName = "Zone \(permitAreas[0])"
            } else {
                // Multi-RPP: show all zones
                locationName = "Zones \(permitAreas.joined(separator: " & "))"
            }
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
        case "outsideCoverage": return .outsideCoverage
        case "unknownArea": return .unknownArea
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

    /// Parse time string (HH:MM format) into hour and minute
    private func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
        let components = timeStr.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return (hour: components[0], minute: components[1])
    }

    /// Find next street cleaning window
    private func findNextStreetCleaningWindow(
        regulation: BlockfaceRegulation,
        from startTime: Date
    ) -> (start: Date, end: Date)? {
        guard let daysStr = regulation.enforcementDays,
              let startStr = regulation.enforcementStart,
              let endStr = regulation.enforcementEnd,
              let parsedStart = parseTime(startStr),
              let parsedEnd = parseTime(endStr) else {
            return nil
        }

        // Convert string days to DayOfWeek
        let days = daysStr.compactMap { dayStr -> DayOfWeek? in
            DayOfWeek.allCases.first { $0.rawValue.lowercased() == dayStr.lowercased() }
        }
        guard !days.isEmpty else { return nil }

        let calendar = Calendar.current

        // Check next 7 days for street cleaning
        for dayOffset in 0..<7 {
            let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: startTime)!
            let weekday = calendar.component(.weekday, from: checkDate)
            guard let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) else { continue }

            if days.contains(dayOfWeek) {
                // Found a street cleaning day
                guard let cleaningStart = calendar.date(
                    bySettingHour: parsedStart.hour,
                    minute: parsedStart.minute,
                    second: 0,
                    of: checkDate
                ),
                let cleaningEnd = calendar.date(
                    bySettingHour: parsedEnd.hour,
                    minute: parsedEnd.minute,
                    second: 0,
                    of: checkDate
                ) else { continue }

                if cleaningStart > startTime {
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
              let parsedEnd = parseTime(endStr) else {
            return nil
        }

        let calendar = Calendar.current
        guard let endDate = calendar.date(
            bySettingHour: parsedEnd.hour,
            minute: parsedEnd.minute,
            second: 0,
            of: startTime
        ) else { return nil }

        return endDate > startTime ? endDate : nil
    }
}

// MARK: - Extensions
// (TimeOfDay.formatted already exists in TimeOfDay model)

// MARK: - Park Until Calculator

/// Display format for "Park Until" calculation
enum ParkUntilDisplay {
    case timeLimit(date: Date)                          // Expires at specific time due to time limit
    case enforcementStart(time: TimeOfDay, date: Date)  // Can park until enforcement starts
    case restriction(type: String, date: Date)          // Restriction starts (street cleaning, tow-away)
    case meteredEnd(date: Date)                         // Metered enforcement ends
    case unknown                                        // Unable to calculate

    /// Get the underlying date for comparison
    var date: Date? {
        switch self {
        case .timeLimit(let date), .restriction(_, let date), .meteredEnd(let date):
            return date
        case .enforcementStart(_, let targetDate):
            return targetDate
        case .unknown:
            return nil
        }
    }

    /// Format for display (e.g., "Park until 3:00 PM", "Park until Mon 8:00 AM (street cleaning)")
    func formatted() -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        switch self {
        case .timeLimit(let date):
            formatter.dateFormat = calendar.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
            return "Park until \(formatter.string(from: date))"

        case .restriction(let type, let date):
            formatter.dateFormat = calendar.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
            return "Park until \(formatter.string(from: date))"

        case .meteredEnd(let date):
            formatter.dateFormat = calendar.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
            return "Park until \(formatter.string(from: date))"

        case .enforcementStart(let time, let targetDate):
            let now = Date()
            let currentHour = calendar.component(.hour, from: now)
            let targetIsAM = time.hour < 12

            if calendar.isDateInToday(targetDate) {
                formatter.dateFormat = "h:mm a"
                guard let dateAtTime = calendar.date(
                    bySettingHour: time.hour,
                    minute: time.minute,
                    second: 0,
                    of: targetDate
                ) else {
                    return "Park until \(time.hour):\(String(format: "%02d", time.minute))"
                }
                return "Park until \(formatter.string(from: dateAtTime))"
            }

            if calendar.isDateInTomorrow(targetDate) && currentHour >= 12 && targetIsAM {
                formatter.dateFormat = "h:mm a"
                guard let dateAtTime = calendar.date(
                    bySettingHour: time.hour,
                    minute: time.minute,
                    second: 0,
                    of: targetDate
                ) else {
                    return "Park until \(time.hour):\(String(format: "%02d", time.minute))"
                }
                return "Park until \(formatter.string(from: dateAtTime))"
            }

            formatter.dateFormat = "EEE h:mm a"
            guard let dateAtTime = calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: targetDate
            ) else {
                return "Park until tomorrow"
            }
            return "Park until \(formatter.string(from: dateAtTime))"

        case .unknown:
            return "Check posted signs"
        }
    }

    /// Short format for compact display (e.g., "Until 3:00 PM")
    func shortFormatted() -> String {
        formatted().replacingOccurrences(of: "Park until ", with: "Until ")
    }
}

/// Helper for calculating "Park Until" times based on ALL regulations
/// Considers time limits, street cleaning, metered enforcement, and permit enforcement
/// Works with data from both zones and blockfaces
struct ParkUntilCalculator {
    let timeLimitMinutes: Int?
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let enforcementDays: [DayOfWeek]?
    let validityStatus: PermitValidityStatus
    let allRegulations: [RegulationInfo]

    private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ParkUntilCalculator")

    /// Calculate when parking expires, considering ALL regulations
    func calculateParkUntil(at date: Date = Date()) -> ParkUntilDisplay? {
        logger.info("🔍 ParkUntilCalculator.calculateParkUntil: validityStatus=\(String(describing: self.validityStatus)), regulationCount=\(self.allRegulations.count)")
        for (index, reg) in allRegulations.enumerated() {
            logger.info("  [\(index)] type=\(String(describing: reg.type)), desc=\(reg.description), enforcementDays=\(reg.enforcementDays?.map { $0.rawValue }.joined(separator: ",") ?? "nil")")
        }

        var earliestRestriction: ParkUntilDisplay?
        var earliestDate: Date?

        let calendar = Calendar.current

        // 1. Check for upcoming street cleaning and no parking zones
        // IMPORTANT: These restrictions apply to EVERYONE, including valid permit holders.
        // Valid permits do NOT exempt users from street cleaning or no parking restrictions.
        logger.info("🔍 Step 1: Checking street cleaning and no parking regulations...")
        for regulation in allRegulations {
            if regulation.type == .streetCleaning || regulation.type == .noParking {
                logger.info("  Found \(String(describing: regulation.type)) regulation: \(regulation.description)")
                if let nextOccurrence = findNextOccurrence(of: regulation, from: date) {
                    logger.info("  Next occurrence: \(nextOccurrence, privacy: .public)")
                    if earliestDate == nil || nextOccurrence < earliestDate! {
                        earliestDate = nextOccurrence
                        earliestRestriction = .restriction(
                            type: regulation.type == .streetCleaning ? "Street cleaning" : "No parking",
                            date: nextOccurrence
                        )
                    }
                }
            }
        }

        // 2. Check time limit (only for users without valid permits)
        // Valid permit holders are exempt from time limits, but NOT from street cleaning (checked above)
        if validityStatus == .invalid || validityStatus == .noPermitSet {
            logger.info("🔍 Step 2: Checking time limits for non-permit holders...")

            // Check time-limited regulations in allRegulations array
            for regulation in allRegulations where regulation.type == .timeLimited {
                logger.info("  Found time-limited regulation: \(regulation.description), timeLimit=\(regulation.timeLimit ?? 0) min")

                if let limit = regulation.timeLimit,
                   let startStr = regulation.enforcementStart,
                   let endStr = regulation.enforcementEnd,
                   let startTime = parseTimeString(startStr),
                   let endTime = parseTimeString(endStr) {

                    let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
                    let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    let startMinutes = startTime.totalMinutes
                    let endMinutes = endTime.totalMinutes

                    var currentDayOfWeek: DayOfWeek?
                    var isEnforcementDay = true
                    if let days = regulation.enforcementDays, !days.isEmpty,
                       let weekday = components.weekday,
                       let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
                        currentDayOfWeek = dayOfWeek
                        isEnforcementDay = days.contains(dayOfWeek)
                    }

                    if isEnforcementDay && currentMinutes >= startMinutes && currentMinutes < endMinutes {
                        let timeLimitEnd = date.addingTimeInterval(TimeInterval(limit * 60))

                        // Check if time limit extends past enforcement end
                        let timeLimitComponents = calendar.dateComponents([.hour, .minute], from: timeLimitEnd)
                        let timeLimitMinutes = (timeLimitComponents.hour ?? 0) * 60 + (timeLimitComponents.minute ?? 0)

                        if timeLimitMinutes >= endMinutes {
                            // Time limit extends past enforcement - can park until next enforcement start
                            logger.info("  Time limit extends past enforcement end, finding next enforcement start...")
                            let nextStart = findNextEnforcementStart(from: date, startTime: startTime, days: regulation.enforcementDays, currentDay: currentDayOfWeek)
                            if case .enforcementStart(_, let nextDate) = nextStart {
                                logger.info("  Can park until next enforcement starts: \(nextDate, privacy: .public)")
                                if earliestDate == nil || nextDate < earliestDate! {
                                    earliestDate = nextDate
                                    earliestRestriction = nextStart
                                }
                            }
                        } else {
                            logger.info("  Time limit active NOW, expires at: \(timeLimitEnd, privacy: .public)")
                            if earliestDate == nil || timeLimitEnd < earliestDate! {
                                earliestDate = timeLimitEnd
                                earliestRestriction = .timeLimit(date: timeLimitEnd)
                            }
                        }
                    }
                }
            }

            // Also check the top-level timeLimitMinutes parameter
            if let limit = timeLimitMinutes {
                logger.info("  Found top-level time limit: \(limit) min")
                if let startTime = enforcementStartTime, let endTime = enforcementEndTime {
                    let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
                    let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    let startMinutes = startTime.totalMinutes
                    let endMinutes = endTime.totalMinutes

                    var currentDayOfWeek: DayOfWeek?
                    var isEnforcementDay = true
                    if let days = enforcementDays, !days.isEmpty,
                       let weekday = components.weekday,
                       let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
                        currentDayOfWeek = dayOfWeek
                        isEnforcementDay = days.contains(dayOfWeek)
                        logger.info("  Top-level time limit - currentDay=\(dayOfWeek.rawValue), enforcementDays=\(days.map { $0.rawValue }), isEnforcementDay=\(isEnforcementDay)")
                    }
                    logger.info("  Top-level time limit - currentTime=\(currentMinutes)min, enforcement=\(startMinutes)-\(endMinutes)min, isEnforcementDay=\(isEnforcementDay)")

                    if isEnforcementDay && currentMinutes >= startMinutes && currentMinutes < endMinutes {
                        let timeLimitEnd = date.addingTimeInterval(TimeInterval(limit * 60))

                        // Check if time limit extends past enforcement end
                        let timeLimitComponents = calendar.dateComponents([.hour, .minute], from: timeLimitEnd)
                        let timeLimitMinutesOfDay = (timeLimitComponents.hour ?? 0) * 60 + (timeLimitComponents.minute ?? 0)

                        if timeLimitMinutesOfDay >= endMinutes {
                            // Time limit extends past enforcement - can park until next enforcement start
                            logger.info("  Top-level time limit extends past enforcement end, finding next enforcement start...")
                            let nextStart = findNextEnforcementStart(from: date, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
                            if case .enforcementStart(_, let nextDate) = nextStart {
                                logger.info("  Can park until next enforcement starts: \(nextDate, privacy: .public)")
                                if earliestDate == nil || nextDate < earliestDate! {
                                    earliestDate = nextDate
                                    earliestRestriction = nextStart
                                }
                            }
                        } else {
                            logger.info("  Top-level time limit active NOW, expires at: \(timeLimitEnd, privacy: .public)")
                            if earliestDate == nil || timeLimitEnd < earliestDate! {
                                earliestDate = timeLimitEnd
                                earliestRestriction = .timeLimit(date: timeLimitEnd)
                            }
                        }
                    } else {
                        // Outside enforcement window (wrong day OR outside hours)
                        logger.info("  Top-level time limit NOT currently enforced (outside enforcement window)")
                    }
                } else {
                    let timeLimitEnd = date.addingTimeInterval(TimeInterval(limit * 60))
                    logger.info("  Top-level time limit (no enforcement hours), expires at: \(timeLimitEnd, privacy: .public)")
                    if earliestDate == nil || timeLimitEnd < earliestDate! {
                        earliestDate = timeLimitEnd
                        earliestRestriction = .timeLimit(date: timeLimitEnd)
                    }
                }
            }
        }

        // 3. Check for metered enforcement ending (if currently enforced)
        // OR find when metered enforcement starts next (if not currently enforced)
        for regulation in allRegulations {
            if regulation.type == .metered {
                if let startTime = regulation.enforcementStart,
                   let endTime = regulation.enforcementEnd,
                   let days = regulation.enforcementDays,
                   let startTimeOfDay = parseTimeString(startTime),
                   let endTimeOfDay = parseTimeString(endTime) {

                    let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
                    let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    let startMinutes = startTimeOfDay.totalMinutes
                    let endMinutes = endTimeOfDay.totalMinutes

                    if let weekday = components.weekday,
                       let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {

                        let isEnforcementDay = days.contains(dayOfWeek)
                        let isDuringEnforcementHours = currentMinutes >= startMinutes && currentMinutes < endMinutes

                        logger.info("  Metered check - currentDay=\(dayOfWeek.rawValue), enforcementDays=\(days.map { $0.rawValue }), isEnforcementDay=\(isEnforcementDay)")
                        logger.info("  Metered check - currentTime=\(currentMinutes)min, enforcement=\(startMinutes)-\(endMinutes)min, isDuringHours=\(isDuringEnforcementHours)")

                        if isEnforcementDay && isDuringEnforcementHours {
                            // Currently enforced - show when enforcement ends
                            if let endDate = calendar.date(
                                bySettingHour: endTimeOfDay.hour,
                                minute: endTimeOfDay.minute,
                                second: 0,
                                of: date
                            ), endDate > date {
                                logger.info("  Metered enforcement active, ends at: \(endDate, privacy: .public)")
                                if earliestDate == nil || endDate < earliestDate! {
                                    earliestDate = endDate
                                    earliestRestriction = .meteredEnd(date: endDate)
                                }
                            }
                        } else {
                            // Not currently enforced - find next enforcement start
                            logger.info("  Metered NOT currently enforced, finding next enforcement start...")
                            let nextStart = findNextEnforcementStart(from: date, startTime: startTimeOfDay, days: days, currentDay: dayOfWeek)
                            if case .enforcementStart(_, let nextDate) = nextStart {
                                logger.info("  Parking free until metered enforcement starts: \(nextDate, privacy: .public)")
                                if earliestDate == nil || nextDate < earliestDate! {
                                    earliestDate = nextDate
                                    earliestRestriction = nextStart
                                }
                            }
                        }
                    }
                }
            }
        }

        if let result = earliestRestriction {
            logger.info("✅ ParkUntilCalculator result: \(String(describing: result))")
        } else {
            logger.info("✅ ParkUntilCalculator result: nil")
        }
        return earliestRestriction
    }

    /// Check if currently outside enforcement hours
    func isOutsideEnforcement(at date: Date = Date()) -> Bool {
        guard let startTime = enforcementStartTime,
              let endTime = enforcementEndTime else {
            return false
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.totalMinutes
        let endMinutes = endTime.totalMinutes

        if let days = enforcementDays, !days.isEmpty,
           let weekday = components.weekday,
           let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
            if !days.contains(dayOfWeek) {
                return true
            }
        }

        return currentMinutes < startMinutes || currentMinutes >= endMinutes
    }

    // MARK: - Private Helpers

    private func findNextOccurrence(of regulation: RegulationInfo, from date: Date) -> Date? {
        guard let days = regulation.enforcementDays,
              let startTime = regulation.enforcementStart,
              let timeOfDay = parseTimeString(startTime) else {
            return nil
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let currentWeekday = components.weekday,
              let currentDayOfWeek = DayOfWeek.from(calendarWeekday: currentWeekday) else {
            return nil
        }

        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let targetMinutes = timeOfDay.hour * 60 + timeOfDay.minute

        if days.contains(currentDayOfWeek) && currentMinutes < targetMinutes {
            return calendar.date(
                bySettingHour: timeOfDay.hour,
                minute: timeOfDay.minute,
                second: 0,
                of: date
            )
        }

        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: currentDayOfWeek) else {
            return nil
        }

        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if days.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: date) {
                    return calendar.date(
                        bySettingHour: timeOfDay.hour,
                        minute: timeOfDay.minute,
                        second: 0,
                        of: targetDate
                    )
                }
                break
            }
        }

        return nil
    }

    private func parseTimeString(_ timeStr: String) -> TimeOfDay? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return TimeOfDay(hour: parts[0], minute: parts[1])
    }

    private func findNextEnforcementStart(
        from date: Date,
        startTime: TimeOfDay,
        days: [DayOfWeek]?,
        currentDay: DayOfWeek?
    ) -> ParkUntilDisplay {
        let calendar = Calendar.current

        guard let enforcementDays = days, !enforcementDays.isEmpty, let current = currentDay else {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
                return .enforcementStart(time: startTime, date: tomorrow)
            }
            return .unknown
        }

        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: current) else {
            return .unknown
        }

        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if enforcementDays.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: date) {
                    return .enforcementStart(time: startTime, date: targetDate)
                }
                break
            }
        }

        return .unknown
    }
}
