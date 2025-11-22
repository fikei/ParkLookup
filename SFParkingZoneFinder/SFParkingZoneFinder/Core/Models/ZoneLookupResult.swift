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

    /// Error that occurred during lookup (data loading failure)
    let dataError: ZoneDataError?

    init(
        primaryZone: ParkingZone?,
        overlappingZones: [ParkingZone] = [],
        confidence: LookupConfidence,
        timestamp: Date = Date(),
        coordinate: CLLocationCoordinate2D,
        nearestBoundaryDistance: Double? = nil,
        dataError: ZoneDataError? = nil
    ) {
        self.primaryZone = primaryZone
        self.overlappingZones = overlappingZones.isEmpty && primaryZone != nil ? [primaryZone!] : overlappingZones
        self.confidence = confidence
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.nearestBoundaryDistance = nearestBoundaryDistance
        self.dataError = dataError
    }
}

// MARK: - Zone Data Error

/// Error types specific to zone data loading
enum ZoneDataError: Error, Equatable {
    case fileNotFound(filename: String)
    case decodingFailed(details: String)
    case noZonesLoaded
    case unknown(message: String)

    var localizedDescription: String {
        switch self {
        case .fileNotFound(let filename):
            return "Data file '\(filename)' not found"
        case .decodingFailed(let details):
            return "Failed to decode zone data: \(details)"
        case .noZonesLoaded:
            return "No zones were loaded"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Computed Properties

extension ZoneLookupResult {
    /// Whether multiple zones overlap at this location
    var hasOverlappingZones: Bool {
        overlappingZones.count > 1
    }

    /// Whether this result indicates outside coverage (truly outside supported cities)
    var isOutsideCoverage: Bool {
        confidence == .outsideCoverage
    }

    /// Whether this result indicates in-city but not in any known zone
    var isUnknownArea: Bool {
        confidence == .unknownArea
    }

    /// Whether there was an error loading zone data
    var hasDataError: Bool {
        dataError != nil
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
        case .unknownArea:
            return "Status unknown"
        case .outsideCoverage:
            return "Outside San Francisco"
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

    /// In supported city but not in any known zone (status unknown)
    case unknownArea

    /// Location not in any supported city
    case outsideCoverage

    var iconName: String {
        switch self {
        case .high: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        case .unknownArea: return "questionmark.circle.fill"
        case .outsideCoverage: return "xmark.circle.fill"
        }
    }

    var displayText: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        case .unknownArea: return "Unknown area"
        case .outsideCoverage: return "Outside coverage"
        }
    }
}

// MARK: - Factory Methods

extension ZoneLookupResult {
    /// Create a result for outside coverage (outside supported cities)
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

    /// Create a result for unknown area (in city but no zone data)
    static func unknownArea(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date()
    ) -> ZoneLookupResult {
        ZoneLookupResult(
            primaryZone: nil,
            overlappingZones: [],
            confidence: .unknownArea,
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

    /// Create a result for data loading failure
    static func dataLoadError(
        _ error: ZoneDataError,
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date()
    ) -> ZoneLookupResult {
        ZoneLookupResult(
            primaryZone: nil,
            overlappingZones: [],
            confidence: .outsideCoverage,
            timestamp: timestamp,
            coordinate: coordinate,
            nearestBoundaryDistance: nil,
            dataError: error
        )
    }
}
