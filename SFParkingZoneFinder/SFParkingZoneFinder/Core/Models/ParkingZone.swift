import Foundation
import CoreLocation

/// Represents a parking zone with boundaries and rules
struct ParkingZone: Codable, Identifiable, Hashable {
    let id: String
    let cityCode: String
    let displayName: String
    let zoneType: ZoneType
    let permitArea: String?
    let validPermitAreas: [String]
    let boundary: [Coordinate]
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

// MARK: - Computed Properties

extension ParkingZone {
    /// Boundary as CLLocationCoordinate2D array
    var boundaryCoordinates: [CLLocationCoordinate2D] {
        boundary.map { $0.clCoordinate }
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
    let lastUpdated: Date
    let accuracy: DataAccuracy

    enum CodingKeys: String, CodingKey {
        case dataSource
        case lastUpdated
        case accuracy
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
