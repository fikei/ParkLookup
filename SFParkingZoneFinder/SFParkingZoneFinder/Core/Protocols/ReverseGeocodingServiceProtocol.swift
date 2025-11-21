import Foundation
import CoreLocation

/// Protocol for reverse geocoding services
protocol ReverseGeocodingServiceProtocol {
    /// Convert coordinates to a human-readable address
    /// - Parameter location: The location to reverse geocode
    /// - Returns: Formatted address
    /// - Throws: GeocodingError if geocoding fails
    func reverseGeocode(location: CLLocation) async throws -> Address
}

// MARK: - Geocoding Errors

enum GeocodingError: LocalizedError {
    case noResults
    case networkError
    case quotaExceeded
    case invalidCoordinates

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No address found for this location."
        case .networkError:
            return "Network error during geocoding."
        case .quotaExceeded:
            return "Geocoding quota exceeded. Try again later."
        case .invalidCoordinates:
            return "Invalid coordinates provided."
        }
    }
}
