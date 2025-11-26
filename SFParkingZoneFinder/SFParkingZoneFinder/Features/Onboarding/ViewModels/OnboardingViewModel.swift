import Foundation
import CoreLocation
import Combine
import UserNotifications

/// Manages onboarding flow state and user selections
@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentStep: OnboardingStep = .welcome
    @Published var selectedPermitAreas: Set<String> = []
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isRequestingLocation = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isRequestingNotification = false

    // MARK: - Dependencies

    private let locationService: LocationServiceProtocol
    private let permitService: PermitServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        locationService: LocationServiceProtocol,
        permitService: PermitServiceProtocol
    ) {
        self.locationService = locationService
        self.permitService = permitService

        setupBindings()
    }

    /// Convenience initializer using shared dependency container
    convenience init() {
        let container = DependencyContainer.shared
        self.init(
            locationService: container.locationService,
            permitService: container.permitService
        )
    }

    // MARK: - Public Methods

    func nextStep() {
        switch currentStep {
        case .welcome:
            currentStep = .locationPermission
        case .locationPermission:
            currentStep = .notificationPermission
        case .notificationPermission:
            currentStep = .permitSetup
        case .permitSetup:
            savePermitsAndComplete()
        }
    }

    func skipPermitSetup() {
        completeOnboarding()
    }

    func requestLocationPermission() {
        isRequestingLocation = true
        locationService.requestWhenInUseAuthorization()
    }

    func requestNotificationPermission() {
        isRequestingNotification = true
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await updateNotificationStatus()
                isRequestingNotification = false
            } catch {
                isRequestingNotification = false
            }
        }
    }

    func checkNotificationStatus() {
        Task {
            await updateNotificationStatus()
        }
    }

    private func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.notificationStatus = settings.authorizationStatus
        }
    }

    func togglePermitArea(_ area: String) {
        if selectedPermitAreas.contains(area) {
            selectedPermitAreas.remove(area)
        } else {
            selectedPermitAreas.insert(area)
        }
    }

    func selectAllAreas(_ areas: [String]) {
        selectedPermitAreas = Set(areas)
    }

    func clearAllAreas() {
        selectedPermitAreas.removeAll()
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Listen for authorization changes
        locationService.authorizationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                self.locationStatus = status
                self.isRequestingLocation = false

                // Auto-advance to next screen when location permission is granted
                if (status == .authorizedWhenInUse || status == .authorizedAlways) &&
                   self.currentStep == .locationPermission {
                    // Add small delay for better UX - let user see success state briefly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.nextStep()
                    }
                }
            }
            .store(in: &cancellables)

        // Get initial status
        locationStatus = locationService.authorizationStatus

        // Check initial notification status
        checkNotificationStatus()
    }

    private func savePermitsAndComplete() {
        // Create permits for selected areas
        for area in selectedPermitAreas {
            let permit = ParkingPermit(type: .residential, area: area)
            permitService.addPermit(permit)
        }

        // Set first permit as primary if any selected
        if let firstArea = selectedPermitAreas.sorted().first {
            let primaryPermit = ParkingPermit(type: .residential, area: firstArea)
            permitService.setPrimaryPermit(primaryPermit)
        }

        completeOnboarding()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

// MARK: - Onboarding Steps

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case locationPermission = 1
    case notificationPermission = 2
    case permitSetup = 3

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .locationPermission: return "Location"
        case .notificationPermission: return "Notifications"
        case .permitSetup: return "Permits"
        }
    }
}

// MARK: - SF Permit Areas

struct SFPermitAreas {
    static let all: [String] = [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
        "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y", "Z"
    ]

    static let popular: [String] = ["Q", "R", "L", "N", "K", "A", "B", "C"]
}
