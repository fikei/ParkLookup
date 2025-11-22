import Foundation
import CoreLocation
import Combine

/// Protocol for location services abstraction
protocol LocationServiceProtocol {
    /// Current device location (may be nil if not yet acquired)
    var currentLocation: CLLocation? { get }

    /// Publisher for location updates
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }

    /// Current authorization status
    var authorizationStatus: CLAuthorizationStatus { get }

    /// Publisher for authorization status changes
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }

    /// Request "When In Use" location permission
    func requestWhenInUseAuthorization()

    /// Start continuous location updates
    func startUpdatingLocation()

    /// Stop continuous location updates
    func stopUpdatingLocation()

    /// Request a single location update
    /// - Returns: The acquired location
    /// - Throws: LocationError if location cannot be acquired
    func requestSingleLocation() async throws -> CLLocation
}

// MARK: - Location Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case permissionRestricted
    case locationUnknown
    case timeout
    case serviceDisabled
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission was denied. Please enable in Settings."
        case .permissionRestricted:
            return "Location services are restricted on this device."
        case .locationUnknown:
            return "Unable to determine your location. Please try again."
        case .timeout:
            return "Location request timed out. Please try again."
        case .serviceDisabled:
            return "Location services are disabled. Please enable in Settings."
        case .cancelled:
            return "Location request was cancelled."
        }
    }
}
