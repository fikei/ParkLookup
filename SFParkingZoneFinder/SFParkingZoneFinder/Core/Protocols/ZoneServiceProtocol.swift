import Foundation
import CoreLocation

/// High-level protocol for zone-related operations
/// Combines lookup, interpretation, and permit validation
protocol ZoneServiceProtocol {
    /// Get the complete parking result for a location
    /// - Parameters:
    ///   - coordinate: The GPS coordinate
    ///   - time: The time to evaluate (defaults to now)
    /// - Returns: Complete parking result with zone, validity, and rules
    func getParkingResult(
        at coordinate: CLLocationCoordinate2D,
        time: Date
    ) async -> ParkingResult

    /// Get all zones for a city
    /// - Parameter city: The city identifier
    /// - Returns: Array of all parking zones
    func getAllZones(for city: CityIdentifier) async throws -> [ParkingZone]

    /// Get data version information
    var dataVersion: String { get }

    /// Check if service is ready
    var isReady: Bool { get }
}

// MARK: - Parking Result

/// Complete parking result combining zone lookup and rule interpretation
struct ParkingResult {
    /// The lookup result from zone engine
    let lookupResult: ZoneLookupResult

    /// The rule interpretation for primary zone
    let primaryInterpretation: RuleInterpretationResult?

    /// Interpretations for all overlapping zones
    let allInterpretations: [RuleInterpretationResult]

    /// Reverse geocoded address
    let address: Address?

    /// Timestamp of this result
    let timestamp: Date

    /// Whether the result indicates an error state
    var isError: Bool {
        lookupResult.confidence == .outsideCoverage || lookupResult.primaryZone == nil
    }

    /// Quick access to validity status
    var validityStatus: PermitValidityStatus? {
        primaryInterpretation?.validityStatus
    }
}
