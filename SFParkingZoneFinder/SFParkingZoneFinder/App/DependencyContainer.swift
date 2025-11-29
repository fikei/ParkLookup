import Foundation
import SwiftUI
import Combine

/// Central dependency container for service registration and resolution
/// Uses protocol-based abstractions for testability
@MainActor
final class DependencyContainer: ObservableObject {

    // MARK: - Singleton

    static let shared = DependencyContainer()

    // MARK: - Published Services (for SwiftUI observation)

    @Published private(set) var isInitialized = false
    @Published private(set) var isZonesLoaded = false
    @Published private(set) var zoneLoadingStatus = "Starting up..."

    // MARK: - Service Instances

    // Location Services
    private(set) lazy var locationService: LocationServiceProtocol = LocationService()
    private(set) lazy var reverseGeocodingService: ReverseGeocodingServiceProtocol = ReverseGeocodingService()

    // Data Services
    private(set) lazy var zoneDataSource: ZoneDataSourceProtocol = LocalZoneDataSource()
    private(set) lazy var zoneCache: ZoneCacheProtocol = PersistentZoneCache()
    private(set) lazy var zoneRepository: ZoneRepository = ZoneRepository(
        dataSource: zoneDataSource,
        cache: zoneCache
    )

    // Business Logic
    private(set) lazy var zoneLookupEngine: ZoneLookupEngineProtocol = ZoneLookupEngine(
        repository: zoneRepository
    )
    private(set) lazy var ruleInterpreter: RuleInterpreterProtocol = RuleInterpreter()
    private(set) lazy var permitService: PermitServiceProtocol = PermitService()

    // Notification Services
    private(set) lazy var notificationService: NotificationServiceProtocol = NotificationService()

    // Session Management
    private(set) lazy var parkingSessionManager: ParkingSessionManagerProtocol = ParkingSessionManager(
        notificationService: notificationService
    )

    // Map Services
    private(set) lazy var mapProvider: MapProviderProtocol = GoogleMapsAdapter()

    // MARK: - Initialization

    private init() {
        // Start loading zones immediately in background
        Task { @MainActor in
            await loadZonesInBackground()
        }
    }

    /// Load zones in background - called automatically on init
    private func loadZonesInBackground() async {
        zoneLoadingStatus = "Loading parking zones..."

        do {
            _ = try await zoneRepository.getZones(for: .sanFrancisco)
            zoneLoadingStatus = "Ready!"
            isZonesLoaded = true
            isInitialized = true
        } catch {
            print("Failed to initialize zone data: \(error)")
            zoneLoadingStatus = "Ready"
            // App can still function, will show error state
            isZonesLoaded = true
            isInitialized = true
        }
    }

    /// Wait for zones to be loaded (for use after onboarding)
    func waitForZonesLoaded() async {
        // If already loaded, return immediately
        if isZonesLoaded { return }

        // Otherwise wait for the published property to change
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = $isZonesLoaded
                .filter { $0 }
                .first()
                .sink { _ in
                    cancellable?.cancel()
                    continuation.resume()
                }
        }
    }

    // MARK: - Testing Support

    /// Creates a container with mock services for testing
    static func forTesting(
        locationService: LocationServiceProtocol? = nil,
        zoneDataSource: ZoneDataSourceProtocol? = nil,
        permitService: PermitServiceProtocol? = nil
    ) -> DependencyContainer {
        let container = DependencyContainer()

        // Override with mocks if provided
        if let locationService = locationService {
            container._locationService = locationService
        }
        if let zoneDataSource = zoneDataSource {
            container._zoneDataSource = zoneDataSource
        }
        if let permitService = permitService {
            container._permitService = permitService
        }

        return container
    }

    // Private backing stores for testing overrides
    private var _locationService: LocationServiceProtocol?
    private var _zoneDataSource: ZoneDataSourceProtocol?
    private var _permitService: PermitServiceProtocol?
}

// MARK: - Service Resolution Helpers

extension DependencyContainer {

    /// Resolve the zone service with all dependencies wired
    var zoneService: ZoneServiceProtocol {
        ZoneService(
            repository: zoneRepository,
            lookupEngine: zoneLookupEngine,
            ruleInterpreter: ruleInterpreter,
            permitService: permitService
        )
    }
}
