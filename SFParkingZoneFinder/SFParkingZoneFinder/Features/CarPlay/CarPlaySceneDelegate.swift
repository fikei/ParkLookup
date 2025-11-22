import CarPlay
import CoreLocation
import Combine
import AVFoundation

/// Handles CarPlay connection and UI
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?

    private let locationService: LocationServiceProtocol
    private let zoneService: ZoneServiceProtocol
    private let permitService: PermitServiceProtocol

    private var cancellables = Set<AnyCancellable>()
    private var currentZoneName: String = "—"
    private var currentValidityStatus: PermitValidityStatus = .noPermitRequired
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var voiceFeedbackEnabled: Bool = true

    // MARK: - Initialization

    override init() {
        let container = DependencyContainer.shared
        self.locationService = container.locationService
        self.zoneService = container.zoneService
        self.permitService = container.permitService
        super.init()
    }

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        self.carWindow = window

        // Set up the root template
        let rootTemplate = createZoneInfoTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)

        // Start location updates
        startLocationUpdates()

        // Initialize speech synthesizer for voice feedback
        speechSynthesizer = AVSpeechSynthesizer()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
        self.carWindow = nil
        cancellables.removeAll()
        speechSynthesizer = nil
    }

    // MARK: - Template Creation

    private func createZoneInfoTemplate() -> CPInformationTemplate {
        let items = createInformationItems()

        let template = CPInformationTemplate(
            title: "Parking Zone",
            layout: .leading,
            items: items,
            actions: createActions()
        )

        return template
    }

    private func createInformationItems() -> [CPInformationItem] {
        let zoneItem = CPInformationItem(
            title: "Current Zone",
            detail: currentZoneName
        )

        let statusItem = CPInformationItem(
            title: "Permit Status",
            detail: currentValidityStatus.displayText
        )

        let confidenceItem = CPInformationItem(
            title: "Location",
            detail: "Updating..."
        )

        return [zoneItem, statusItem, confidenceItem]
    }

    private func createActions() -> [CPTextButton] {
        let refreshButton = CPTextButton(
            title: "Refresh",
            textStyle: .normal
        ) { [weak self] _ in
            self?.refreshLocation()
        }

        let voiceButton = CPTextButton(
            title: voiceFeedbackEnabled ? "Voice: On" : "Voice: Off",
            textStyle: .normal
        ) { [weak self] _ in
            self?.toggleVoiceFeedback()
        }

        return [refreshButton, voiceButton]
    }

    // MARK: - Location Updates

    private func startLocationUpdates() {
        // Check authorization
        guard locationService.authorizationStatus == .authorizedWhenInUse ||
              locationService.authorizationStatus == .authorizedAlways else {
            updateTemplateWithError("Location access required")
            return
        }

        // Start continuous location updates
        locationService.startUpdatingLocation()

        // Subscribe to location updates
        locationService.locationPublisher
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        Task { @MainActor in
            let result = await zoneService.getParkingResult(
                at: location.coordinate,
                time: Date()
            )

            let previousZone = currentZoneName

            // Update state
            if let zone = result.lookupResult.primaryZone {
                currentZoneName = zone.displayName
            } else if result.lookupResult.isOutsideCoverage {
                currentZoneName = "Outside SF"
            } else if result.lookupResult.isUnknownArea {
                currentZoneName = "Unknown Area"
            } else {
                currentZoneName = "—"
            }

            if let interpretation = result.primaryInterpretation {
                currentValidityStatus = interpretation.validityStatus
            } else {
                currentValidityStatus = .noPermitRequired
            }

            // Update the template
            updateTemplate(with: result)

            // Voice feedback if zone changed
            if previousZone != currentZoneName && previousZone != "—" {
                announceZoneChange()
            }
        }
    }

    private func refreshLocation() {
        Task { @MainActor in
            do {
                let location = try await locationService.requestSingleLocation()
                handleLocationUpdate(location)
            } catch {
                updateTemplateWithError("Location unavailable")
            }
        }
    }

    // MARK: - Template Updates

    private func updateTemplate(with result: ParkingResult) {
        guard let interfaceController = interfaceController else { return }

        let items = [
            CPInformationItem(title: "Current Zone", detail: currentZoneName),
            CPInformationItem(title: "Permit Status", detail: currentValidityStatus.displayText),
            CPInformationItem(title: "Confidence", detail: result.lookupResult.confidenceDescription)
        ]

        let template = CPInformationTemplate(
            title: "Parking Zone",
            layout: .leading,
            items: items,
            actions: createActions()
        )

        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }

    private func updateTemplateWithError(_ message: String) {
        guard let interfaceController = interfaceController else { return }

        let items = [
            CPInformationItem(title: "Status", detail: message)
        ]

        let template = CPInformationTemplate(
            title: "Parking Zone",
            layout: .leading,
            items: items,
            actions: createActions()
        )

        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Voice Feedback

    private func toggleVoiceFeedback() {
        voiceFeedbackEnabled.toggle()

        // Update the template to reflect the change
        if let interfaceController = interfaceController,
           let currentTemplate = interfaceController.rootTemplate as? CPInformationTemplate {
            let updatedTemplate = CPInformationTemplate(
                title: currentTemplate.title,
                layout: .leading,
                items: currentTemplate.items,
                actions: createActions()
            )
            interfaceController.setRootTemplate(updatedTemplate, animated: false, completion: nil)
        }

        // Announce the change
        if voiceFeedbackEnabled {
            speak("Voice feedback enabled")
        }
    }

    private func announceZoneChange() {
        guard voiceFeedbackEnabled else { return }

        let statusText: String
        switch currentValidityStatus {
        case .valid:
            statusText = "Your permit is valid here."
        case .invalid:
            statusText = "Warning: Your permit is not valid here."
        case .noPermitRequired:
            statusText = "No permit required."
        case .conditional:
            statusText = "Conditional restrictions apply."
        case .multipleApply:
            statusText = "Multiple permits apply."
        case .noPermitSet:
            statusText = "Permit required in this area."
        }

        let announcement = "Entering \(currentZoneName). \(statusText)"
        speak(announcement)
    }

    private func speak(_ text: String) {
        guard let synthesizer = speechSynthesizer else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.speak(utterance)
    }
}
