import Foundation

/// Protocol for parking zone data sources (local or remote)
protocol ZoneDataSourceProtocol {
    /// Load all zones for a specific city
    /// - Parameter city: The city identifier
    /// - Returns: Array of parking zones
    /// - Throws: DataSourceError if loading fails
    func loadZones(for city: CityIdentifier) async throws -> [ParkingZone]

    /// Get the current data version string
    func getDataVersion() -> String
}

/// Protocol for zone caching
protocol ZoneCacheProtocol {
    /// Get cached zones for a city (nil if not cached or expired)
    func getCachedZones(for city: CityIdentifier) -> [ParkingZone]?

    /// Cache zones for a city
    func cacheZones(_ zones: [ParkingZone], for city: CityIdentifier)

    /// Invalidate cache for a specific city
    func invalidateCache(for city: CityIdentifier)

    /// Invalidate all cached data
    func invalidateAllCaches()

    /// Last time the cache was updated
    var lastUpdated: Date? { get }
}

// MARK: - Data Source Errors

enum DataSourceError: LocalizedError {
    case fileNotFound(String)
    case parsingFailed(String)
    case invalidData(String)
    case cityNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Data file not found: \(filename)"
        case .parsingFailed(let reason):
            return "Failed to parse data: \(reason)"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .cityNotSupported(let city):
            return "City not supported: \(city)"
        }
    }
}
