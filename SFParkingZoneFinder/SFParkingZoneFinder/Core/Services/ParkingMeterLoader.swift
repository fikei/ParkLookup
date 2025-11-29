import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ParkingMeterLoader")

/// Loads parking meter data from external GeoJSON file
class ParkingMeterLoader {
    static let shared = ParkingMeterLoader()

    private var cachedMeters: [ParkingMeter]?

    private init() {}

    /// Load parking meters from external GeoJSON file
    func loadParkingMeters() throws -> [ParkingMeter] {
        if let cached = cachedMeters {
            logger.info("Returning cached parking meters")
            return cached
        }

        logger.info("Loading parking meters from external GeoJSON")

        // Path to the external dataset
        let fileURL = URL(fileURLWithPath: "/home/user/ParkLookup/Data Sets/Parking_Meters_20251128.geojson")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Parking_Meters_20251128.geojson not found at path: \(fileURL.path)")
            throw ParkingMeterLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)

        // Decode GeoJSON
        let response = try JSONDecoder().decode(ParkingMeterGeoJSON.self, from: data)

        // Convert features to ParkingMeter models
        let meters = response.features.compactMap { $0.toParkingMeter() }

        cachedMeters = meters

        logger.info("Loaded \(meters.count) parking meters")

        return meters
    }

    /// Get active parking meters only
    func getActiveMeters() throws -> [ParkingMeter] {
        let meters = try loadParkingMeters()
        return meters.filter { $0.isActive }
    }

    /// Clear cache to reload data
    func clearCache() {
        cachedMeters = nil
        logger.info("Cleared parking meter cache")
    }
}

/// GeoJSON FeatureCollection wrapper
struct ParkingMeterGeoJSON: Codable {
    let type: String
    let features: [ParkingMeterFeature]
}

enum ParkingMeterLoaderError: Error {
    case fileNotFound
    case invalidData
}
