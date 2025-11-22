import Foundation
import CoreLocation
import Combine

/// ViewModel for the main parking result view
@MainActor
final class MainResultViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // Zone & Rules
    @Published private(set) var zoneName: String = "—"
    @Published private(set) var validityStatus: PermitValidityStatus = .noPermitRequired
    @Published private(set) var ruleSummary: String = ""
    @Published private(set) var ruleSummaryLines: [String] = []
    @Published private(set) var warnings: [ParkingWarning] = []
    @Published private(set) var conditionalFlags: [ConditionalFlag] = []

    // Overlapping zones
    @Published private(set) var hasOverlappingZones = false
    @Published private(set) var overlappingZones: [ParkingZone] = []

    // Location
    @Published private(set) var currentAddress: String = "Locating..."
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lookupConfidence: LookupConfidence = .high

    // User permits
    @Published private(set) var applicablePermits: [ParkingPermit] = []
    @Published private(set) var userPermits: [ParkingPermit] = []

    // Map
    @Published var showFloatingMap = true
    @Published var mapPosition: MapPosition = .topRight

    // MARK: - Dependencies

    private let locationService: LocationServiceProtocol
    private let zoneService: ZoneServiceProtocol
    private let reverseGeocodingService: ReverseGeocodingServiceProtocol
    private let permitService: PermitServiceProtocol

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        locationService: LocationServiceProtocol,
        zoneService: ZoneServiceProtocol,
        reverseGeocodingService: ReverseGeocodingServiceProtocol,
        permitService: PermitServiceProtocol
    ) {
        self.locationService = locationService
        self.zoneService = zoneService
        self.reverseGeocodingService = reverseGeocodingService
        self.permitService = permitService

        setupBindings()
    }

    /// Convenience initializer using shared dependency container
    convenience init() {
        let container = DependencyContainer.shared
        self.init(
            locationService: container.locationService,
            zoneService: container.zoneService,
            reverseGeocodingService: container.reverseGeocodingService,
            permitService: container.permitService
        )
    }

    // MARK: - Public Methods

    /// Refresh location and update parking result
    func refreshLocation() {
        Task {
            await performLookup()
        }
    }

    /// Called when view appears
    func onAppear() {
        // Check location authorization
        let status = locationService.authorizationStatus
        print("DEBUG onAppear: authorization status = \(status.rawValue)")

        if status == .notDetermined {
            // Request permission - the authorizationPublisher callback will trigger lookup when granted
            print("DEBUG onAppear: requesting authorization...")
            locationService.requestWhenInUseAuthorization()
            isLoading = true // Show loading while waiting for permission
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            // Already authorized - perform lookup
            print("DEBUG onAppear: already authorized, calling refreshLocation")
            refreshLocation()
        } else {
            // Denied or restricted
            print("DEBUG onAppear: denied/restricted")
            error = .locationPermissionDenied
        }
    }

    /// Report an issue with zone data
    func reportIssue() {
        // TODO: Implement issue reporting (email, feedback form)
        print("Report issue tapped")
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Listen for permit changes
        permitService.permitsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] permits in
                self?.userPermits = permits
                // Re-evaluate if we have a current location
                if self?.lastUpdated != nil {
                    self?.refreshLocation()
                }
            }
            .store(in: &cancellables)

        // Listen for location authorization changes
        locationService.authorizationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                print("DEBUG authCallback: status changed to \(status.rawValue)")
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    print("DEBUG authCallback: authorized, calling refreshLocation")
                    self.error = nil
                    self.refreshLocation()
                case .denied, .restricted:
                    print("DEBUG authCallback: denied/restricted")
                    self.isLoading = false
                    self.error = .locationPermissionDenied
                case .notDetermined:
                    print("DEBUG authCallback: still notDetermined")
                    break // Still waiting for user response
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func performLookup() async {
        // Check authorization
        guard locationService.authorizationStatus == .authorizedWhenInUse ||
              locationService.authorizationStatus == .authorizedAlways else {
            error = .locationPermissionDenied
            return
        }

        isLoading = true
        error = nil

        do {
            // Get current location
            print("DEBUG: Requesting location...")
            let location = try await locationService.requestSingleLocation()
            print("DEBUG: Got location: \(location.coordinate.latitude), \(location.coordinate.longitude)")

            // Get parking result
            print("DEBUG: Getting parking result...")
            let result = await zoneService.getParkingResult(
                at: location.coordinate,
                time: Date()
            )
            print("DEBUG: Got parking result, zone: \(result.lookupResult.primaryZone?.displayName ?? "none")")

            // Update UI state
            updateState(from: result)

            // Get address (don't fail if this fails)
            print("DEBUG: Getting address...")
            await updateAddress(for: location)
            print("DEBUG: Done")

            lastUpdated = Date()

        } catch let locationError as LocationError {
            print("DEBUG: Location error: \(locationError)")
            error = AppError.from(locationError)
        } catch {
            print("DEBUG: Other error: \(error)")
            self.error = .unknown(error.localizedDescription)
        }

        isLoading = false
    }

    private func updateState(from result: ParkingResult) {
        // Zone info
        if let zone = result.lookupResult.primaryZone {
            zoneName = zone.displayName
        } else {
            zoneName = "Unknown Zone"
        }

        // Validity & rules
        if let interpretation = result.primaryInterpretation {
            validityStatus = interpretation.validityStatus
            ruleSummary = interpretation.ruleSummary
            ruleSummaryLines = interpretation.ruleSummaryLines
            warnings = interpretation.warnings
            conditionalFlags = interpretation.conditionalFlags
            applicablePermits = interpretation.applicablePermits
        } else {
            validityStatus = result.lookupResult.isOutsideCoverage ? .noPermitRequired : .invalid
            ruleSummary = result.lookupResult.isOutsideCoverage
                ? "Outside covered area"
                : "Unable to determine parking rules"
            ruleSummaryLines = [ruleSummary]
            warnings = []
            conditionalFlags = []
            applicablePermits = []
        }

        // Overlapping zones
        overlappingZones = result.lookupResult.overlappingZones
        hasOverlappingZones = overlappingZones.count > 1

        // Confidence
        lookupConfidence = result.lookupResult.confidence

        // Check for outside coverage
        if result.lookupResult.isOutsideCoverage {
            error = .outsideCoverage
        }
    }

    private func updateAddress(for location: CLLocation) async {
        do {
            let address = try await reverseGeocodingService.reverseGeocode(location: location)
            currentAddress = address.shortAddress
        } catch {
            currentAddress = String(format: "%.4f, %.4f",
                                   location.coordinate.latitude,
                                   location.coordinate.longitude)
        }
    }
}

// MARK: - Map Position

enum MapPosition: String, CaseIterable, Codable {
    case topLeft
    case topRight
    case bottomRight

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomRight: return .bottomTrailing
        }
    }
}

// MARK: - App Errors

enum AppError: LocalizedError, Identifiable, Equatable {
    case locationPermissionDenied
    case locationUnavailable
    case outsideCoverage
    case dataLoadFailed
    case unknown(String)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .locationPermissionDenied:
            return "Location access is required to find parking zones near you."
        case .locationUnavailable:
            return "Unable to determine your location. Please try again."
        case .outsideCoverage:
            return "You're outside our coverage area. We currently support San Francisco only."
        case .dataLoadFailed:
            return "Unable to load parking zone data."
        case .unknown(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .locationPermissionDenied:
            return "Open Settings to enable location access."
        case .locationUnavailable:
            return "Make sure you have a clear view of the sky and try again."
        case .outsideCoverage:
            return "More cities coming soon!"
        case .dataLoadFailed:
            return "Try restarting the app."
        case .unknown:
            return nil
        }
    }

    static func from(_ error: LocationError) -> AppError {
        switch error {
        case .permissionDenied, .permissionRestricted:
            return .locationPermissionDenied
        case .locationUnknown, .timeout, .serviceDisabled:
            return .locationUnavailable
        }
    }
}

// MARK: - SwiftUI Alignment Extension

import SwiftUI

extension Alignment {
    static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
