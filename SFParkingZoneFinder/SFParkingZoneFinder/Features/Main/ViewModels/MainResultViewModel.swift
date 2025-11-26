import Foundation
import CoreLocation
import Combine
import os.log

// MARK: - Future Feature TODOs
// TODO: Support time-limited parking zones (non-RPP areas with time restrictions)
//       - Display time limit warnings and "Park Until" time
//       - Handle zones that are time-limited during certain hours only
//
// TODO: Support street cleaning restrictions
//       - Show street cleaning schedule for current location
//       - Warn user if parked during upcoming street cleaning
//       - Calculate "Move by" time based on cleaning schedule
//
// TODO: Support no-parking zones and unlimited parking areas
//       - Handle zones with no parking restrictions (infinity = unlimited)
//       - Show "Unlimited Parking" for truly unrestricted areas
//       - Differentiate from RPP "unlimited" (which means permit holder unlimited)

/// ViewModel for the main parking result view
@MainActor
final class MainResultViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // Zone & Rules
    @Published private(set) var zoneName: String = "—"
    @Published private(set) var zoneType: ZoneType = .residentialPermit
    @Published private(set) var meteredSubtitle: String? = nil  // "$2/hr • 2hr max" for metered zones
    @Published private(set) var timeLimitMinutes: Int? = nil  // Time limit in minutes for non-permit holders
    @Published private(set) var validityStatus: PermitValidityStatus = .noPermitRequired
    @Published private(set) var ruleSummary: String = ""
    @Published private(set) var ruleSummaryLines: [String] = []
    @Published private(set) var warnings: [ParkingWarning] = []
    @Published private(set) var conditionalFlags: [ConditionalFlag] = []

    // Enforcement hours (for calculating "Park Until" time)
    @Published private(set) var enforcementStartTime: TimeOfDay? = nil
    @Published private(set) var enforcementEndTime: TimeOfDay? = nil
    @Published private(set) var enforcementDays: [DayOfWeek]? = nil

    // Overlapping zones
    @Published private(set) var hasOverlappingZones = false
    @Published private(set) var overlappingZones: [ParkingZone] = []
    @Published private(set) var currentZoneId: String?
    @Published private(set) var allValidPermitAreas: [String] = []  // All valid permits from overlapping zones

    // Location
    @Published private(set) var currentAddress: String = "Locating..."
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lookupConfidence: LookupConfidence = .high
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    /// Last known GPS location (separate from searched coordinates)
    private var lastKnownGPSCoordinate: CLLocationCoordinate2D?

    // User permits
    @Published private(set) var applicablePermits: [ParkingPermit] = []
    @Published private(set) var userPermits: [ParkingPermit] = []

    // Logging
    private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "MainViewModel")

    // Map preferences (read from UserDefaults)
    @Published var showFloatingMap: Bool
    @Published var mapPosition: MapPosition
    @Published var showParkingMeters: Bool  // Individual meter pins (not zone polygons)

    /// All loaded zones for map display (metered zone polygons always shown)
    var allLoadedZones: [ParkingZone] {
        zoneService.allLoadedZones
    }

    // MARK: - Dependencies

    private let locationService: LocationServiceProtocol
    private let zoneService: ZoneServiceProtocol
    private let reverseGeocodingService: ReverseGeocodingServiceProtocol
    private let permitService: PermitServiceProtocol
    private let parkingSessionManager: ParkingSessionManagerProtocol

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        locationService: LocationServiceProtocol,
        zoneService: ZoneServiceProtocol,
        reverseGeocodingService: ReverseGeocodingServiceProtocol,
        permitService: PermitServiceProtocol,
        parkingSessionManager: ParkingSessionManagerProtocol
    ) {
        self.locationService = locationService
        self.zoneService = zoneService
        self.reverseGeocodingService = reverseGeocodingService
        self.permitService = permitService
        self.parkingSessionManager = parkingSessionManager

        // Load map preferences from UserDefaults
        self.showFloatingMap = UserDefaults.standard.object(forKey: "showFloatingMap") as? Bool ?? true
        let positionRaw = UserDefaults.standard.string(forKey: "mapPosition") ?? MapPosition.topRight.rawValue
        self.mapPosition = MapPosition(rawValue: positionRaw) ?? .topRight
        // Show parking meters (individual pins) is OFF by default
        self.showParkingMeters = UserDefaults.standard.object(forKey: "showParkingMeters") as? Bool ?? false

        setupBindings()
    }

    /// Convenience initializer using shared dependency container
    convenience init() {
        let container = DependencyContainer.shared
        self.init(
            locationService: container.locationService,
            zoneService: container.zoneService,
            reverseGeocodingService: container.reverseGeocodingService,
            permitService: container.permitService,
            parkingSessionManager: container.parkingSessionManager
        )
    }

    // MARK: - Public Methods

    /// Refresh location and update parking result
    func refreshLocation() {
        Task {
            await performLookup()
        }
    }

    /// Return to GPS location after viewing a searched address
    /// Uses cached GPS coordinate to avoid timeout issues with GPS cold start
    func returnToGPSLocation() {
        logger.info("🔄 returnToGPSLocation called")
        // Use last known GPS location if available (avoids GPS timeout on cold start)
        if let gpsCoord = lastKnownGPSCoordinate {
            logger.info("✅ Using cached GPS: (\(gpsCoord.latitude), \(gpsCoord.longitude))")
            currentCoordinate = gpsCoord
            Task {
                await performLookupAt(gpsCoord)
            }
        } else {
            // No cached GPS - need fresh location
            logger.info("⚠️ No cached GPS, requesting fresh location")
            refreshLocation()
        }
    }

    /// Look up zone at a specific coordinate (for address search)
    func lookupZone(at coordinate: CLLocationCoordinate2D) {
        Task {
            await performLookupAt(coordinate)
        }
    }

    /// Clear error and use last known GPS location (for "Back to Map" after area errors)
    /// This avoids requiring a fresh GPS fix which may timeout
    func clearErrorAndUseLastLocation() {
        error = nil
        // Use last known GPS location (not searched location) if available
        if let gpsCoord = lastKnownGPSCoordinate {
            currentCoordinate = gpsCoord
            Task {
                await performLookupAt(gpsCoord)
            }
        } else {
            // Fall back to fresh location request
            refreshLocation()
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
        isLoading = true  // Show loading until first location

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

        // Use a longer timeout for initial location (GPS cold start can be slow)
        // Don't block on immediate lookup - let continuous updates handle it
        Task {
            do {
                // Wait up to 30 seconds for first location from continuous updates
                try await Task.sleep(nanoseconds: 30_000_000_000)
                // If still loading after 30s and no location, show timeout
                if isLoading && lastKnownGPSCoordinate == nil {
                    error = .locationUnavailable
                    isLoading = false
                }
            } catch {
                // Task cancelled, ignore
            }
        }
    }

    /// Process a location update from continuous tracking
    private func processLocationUpdate(_ location: CLLocation) async {
        // For initial location, allow processing even if loading
        // For subsequent updates, skip if already loading
        let isInitialLocation = lastKnownGPSCoordinate == nil
        if !isInitialLocation && isLoading { return }

        // Skip if location hasn't changed significantly (backup check, LocationService already filters at 10m)
        if let current = currentCoordinate {
            let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            let distance = location.distance(from: currentLocation)
            // Only update if moved more than 20 meters
            guard distance > 20 else { return }
        }

        // Perform the lookup
        currentCoordinate = location.coordinate
        lastKnownGPSCoordinate = location.coordinate  // Save GPS location
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
        isLoading = false  // Done loading (handles initial load case)
    }

    /// Report an issue with zone data
    func reportIssue() {
        // TODO: Implement issue reporting (email, feedback form)
        print("Report issue tapped")
    }

    // MARK: - Parking Session

    /// Start a parking session at the current location
    func startParkingSession() async {
        guard let coordinate = self.currentCoordinate else {
            self.logger.warning("Cannot start parking session: no current location")
            return
        }

        // Convert current zone rules to session rules
        let rules = self.createSessionRules()

        // Start the session
        await self.parkingSessionManager.startSession(
            location: coordinate,
            address: self.currentAddress != "Locating..." ? self.currentAddress : nil,
            zoneName: self.zoneName,
            zoneType: self.zoneType,
            rules: rules
        )

        self.logger.info("Started parking session at \(self.zoneName)")
    }

    /// Get the current active parking session
    func getActiveSession() -> ParkingSession? {
        parkingSessionManager.getActiveSession()
    }

    /// End the active parking session
    func endParkingSession() async {
        await parkingSessionManager.endSession()
        logger.info("Ended parking session")
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
                self.showParkingMeters = UserDefaults.standard.object(forKey: "showParkingMeters") as? Bool ?? false
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
            lastKnownGPSCoordinate = location.coordinate  // Save GPS location

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

    /// Perform lookup at a specific coordinate (for address search)
    private func performLookupAt(_ coordinate: CLLocationCoordinate2D) async {
        logger.info("🔍 performLookupAt: (\(coordinate.latitude), \(coordinate.longitude))")
        isLoading = true
        error = nil

        // Update coordinate
        currentCoordinate = coordinate

        // Get parking result
        let result = await zoneService.getParkingResult(
            at: coordinate,
            time: Date()
        )

        // Log the result
        if let zone = result.lookupResult.primaryZone {
            logger.info("✅ Zone found: \(zone.displayName) (type: \(zone.zoneType.rawValue))")
        } else if result.lookupResult.isUnknownArea {
            logger.warning("⚠️ Unknown area - no zone found at coordinate")
        } else if result.lookupResult.isOutsideCoverage {
            logger.warning("⚠️ Outside coverage area")
        }

        // Update UI state
        updateState(from: result)

        // Get address for the searched location
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        await updateAddress(for: location)

        lastUpdated = Date()
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
            meteredSubtitle = zone.meteredSubtitle  // "$2/hr • 2hr max" for metered zones
            timeLimitMinutes = zone.nonPermitTimeLimit  // Time limit for non-permit holders
            currentZoneId = zone.id

            // Extract enforcement hours from the zone's rules
            if let rule = zone.rules.first(where: { $0.enforcementStartTime != nil }) {
                enforcementStartTime = rule.enforcementStartTime
                enforcementEndTime = rule.enforcementEndTime
                enforcementDays = rule.enforcementDays
            } else {
                enforcementStartTime = nil
                enforcementEndTime = nil
                enforcementDays = nil
            }
        } else {
            zoneName = "Unknown Zone"
            zoneType = .residentialPermit
            meteredSubtitle = nil
            timeLimitMinutes = nil
            currentZoneId = nil
            enforcementStartTime = nil
            enforcementEndTime = nil
            enforcementDays = nil
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

        // Collect all valid permit areas from overlapping RPP zones
        allValidPermitAreas = overlappingZones
            .filter { $0.zoneType == .residentialPermit }
            .compactMap { $0.permitArea }
            .sorted()

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
            // Fallback to a user-friendly message instead of coordinates
            currentAddress = "Address unavailable"
        }
    }

    /// Create session rules from current zone information
    private func createSessionRules() -> [SessionRule] {
        var rules: [SessionRule] = []

        // Add time limit rule if present
        if let timeLimit = timeLimitMinutes,
           let startTime = enforcementStartTime,
           let endTime = enforcementEndTime {

            // Calculate deadline based on current time and enforcement hours
            let deadline = calculateParkingDeadline(
                timeLimitMinutes: timeLimit,
                enforcementStart: startTime,
                enforcementEnd: endTime,
                enforcementDays: enforcementDays
            )

            let description: String
            let hours = timeLimit / 60
            if hours > 0 {
                description = "\(hours)-hour limit"
            } else {
                description = "\(timeLimit)-minute limit"
            }

            rules.append(SessionRule(
                type: .timeLimit,
                description: description,
                deadline: deadline
            ))
        }

        // Add enforcement hours info
        if let start = enforcementStartTime,
           let end = enforcementEndTime {
            let daysText: String
            if let days = enforcementDays, !days.isEmpty {
                if days == [.monday, .tuesday, .wednesday, .thursday, .friday] {
                    daysText = "Mon-Fri"
                } else if days == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday] {
                    daysText = "Mon-Sat"
                } else {
                    daysText = days.map { $0.shortName }.joined(separator: ", ")
                }
            } else {
                daysText = "Daily"
            }

            rules.append(SessionRule(
                type: .enforcement,
                description: "Enforced \(daysText), \(start.formatted) - \(end.formatted)",
                deadline: nil
            ))
        }

        // Add metered zone info if applicable
        if let subtitle = meteredSubtitle {
            rules.append(SessionRule(
                type: .meter,
                description: subtitle,
                deadline: nil
            ))
        }

        return rules
    }

    /// Calculate the parking deadline based on time limit and enforcement hours
    private func calculateParkingDeadline(
        timeLimitMinutes: Int,
        enforcementStart: TimeOfDay,
        enforcementEnd: TimeOfDay,
        enforcementDays: [DayOfWeek]?
    ) -> Date {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = enforcementStart.totalMinutes
        let endMinutes = enforcementEnd.totalMinutes

        // Check if today is an enforcement day
        var isEnforcementDay = true
        if let days = enforcementDays, !days.isEmpty,
           let weekday = components.weekday,
           let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
            isEnforcementDay = days.contains(dayOfWeek)
        }

        // If currently in enforcement window, deadline is time limit from now or enforcement end (whichever is sooner)
        if isEnforcementDay && currentMinutes >= startMinutes && currentMinutes < endMinutes {
            let timeLimitEnd = now.addingTimeInterval(TimeInterval(timeLimitMinutes * 60))
            let todayEndDate = calendar.date(bySettingHour: enforcementEnd.hour, minute: enforcementEnd.minute, second: 0, of: now) ?? now
            return min(timeLimitEnd, todayEndDate)
        }

        // Otherwise, parking is allowed until next enforcement start
        // For simplicity, return enforcement start time today or tomorrow
        if let nextEnforcement = calendar.date(bySettingHour: enforcementStart.hour, minute: enforcementStart.minute, second: 0, of: now) {
            if nextEnforcement > now {
                return nextEnforcement
            } else {
                // Next enforcement is tomorrow
                return calendar.date(byAdding: .day, value: 1, to: nextEnforcement) ?? now
            }
        }

        // Fallback: time limit from now
        return now.addingTimeInterval(TimeInterval(timeLimitMinutes * 60))
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
