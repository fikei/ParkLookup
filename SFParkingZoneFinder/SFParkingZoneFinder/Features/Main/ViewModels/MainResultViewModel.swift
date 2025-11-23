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
    @Published private(set) var zoneType: ZoneType = .residentialPermit
    @Published private(set) var validityStatus: PermitValidityStatus = .noPermitRequired
    @Published private(set) var ruleSummary: String = ""
    @Published private(set) var ruleSummaryLines: [String] = []
    @Published private(set) var warnings: [ParkingWarning] = []
    @Published private(set) var conditionalFlags: [ConditionalFlag] = []

    // Overlapping zones
    @Published private(set) var hasOverlappingZones = false
    @Published private(set) var overlappingZones: [ParkingZone] = []
    @Published private(set) var currentZoneId: String?

    // Location
    @Published private(set) var currentAddress: String = "Locating..."
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lookupConfidence: LookupConfidence = .high
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    // User permits
    @Published private(set) var applicablePermits: [ParkingPermit] = []
    @Published private(set) var userPermits: [ParkingPermit] = []

    // Map preferences (read from UserDefaults)
    @Published var showFloatingMap: Bool
    @Published var mapPosition: MapPosition

    /// All loaded zones for map display
    var allLoadedZones: [ParkingZone] {
        zoneService.allLoadedZones
    }

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

        // Load map preferences from UserDefaults
        self.showFloatingMap = UserDefaults.standard.object(forKey: "showFloatingMap") as? Bool ?? true
        let positionRaw = UserDefaults.standard.string(forKey: "mapPosition") ?? MapPosition.topRight.rawValue
        self.mapPosition = MapPosition(rawValue: positionRaw) ?? .topRight

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

        if status == .notDetermined {
            // Request permission - the authorizationPublisher callback will trigger lookup when granted
            locationService.requestWhenInUseAuthorization()
            isLoading = true // Show loading while waiting for permission
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            // Already authorized - start continuous updates for real-time driving
            startContinuousLocationUpdates()
        } else {
            // Denied or restricted
            error = .locationPermissionDenied
        }
    }

    /// Called when view disappears
    func onDisappear() {
        locationService.stopUpdatingLocation()
    }

    /// Start continuous location updates for real-time driving use
    private func startContinuousLocationUpdates() {
        // Start tracking location
        locationService.startUpdatingLocation()

        // Subscribe to location updates with debouncing
        locationService.locationPublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main) // Debounce to avoid excessive updates
            .sink { [weak self] location in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.processLocationUpdate(location)
                }
            }
            .store(in: &cancellables)

        // Also do an immediate lookup
        refreshLocation()
    }

    /// Process a location update from continuous tracking
    private func processLocationUpdate(_ location: CLLocation) async {
        // Skip if we're already loading
        guard !isLoading else { return }

        // Skip if location hasn't changed significantly (backup check, LocationService already filters at 10m)
        if let current = currentCoordinate {
            let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            let distance = location.distance(from: currentLocation)
            // Only update if moved more than 20 meters
            guard distance > 20 else { return }
        }

        // Perform the lookup
        currentCoordinate = location.coordinate
        error = nil

        // Get parking result
        let result = await zoneService.getParkingResult(
            at: location.coordinate,
            time: Date()
        )

        // Update UI state
        updateState(from: result)

        // Get address (don't fail if this fails)
        await updateAddress(for: location)

        lastUpdated = Date()
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

        // Listen for map preference changes from Settings
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.showFloatingMap = UserDefaults.standard.object(forKey: "showFloatingMap") as? Bool ?? true
                let positionRaw = UserDefaults.standard.string(forKey: "mapPosition") ?? MapPosition.topRight.rawValue
                self.mapPosition = MapPosition(rawValue: positionRaw) ?? .topRight
            }
            .store(in: &cancellables)

        // Listen for location authorization changes
        locationService.authorizationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    self.error = nil
                    self.startContinuousLocationUpdates()
                case .denied, .restricted:
                    self.isLoading = false
                    self.error = .locationPermissionDenied
                case .notDetermined:
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
            let location = try await locationService.requestSingleLocation()
            currentCoordinate = location.coordinate

            // Get parking result
            let result = await zoneService.getParkingResult(
                at: location.coordinate,
                time: Date()
            )

            // Update UI state
            updateState(from: result)

            // Get address (don't fail if this fails)
            await updateAddress(for: location)

            lastUpdated = Date()

        } catch let locationError as LocationError {
            error = AppError.from(locationError)
        } catch {
            self.error = .unknown(error.localizedDescription)
        }

        isLoading = false
    }

    private func updateState(from result: ParkingResult) {
        // Check for data loading errors first
        if let dataError = result.lookupResult.dataError {
            error = convertToAppError(dataError)
            zoneName = "Data Error"
            ruleSummary = ""
            ruleSummaryLines = []
            warnings = []
            conditionalFlags = []
            applicablePermits = []
            overlappingZones = []
            hasOverlappingZones = false
            return
        }

        // Zone info
        if let zone = result.lookupResult.primaryZone {
            zoneName = zone.displayName
            zoneType = zone.zoneType
            currentZoneId = zone.id
        } else {
            zoneName = "Unknown Zone"
            zoneType = .residentialPermit
            currentZoneId = nil
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

        // Check for special location statuses
        if result.lookupResult.isOutsideCoverage {
            error = .outsideCoverage
        } else if result.lookupResult.isUnknownArea {
            error = .unknownArea
        }
    }

    /// Convert zone data error to user-facing app error
    private func convertToAppError(_ zoneError: ZoneDataError) -> AppError {
        let dataError: DataLoadError
        switch zoneError {
        case .fileNotFound(let filename):
            dataError = DataLoadError(type: .fileNotFound, technicalDetails: filename)
        case .decodingFailed(let details):
            dataError = DataLoadError(type: .decodingFailed, technicalDetails: details)
        case .noZonesLoaded:
            dataError = DataLoadError(type: .noZonesLoaded, technicalDetails: nil)
        case .unknown(let message):
            dataError = DataLoadError(type: .unknown, technicalDetails: message)
        }
        return .dataLoadFailed(dataError)
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

enum MapPosition: String, CaseIterable, Codable, Hashable {
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

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomRight: return "Bottom Right"
        }
    }
}

// MARK: - App Errors

enum AppError: LocalizedError, Identifiable, Equatable {
    case locationPermissionDenied
    case locationUnavailable
    case unknownArea        // In SF but not in any known zone
    case outsideCoverage    // Outside SF entirely
    case dataLoadFailed(DataLoadError)
    case unknown(String)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .locationPermissionDenied:
            return "Location access is required to find parking zones near you."
        case .locationUnavailable:
            return "Unable to determine your location. Please try again."
        case .unknownArea:
            return "We don't have parking data for this specific location yet."
        case .outsideCoverage:
            return "You're outside San Francisco. We currently support SF only."
        case .dataLoadFailed(let dataError):
            return dataError.userMessage
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
        case .unknownArea:
            return "Check posted signs for parking restrictions."
        case .outsideCoverage:
            return "More cities coming soon!"
        case .dataLoadFailed(let dataError):
            return dataError.recoverySuggestion
        case .unknown:
            return nil
        }
    }

    var iconName: String {
        switch self {
        case .locationPermissionDenied:
            return "location.slash.fill"
        case .locationUnavailable:
            return "location.fill.viewfinder"
        case .unknownArea:
            return "questionmark.circle.fill"
        case .outsideCoverage:
            return "map"
        case .dataLoadFailed:
            return "exclamationmark.icloud.fill"
        case .unknown:
            return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .locationPermissionDenied:
            return .red
        case .locationUnavailable:
            return .orange
        case .unknownArea:
            return .yellow
        case .outsideCoverage:
            return .blue
        case .dataLoadFailed:
            return .red
        case .unknown:
            return .orange
        }
    }

    var canRetry: Bool {
        switch self {
        case .locationPermissionDenied:
            return false
        case .locationUnavailable, .dataLoadFailed, .unknown:
            return true
        case .unknownArea:
            return true // User might move to a known area
        case .outsideCoverage:
            return true // User might move
        }
    }

    static func from(_ error: LocationError) -> AppError {
        switch error {
        case .permissionDenied, .permissionRestricted:
            return .locationPermissionDenied
        case .locationUnknown, .timeout, .serviceDisabled:
            return .locationUnavailable
        case .cancelled:
            return .locationUnavailable // Treat cancelled as unavailable
        }
    }
}

// MARK: - Data Load Error

/// Detailed error information for data loading failures
struct DataLoadError: Equatable {
    let type: DataLoadErrorType
    let technicalDetails: String?

    var userMessage: String {
        switch type {
        case .fileNotFound:
            return "Parking zone data is missing."
        case .decodingFailed:
            return "Parking zone data is corrupted or invalid."
        case .noZonesLoaded:
            return "No parking zones available."
        case .networkError:
            return "Unable to download parking data."
        case .unknown:
            return "Unable to load parking zone data."
        }
    }

    var recoverySuggestion: String {
        switch type {
        case .fileNotFound:
            return "Try reinstalling the app to restore the data."
        case .decodingFailed:
            return "Try updating the app or contact support if the issue persists."
        case .noZonesLoaded:
            return "Try refreshing or contact support."
        case .networkError:
            return "Check your internet connection and try again."
        case .unknown:
            return "Try restarting the app."
        }
    }

    /// For debugging - shown in dev builds
    var debugDescription: String {
        if let details = technicalDetails {
            return "\(type.rawValue): \(details)"
        }
        return type.rawValue
    }
}

enum DataLoadErrorType: String {
    case fileNotFound = "file_not_found"
    case decodingFailed = "decoding_failed"
    case noZonesLoaded = "no_zones_loaded"
    case networkError = "network_error"
    case unknown = "unknown"
}

// MARK: - SwiftUI Alignment Extension

import SwiftUI

extension Alignment {
    static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
