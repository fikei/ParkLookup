import Foundation
import CoreLocation

/// Codable coordinate for JSON parsing
struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    /// Convert to CoreLocation coordinate
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// MARK: - GeoJSON Support

extension Coordinate {
    /// Initialize from GeoJSON coordinate array [longitude, latitude]
    init?(geoJSON: [Double]) {
        guard geoJSON.count >= 2 else { return nil }
        // GeoJSON uses [longitude, latitude] order
        self.longitude = geoJSON[0]
        self.latitude = geoJSON[1]
    }

    /// Convert to GeoJSON coordinate array
    var geoJSONArray: [Double] {
        [longitude, latitude]
    }
}

// MARK: - Distance Calculation

extension Coordinate {
    /// Calculate distance in meters to another coordinate
    func distance(to other: Coordinate) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }

    /// Calculate distance to a CLLocationCoordinate2D
    func distance(to other: CLLocationCoordinate2D) -> Double {
        distance(to: Coordinate(other))
    }
}
