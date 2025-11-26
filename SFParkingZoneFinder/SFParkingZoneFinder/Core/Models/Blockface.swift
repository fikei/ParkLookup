import Foundation
import CoreLocation

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

    /// Get permit zone if this is a residential permit area
    var permitZone: String? {
        regulations.first(where: { $0.type == "residentialPermit" })?.permitZone
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
    let type: String  // "streetCleaning", "timeLimit", "residentialPermit", etc.
    let permitZone: String?
    let timeLimit: Int?  // Minutes
    let enforcementDays: [String]?  // ["monday", "thursday"]
    let enforcementStart: String?   // "08:00"
    let enforcementEnd: String?     // "10:00"

    enum CodingKeys: String, CodingKey {
        case type, permitZone, timeLimit
        case enforcementDays, enforcementStart, enforcementEnd
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
        return "\(hours) hour limit"
    }

    private var permitDescription: String {
        if let zone = permitZone {
            return "Zone \(zone) permit required"
        } else {
            return "Permit required"
        }
    }

    /// Check if this regulation is in effect at a given date
    func isInEffect(at date: Date) -> Bool {
        guard let days = enforcementDays else { return true }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        // Convert weekday to day name
        let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let dayName = dayNames[weekday - 1]

        return days.contains(dayName)
    }
}
