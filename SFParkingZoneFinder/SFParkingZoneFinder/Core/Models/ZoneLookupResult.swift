import Foundation
import CoreLocation

/// Result of a zone lookup operation
struct ZoneLookupResult {
    /// The primary zone (most restrictive when multiple overlap)
    let primaryZone: ParkingZone?

    /// All zones that contain or are near the coordinate
    let overlappingZones: [ParkingZone]

    /// Confidence level of the lookup
    let confidence: LookupConfidence

    /// Timestamp of the lookup
    let timestamp: Date

    /// The coordinate that was looked up
    let coordinate: CLLocationCoordinate2D

    /// Distance to nearest zone boundary in meters (for boundary detection)
    let nearestBoundaryDistance: Double?

    init(
        primaryZone: ParkingZone?,
        overlappingZones: [ParkingZone] = [],
        confidence: LookupConfidence,
        timestamp: Date = Date(),
        coordinate: CLLocationCoordinate2D,
        nearestBoundaryDistance: Double? = nil
    ) {
        self.primaryZone = primaryZone
        self.overlappingZones = overlappingZones.isEmpty && primaryZone != nil ? [primaryZone!] : overlappingZones
        self.confidence = confidence
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.nearestBoundaryDistance = nearestBoundaryDistance
    }
}

// MARK: - Computed Properties

extension ZoneLookupResult {
    /// Whether multiple zones overlap at this location
    var hasOverlappingZones: Bool {
        overlappingZones.count > 1
    }

    /// Whether this result indicates outside coverage
    var isOutsideCoverage: Bool {
        confidence == .outsideCoverage || primaryZone == nil
    }

    /// Whether user is near a zone boundary (within threshold)
    var isNearBoundary: Bool {
        guard let distance = nearestBoundaryDistance else { return false }
        return distance < 10 // meters
    }

    /// User-friendly description of the lookup quality
    var confidenceDescription: String {
        switch confidence {
        case .high:
            return "Location confirmed"
        case .medium:
            return "Near zone boundary"
        case .low:
            return "Location approximate"
        case .outsideCoverage:
            return "Outside covered area"
        }
    }
}

// MARK: - Lookup Confidence

enum LookupConfidence: String, Codable {
    /// Clearly within a single zone
    case high

    /// Near boundary, defaulting to most restrictive
    case medium

    /// Poor GPS accuracy or at exact boundary
    case low

    /// Location not in any known zone
    case outsideCoverage

    var iconName: String {
        switch self {
        case .high: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        case .outsideCoverage: return "xmark.circle.fill"
        }
    }

    var displayText: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        case .outsideCoverage: return "Outside coverage"
        }
    }
}

// MARK: - Factory Methods

extension ZoneLookupResult {
    /// Create a result for outside coverage
    static func outsideCoverage(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date()
    ) -> ZoneLookupResult {
        ZoneLookupResult(
            primaryZone: nil,
            overlappingZones: [],
            confidence: .outsideCoverage,
            timestamp: timestamp,
            coordinate: coordinate,
            nearestBoundaryDistance: nil
        )
    }

    /// Create a result for a single zone match
    static func singleZone(
        _ zone: ParkingZone,
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date()
    ) -> ZoneLookupResult {
        ZoneLookupResult(
            primaryZone: zone,
            overlappingZones: [zone],
            confidence: .high,
            timestamp: timestamp,
            coordinate: coordinate,
            nearestBoundaryDistance: nil
        )
    }
}
