import Foundation
import CoreLocation

/// Identifies a supported city for parking zone data
struct CityIdentifier: Codable, Hashable, Identifiable {
    let code: String      // "sf", "oak", "sj"
    let name: String      // "San Francisco"
    let state: String     // "CA"

    var id: String { code }

    // MARK: - Predefined Cities

    static let sanFrancisco = CityIdentifier(
        code: "sf",
        name: "San Francisco",
        state: "CA"
    )

    static let oakland = CityIdentifier(
        code: "oak",
        name: "Oakland",
        state: "CA"
    )

    static let berkeley = CityIdentifier(
        code: "berk",
        name: "Berkeley",
        state: "CA"
    )

    // MARK: - Supported Cities (V1 = SF only)

    static let supportedCities: [CityIdentifier] = [
        .sanFrancisco
    ]

    /// Check if a city code is supported
    static func isSupported(_ code: String) -> Bool {
        supportedCities.contains { $0.code == code }
    }

    /// Get city by code
    static func city(for code: String) -> CityIdentifier? {
        supportedCities.first { $0.code == code }
    }
}

// MARK: - City Bounds

extension CityIdentifier {
    /// Geographic bounds for the city
    struct Bounds: Codable {
        let north: Double
        let south: Double
        let east: Double
        let west: Double

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            coordinate.latitude >= south &&
            coordinate.latitude <= north &&
            coordinate.longitude >= west &&
            coordinate.longitude <= east
        }
    }

    /// Get bounds for known cities
    var bounds: Bounds? {
        switch code {
        case "sf":
            return Bounds(
                north: 37.8324,
                south: 37.6398,
                east: -122.3281,
                west: -122.5274
            )
        default:
            return nil
        }
    }

    /// Check if coordinate is within city bounds
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        bounds?.contains(coordinate) ?? false
    }
}
