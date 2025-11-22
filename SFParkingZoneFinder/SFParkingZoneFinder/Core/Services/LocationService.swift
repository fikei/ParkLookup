import Foundation
import CoreLocation
import Combine

/// Location service implementation using CoreLocation
final class LocationService: NSObject, LocationServiceProtocol {

    // MARK: - Properties

    private let locationManager = CLLocationManager()
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let authorizationSubject = PassthroughSubject<CLAuthorizationStatus, Never>()

    private var singleLocationContinuation: CheckedContinuation<CLLocation, Error>?

    private(set) var currentLocation: CLLocation?

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationSubject.eraseToAnyPublisher()
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update when moved 10 meters
    }

    // MARK: - LocationServiceProtocol

    func requestWhenInUseAuthorization() {
        print("DEBUG LocationService: requestWhenInUseAuthorization called")
        print("DEBUG LocationService: current status before request = \(locationManager.authorizationStatus.rawValue)")
        DispatchQueue.main.async {
            print("DEBUG LocationService: calling requestWhenInUseAuthorization on main thread")
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    func requestSingleLocation() async throws -> CLLocation {
        // Check authorization first
        switch authorizationStatus {
        case .denied:
            throw LocationError.permissionDenied
        case .restricted:
            throw LocationError.permissionRestricted
        case .notDetermined:
            requestWhenInUseAuthorization()
            // Wait briefly for authorization
            try await Task.sleep(nanoseconds: 500_000_000)
            if authorizationStatus == .denied {
                throw LocationError.permissionDenied
            }
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.singleLocationContinuation = continuation

            // Set timeout
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if self.singleLocationContinuation != nil {
                    self.singleLocationContinuation?.resume(throwing: LocationError.timeout)
                    self.singleLocationContinuation = nil
                    self.locationManager.stopUpdatingLocation()
                }
            }

            locationManager.requestLocation()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        currentLocation = location
        locationSubject.send(location)

        // Handle single location request
        if let continuation = singleLocationContinuation {
            continuation.resume(returning: location)
            singleLocationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let continuation = singleLocationContinuation {
            let locationError: LocationError
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    locationError = .permissionDenied
                case .locationUnknown:
                    locationError = .locationUnknown
                default:
                    locationError = .locationUnknown
                }
            } else {
                locationError = .locationUnknown
            }
            continuation.resume(throwing: locationError)
            singleLocationContinuation = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("DEBUG LocationService: didChangeAuthorization to \(manager.authorizationStatus.rawValue)")
        authorizationSubject.send(manager.authorizationStatus)
    }
}
