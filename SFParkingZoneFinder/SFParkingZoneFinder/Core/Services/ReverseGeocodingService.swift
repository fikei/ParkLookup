import Foundation
import CoreLocation
import MapKit

/// Reverse geocoding service using MapKit
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

        do {
            // Use MapKit's reverse geocoding request (iOS 26+)
            var request = MKReverseGeocodingRequest()
            request.coordinate = location.coordinate
            let result = try await request.submit()

            guard let mapItem = result.mapItem else {
                throw GeocodingError.noResults
            }

            // Use MKMapItem's properties instead of deprecated MKPlacemark (iOS 26+)
            let addressDict = mapItem.addressDictionary ?? [:]

            let address = Address(
                streetNumber: addressDict["SubThoroughfare"] as? String,
                streetName: addressDict["Thoroughfare"] as? String,
                neighborhood: addressDict["SubLocality"] as? String,
                city: addressDict["City"] as? String,
                formattedAddress: formatAddress(from: addressDict)
            )

            cache[cacheKey] = address
            return address

        } catch let error as GeocodingError {
            throw error
        } catch {
            throw GeocodingError.networkError
        }
    }

    private func formatAddress(from addressDict: [String: Any]) -> String {
        var components: [String] = []

        if let subThoroughfare = addressDict["SubThoroughfare"] as? String {
            components.append(subThoroughfare)
        }
        if let thoroughfare = addressDict["Thoroughfare"] as? String {
            components.append(thoroughfare)
        }
        if let locality = addressDict["City"] as? String {
            if !components.isEmpty {
                components.append(",")
            }
            components.append(locality)
        }

        return components.joined(separator: " ")
    }
}
