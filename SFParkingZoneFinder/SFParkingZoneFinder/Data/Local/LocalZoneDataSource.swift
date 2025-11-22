import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ZoneDataSource")

/// Local data source that loads zones from bundled JSON file
final class LocalZoneDataSource: ZoneDataSourceProtocol {

    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        logger.info("LocalZoneDataSource initialized")
    }

    func loadZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        let filename = "\(city.code)_parking_zones"
        logger.info("Loading zones for city: \(city.code), filename: \(filename)")

        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            logger.error("❌ File not found: \(filename).json")
            throw DataSourceError.fileNotFound(filename)
        }

        logger.info("Found file at: \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            logger.info("Loaded \(data.count) bytes from file")

            let response = try decoder.decode(ZoneDataResponse.self, from: data)
            logger.info("✅ Successfully decoded \(response.zones.count) zones")

            // Log zone details
            for zone in response.zones {
                let boundaryCount = zone.boundaries.count
                let totalPoints = zone.boundaries.reduce(0) { $0 + $1.count }
                logger.info("  Zone \(zone.permitArea ?? zone.id): \(boundaryCount) boundaries, \(totalPoints) total points")
            }

            return response.zones
        } catch let error as DecodingError {
            logger.error("❌ Decoding error: \(self.describeDecodingError(error))")
            throw DataSourceError.parsingFailed(describeDecodingError(error))
        } catch {
            logger.error("❌ Error loading zones: \(error.localizedDescription)")
            throw DataSourceError.parsingFailed(error.localizedDescription)
        }
    }

    /// Provide detailed description of decoding errors
    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch: expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Value not found: \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .keyNotFound(let key, let context):
            return "Key not found: '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    func getDataVersion() -> String {
        // Try to load version from bundled JSON metadata
        guard let url = bundle.url(forResource: "sf_parking_zones", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? decoder.decode(ZoneDataResponse.self, from: data) else {
            return "1.0.0"
        }
        return response.version
    }
}

// MARK: - Response Types

struct ZoneDataResponse: Codable {
    let version: String
    let generatedAt: Date
    let city: CityInfo
    let permitAreas: [PermitAreaInfo]?
    let zones: [ParkingZone]
}

struct CityInfo: Codable {
    let code: String
    let name: String
    let state: String
    let bounds: CityBounds?
}

struct CityBounds: Codable {
    let north: Double
    let south: Double
    let east: Double
    let west: Double
}

struct PermitAreaInfo: Codable {
    let code: String
    let name: String
    let neighborhoods: [String]?
}
