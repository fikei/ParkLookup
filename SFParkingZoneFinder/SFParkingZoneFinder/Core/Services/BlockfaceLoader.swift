import Foundation
import CoreLocation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "BlockfaceLoader")

/// Loads blockface data from embedded JSON file with optimizations
final class BlockfaceLoader: @unchecked Sendable {
    static let shared = BlockfaceLoader()

    private var allBlockfacesCache: [Blockface]?
    private let queue = DispatchQueue(label: "com.sfparkingzonefinder.blockface-loader", qos: .userInitiated)

    private init() {
        // Listen for data source changes to clear cache
        NotificationCenter.default.addObserver(
            forName: .blockfaceDataSourceChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearCache()
        }
    }

    /// Clear the blockface cache (called when data source changes)
    func clearCache() {
        queue.async {
            self.allBlockfacesCache = nil
            logger.info("🗑️ Blockface cache cleared")
        }
    }

    /// Load blockfaces near a specific location (OPTIMIZED for performance)
    /// - Parameters:
    ///   - coordinate: Center coordinate to search around
    ///   - radiusMeters: Radius in meters to search (default: 500m ~= 5-6 blocks)
    ///   - maxCount: Maximum number of blockfaces to return (default: 150)
    /// - Returns: Array of nearby blockfaces
    func loadBlockfacesNear(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 500,
        maxCount: Int = 150
    ) async throws -> [Blockface] {
        let startTime = Date()

        // Load all blockfaces (cached after first load)
        let allBlockfaces = try await loadAllBlockfaces()

        logger.info("🔍 Filtering \(allBlockfaces.count) blockfaces near (\(coordinate.latitude), \(coordinate.longitude)) within \(radiusMeters)m")

        // Filter to nearby blockfaces using spatial filtering
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var nearby: [(blockface: Blockface, distance: Double)] = []

        for blockface in allBlockfaces {
            // Check if any point in the linestring is within radius
            let coords = blockface.geometry.locationCoordinates
            guard !coords.isEmpty else { continue }

            // Use first point as approximate center for distance calculation
            let blockfaceLocation = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
            let distance = userLocation.distance(from: blockfaceLocation)

            if distance <= radiusMeters {
                nearby.append((blockface, distance))
            }
        }

        // Sort by distance and limit to maxCount
        let sorted = nearby.sorted { $0.distance < $1.distance }
        let limited = Array(sorted.prefix(maxCount))
        let result = limited.map { $0.blockface }

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("✅ Loaded \(result.count) blockfaces in \(String(format: "%.3f", elapsed))s (filtered from \(allBlockfaces.count))")

        return result
    }

    /// Load all blockfaces (cached, use sparingly)
    private func loadAllBlockfaces() async throws -> [Blockface] {
        if let cached = allBlockfacesCache {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    // Get selected data source from developer settings
                    let dataSource = DeveloperSettings.shared.blockfaceDataSource
                    let filename = dataSource.filename

                    logger.info("📥 Loading blockface dataset from \(filename).json (32MB)...")
                    let startTime = Date()

                    guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
                        logger.error("\(filename).json not found in bundle")
                        throw BlockfaceLoaderError.fileNotFound
                    }

                    let data = try Data(contentsOf: url)
                    let response = try JSONDecoder().decode(BlockfaceDataResponse.self, from: data)

                    self.allBlockfacesCache = response.blockfaces

                    let elapsed = Date().timeIntervalSince(startTime)
                    logger.info("✅ Loaded \(response.blockfaces.count) blockfaces from \(dataSource.displayName) in \(String(format: "%.2f", elapsed))s")

                    continuation.resume(returning: response.blockfaces)
                } catch {
                    logger.error("❌ Failed to load blockfaces: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Legacy method - loads all blockfaces (NOT RECOMMENDED - use loadBlockfacesNear instead)
    @available(*, deprecated, message: "Use loadBlockfacesNear(coordinate:radiusMeters:maxCount:) instead for better performance")
    func loadBlockfaces() throws -> [Blockface] {
        if let cached = allBlockfacesCache {
            logger.info("Returning cached blockfaces")
            return cached
        }

        // Get selected data source from developer settings
        let dataSource = DeveloperSettings.shared.blockfaceDataSource
        let filename = dataSource.filename

        logger.info("⚠️ Loading ALL blockfaces from \(filename).json synchronously (SLOW) - consider using loadBlockfacesNear instead")

        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            logger.error("\(filename).json not found in bundle")
            throw BlockfaceLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(BlockfaceDataResponse.self, from: data)

        allBlockfacesCache = response.blockfaces

        logger.info("Loaded \(response.blockfaces.count) blockfaces from \(dataSource.displayName)")

        return response.blockfaces
    }

    /// Find blockfaces with active street cleaning (optimized version)
    func getActiveStreetCleaningBlockfaces(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 500,
        at date: Date = Date()
    ) async throws -> [Blockface] {
        let nearby = try await loadBlockfacesNear(coordinate: coordinate, radiusMeters: radiusMeters, maxCount: 150)
        return nearby.filter { $0.hasActiveStreetCleaning(at: date) }
    }
}

struct BlockfaceDataResponse: Codable {
    let blockfaces: [Blockface]
}

enum BlockfaceLoaderError: Error {
    case fileNotFound
    case invalidData
}
