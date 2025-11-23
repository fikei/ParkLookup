import Foundation
import CoreLocation

/// Represents a parking zone with boundaries and rules
struct ParkingZone: Identifiable, Hashable {
    let id: String
    let cityCode: String
    let displayName: String
    let zoneType: ZoneType
    let permitArea: String?
    let validPermitAreas: [String]
    let boundaries: [[Coordinate]]  // MultiPolygon: array of polygon boundaries
    let multiPermitBoundaries: [MultiPermitBoundary]  // Boundaries that accept multiple permits
    let rules: [ParkingRule]
    let requiresPermit: Bool
    let restrictiveness: Int  // 1-10 scale, higher = more restrictive
    let metadata: ZoneMetadata

    // MARK: - Hashable (by ID only for performance)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ParkingZone, rhs: ParkingZone) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Multi-Permit Boundary

/// Represents a boundary that accepts multiple parking permits
struct MultiPermitBoundary: Codable, Hashable {
    let boundaryIndex: Int
    let validPermitAreas: [String]
}

// MARK: - Custom Codable (backward compatible with "boundary" and "boundaries")

extension ParkingZone: Codable {
    enum CodingKeys: String, CodingKey {
        case id, cityCode, displayName, zoneType, permitArea, validPermitAreas
        case boundaries  // New MultiPolygon format
        case boundary    // Old single polygon format (for backward compatibility)
        case multiPermitBoundaries
        case rules, requiresPermit, restrictiveness, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        cityCode = try container.decode(String.self, forKey: .cityCode)
        displayName = try container.decode(String.self, forKey: .displayName)
        zoneType = try container.decode(ZoneType.self, forKey: .zoneType)
        permitArea = try container.decodeIfPresent(String.self, forKey: .permitArea)
        validPermitAreas = try container.decode([String].self, forKey: .validPermitAreas)
        rules = try container.decode([ParkingRule].self, forKey: .rules)
        requiresPermit = try container.decode(Bool.self, forKey: .requiresPermit)
        restrictiveness = try container.decode(Int.self, forKey: .restrictiveness)
        metadata = try container.decode(ZoneMetadata.self, forKey: .metadata)

        // Try "boundaries" first (new MultiPolygon format), fall back to "boundary" (old format)
        if let multiBoundaries = try? container.decode([[Coordinate]].self, forKey: .boundaries) {
            boundaries = multiBoundaries
        } else if let singleBoundary = try? container.decode([Coordinate].self, forKey: .boundary) {
            // Wrap single boundary in array for MultiPolygon compatibility
            boundaries = [singleBoundary]
        } else {
            boundaries = []
        }

        // Load multi-permit boundaries (optional, may not exist in older data)
        multiPermitBoundaries = (try? container.decode([MultiPermitBoundary].self, forKey: .multiPermitBoundaries)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(cityCode, forKey: .cityCode)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(zoneType, forKey: .zoneType)
        try container.encodeIfPresent(permitArea, forKey: .permitArea)
        try container.encode(validPermitAreas, forKey: .validPermitAreas)
        try container.encode(boundaries, forKey: .boundaries)
        try container.encode(multiPermitBoundaries, forKey: .multiPermitBoundaries)
        try container.encode(rules, forKey: .rules)
        try container.encode(requiresPermit, forKey: .requiresPermit)
        try container.encode(restrictiveness, forKey: .restrictiveness)
        try container.encode(metadata, forKey: .metadata)
    }
}

// MARK: - Computed Properties

extension ParkingZone {
    /// All boundaries as arrays of CLLocationCoordinate2D (MultiPolygon)
    var allBoundaryCoordinates: [[CLLocationCoordinate2D]] {
        boundaries.map { $0.map { $0.clCoordinate } }
    }

    /// First boundary for backward compatibility
    var boundaryCoordinates: [CLLocationCoordinate2D] {
        allBoundaryCoordinates.first ?? []
    }

    /// Get the primary rule description
    var primaryRuleDescription: String? {
        rules.first?.description
    }

    /// Time limit for non-permit holders (in minutes)
    var nonPermitTimeLimit: Int? {
        rules.first { $0.ruleType == .timeLimit }?.timeLimit
    }

    /// Enforcement hours description
    var enforcementHours: String? {
        guard let rule = rules.first(where: { $0.enforcementStartTime != nil }) else {
            return nil
        }
        return rule.enforcementHoursDescription
    }

    /// Street cleaning schedule if applicable
    var streetCleaning: String? {
        rules.first { $0.ruleType == .streetCleaning }?.description
    }

    /// Check if zone has time-based restrictions
    var hasTimeRestrictions: Bool {
        rules.contains { $0.enforcementStartTime != nil || $0.enforcementDays != nil }
    }

    /// Description of time restrictions
    var timeRestrictionDescription: String {
        guard let rule = rules.first(where: { $0.enforcementStartTime != nil }) else {
            return "No time restrictions"
        }
        return rule.enforcementHoursDescription ?? "Time restrictions apply"
    }

    /// Check if a boundary at the given index is a multi-permit boundary
    func isMultiPermitBoundary(at index: Int) -> Bool {
        multiPermitBoundaries.contains { $0.boundaryIndex == index }
    }

    /// Get all valid permit areas for a boundary at the given index
    func validPermitAreas(for boundaryIndex: Int) -> [String]? {
        multiPermitBoundaries.first { $0.boundaryIndex == boundaryIndex }?.validPermitAreas
    }

    /// Set of multi-permit boundary indices for quick lookup
    var multiPermitBoundaryIndices: Set<Int> {
        Set(multiPermitBoundaries.map { $0.boundaryIndex })
    }

    /// Formatted subtitle for metered zones (e.g., "$2/hr • 2hr max")
    var meteredSubtitle: String? {
        guard zoneType == .metered else { return nil }

        let rate = metadata.hourlyRate ?? 2.0
        let timeLimit = metadata.avgTimeLimit ?? 120

        let rateStr = rate.truncatingRemainder(dividingBy: 1) == 0
            ? "$\(Int(rate))/hr"
            : String(format: "$%.2f/hr", rate)

        let timeStr: String
        if timeLimit >= 60 {
            let hours = timeLimit / 60
            timeStr = "\(hours)hr max"
        } else {
            timeStr = "\(timeLimit)min max"
        }

        return "\(rateStr) • \(timeStr)"
    }
}

// MARK: - Zone Type

enum ZoneType: String, Codable, CaseIterable {
    case residentialPermit = "rpp"
    case metered = "metered"
    case timeLimited = "time_limited"
    case noParking = "no_parking"
    case towAway = "tow_away"
    case mixed = "mixed"

    var displayName: String {
        switch self {
        case .residentialPermit: return "Residential Permit Zone"
        case .metered: return "Metered Parking"
        case .timeLimited: return "Time Limited Parking"
        case .noParking: return "No Parking"
        case .towAway: return "Tow-Away Zone"
        case .mixed: return "Mixed Parking Zone"
        }
    }

    var iconName: String {
        switch self {
        case .residentialPermit: return "house.fill"
        case .metered: return "dollarsign.circle.fill"
        case .timeLimited: return "clock.fill"
        case .noParking: return "nosign"
        case .towAway: return "exclamationmark.triangle.fill"
        case .mixed: return "square.stack.fill"
        }
    }
}

// MARK: - Zone Metadata

struct ZoneMetadata: Codable, Hashable {
    let dataSource: String
    let lastUpdatedString: String  // Store as string for flexible parsing
    let accuracy: DataAccuracy

    // Metered zone specific data
    let hourlyRate: Double?  // Hourly rate in dollars (e.g., 2.0 = $2/hr)
    let avgTimeLimit: Int?   // Average time limit in minutes (e.g., 120 = 2hr max)
    let meterCount: Int?     // Number of meters in zone

    /// Computed Date property with flexible parsing
    var lastUpdated: Date {
        ZoneMetadata.parseDate(lastUpdatedString) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case dataSource
        case lastUpdatedString = "lastUpdated"
        case accuracy
        case hourlyRate
        case avgTimeLimit
        case meterCount
    }

    // Simple date parser for metadata dates
    private static func parseDate(_ string: String) -> Date? {
        // Try ISO8601 formats
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: string) {
            return date
        }

        // Try without fractional seconds
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: string) {
            return date
        }

        // Try basic format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }
}

enum DataAccuracy: String, Codable {
    case high
    case medium
    case low

    var description: String {
        switch self {
        case .high: return "High accuracy - verified official data"
        case .medium: return "Medium accuracy - simplified boundaries"
        case .low: return "Low accuracy - approximate boundaries"
        }
    }
}
