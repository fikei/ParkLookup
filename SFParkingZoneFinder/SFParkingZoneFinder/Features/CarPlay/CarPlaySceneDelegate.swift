import CarPlay
import CoreLocation
import Combine
import AVFoundation
import MapKit
import os.log

/// Handles CarPlay connection and UI
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?

    private let locationService: LocationServiceProtocol
    private let zoneService: ZoneServiceProtocol
    private let permitService: PermitServiceProtocol
    private let parkingSessionManager: ParkingSessionManagerProtocol

    private var cancellables = Set<AnyCancellable>()

    // Current parking state
    private var currentZoneName: String = "—"
    private var currentValidityStatus: PermitValidityStatus = .noPermitRequired
    private var currentParkUntil: Date?
    private var currentParkingResult: ParkingLookupResult?
    private var currentLocation: CLLocationCoordinate2D?
    private var userPermits: [ParkingPermit] = []

    // Active parking session
    private var activeSession: ParkingSession?

    // Nearby zone tracking for proactive announcements
    private var nearbyValidZones: [(zone: ParkingZone, distance: Double)] = []
    private var nearestValidZone: (zone: ParkingZone, distance: Double)?
    private var lastAnnouncedProximity: Double = .infinity
    private var hasAnnouncedNearbyParking = false

    // Filter state
    private enum ParkingFilter {
        case all
        case freeOnly
        case allDay
        case myPermitsOnly
    }
    private var currentFilter: ParkingFilter = .all

    // Template state
    private var isShowingMap = false

    private var speechSynthesizer: AVSpeechSynthesizer?
    private var voiceFeedbackEnabled: Bool = true

    private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "CarPlay")

    // MARK: - Initialization

    override init() {
        let container = DependencyContainer.shared
        self.locationService = container.locationService
        self.zoneService = container.zoneService
        self.permitService = container.permitService
        self.parkingSessionManager = container.parkingSessionManager
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

        logger.info("CarPlay connected")

        // Load user permits
        userPermits = permitService.permits

        // Load active parking session
        activeSession = parkingSessionManager.getActiveSession()

        // Set up the root template
        let rootTemplate = createZoneInfoTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)

        // Start location updates
        startLocationUpdates()

        // Initialize speech synthesizer for voice feedback
        speechSynthesizer = AVSpeechSynthesizer()

        // Subscribe to permit changes
        setupBindings()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        logger.info("CarPlay disconnected")
        self.interfaceController = nil
        self.carWindow = nil
        cancellables.removeAll()
        speechSynthesizer = nil
    }

    // MARK: - Bindings

    private func setupBindings() {
        // Subscribe to permit changes
        permitService.permitsPublisher
            .sink { [weak self] permits in
                self?.userPermits = permits
                // Re-evaluate current location with new permits
                if let location = self?.currentLocation {
                    Task { @MainActor in
                        await self?.handleLocationUpdate(CLLocation(
                            latitude: location.latitude,
                            longitude: location.longitude
                        ))
                    }
                }
            }
            .store(in: &cancellables)

        // Subscribe to parking session changes
        parkingSessionManager.activeSessionPublisher
            .sink { [weak self] session in
                self?.activeSession = session
                self?.updateTemplate()
            }
            .store(in: &cancellables)
    }

    // MARK: - Template Creation

    private func createZoneInfoTemplate() -> CPInformationTemplate {
        let items = createInformationItems()

        let template = CPInformationTemplate(
            title: activeSession != nil ? "Parked" : "Parking Zone",
            layout: .leading,
            items: items,
            actions: createActions()
        )

        return template
    }

    private func createInformationItems() -> [CPInformationItem] {
        var items: [CPInformationItem] = []

        // If there's an active parking session, show session info
        if let session = activeSession {
            items.append(CPInformationItem(
                title: "Location",
                detail: session.location.address ?? session.zoneName
            ))

            if let parkUntil = session.parkUntil {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeRemaining = parkUntil.timeIntervalSince(Date())
                let hoursRemaining = Int(timeRemaining) / 3600
                let minutesRemaining = (Int(timeRemaining) % 3600) / 60

                items.append(CPInformationItem(
                    title: "Move By",
                    detail: formatter.string(from: parkUntil)
                ))

                if timeRemaining > 0 {
                    items.append(CPInformationItem(
                        title: "Time Remaining",
                        detail: hoursRemaining > 0 ? "\(hoursRemaining)h \(minutesRemaining)m" : "\(minutesRemaining)m"
                    ))
                } else {
                    items.append(CPInformationItem(
                        title: "Status",
                        detail: "⚠️ Time Expired"
                    ))
                }
            }

            return items
        }

        // Otherwise, show current zone info
        items.append(CPInformationItem(
            title: "Current Zone",
            detail: currentZoneName
        ))

        items.append(CPInformationItem(
            title: "Permit Status",
            detail: currentValidityStatus.displayText
        ))

        // Show distance to nearest valid parking
        if currentValidityStatus == .invalid || currentValidityStatus == .noPermitSet {
            if let nearest = nearestValidZone {
                let distanceText = formatDistance(nearest.distance)
                items.append(CPInformationItem(
                    title: "Nearest Valid Parking",
                    detail: "\(distanceText) - \(nearest.zone.displayName)"
                ))
            }
        }

        // Show park until time if available
        if let parkUntil = currentParkUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            items.append(CPInformationItem(
                title: "Park Until",
                detail: formatter.string(from: parkUntil)
            ))
        }

        // Show metered parking info if applicable
        if let result = currentParkingResult,
           result.primaryRegulationType == .metered {
            items.append(CPInformationItem(
                title: "Parking Type",
                detail: "Metered - Pay at meter"
            ))
        }

        return items
    }

    private func createActions() -> [CPTextButton] {
        var buttons: [CPTextButton] = []

        // If there's an active session, show end parking button
        if activeSession != nil {
            let endParkingButton = CPTextButton(
                title: "End Parking",
                textStyle: .cancel
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.endParking()
                }
            }
            buttons.append(endParkingButton)
        } else {
            // Find Parking button - primary action
            if currentValidityStatus == .invalid || currentValidityStatus == .noPermitSet {
                let findParkingButton = CPTextButton(
                    title: "Find Parking",
                    textStyle: .confirm
                ) { [weak self] _ in
                    self?.navigateToNearestValidParking()
                }
                buttons.append(findParkingButton)
            } else {
                // Park here button if in valid zone
                let parkHereButton = CPTextButton(
                    title: "Park Here",
                    textStyle: .confirm
                ) { [weak self] _ in
                    Task { @MainActor in
                        await self?.startParking()
                    }
                }
                buttons.append(parkHereButton)
            }

            // Show Map button
            let mapButton = CPTextButton(
                title: "Show Map",
                textStyle: .normal
            ) { [weak self] _ in
                self?.showMapView()
            }
            buttons.append(mapButton)

            // Filter button (cycles through filters)
            let filterTitle: String
            switch currentFilter {
            case .all:
                filterTitle = "Filter: All"
            case .freeOnly:
                filterTitle = "Filter: Free"
            case .allDay:
                filterTitle = "Filter: All Day"
            case .myPermitsOnly:
                filterTitle = "Filter: My Permits"
            }

            let filterButton = CPTextButton(
                title: filterTitle,
                textStyle: .normal
            ) { [weak self] _ in
                self?.cycleFilter()
            }
            buttons.append(filterButton)
        }

        let voiceButton = CPTextButton(
            title: voiceFeedbackEnabled ? "Voice: On" : "Voice: Off",
            textStyle: .normal
        ) { [weak self] _ in
            self?.toggleVoiceFeedback()
        }
        buttons.append(voiceButton)

        return buttons
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

    private func handleLocationUpdate(_ location: CLLocation) async {
        currentLocation = location.coordinate

        // Use blockface data if enabled, otherwise use zone data
        if DeveloperSettings.shared.useBlockfaceForFeatures {
            let adapterResult = await ParkingDataAdapter.shared.lookupParking(at: location.coordinate)

            if let result = adapterResult {
                await updateStateFromBlockface(result)
            } else {
                logger.warning("⚠️ Blockface lookup failed, falling back to zone data")
                await updateStateFromZone(location)
            }
        } else {
            // Use legacy zone-based data
            await updateStateFromZone(location)
        }
    }

    @MainActor
    private func updateStateFromBlockface(_ result: ParkingLookupResult) {
        let previousZone = currentZoneName
        currentParkingResult = result

        // Update zone name
        currentZoneName = result.locationName

        // Determine validity status based on permits
        let userPermitSet = Set(userPermits.map { $0.area.uppercased() })
        if let permitAreas = result.permitAreas {
            let permitAreaSet = Set(permitAreas.map { $0.uppercased() })
            let hasMatchingPermit = !permitAreaSet.isDisjoint(with: userPermitSet)

            if hasMatchingPermit {
                currentValidityStatus = permitAreaSet.count > 1 ? .multipleApply : .valid
            } else if result.primaryRegulationType == .metered {
                currentValidityStatus = .noPermitRequired
            } else {
                currentValidityStatus = .invalid
            }
        } else if result.primaryRegulationType == .metered || result.primaryRegulationType == .free {
            currentValidityStatus = .noPermitRequired
        } else {
            currentValidityStatus = .noPermitSet
        }

        // Calculate park until time
        if let parkUntilResult = ParkingDataAdapter.shared.calculateParkUntil(
            for: result,
            userPermits: userPermitSet,
            parkingStartTime: Date()
        ) {
            currentParkUntil = parkUntilResult.parkUntilTime
            logger.info("✅ Park until: \(parkUntilResult.parkUntilTime) - \(parkUntilResult.reason)")
        } else {
            currentParkUntil = nil
        }

        // Find nearby valid zones for proactive guidance
        if let location = currentLocation {
            findNearbyValidZones(at: location)
        }

        // Update template
        updateTemplate()

        // Voice feedback if zone changed
        if previousZone != currentZoneName && previousZone != "—" {
            announceZoneChange()
        }

        // Proactive announcement if approaching valid parking
        checkProximityAndAnnounce()
    }

    @MainActor
    private func updateStateFromZone(_ location: CLLocation) async {
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

        // Try to get park until time from zone rules
        if let zone = result.lookupResult.primaryZone,
           let rule = zone.rules.first(where: { $0.timeLimit != nil }),
           let timeLimit = rule.timeLimit {
            // Simple calculation: current time + time limit
            currentParkUntil = Date().addingTimeInterval(TimeInterval(timeLimit * 60))
        } else {
            currentParkUntil = nil
        }

        // Find nearby valid zones for proactive guidance
        findNearbyValidZones(at: location.coordinate)

        // Update the template
        updateTemplate()

        // Voice feedback if zone changed
        if previousZone != currentZoneName && previousZone != "—" {
            announceZoneChange()
        }

        // Proactive announcement if approaching valid parking
        checkProximityAndAnnounce()
    }

    private func refreshLocation() {
        Task { @MainActor in
            do {
                let location = try await locationService.requestSingleLocation()
                await handleLocationUpdate(location)
            } catch {
                updateTemplateWithError("Location unavailable")
            }
        }
    }

    // MARK: - Parking Session Management

    @MainActor
    private func startParking() async {
        guard let location = currentLocation else {
            logger.warning("Cannot start parking: no current location")
            return
        }

        logger.info("Starting parking session from CarPlay")

        // Create session rules from current state
        var rules: [SessionRule] = []

        if let parkUntil = currentParkUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short

            rules.append(SessionRule(
                type: .timeLimit,
                description: "Park until \(formatter.string(from: parkUntil))",
                deadline: parkUntil
            ))
        }

        // Add enforcement info if available
        if let result = currentParkingResult {
            for regulation in result.allRegulations {
                let ruleType: SessionRuleType
                switch regulation.type {
                case .streetCleaning:
                    ruleType = .streetCleaning
                case .timeLimited:
                    ruleType = .timeLimit
                case .metered:
                    ruleType = .meter
                case .noParking:
                    ruleType = .noParking
                default:
                    ruleType = .enforcement
                }

                rules.append(SessionRule(
                    type: ruleType,
                    description: regulation.description,
                    deadline: nil
                ))
            }
        }

        // Start the session
        await parkingSessionManager.startSession(
            location: location,
            address: nil,
            zoneName: currentZoneName,
            zoneType: currentParkingResult?.primaryRegulationType == .metered ? .metered : .residentialPermit,
            rules: rules
        )

        logger.info("Parking session started from CarPlay")

        // Voice feedback
        speak("Parking session started at \(currentZoneName)")
    }

    @MainActor
    private func endParking() async {
        logger.info("Ending parking session from CarPlay")
        await parkingSessionManager.endSession()

        // Voice feedback
        speak("Parking session ended")
    }

    // MARK: - Template Updates

    @MainActor
    private func updateTemplate() {
        guard let interfaceController = interfaceController else { return }

        let items = createInformationItems()

        let template = CPInformationTemplate(
            title: activeSession != nil ? "Parked" : "Parking Zone",
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

        var announcement = "Entering \(currentZoneName). \(statusText)"

        // Add park until information if available
        if let parkUntil = currentParkUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            announcement += " Park until \(formatter.string(from: parkUntil))."
        }

        // Add metered parking warning
        if let result = currentParkingResult,
           result.primaryRegulationType == .metered {
            announcement += " This is metered parking. Pay at meter."
        }

        speak(announcement)
    }

    private func speak(_ text: String) {
        guard let synthesizer = speechSynthesizer else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.speak(utterance)
    }

    // MARK: - Nearby Zone Discovery & Proactive Announcements

    private func findNearbyValidZones(at coordinate: CLLocationCoordinate2D) {
        let allZones = zoneService.allLoadedZones
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let userPermitSet = Set(userPermits.map { $0.area.uppercased() })

        // Find zones within 500m and check if valid for user
        var validZones: [(zone: ParkingZone, distance: Double)] = []

        for zone in allZones {
            // Calculate distance to zone (use first boundary point as approximation)
            guard let firstBoundary = zone.boundaries.first,
                  let firstPoint = firstBoundary.coordinates.first else {
                continue
            }

            let zoneLocation = CLLocation(
                latitude: firstPoint.latitude,
                longitude: firstPoint.longitude
            )
            let distance = userLocation.distance(from: zoneLocation)

            // Only consider zones within 500m
            guard distance <= 500 else { continue }

            // Check if zone is valid for user based on filter
            let isValidForUser: Bool
            switch currentFilter {
            case .all:
                isValidForUser = isZoneValidForUser(zone, userPermits: userPermitSet)
            case .freeOnly:
                isValidForUser = zone.zoneType != .metered && isZoneValidForUser(zone, userPermits: userPermitSet)
            case .allDay:
                // All day = no time limits
                let hasTimeLimit = zone.rules.contains { $0.timeLimit != nil && $0.timeLimit! < 240 }
                isValidForUser = !hasTimeLimit && isZoneValidForUser(zone, userPermits: userPermitSet)
            case .myPermitsOnly:
                isValidForUser = isZoneValidForUser(zone, userPermits: userPermitSet)
            }

            if isValidForUser {
                validZones.append((zone: zone, distance: distance))
            }
        }

        // Sort by distance
        validZones.sort { $0.distance < $1.distance }

        nearbyValidZones = validZones
        nearestValidZone = validZones.first

        logger.info("Found \(validZones.count) valid zones nearby")
        if let nearest = nearestValidZone {
            logger.info("Nearest valid: \(nearest.zone.displayName) at \(Int(nearest.distance))m")
        }
    }

    private func isZoneValidForUser(_ zone: ParkingZone, userPermits: Set<String>) -> Bool {
        if zone.zoneType == .metered {
            return true  // Can always park at metered (just need to pay)
        }

        // For RPP zones, check if user has matching permit
        if zone.zoneType == .residentialPermit {
            let zonePermitAreas = Set(zone.validPermitAreas.map { $0.uppercased() })
            return !zonePermitAreas.isDisjoint(with: userPermits)
        }

        return true
    }

    private func checkProximityAndAnnounce() {
        guard voiceFeedbackEnabled else { return }
        guard currentValidityStatus == .invalid || currentValidityStatus == .noPermitSet else {
            // Reset announcement state when in valid zone
            hasAnnouncedNearbyParking = false
            lastAnnouncedProximity = .infinity
            return
        }

        guard let nearest = nearestValidZone else { return }

        // Announce at different proximity thresholds
        let distance = nearest.distance

        if distance <= 100 && lastAnnouncedProximity > 100 {
            // Very close - 100m
            speak("Valid parking zone ahead in 100 meters")
            lastAnnouncedProximity = 100
        } else if distance <= 200 && lastAnnouncedProximity > 200 {
            // Close - 200m
            speak("Valid parking zone ahead in 200 meters - \(nearest.zone.displayName)")
            lastAnnouncedProximity = 200
        } else if distance <= 400 && !hasAnnouncedNearbyParking {
            // Nearby - 400m
            let distanceText = formatDistance(distance)
            speak("Valid parking found \(distanceText) ahead")
            hasAnnouncedNearbyParking = true
        }
    }

    // MARK: - Navigation & Actions

    private func navigateToNearestValidParking() {
        guard let nearest = nearestValidZone else {
            speak("No valid parking zones found nearby")
            return
        }

        logger.info("Navigating to \(nearest.zone.displayName)")

        // Get zone center coordinate
        guard let firstBoundary = nearest.zone.boundaries.first,
              let centerPoint = firstBoundary.coordinates.first else {
            speak("Unable to navigate to parking zone")
            return
        }

        // Create map item for destination
        let placemark = MKPlacemark(coordinate: centerPoint)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = nearest.zone.displayName

        // Open in Maps with driving directions
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])

        let distanceText = formatDistance(nearest.distance)
        speak("Navigating to \(nearest.zone.displayName), \(distanceText) away")
    }

    private func showMapView() {
        guard let interfaceController = interfaceController else { return }
        guard let currentLocation = currentLocation else {
            speak("Location unavailable")
            return
        }

        logger.info("Showing map view")

        // Create map template
        let mapTemplate = CPMapTemplate()
        mapTemplate.showPanningInterface(animated: false)

        // Create map region centered on current location
        let region = MKCoordinateRegion(
            center: currentLocation,
            latitudinalMeters: 1000,  // 1km view
            longitudinalMeters: 1000
        )

        // Add zone markers for nearby valid zones
        var mapItems: [MKMapItem] = []
        for (zone, _) in nearbyValidZones.prefix(10) {  // Show up to 10 nearest zones
            guard let firstBoundary = zone.boundaries.first,
                  let centerPoint = firstBoundary.coordinates.first else {
                continue
            }

            let placemark = MKPlacemark(coordinate: centerPoint)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = zone.displayName
            mapItems.append(mapItem)
        }

        // Back button
        let backButton = CPBarButton(title: "Back") { [weak self] _ in
            self?.dismissMapView()
        }
        mapTemplate.leadingNavigationBarButtons = [backButton]

        // Show map
        interfaceController.pushTemplate(mapTemplate, animated: true, completion: nil)
        isShowingMap = true

        speak("Showing nearby parking zones")
    }

    private func dismissMapView() {
        guard let interfaceController = interfaceController else { return }
        interfaceController.popTemplate(animated: true, completion: nil)
        isShowingMap = false
    }

    private func cycleFilter() {
        switch currentFilter {
        case .all:
            currentFilter = .freeOnly
        case .freeOnly:
            currentFilter = .allDay
        case .allDay:
            currentFilter = .myPermitsOnly
        case .myPermitsOnly:
            currentFilter = .all
        }

        logger.info("Filter changed to: \(currentFilter)")

        // Re-find nearby zones with new filter
        if let location = currentLocation {
            findNearbyValidZones(at: location)
        }

        // Update UI
        updateTemplate()

        // Announce filter change
        let filterName: String
        switch currentFilter {
        case .all:
            filterName = "all parking"
        case .freeOnly:
            filterName = "free parking only"
        case .allDay:
            filterName = "all day parking"
        case .myPermitsOnly:
            filterName = "my permits only"
        }
        speak("Filter set to \(filterName)")
    }

    // MARK: - Utilities

    private func formatDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            return "\(Int(meters / 10) * 10)m"  // Round to nearest 10m
        } else {
            let km = meters / 1000.0
            return String(format: "%.1fkm", km)
        }
    }
}
