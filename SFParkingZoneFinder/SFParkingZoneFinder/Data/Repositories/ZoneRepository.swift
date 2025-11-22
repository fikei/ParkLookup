import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ZoneRepository")

/// Repository for accessing parking zone data
final class ZoneRepository {

    private let dataSource: ZoneDataSourceProtocol
    private let cache: ZoneCacheProtocol

    init(dataSource: ZoneDataSourceProtocol, cache: ZoneCacheProtocol) {
        self.dataSource = dataSource
        self.cache = cache
        logger.info("ZoneRepository initialized")
    }

    /// Get zones for a city, using cache when available
    func getZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        logger.info("Getting zones for city: \(city.code)")

        // Check cache first
        if let cachedZones = cache.getCachedZones(for: city) {
            logger.info("✓ Returning \(cachedZones.count) zones from cache")
            return cachedZones
        }

        logger.info("Cache miss, loading from data source...")

        // Load from data source
        let zones = try await dataSource.loadZones(for: city)
        logger.info("✅ Loaded \(zones.count) zones from data source")

        // Cache the results
        cache.cacheZones(zones, for: city)
        logger.info("Cached \(zones.count) zones")

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
