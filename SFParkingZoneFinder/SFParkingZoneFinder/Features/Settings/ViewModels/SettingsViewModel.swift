import Foundation
import Combine
import UIKit

/// ViewModel for the Settings screen
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var permits: [ParkingPermit] = []
    @Published var showFloatingMap: Bool {
        didSet {
            UserDefaults.standard.set(showFloatingMap, forKey: "showFloatingMap")
        }
    }
    @Published var mapPosition: MapPosition {
        didSet {
            UserDefaults.standard.set(mapPosition.rawValue, forKey: "mapPosition")
        }
    }
    @Published var showParkingMeters: Bool {
        didSet {
            UserDefaults.standard.set(showParkingMeters, forKey: "showParkingMeters")
        }
    }

    // MARK: - Dependencies

    private let permitService: PermitServiceProtocol
    private let zoneDataSource: ZoneDataSourceProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - App Info

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var dataVersion: String {
        zoneDataSource.getDataVersion()
    }

    var dataSourceAttribution: String {
        "Data from DataSF & SFMTA"
    }

    // MARK: - Initialization

    init(permitService: PermitServiceProtocol, zoneDataSource: ZoneDataSourceProtocol) {
        self.permitService = permitService
        self.zoneDataSource = zoneDataSource
        self.showFloatingMap = UserDefaults.standard.object(forKey: "showFloatingMap") as? Bool ?? true
        let positionRaw = UserDefaults.standard.string(forKey: "mapPosition") ?? MapPosition.topRight.rawValue
        self.mapPosition = MapPosition(rawValue: positionRaw) ?? .topRight
        // Show parking meters (individual pins) is OFF by default
        self.showParkingMeters = UserDefaults.standard.object(forKey: "showParkingMeters") as? Bool ?? false

        setupBindings()
    }

    convenience init() {
        self.init(
            permitService: DependencyContainer.shared.permitService,
            zoneDataSource: DependencyContainer.shared.zoneDataSource
        )
    }

    // MARK: - Private Methods

    private func setupBindings() {
        permitService.permitsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] permits in
                self?.permits = permits
            }
            .store(in: &cancellables)
    }

    // MARK: - Permit Management

    func addPermit(area: String) {
        let permit = ParkingPermit(
            type: .residential,
            area: area,
            cityCode: "sf"
        )
        permitService.addPermit(permit)
    }

    func removePermit(_ permit: ParkingPermit) {
        permitService.removePermit(permit)
    }

    func setPrimaryPermit(_ permit: ParkingPermit) {
        permitService.setPrimaryPermit(permit)
    }

    // MARK: - Actions

    func openPrivacyPolicy() {
        if let url = URL(string: "https://sfparkingzone.app/privacy") {
            UIApplication.shared.open(url)
        }
    }

    func openSupport() {
        if let url = URL(string: "mailto:support@sfparkingzone.app") {
            UIApplication.shared.open(url)
        }
    }

    func rateApp() {
        // App Store URL would go here
        if let url = URL(string: "https://apps.apple.com/app/id0000000000") {
            UIApplication.shared.open(url)
        }
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }
}
