import Foundation
import CoreLocation

/// Protocol for zone lookup engine
protocol ZoneLookupEngineProtocol {
    /// Find all zones containing or near the given coordinate
    /// - Parameter coordinate: The GPS coordinate to look up
    /// - Returns: Lookup result with primary zone and any overlapping zones
    func findZone(at coordinate: CLLocationCoordinate2D) async -> ZoneLookupResult

    /// Check if the engine has loaded zone data
    var isReady: Bool { get }

    /// Reload zone data
    func reloadZones() async throws
}
