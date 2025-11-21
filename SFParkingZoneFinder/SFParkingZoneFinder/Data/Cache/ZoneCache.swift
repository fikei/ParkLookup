import Foundation

/// In-memory cache for parking zones
final class ZoneCache: ZoneCacheProtocol {

    private var cache: [String: CacheEntry] = [:]
    private let cacheDuration: TimeInterval

    private(set) var lastUpdated: Date?

    init(cacheDuration: TimeInterval = 300) { // 5 minutes default
        self.cacheDuration = cacheDuration
    }

    func getCachedZones(for city: CityIdentifier) -> [ParkingZone]? {
        guard let entry = cache[city.code] else { return nil }

        // Check if cache is still valid
        if Date().timeIntervalSince(entry.timestamp) > cacheDuration {
            cache.removeValue(forKey: city.code)
            return nil
        }

        return entry.zones
    }

    func cacheZones(_ zones: [ParkingZone], for city: CityIdentifier) {
        let entry = CacheEntry(zones: zones, timestamp: Date())
        cache[city.code] = entry
        lastUpdated = Date()
    }

    func invalidateCache(for city: CityIdentifier) {
        cache.removeValue(forKey: city.code)
    }

    func invalidateAllCaches() {
        cache.removeAll()
        lastUpdated = nil
    }
}

// MARK: - Cache Entry

private struct CacheEntry {
    let zones: [ParkingZone]
    let timestamp: Date
}
