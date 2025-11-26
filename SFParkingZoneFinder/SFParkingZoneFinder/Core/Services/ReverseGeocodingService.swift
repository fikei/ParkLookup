import Foundation
import CoreLocation
import MapKit

/// Reverse geocoding service using CLGeocoder
final class ReverseGeocodingService: ReverseGeocodingServiceProtocol {

    private var cache: [String: Address] = [:]
    private let geocoder = CLGeocoder()

    func reverseGeocode(location: CLLocation) async throws -> Address {
        // Create cache key (rounded to ~10 meter precision)
        let cacheKey = "\(round(location.coordinate.latitude * 10000))," +
                       "\(round(location.coordinate.longitude * 10000))"

        // Check cache
        if let cached = cache[cacheKey] {
            return cached
        }

        // Use CLGeocoder for reverse geocoding (the correct API for coordinate → address)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)

            guard let placemark = placemarks.first else {
                throw GeocodingError.noResults
            }

            let address = Address(
                streetNumber: placemark.subThoroughfare,
                streetName: placemark.thoroughfare,
                neighborhood: placemark.subLocality,
                city: placemark.locality,
                formattedAddress: formatAddress(from: placemark)
            )

            cache[cacheKey] = address
            return address

        } catch let error as CLError {
            // Handle specific CLGeocoder errors
            if error.code == .network {
                throw GeocodingError.networkError
            } else {
                throw GeocodingError.noResults
            }
        } catch {
            throw GeocodingError.networkError
        }
    }

    private func formatAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []

        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        if let locality = placemark.locality {
            if !components.isEmpty {
                components.append(",")
            }
            components.append(locality)
        }

        let formatted = components.joined(separator: " ")
        // Ensure we never return empty string - use neighborhood or city as fallback
        if formatted.isEmpty {
            return placemark.subLocality ?? placemark.locality ?? "San Francisco"
        }
        return formatted
    }
}
