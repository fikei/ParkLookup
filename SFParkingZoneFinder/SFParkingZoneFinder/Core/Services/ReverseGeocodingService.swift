import Foundation
import CoreLocation
import MapKit

/// Reverse geocoding service using MapKit MKLocalSearch
final class ReverseGeocodingService: ReverseGeocodingServiceProtocol {

    private var cache: [String: Address] = [:]

    func reverseGeocode(location: CLLocation) async throws -> Address {
        // Create cache key (rounded to ~10 meter precision)
        let cacheKey = "\(round(location.coordinate.latitude * 10000))," +
                       "\(round(location.coordinate.longitude * 10000))"

        // Check cache
        if let cached = cache[cacheKey] {
            return cached
        }

        // Use MKLocalSearch with coordinate region for reverse geocoding
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 50,
            longitudinalMeters: 50
        )
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()

            guard let mapItem = response.mapItems.first else {
                throw GeocodingError.noResults
            }

            let placemark = mapItem.placemark

            let address = Address(
                streetNumber: placemark.subThoroughfare,
                streetName: placemark.thoroughfare,
                neighborhood: placemark.subLocality,
                city: placemark.locality,
                formattedAddress: formatAddress(from: placemark)
            )

            cache[cacheKey] = address
            return address

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

        return components.joined(separator: " ")
    }
}
