import Foundation

/// Represents a user's parking permit
struct ParkingPermit: Codable, Identifiable, Hashable {
    let id: UUID
    let type: PermitType
    let area: String              // "Q", "R", etc.
    let cityCode: String          // "sf"
    var expirationDate: Date?
    var isPrimary: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: PermitType,
        area: String,
        cityCode: String = "sf",
        expirationDate: Date? = nil,
        isPrimary: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.area = area
        self.cityCode = cityCode
        self.expirationDate = expirationDate
        self.isPrimary = isPrimary
        self.createdAt = createdAt
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ParkingPermit, rhs: ParkingPermit) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Computed Properties

extension ParkingPermit {
    /// Display name for the permit
    var displayName: String {
        switch type {
        case .residential:
            return "Area \(area) Permit"
        case .commercial:
            return "Commercial Permit"
        case .disabled:
            return "Disabled Placard"
        case .visitor:
            return "Visitor Permit - Area \(area)"
        }
    }

    /// Whether the permit is expired
    var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return expiration < Date()
    }

    /// Days until expiration (nil if no expiration date)
    var daysUntilExpiration: Int? {
        guard let expiration = expirationDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
        return days
    }

    /// Whether permit should show expiration warning (< 30 days)
    var shouldWarnExpiration: Bool {
        guard let days = daysUntilExpiration else { return false }
        return days > 0 && days <= 30
    }
}

// MARK: - Permit Type

enum PermitType: String, Codable, CaseIterable {
    case residential = "rpp"
    case commercial = "commercial"
    case disabled = "disabled"
    case visitor = "visitor"

    var displayName: String {
        switch self {
        case .residential: return "Residential Permit (RPP)"
        case .commercial: return "Commercial Vehicle"
        case .disabled: return "Disabled Placard"
        case .visitor: return "Visitor Permit"
        }
    }

    var iconName: String {
        switch self {
        case .residential: return "house.fill"
        case .commercial: return "truck.box.fill"
        case .disabled: return "figure.roll"
        case .visitor: return "person.fill"
        }
    }

    /// Whether this permit type is available in V1
    var isAvailable: Bool {
        switch self {
        case .residential: return true
        case .commercial, .disabled, .visitor: return false
        }
    }
}

// MARK: - SF Permit Areas

struct PermitAreas {
    /// All San Francisco residential permit areas
    static let sanFrancisco: [String] = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
        "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y", "Z"
    ]

    /// Get neighborhood hints for permit areas
    static func neighborhoodHint(for area: String) -> String? {
        switch area {
        case "A": return "Telegraph Hill, North Beach"
        case "B": return "Marina, Cow Hollow"
        case "C": return "Russian Hill"
        case "D": return "Pacific Heights"
        case "E": return "Presidio Heights"
        case "F": return "Inner Richmond"
        case "G": return "Outer Richmond"
        case "H": return "Sunset"
        case "I": return "Parkside"
        case "J": return "West Portal"
        case "K": return "Glen Park, Diamond Heights"
        case "L": return "Noe Valley"
        case "M": return "Bernal Heights"
        case "N": return "Potrero Hill"
        case "O": return "South Beach, Mission Bay"
        case "P": return "Inner Sunset"
        case "Q": return "Castro, Upper Market"
        case "R": return "Haight-Ashbury"
        case "S": return "Hayes Valley"
        case "T": return "Western Addition"
        case "U": return "Lower Pacific Heights"
        case "V": return "Japantown"
        case "W": return "Tenderloin"
        case "X": return "Civic Center"
        case "Y": return "SoMa"
        case "Z": return "Mission"
        default: return nil
        }
    }
}
