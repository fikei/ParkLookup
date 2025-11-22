import Foundation

/// Represents a parking rule within a zone
struct ParkingRule: Codable, Identifiable, Hashable {
    let id: String
    let ruleType: RuleType
    let description: String
    let enforcementDays: [DayOfWeek]?
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let timeLimit: Int?       // Minutes, nil if no limit
    let meterRate: Decimal?   // Dollars per hour
    let specialConditions: String?

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ParkingRule, rhs: ParkingRule) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Computed Properties

extension ParkingRule {
    /// Human-readable enforcement hours
    var enforcementHoursDescription: String? {
        guard let start = enforcementStartTime, let end = enforcementEndTime else {
            return nil
        }

        let daysStr: String
        if let days = enforcementDays, !days.isEmpty {
            if days.count == 7 {
                daysStr = "Daily"
            } else if days == [.monday, .tuesday, .wednesday, .thursday, .friday] {
                daysStr = "Mon-Fri"
            } else if days == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday] {
                daysStr = "Mon-Sat"
            } else {
                daysStr = days.map { $0.shortName }.joined(separator: ", ")
            }
        } else {
            daysStr = "Daily"
        }

        return "\(daysStr), \(start.formatted) - \(end.formatted)"
    }

    /// Whether this rule is currently in effect
    func isInEffect(at date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)

        // Check day of week
        if let days = enforcementDays, !days.isEmpty {
            guard let weekday = components.weekday,
                  let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) else {
                return false
            }
            if !days.contains(dayOfWeek) {
                return false
            }
        }

        // Check time of day
        if let start = enforcementStartTime, let end = enforcementEndTime,
           let hour = components.hour, let minute = components.minute {
            let currentMinutes = hour * 60 + minute
            let startMinutes = start.hour * 60 + start.minute
            let endMinutes = end.hour * 60 + end.minute

            if currentMinutes < startMinutes || currentMinutes >= endMinutes {
                return false
            }
        }

        return true
    }
}

// MARK: - Rule Type

enum RuleType: String, Codable, CaseIterable {
    case permitRequired = "permit_required"
    case timeLimit = "time_limit"
    case metered = "metered"
    case streetCleaning = "street_cleaning"
    case towAway = "tow_away"
    case noParking = "no_parking"
    case loadingZone = "loading_zone"

    var displayName: String {
        switch self {
        case .permitRequired: return "Permit Required"
        case .timeLimit: return "Time Limit"
        case .metered: return "Metered"
        case .streetCleaning: return "Street Cleaning"
        case .towAway: return "Tow-Away"
        case .noParking: return "No Parking"
        case .loadingZone: return "Loading Zone"
        }
    }

    var iconName: String {
        switch self {
        case .permitRequired: return "car.fill"
        case .timeLimit: return "clock.fill"
        case .metered: return "dollarsign.circle.fill"
        case .streetCleaning: return "leaf.fill"
        case .towAway: return "exclamationmark.triangle.fill"
        case .noParking: return "nosign"
        case .loadingZone: return "shippingbox.fill"
        }
    }
}

// MARK: - Time of Day

struct TimeOfDay: Codable, Hashable {
    let hour: Int     // 0-23
    let minute: Int   // 0-59

    var formatted: String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Total minutes since midnight
    var totalMinutes: Int {
        hour * 60 + minute
    }
}

// MARK: - Day of Week

enum DayOfWeek: String, Codable, CaseIterable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    /// Calendar weekday (1 = Sunday)
    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    /// Create from Calendar weekday component
    static func from(calendarWeekday: Int) -> DayOfWeek? {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
}
