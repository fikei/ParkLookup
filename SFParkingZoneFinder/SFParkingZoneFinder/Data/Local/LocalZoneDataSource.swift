import Foundation

/// Local data source that loads zones from bundled JSON file
final class LocalZoneDataSource: ZoneDataSourceProtocol {

    private let bundle: Bundle
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadZones(for city: CityIdentifier) async throws -> [ParkingZone] {
        let filename = "\(city.code)_parking_zones"

        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            throw DataSourceError.fileNotFound(filename)
        }

        do {
            let data = try Data(contentsOf: url)
            let response = try decoder.decode(ZoneDataResponse.self, from: data)
            return response.zones
        } catch let error as DecodingError {
            throw DataSourceError.parsingFailed(error.localizedDescription)
        } catch {
            throw DataSourceError.parsingFailed(error.localizedDescription)
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
