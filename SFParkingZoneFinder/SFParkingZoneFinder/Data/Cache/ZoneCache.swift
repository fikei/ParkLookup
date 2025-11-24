import Foundation

/// Thread-safe in-memory cache for parking zones
final class ZoneCache: ZoneCacheProtocol {

    private var cache: [String: CacheEntry] = [:]
    private let cacheDuration: TimeInterval
    private let lock = NSLock()

    private(set) var lastUpdated: Date?

    init(cacheDuration: TimeInterval = 300) { // 5 minutes default
        self.cacheDuration = cacheDuration
    }

    func getCachedZones(for city: CityIdentifier) -> [ParkingZone]? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[city.code] else { return nil }

        // Check if cache is still valid
        if Date().timeIntervalSince(entry.timestamp) > cacheDuration {
            cache.removeValue(forKey: city.code)
            return nil
        }

        return entry.zones
    }

    func cacheZones(_ zones: [ParkingZone], for city: CityIdentifier) {
        lock.lock()
        defer { lock.unlock() }

        let entry = CacheEntry(zones: zones, timestamp: Date())
        cache[city.code] = entry
        lastUpdated = Date()
    }

    func invalidateCache(for city: CityIdentifier) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: city.code)
    }

    func invalidateAllCaches() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        lastUpdated = nil
    }
}

// MARK: - Cache Entry

private struct CacheEntry {
    let zones: [ParkingZone]
    let timestamp: Date
}
