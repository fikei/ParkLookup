import Foundation

/// Repository for accessing parking zone data
final class ZoneRepository {

    private let dataSource: ZoneDataSourceProtocol
    private let cache: ZoneCacheProtocol

    init(dataSource: ZoneDataSourceProtocol, cache: ZoneCacheProtocol) {
        self.dataSource = dataSource
        self.cache = cache
    }

    /// Get zones for a city, using cache when available
    func getZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        // Check cache first
        if let cachedZones = cache.getCachedZones(for: city) {
            return cachedZones
        }

        // Load from data source
        let zones = try await dataSource.loadZones(for: city)

        // Cache the results
        cache.cacheZones(zones, for: city)

        return zones
    }

    /// Force refresh zones from data source
    func refreshZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        cache.invalidateCache(for: city)
        return try await getZones(for: city)
    }

    /// Get data version
    var dataVersion: String {
        dataSource.getDataVersion()
    }

    /// Invalidate all cached data
    func invalidateAllCaches() {
        cache.invalidateAllCaches()
    }
}
