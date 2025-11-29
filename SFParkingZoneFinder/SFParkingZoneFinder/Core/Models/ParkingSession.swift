import Foundation
import CoreLocation

/// Represents an active or past parking session
struct ParkingSession: Codable, Identifiable {
    let id: String
    let startTime: Date
    var endTime: Date?
    let location: ParkingLocation
    let zoneName: String
    let zoneType: ZoneType
    let rules: [SessionRule]
    var isActive: Bool

    /// Calculated parking deadline based on rules
    var parkUntil: Date? {
        // Find the earliest deadline from all rules
        let deadlines = rules.compactMap { $0.deadline }
        return deadlines.min()
    }

    /// Time remaining until parking deadline
    var timeRemaining: TimeInterval? {
        guard let deadline = parkUntil else { return nil }
        return deadline.timeIntervalSince(Date())
    }

    /// Duration of parking session
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    /// Whether parking deadline has passed
    var hasExpired: Bool {
        guard let deadline = parkUntil else { return false }
        return Date() >= deadline
    }

    init(
        id: String = UUID().uuidString,
        startTime: Date = Date(),
        endTime: Date? = nil,
        location: ParkingLocation,
        zoneName: String,
        zoneType: ZoneType,
        rules: [SessionRule],
        isActive: Bool = true
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.zoneName = zoneName
        self.zoneType = zoneType
        self.rules = rules
        self.isActive = isActive
    }
}

// MARK: - Parking Location

struct ParkingLocation: Codable {
    let latitude: Double
    let longitude: Double
    let address: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, address: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.address = address
    }
}

// MARK: - Session Rule

/// Parking rule that applies to a session
struct SessionRule: Codable, Identifiable {
    let id: String
    let type: SessionRuleType
    let description: String
    let deadline: Date?

    init(
        id: String = UUID().uuidString,
        type: SessionRuleType,
        description: String,
        deadline: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.deadline = deadline
    }
}

enum SessionRuleType: String, Codable {
    case timeLimit = "time_limit"
    case streetCleaning = "street_cleaning"
    case enforcement = "enforcement"
    case meter = "meter"
    case noParking = "no_parking"

    var iconName: String {
        switch self {
        case .timeLimit: return "clock.fill"
        case .streetCleaning: return "leaf.fill"
        case .enforcement: return "exclamationmark.shield.fill"
        case .meter: return "dollarsign.circle.fill"
        case .noParking: return "nosign"
        }
    }

    var color: String {
        switch self {
        case .timeLimit: return "orange"
        case .streetCleaning: return "red"
        case .enforcement: return "yellow"
        case .meter: return "blue"
        case .noParking: return "red"
        }
    }
}

// MARK: - Notification Timing

/// When to send notifications relative to parking deadline
enum NotificationTiming: String, Codable, CaseIterable {
    case oneHour = "1_hour"
    case fifteenMinutes = "15_minutes"
    case atDeadline = "at_deadline"

    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour Before"
        case .fifteenMinutes: return "15 Minutes Before"
        case .atDeadline: return "When Time Expires"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return -3600  // 1 hour before
        case .fifteenMinutes: return -900  // 15 minutes before
        case .atDeadline: return 0  // At deadline
        }
    }
}
