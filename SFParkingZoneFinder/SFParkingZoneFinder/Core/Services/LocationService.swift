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
    private var timeoutTask: Task<Void, Never>?
    private let continuationLock = NSLock()
    private var isContinuousUpdatesActive = false

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
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        isContinuousUpdatesActive = true
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        isContinuousUpdatesActive = false
        locationManager.stopUpdatingLocation()
    }

    func requestSingleLocation() async throws -> CLLocation {
        // If continuous updates are active and we have a recent location, return it immediately
        if isContinuousUpdatesActive, let current = currentLocation {
            // Check if the location is recent (within last 30 seconds)
            if Date().timeIntervalSince(current.timestamp) < 30 {
                return current
            }
        }

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
            continuationLock.lock()

            // Cancel any existing continuation
            if let existing = singleLocationContinuation {
                existing.resume(throwing: LocationError.cancelled)
            }

            self.singleLocationContinuation = continuation
            continuationLock.unlock()

            // Cancel any existing timeout
            timeoutTask?.cancel()

            // Set timeout
            timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    self.resumeContinuationWithError(LocationError.timeout)
                } catch {
                    // Task was cancelled, do nothing
                }
            }

            // Request a single location update
            locationManager.requestLocation()
        }
    }

    // MARK: - Private Methods

    private func resumeContinuationWithLocation(_ location: CLLocation) {
        continuationLock.lock()
        defer { continuationLock.unlock() }

        if let continuation = singleLocationContinuation {
            singleLocationContinuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume(returning: location)
        }
    }

    private func resumeContinuationWithError(_ error: LocationError) {
        continuationLock.lock()
        defer { continuationLock.unlock() }

        if let continuation = singleLocationContinuation {
            singleLocationContinuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        currentLocation = location

        // Always publish for continuous updates
        locationSubject.send(location)

        // Handle single location request (thread-safe)
        resumeContinuationWithLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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

        // Handle single location request error (thread-safe)
        resumeContinuationWithError(locationError)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationSubject.send(manager.authorizationStatus)
    }
}
