import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "PersistentZoneCache")

/// Zone cache with disk persistence for faster app launch
/// Uses binary plist encoding for efficient serialization of [ParkingZone]
final class PersistentZoneCache: ZoneCacheProtocol {

    // MARK: - Properties

    private let memoryCache: ZoneCache
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let lock = NSLock()

    /// Current data version - change this when zone data format changes
    /// Bumped to 1.3: merged adjacent blocks into zone-level polygons (98% reduction)
    private let cacheVersion = "1.3"

    private(set) var lastUpdated: Date?

    // MARK: - Initialization

    init(
        memoryCache: ZoneCache = ZoneCache(),
        fileManager: FileManager = .default
    ) {
        self.memoryCache = memoryCache
        self.fileManager = fileManager

        // Use Caches directory (iOS can clear if storage is low)
        let cachesPath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesPath.appendingPathComponent("ZoneData", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        logger.info("PersistentZoneCache initialized at: \(self.cacheDirectory.path)")
    }

    // MARK: - ZoneCacheProtocol

    func getCachedZones(for city: CityIdentifier) -> [ParkingZone]? {
        // First check memory cache
        if let zones = memoryCache.getCachedZones(for: city) {
            logger.debug("Cache hit (memory) for city: \(city.code)")
            return zones
        }

        // Fall back to disk cache
        return loadFromDisk(for: city)
    }

    func cacheZones(_ zones: [ParkingZone], for city: CityIdentifier) {
        // Update memory cache
        memoryCache.cacheZones(zones, for: city)

        // Persist to disk asynchronously
        Task.detached(priority: .utility) { [weak self] in
            self?.saveToDisk(zones, for: city)
        }

        lastUpdated = Date()
        logger.info("Cached \(zones.count) zones for city: \(city.code)")
    }

    func invalidateCache(for city: CityIdentifier) {
        lock.lock()
        defer { lock.unlock() }

        memoryCache.invalidateCache(for: city)
        deleteFromDisk(for: city)
        logger.info("Invalidated cache for city: \(city.code)")
    }

    func invalidateAllCaches() {
        lock.lock()
        defer { lock.unlock() }

        memoryCache.invalidateAllCaches()
        deleteAllFromDisk()
        lastUpdated = nil
        logger.info("Invalidated all caches")
    }

    // MARK: - Version-aware Cache Loading

    /// Load zones from disk cache if version matches
    /// Returns nil if no cache exists or version mismatch
    func loadFromDisk(for city: CityIdentifier) -> [ParkingZone]? {
        lock.lock()
        defer { lock.unlock() }

        let cacheFile = cacheFileURL(for: city)
        let metaFile = metadataFileURL(for: city)

        guard fileManager.fileExists(atPath: cacheFile.path),
              fileManager.fileExists(atPath: metaFile.path) else {
            logger.debug("No disk cache found for city: \(city.code)")
            return nil
        }

        do {
            // Check version first
            let metaData = try Data(contentsOf: metaFile)
            let metadata = try PropertyListDecoder().decode(CacheMetadata.self, from: metaData)

            guard metadata.version == cacheVersion else {
                logger.info("Cache version mismatch (\(metadata.version) vs \(self.cacheVersion)), invalidating")
                deleteFromDisk(for: city)
                return nil
            }

            // Load zones
            let startTime = CFAbsoluteTimeGetCurrent()
            let data = try Data(contentsOf: cacheFile)
            let zones = try PropertyListDecoder().decode([ParkingZone].self, from: data)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            logger.info("Loaded \(zones.count) zones from disk cache in \(String(format: "%.1f", elapsed))ms")

            // Populate memory cache
            memoryCache.cacheZones(zones, for: city)
            lastUpdated = metadata.savedAt

            return zones
        } catch {
            logger.error("Failed to load disk cache: \(error.localizedDescription)")
            deleteFromDisk(for: city)
            return nil
        }
    }

    // MARK: - Disk Operations

    private func saveToDisk(_ zones: [ParkingZone], for city: CityIdentifier) {
        lock.lock()
        defer { lock.unlock() }

        let cacheFile = cacheFileURL(for: city)
        let metaFile = metadataFileURL(for: city)

        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Save zones as binary plist
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(zones)
            try data.write(to: cacheFile, options: .atomic)

            // Save metadata
            let metadata = CacheMetadata(version: cacheVersion, savedAt: Date(), zoneCount: zones.count)
            let metaData = try encoder.encode(metadata)
            try metaData.write(to: metaFile, options: .atomic)

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let sizeKB = Double(data.count) / 1024.0

            logger.info("Saved \(zones.count) zones to disk (\(String(format: "%.1f", sizeKB))KB) in \(String(format: "%.1f", elapsed))ms")
        } catch {
            logger.error("Failed to save disk cache: \(error.localizedDescription)")
        }
    }

    private func deleteFromDisk(for city: CityIdentifier) {
        let cacheFile = cacheFileURL(for: city)
        let metaFile = metadataFileURL(for: city)

        try? fileManager.removeItem(at: cacheFile)
        try? fileManager.removeItem(at: metaFile)
    }

    private func deleteAllFromDisk() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - File URLs

    private func cacheFileURL(for city: CityIdentifier) -> URL {
        cacheDirectory.appendingPathComponent("\(city.code)_zones.cache")
    }

    private func metadataFileURL(for city: CityIdentifier) -> URL {
        cacheDirectory.appendingPathComponent("\(city.code)_meta.cache")
    }
}

// MARK: - Cache Metadata

private struct CacheMetadata: Codable {
    let version: String
    let savedAt: Date
    let zoneCount: Int
}
