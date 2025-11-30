import Foundation
import CoreLocation

// MARK: - Array Extensions

extension Array where Element: Hashable {
    /// Remove duplicate elements while preserving order
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// Represents a single street segment (blockface) with parking regulations
struct Blockface: Codable, Identifiable, Hashable {
    let id: String
    let street: String
    let fromStreet: String?
    let toStreet: String?
    let side: String
    let geometry: LineStringGeometry
    let regulations: [BlockfaceRegulation]

    /// Display name for this blockface
    var displayName: String {
        if let from = fromStreet, let to = toStreet {
            return "\(street) (\(from) to \(to)) - \(side) side"
        } else {
            return "\(street) - \(side) side"
        }
    }

    /// Check if this blockface has active street cleaning
    func hasActiveStreetCleaning(at date: Date = Date()) -> Bool {
        regulations.contains { reg in
            reg.type == "streetCleaning" && reg.isInEffect(at: date)
        }
    }

    /// Get permit zone if this is a residential permit area (DEPRECATED: Use allPermitZones instead)
    var permitZone: String? {
        regulations.first(where: { $0.type == "residentialPermit" })?.allPermitZones.first
    }

    /// Get all permit zones applicable to this blockface (supports multi-RPP)
    var allPermitZones: [String] {
        regulations
            .filter { $0.type == "residentialPermit" }
            .flatMap { $0.allPermitZones }
            .unique()
            .sorted()
    }

    /// Check if this blockface belongs to multiple permit zones
    var isMultiPermit: Bool {
        allPermitZones.count > 1
    }
}

/// LineString geometry for street segment
struct LineStringGeometry: Codable, Hashable {
    let type: String  // Always "LineString"
    let coordinates: [[Double]]  // [[lon, lat], [lon, lat], ...]

    /// Convert to array of CLLocationCoordinate2D for MapKit
    var locationCoordinates: [CLLocationCoordinate2D] {
        coordinates.compactMap { coord in
            guard coord.count >= 2 else { return nil }
            return CLLocationCoordinate2D(
                latitude: coord[1],   // GeoJSON is [lon, lat]
                longitude: coord[0]
            )
        }
    }
}

/// Individual parking regulation on a blockface
struct BlockfaceRegulation: Codable, Hashable, Identifiable {
    let id = UUID()
    let type: String  // "streetCleaning", "timeLimit", "residentialPermit", "metered", "towAway", "noParking", "loadingZone"
    let permitZone: String?  // DEPRECATED: Use permitZones instead
    let permitZones: [String]?  // Multiple permit zones (e.g., ["Q", "R"] for overlapping zones)
    let timeLimit: Int?  // Minutes
    let meterRate: Decimal?  // Dollars per hour
    let enforcementDays: [String]?  // ["monday", "thursday"]
    let enforcementStart: String?   // "08:00"
    let enforcementEnd: String?     // "10:00"
    let specialConditions: String?

    enum CodingKeys: String, CodingKey {
        case type, permitZone, permitZones, timeLimit, meterRate
        case enforcementDays, enforcementStart, enforcementEnd, specialConditions
    }

    /// All applicable permit zones (supports backward compatibility with single permitZone)
    var allPermitZones: [String] {
        if let zones = permitZones, !zones.isEmpty {
            return zones
        } else if let zone = permitZone {
            return [zone]
        }
        return []
    }

    /// Human-readable description
    var description: String {
        switch type {
        case "streetCleaning":
            return streetCleaningDescription
        case "timeLimit":
            return timeLimitDescription
        case "residentialPermit":
            return permitDescription
        case "metered":
            return meteredDescription
        case "towAway":
            return "Tow-away zone"
        case "noParking":
            return noParkingDescription
        case "loadingZone":
            return loadingZoneDescription
        default:
            return "Parking regulation"
        }
    }

    private var streetCleaningDescription: String {
        guard let days = enforcementDays, !days.isEmpty else {
            return "Street cleaning"
        }

        let dayNames = days.map { $0.capitalized }.joined(separator: ", ")

        if let start = enforcementStart, let end = enforcementEnd {
            return "Street cleaning \(dayNames) \(start)-\(end)"
        } else {
            return "Street cleaning \(dayNames)"
        }
    }

    private var timeLimitDescription: String {
        guard let limit = timeLimit else {
            return "Time limit"
        }

        let hours = limit / 60
        let minutes = limit % 60

        if minutes == 0 {
            return "\(hours) hour limit"
        } else {
            return "\(hours)h \(minutes)m limit"
        }
    }

    private var permitDescription: String {
        var parts: [String] = []

        let zones = allPermitZones
        if zones.count > 1 {
            parts.append("Zones \(zones.joined(separator: ", ")) permit")
        } else if zones.count == 1 {
            parts.append("Zone \(zones[0]) permit")
        } else {
            parts.append("Permit required")
        }

        if let limit = timeLimit {
            let hours = limit / 60
            parts.append("\(hours) hour limit for visitors")
        }

        return parts.joined(separator: ", ")
    }

    private var meteredDescription: String {
        guard let rate = meterRate else {
            return "Metered parking"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let rateStr = formatter.string(from: rate as NSDecimalNumber) ?? "$\(rate)"

        if let start = enforcementStart, let end = enforcementEnd {
            return "Metered \(rateStr)/hr, \(start)-\(end)"
        } else {
            return "Metered parking \(rateStr)/hr"
        }
    }

    private var noParkingDescription: String {
        if let start = enforcementStart, let end = enforcementEnd {
            return "No parking \(start)-\(end)"
        } else if let days = enforcementDays, !days.isEmpty {
            let dayNames = days.map { $0.capitalized }.joined(separator: ", ")
            return "No parking \(dayNames)"
        } else {
            return "No parking anytime"
        }
    }

    private var loadingZoneDescription: String {
        if let start = enforcementStart, let end = enforcementEnd {
            return "Loading zone \(start)-\(end)"
        } else {
            return "Loading zone"
        }
    }

    /// Check if this regulation is in effect at a given date
    func isInEffect(at date: Date) -> Bool {
        // Check day of week if specified
        if let days = enforcementDays, !days.isEmpty {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: date)
            let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            let dayName = dayNames[weekday - 1]

            if !days.contains(dayName) {
                return false
            }
        }

        // Check time of day if specified
        if let startStr = enforcementStart, let endStr = enforcementEnd {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: date)
            guard let currentHour = components.hour, let currentMinute = components.minute else {
                return true
            }

            let currentMinutes = currentHour * 60 + currentMinute

            // Parse start time
            let startParts = startStr.split(separator: ":").compactMap { Int($0) }
            guard startParts.count == 2 else { return true }
            let startMinutes = startParts[0] * 60 + startParts[1]

            // Parse end time
            let endParts = endStr.split(separator: ":").compactMap { Int($0) }
            guard endParts.count == 2 else { return true }
            let endMinutes = endParts[0] * 60 + endParts[1]

            // Check if current time is within range
            if currentMinutes < startMinutes || currentMinutes >= endMinutes {
                return false
            }
        }

        return true
    }
}
