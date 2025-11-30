import SwiftUI
import UIKit
import MapKit

// MARK: - Haptic Feedback Helper

enum HapticFeedback {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

/// Primary view showing fullscreen map with zone card overlay
struct MainResultView: View {
    @StateObject private var viewModel = MainResultViewModel()
    @ObservedObject private var devSettings = DeveloperSettings.shared
    @State private var showingSettings = false
    @State private var contentAppeared = false
    @State private var isMapExpanded = true  // Default to expanded map view
    @State private var selectedZone: ParkingZone?
    @State private var tappedPermitAreas: [String]?  // Specific permit areas for the tapped boundary
    @State private var searchedCoordinate: CLLocationCoordinate2D?
    @State private var tappedCoordinate: CLLocationCoordinate2D?  // Coordinate where user tapped (for blue dot indicator)
    @State private var recenterTrigger = false  // Toggle to force map recenter
    @State private var showOutsideCoverageBanner = false
    @State private var developerPanelExpanded = false
    @State private var isLoadingOverlays = false
    @State private var overlayLoadingMessage = ""
    @State private var showingActiveParkingView = false

    @Namespace private var cardAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Computed property to check if user is outside SF coverage
    private var isOutsideCoverage: Bool {
        viewModel.error == .outsideCoverage
    }

    /// The coordinate to use for map centering (searched or current)
    /// Validates coordinates to prevent NaN errors in CoreGraphics
    private var activeCoordinate: CLLocationCoordinate2D? {
        let coord = searchedCoordinate ?? viewModel.currentCoordinate
        // Validate coordinate to prevent NaN errors
        guard let c = coord,
              c.latitude.isFinite && c.longitude.isFinite,
              c.latitude >= -90 && c.latitude <= 90,
              c.longitude >= -180 && c.longitude <= 180 else {
            return nil
        }
        return c
    }

    /// Extract permit area code from zone name
    private var currentPermitArea: String? {
        guard viewModel.zoneName.hasPrefix("Area ") else {
            return viewModel.zoneName
        }
        return String(viewModel.zoneName.dropFirst(5))
    }

    /// User's valid permit area codes (uppercase) for map coloring
    /// Uses ALL user permits (not just applicable ones) so all matching zones are colored green
    private var userPermitAreaCodes: Set<String> {
        Set(viewModel.userPermits.map { $0.area.uppercased() })
    }

    /// Create LocationCardData from a tapped ParkingZone
    private func createLocationCardData(for zone: ParkingZone) -> LocationCardData {
        // Determine permit areas for this zone
        let permitAreas = tappedPermitAreas ?? (zone.permitArea.map { [$0] } ?? [])

        // Check if user has valid permit
        let userPermitAreas = Set(viewModel.userPermits.map { $0.area.uppercased() })
        let hasValidPermit = permitAreas.contains { userPermitAreas.contains($0.uppercased()) }

        // Determine validity status
        let validityStatus: PermitValidityStatus
        if zone.zoneType == .metered {
            validityStatus = .noPermitRequired
        } else if hasValidPermit {
            validityStatus = .valid
        } else {
            validityStatus = .invalid
        }

        // Get applicable permits
        let applicablePermits = viewModel.userPermits.filter { permit in
            permitAreas.contains(where: { $0.uppercased() == permit.area.uppercased() })
        }

        // Extract detailed regulations from zone rules
        let detailedRegulations = extractRegulations(from: zone.rules, permitAreas: permitAreas)

        return LocationCardData(
            locationName: zone.displayName,
            locationCode: zone.permitArea,
            locationType: zone.zoneType,
            validityStatus: validityStatus,
            applicablePermits: applicablePermits,
            allValidPermitAreas: permitAreas,
            timeLimitMinutes: zone.nonPermitTimeLimit,
            detailedRegulations: detailedRegulations,
            ruleSummaryLines: zone.primaryRuleDescription.map { [$0] } ?? [],
            enforcementStartTime: zone.rules.first?.enforcementStartTime,
            enforcementEndTime: zone.rules.first?.enforcementEndTime,
            enforcementDays: zone.rules.first?.enforcementDays,
            meteredSubtitle: zone.zoneType == .metered ? zone.enforcementHours : nil,
            isCurrentLocation: false
        )
    }

    /// Convert ParkingRule array to RegulationInfo array for unified card display
    private func extractRegulations(from rules: [ParkingRule], permitAreas: [String]) -> [RegulationInfo] {
        rules.map { rule in
            // Map RuleType to RegulationType
            let type: ParkingLookupResult.RegulationType
            switch rule.ruleType {
            case .permitRequired:
                type = .residentialPermit
            case .timeLimit:
                type = .timeLimited
            case .metered:
                type = .metered
            case .streetCleaning:
                type = .streetCleaning
            case .noParking, .towAway:
                type = .noParking
            case .loadingZone:
                type = .timeLimited  // Loading zones are time-limited
            }

            // Format time strings
            let enforcementStart = rule.enforcementStartTime.map { String(format: "%02d:%02d", $0.hour, $0.minute) }
            let enforcementEnd = rule.enforcementEndTime.map { String(format: "%02d:%02d", $0.hour, $0.minute) }

            // Use first permit area as the permit zone (for RPP rules)
            let permitZone: String? = (type == .residentialPermit) ? permitAreas.first : nil

            return RegulationInfo(
                type: type,
                description: rule.description,
                enforcementDays: rule.enforcementDays,
                enforcementStart: enforcementStart,
                enforcementEnd: enforcementEnd,
                permitZone: permitZone,
                timeLimit: rule.timeLimit
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let _ = print("🔧 DEBUG: MainResultView body - devMode: \(devSettings.developerModeUnlocked), expanded: \(isMapExpanded), panel: \(developerPanelExpanded)")
            ZStack {
            // Layer 1: Fullscreen Map (always visible as background)
            if viewModel.error == nil && !viewModel.isLoading {
                ZStack {
                    ZoneMapView(
                        zones: viewModel.allLoadedZones,
                        currentZoneId: viewModel.currentZoneId,
                        userCoordinate: activeCoordinate,
                        onZoneTapped: { zone, permitAreas, coordinate in
                            // Allow tapping in both collapsed and expanded mode
                            selectedZone = zone
                            tappedPermitAreas = permitAreas
                            tappedCoordinate = coordinate

                            // Haptic feedback
                            HapticFeedback.light()

                            // Expand map to show the tapped card
                            if !isMapExpanded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isMapExpanded = true
                                }
                            }
                        },
                        onMapTapped: { coordinate in
                            // Generic tap handler (works for zones, blockfaces, or empty map areas)
                            tappedCoordinate = coordinate

                            // Trigger lookup at tapped coordinate (updates spot card)
                            viewModel.lookupZone(at: coordinate)

                            // Expand map if collapsed
                            if !isMapExpanded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isMapExpanded = true
                                }
                            }
                        },
                        userPermitAreas: userPermitAreaCodes,
                        devSettingsHash: devSettings.settingsHash,
                        reloadTrigger: devSettings.reloadTrigger,
                        // When collapsed, shift user location below the card
                        // A bias of 0.5 places the user indicator well below the large card
                        verticalBias: isMapExpanded ? 0.0 : 0.5,
                        // Show overlays when expanded OR developer panel is open
                        // Individual overlay types (zones/blockfaces) controlled by their own toggles
                        showOverlays: isMapExpanded || developerPanelExpanded,
                        // Original zoom: 1.0 = ~670m (8-10 blocks)
                        zoomMultiplier: 1.0,
                        // Show pin for searched address
                        searchedCoordinate: searchedCoordinate,
                        // Show blue dot for tapped location
                        tappedCoordinate: tappedCoordinate,
                        // Force recenter trigger
                        recenterTrigger: recenterTrigger,
                        // Show SF overview when outside coverage
                        showSFOverview: showOutsideCoverageBanner || isOutsideCoverage
                    )
                    // Use zone count in ID to allow updates when zones load, but prevent recreation on UI-only changes
                    .id("zoneMapView-\(viewModel.allLoadedZones.count)")

                    // Developer overlay (when developer mode is unlocked and panel is open)
                    // Works on both minimized and expanded map views
                    if devSettings.developerModeUnlocked && developerPanelExpanded {
                        DeveloperMapOverlay(
                            devSettings: devSettings,
                            isPanelExpanded: $developerPanelExpanded,
                            showToggleButton: false
                        )
                    }

                    // Loading overlays
                    if devSettings.developerModeUnlocked {
                        // Detailed developer loading overlay
                        DeveloperLoadingOverlay(
                            isLoadingZones: viewModel.isLoading,
                            isLoadingOverlays: isLoadingOverlays,
                            statusMessage: overlayLoadingMessage
                        )
                    } else {
                        // Simple loading overlay for regular users


                        MapLoadingOverlay(isLoading: viewModel.isLoading || isLoadingOverlays)
                    }
                }
                .ignoresSafeArea()
                .onChange(of: viewModel.allLoadedZones.count) { _, newCount in
                    // Simulate overlay loading state
                    if newCount > 0 && !isLoadingOverlays {
                        isLoadingOverlays = true
                        overlayLoadingMessage = "Rendering \(newCount) zone overlays..."

                        // Clear loading state after a delay (overlays load asynchronously)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isLoadingOverlays = false
                            overlayLoadingMessage = ""
                        }
                    }
                }
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            // Layer 2: Card overlays
            if !viewModel.isLoading && viewModel.error == nil {
                VStack {
                    // Address search card (always visible for location button)
                    AddressSearchCard(
                        currentAddress: viewModel.currentAddress,
                        isAtCurrentLocation: searchedCoordinate == nil && tappedCoordinate == nil,
                        onAddressSelected: { coordinate in
                            searchedCoordinate = coordinate
                            // Trigger zone lookup for the new coordinate
                            viewModel.lookupZone(at: coordinate)
                        },
                        onResetToCurrentLocation: {
                            searchedCoordinate = nil
                            tappedCoordinate = nil
                            selectedZone = nil  // Close tapped spot card
                            showOutsideCoverageBanner = false  // Hide banner when returning to GPS
                            viewModel.returnToGPSLocation()
                            recenterTrigger.toggle()  // Force map recenter
                        },
                        onOutsideCoverage: {
                            showOutsideCoverageBanner = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    // Out of coverage banner
                    if showOutsideCoverageBanner || isOutsideCoverage {
                        OutOfCoverageBanner(
                            onDismiss: {
                                showOutsideCoverageBanner = false
                                // Return to current GPS location
                                searchedCoordinate = nil
                                tappedCoordinate = nil
                                selectedZone = nil
                                viewModel.returnToGPSLocation()
                                recenterTrigger.toggle()
                            }
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Unified parking location card
                    if selectedZone == nil {
                        // Current location card (primary or compact mode)
                        ParkingLocationCard(
                            data: LocationCardData(
                                locationName: viewModel.zoneName,
                                locationCode: currentPermitArea,
                                locationType: viewModel.zoneType,
                                validityStatus: viewModel.validityStatus,
                                applicablePermits: viewModel.applicablePermits,
                                allValidPermitAreas: viewModel.allValidPermitAreas,
                                timeLimitMinutes: viewModel.timeLimitMinutes,
                                detailedRegulations: viewModel.detailedRegulations,
                                ruleSummaryLines: viewModel.ruleSummaryLines,
                                enforcementStartTime: viewModel.enforcementStartTime,
                                enforcementEndTime: viewModel.enforcementEndTime,
                                enforcementDays: viewModel.enforcementDays,
                                meteredSubtitle: viewModel.meteredSubtitle,
                                isCurrentLocation: true
                            ),
                            displayMode: isMapExpanded ? .compact : .primary,
                            screenHeight: geometry.size.height,
                            namespace: cardAnimation
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .opacity(contentAppeared ? 1 : 0)
                        .offset(y: contentAppeared ? 0 : 20)
                    }

                    Spacer()

                    // Bottom section - Tapped location card (only in expanded mode)
                    if isMapExpanded, let selected = selectedZone {
                        VStack(alignment: .leading, spacing: 8) {
                            ParkingLocationCard(
                                data: createLocationCardData(for: selected),
                                displayMode: .spotDetail,
                                screenHeight: geometry.size.height
                            )

                            // Close button
                            Button {
                                selectedZone = nil
                                tappedPermitAreas = nil
                                tappedCoordinate = nil
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Close")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            // Layer 3: Bottom Navigation Bar (always visible when not loading/error)
            if !viewModel.isLoading && viewModel.error == nil {
                VStack {
                    Spacer()
                    BottomNavigationBar(
                        isDeveloperModeActive: devSettings.developerModeUnlocked,
                        hasActiveSession: viewModel.getActiveSession() != nil,
                        onDeveloperTap: {
                            print("🔧 DEBUG: Developer button tapped! Panel will expand")
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                developerPanelExpanded.toggle()
                            }
                        },
                        onParkTap: {
                            Task {
                                await viewModel.startParkingSession()
                                showingActiveParkingView = true
                            }
                        },
                        onSettingsTap: {
                            showingSettings = true
                        },
                        onExpandTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isMapExpanded.toggle()
                                if !isMapExpanded {
                                    selectedZone = nil
                                    tappedPermitAreas = nil
                                    developerPanelExpanded = false
                                    // Reset to current location when minimizing
                                    if searchedCoordinate != nil {
                                        searchedCoordinate = nil
                                        viewModel.returnToGPSLocation()
                                    }
                                }
                            }
                        },
                        isExpanded: isMapExpanded
                    )
                }
            }

            // Loading overlay
            if viewModel.isLoading {
                LoadingOverlay()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.05)))
            }

            // Error state (but not for outside coverage - that's shown as a banner)
            if let error = viewModel.error, error != .outsideCoverage {
                ErrorView(
                    error: error,
                    onRetry: {
                        HapticFeedback.medium()
                        viewModel.refreshLocation()
                    },
                    onDismiss: {
                        // Clear searched coordinate and use last known location
                        // This avoids requiring a fresh GPS fix which may timeout
                        HapticFeedback.light()
                        searchedCoordinate = nil
                        viewModel.clearErrorAndUseLastLocation()
                    }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                .onAppear {
                    HapticFeedback.error()
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isMapExpanded)
        .animation(.easeInOut(duration: 0.2), value: selectedZone?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.error != nil)
        .onAppear {
            viewModel.onAppear()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.1)) {
                contentAppeared = true
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.zoneName) { _, _ in
            if !viewModel.isLoading && viewModel.error == nil {
                HapticFeedback.success()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingActiveParkingView) {
            if let session = viewModel.getActiveSession() {
                ActiveParkingView(
                    session: session,
                    userLocation: viewModel.currentCoordinate,
                    onDismiss: {
                        showingActiveParkingView = false
                    },
                    onEndParking: {
                        await viewModel.endParkingSession()
                        showingActiveParkingView = false
                    }
                )
            }
        }
        }
    }
}

// MARK: - DEPRECATED COMPONENTS REMOVED
// AnimatedZoneCard has been replaced by ParkingLocationCard
// TappedSpotInfoCard has been replaced by ParkingLocationCard

// MARK: - Deprecated - Animated Zone Card (REMOVED - use ParkingLocationCard)

/*
private struct AnimatedZoneCard: View {
    let isExpanded: Bool
    var namespace: Namespace.ID
    let zoneName: String
    let zoneCode: String?
    let zoneType: ZoneType
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let allValidPermitAreas: [String]
    let meteredSubtitle: String?
    let timeLimitMinutes: Int?
    let ruleSummaryLines: [String]
    let detailedRegulations: [RegulationInfo]  // Detailed regulations for drawer

    // Enforcement hours for "Park Until" calculation
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let enforcementDays: [DayOfWeek]?

    let screenHeight: CGFloat

    @State private var animationIndex: Int = 0
    @State private var isFlipped: Bool = false
    @State private var showRegulationsDrawer = false

    private var isMultiPermitLocation: Bool {
        allValidPermitAreas.count > 1
    }

    private var orderedPermitAreas: [String] {
        guard isMultiPermitLocation else {
            return allValidPermitAreas.isEmpty ? [singleZoneCode] : allValidPermitAreas
        }
        var areas = allValidPermitAreas
        if let userPermitArea = applicablePermits.first?.area,
           let index = areas.firstIndex(of: userPermitArea) {
            areas.remove(at: index)
            areas.insert(userPermitArea, at: 0)
        }
        return areas
    }

    private var singleZoneCode: String {
        if zoneType == .metered { return "$" }
        if zoneName.hasPrefix("Area ") { return String(zoneName.dropFirst(5)) }
        if zoneName.hasPrefix("Zone ") { return String(zoneName.dropFirst(5)) }
        return zoneName
    }

    private var isValidStyle: Bool {
        validityStatus == .valid || validityStatus == .multipleApply
    }

    private var cardBackground: Color {
        if zoneType == .metered { return Color(.systemBackground) }
        return isValidStyle ? Color.accessibleValidGreen : Color(.systemBackground)
    }

    private var circleBackground: Color {
        ZoneColorProvider.swiftUIColor(for: zoneCode)
    }

    private var currentSelectedArea: String {
        guard isMultiPermitLocation, animationIndex < orderedPermitAreas.count else {
            return zoneCode ?? singleZoneCode
        }
        return orderedPermitAreas[animationIndex]
    }

    /// Whether we're currently outside enforcement hours (for banner display)
    private var isOutsideEnforcement: Bool {
        guard let startTime = enforcementStartTime, let endTime = enforcementEndTime else {
            return false
        }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.totalMinutes
        let endMinutes = endTime.totalMinutes

        // Check if today is an enforcement day
        if let days = enforcementDays, !days.isEmpty,
           let weekday = components.weekday,
           let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
            if !days.contains(dayOfWeek) {
                return true // Not an enforcement day
            }
        }

        // Check if outside enforcement hours
        return currentMinutes < startMinutes || currentMinutes >= endMinutes
    }

    /// "Park Until" text for when parking is unlimited due to being outside enforcement hours
    private var unlimitedUntilText: String? {
        guard isOutsideEnforcement,
              let startTime = enforcementStartTime else { return nil }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.totalMinutes

        // Check if today is an enforcement day
        var currentDayOfWeek: DayOfWeek?
        var isEnforcementDay = true
        if let days = enforcementDays, !days.isEmpty,
           let weekday = components.weekday,
           let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
            currentDayOfWeek = dayOfWeek
            isEnforcementDay = days.contains(dayOfWeek)
        }

        if isEnforcementDay && currentMinutes < startMinutes {
            // Before enforcement starts today - can park until enforcement begins
            return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: now)
        } else {
            // After enforcement ends today or not an enforcement day - find next enforcement start
            return findNextEnforcementStart(from: now, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
        }
    }

    private var parkUntilText: String? {
        guard (validityStatus == .invalid || validityStatus == .noPermitSet),
              let _ = timeLimitMinutes else { return nil }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        // Check if enforcement is currently active
        if let startTime = enforcementStartTime, let endTime = enforcementEndTime {
            let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let startMinutes = startTime.totalMinutes
            let endMinutes = endTime.totalMinutes

            // Check if today is an enforcement day
            var isEnforcementDay = true
            var currentDayOfWeek: DayOfWeek?
            if let days = enforcementDays, !days.isEmpty,
               let weekday = components.weekday,
               let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
                currentDayOfWeek = dayOfWeek
                isEnforcementDay = days.contains(dayOfWeek)
            }

            if isEnforcementDay {
                if currentMinutes < startMinutes {
                    // Before enforcement starts today - can park until enforcement begins
                    return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: now)
                } else if currentMinutes >= endMinutes {
                    // After enforcement ends today - find next enforcement start
                    return findNextEnforcementStart(from: now, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
                } else {
                    // During enforcement - check if time limit extends beyond enforcement end
                    return calculateTimeLimitEndWithEnforcementAwareness(
                        from: now,
                        endTime: endTime,
                        startTime: startTime,
                        days: enforcementDays,
                        currentDay: currentDayOfWeek
                    )
                }
            } else {
                // Not an enforcement day - find next enforcement start
                return findNextEnforcementStart(from: now, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
            }
        }

        // No enforcement hours defined - just use time limit
        return calculateTimeLimitEnd(from: now, endTime: nil)
    }

    /// Format "Park until" with day only when ambiguous
    private func formatParkUntil(hour: Int, minute: Int, on date: Date) -> String {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else {
            return "Park until \(hour):\(String(format: "%02d", minute))"
        }

        let formatter = DateFormatter()
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let targetIsAM = hour < 12

        // If target is today, never show day
        if calendar.isDateInToday(targetDate) {
            formatter.dateFormat = "h:mm a"
            return "Park until \(formatter.string(from: targetDate))"
        }

        // If target is tomorrow AND it's after noon AND target is AM, it's obvious - don't show day
        if calendar.isDateInTomorrow(targetDate) && currentHour >= 12 && targetIsAM {
            formatter.dateFormat = "h:mm a"
            return "Park until \(formatter.string(from: targetDate))"
        }

        // Otherwise show day for clarity
        formatter.dateFormat = "EEE h:mm a"
        return "Park until \(formatter.string(from: targetDate))"
    }

    /// Find the next enforcement start time
    private func findNextEnforcementStart(from now: Date, startTime: TimeOfDay, days: [DayOfWeek]?, currentDay: DayOfWeek?) -> String {
        let calendar = Calendar.current

        // If no specific days, enforcement is daily - next enforcement is tomorrow
        guard let enforcementDays = days, !enforcementDays.isEmpty, let current = currentDay else {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: tomorrow)
            }
            return "Park until tomorrow"
        }

        // Find the next enforcement day
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: current) else {
            return "Park until tomorrow"
        }

        // Look for the next enforcement day (starting from tomorrow)
        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if enforcementDays.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: now) {
                    return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: targetDate)
                }
                break
            }
        }

        return "Park until tomorrow"
    }

    /// Calculate when time limit expires (capped at enforcement end if applicable)
    private func calculateTimeLimitEnd(from now: Date, endTime: TimeOfDay?) -> String {
        guard let limit = timeLimitMinutes else { return nil ?? "Check posted signs" }

        let calendar = Calendar.current
        let parkUntil = now.addingTimeInterval(TimeInterval(limit * 60))

        // Cap at enforcement end time if provided
        if let end = endTime,
           let endDate = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: now) {
            let actualEnd = min(parkUntil, endDate)
            return formatParkUntil(hour: calendar.component(.hour, from: actualEnd),
                                   minute: calendar.component(.minute, from: actualEnd),
                                   on: actualEnd)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Park until \(formatter.string(from: parkUntil))"
    }

    /// Calculate when time limit expires with enforcement awareness
    /// If time limit extends beyond enforcement end, returns next enforcement start instead
    private func calculateTimeLimitEndWithEnforcementAwareness(
        from now: Date,
        endTime: TimeOfDay,
        startTime: TimeOfDay,
        days: [DayOfWeek]?,
        currentDay: DayOfWeek?
    ) -> String {
        guard let limit = timeLimitMinutes else { return "Check posted signs" }

        let calendar = Calendar.current
        let parkUntil = now.addingTimeInterval(TimeInterval(limit * 60))

        // Get enforcement end time for today
        guard let endDate = calendar.date(bySettingHour: endTime.hour, minute: endTime.minute, second: 0, of: now) else {
            // Fallback if we can't calculate enforcement end
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Park until \(formatter.string(from: parkUntil))"
        }

        // Check if time limit extends beyond enforcement end
        if parkUntil > endDate {
            // Time limit would expire after enforcement ends
            // So you can park until enforcement starts again!
            return findNextEnforcementStart(from: now, startTime: startTime, days: days, currentDay: currentDay)
        } else {
            // Time limit expires during enforcement - show time limit end
            return formatParkUntil(
                hour: calendar.component(.hour, from: parkUntil),
                minute: calendar.component(.minute, from: parkUntil),
                on: parkUntil
            )
        }
    }

    /// Responsive card height for large mode
    private var largeCardHeight: CGFloat {
        let safeAreaTop: CGFloat = 59
        let safeAreaBottom: CGFloat = 34
        let padding: CGFloat = 32
        let mapCardHeight: CGFloat = 120
        let rulesHeaderPeek: CGFloat = 20
        let spacing: CGFloat = 32
        let availableHeight = screenHeight - safeAreaTop - safeAreaBottom - padding - mapCardHeight - rulesHeaderPeek - spacing
        return min(max(availableHeight, 300), 520)
    }

    var body: some View {
        ZStack {
            // Animated background that morphs between sizes
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .matchedGeometryEffect(id: "cardBackground", in: namespace)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)

            // Content changes based on expanded state
            if isExpanded {
                miniContent
                    .transition(.opacity)
            } else {
                largeContent
                    .transition(.opacity)
            }
        }
        .frame(height: isExpanded ? miniCardHeight : largeCardHeight)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .sheet(isPresented: $showRegulationsDrawer) {
            RegulationsDrawerView(
                zoneName: zoneName,
                zoneType: zoneType,
                validityStatus: validityStatus,
                applicablePermits: applicablePermits,
                timeLimitMinutes: timeLimitMinutes,
                regulations: detailedRegulations
            )
        }
    }

    /// Fixed height for mini card (reduced by 20%)
    private var miniCardHeight: CGFloat { 70 }

    // MARK: - Mini Content (expanded map mode)

    private var miniContent: some View {
        ZStack {
            HStack(spacing: 12) {
                // Zone circle (scaled down to fit reduced card height)
                zoneCircle(size: 44)

                // Zone info - state-specific content
                VStack(alignment: .leading, spacing: 4) {
                    if zoneType == .metered {
                        // PAID PARKING STATE
                        Text(zoneName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(meteredSubtitle ?? "$2/hr • 2hr max")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if isValidStyle {
                        // IN PERMIT ZONE (valid) - single or multi
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.headline)
                            Text("Unlimited Parking")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        Text(isMultiPermitLocation ? formattedZonesList : zoneName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    } else if isMultiPermitLocation {
                        // MULTI-PERMIT ZONE (invalid permit)
                        Text("Zone \(currentSelectedArea)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .animation(.easeInOut(duration: 0.2), value: animationIndex)
                        Text(formattedZonesList)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // OUT OF PERMIT ZONE (invalid) - show status as title, zone on line 2
                        if let unlimited = unlimitedUntilText {
                            // Outside enforcement - show when enforcement starts
                            Text(unlimited)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(zoneName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let parkUntil = parkUntilText {
                            // During enforcement - show "Park until" time
                            Text(parkUntil)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(zoneName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(zoneName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Permit Required")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Status badge
                    miniStatusBadge
                }

                Spacer()
            }
            .padding()
        }
    }

    /// Mini card status badge - state-specific
    private var miniStatusBadge: some View {
        Group {
            if zoneType == .metered {
                // PAID PARKING - show payment indicator
                HStack(spacing: 6) {
                    Image(systemName: "creditcard")
                        .font(.caption)
                    Text("Paid Parking")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
            } else if isValidStyle {
                // IN PERMIT ZONE - valid (checkmark already in header, zone name in subtitle)
                EmptyView()
            } else if let _ = parkUntilText {
                // OUT OF PERMIT - park until time already shown in header, no badge needed
                EmptyView()
            } else {
                // Default status
                HStack(spacing: 6) {
                    Image(systemName: validityStatus.iconName)
                        .font(.caption)
                    Text(validityStatus.displayText)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(Color.forValidityStatus(validityStatus))
            }
        }
    }

    // MARK: - Large Content (home screen mode)

    private var largeContent: some View {
        ZStack {
            if !isFlipped {
                // Front of card - state-specific content
                VStack(spacing: 8) {
                    // Zone circle centered
                    zoneCircle(size: 160)

                    // State-specific subtitle and info
                    largeCardSubtitle
                }

                // Top row: Status badge (left) and Info button (right)
                VStack {
                    HStack {
                        // State-specific top badge
                        largeCardTopBadge

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                isFlipped = true
                            }
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title2)
                                .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
                        }
                    }
                    .padding(16)
                    Spacer()
                }

                // Bottom section: See regulations link + validity badge
                VStack {
                    Spacer()

                    // "See regulations" button
                    if !detailedRegulations.isEmpty {
                        Button {
                            showRegulationsDrawer = true
                        } label: {
                            Text("See regulations")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isValidStyle ? .white.opacity(0.9) : .blue)
                                .underline()
                        }
                        .padding(.bottom, 8)
                    }

                    ValidityBadgeView(
                        status: validityStatus,
                        permits: applicablePermits,
                        onColoredBackground: isValidStyle,
                        timeLimitMinutes: timeLimitMinutes,
                        enforcementStartTime: enforcementStartTime,
                        enforcementEndTime: enforcementEndTime,
                        enforcementDays: enforcementDays
                    )
                    .padding(.bottom, 24)
                }
            } else {
                // Back of card (rules)
                rulesContent
            }
        }
        .rotation3DEffect(
            .degrees(isFlipped ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.8
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isFlipped)
    }

    /// Format multi-permit zones as "Zones A & B" or "Zones A, B & C"
    private var formattedZonesList: String {
        let areas = orderedPermitAreas
        switch areas.count {
        case 0:
            return "Zone"
        case 1:
            return "Zone \(areas[0])"
        case 2:
            return "Zones \(areas[0]) & \(areas[1])"
        default:
            let allButLast = areas.dropLast().joined(separator: ", ")
            return "Zones \(allButLast) & \(areas.last!)"
        }
    }

    private var displaySubtitle: String? {
        if zoneType == .metered { return meteredSubtitle ?? "$2/hr • 2hr max" }
        if isMultiPermitLocation { return formattedZonesList }
        return nil
    }

    // MARK: - Large Card State-Specific Components

    /// Subtitle content below the zone circle on large card
    @ViewBuilder
    private var largeCardSubtitle: some View {
        if zoneType == .metered {
            // PAID PARKING STATE
            VStack(spacing: 4) {
                Text(meteredSubtitle ?? "$2/hr • 2hr max")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Metered Parking")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        } else if isValidStyle {
            // IN PERMIT ZONE (valid) - single or multi
            VStack(spacing: 4) {
                if isMultiPermitLocation {
                    Text(formattedZonesList)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                }
                Text("Unlimited Parking")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        } else if isMultiPermitLocation {
            // MULTI-PERMIT ZONE (invalid permit)
            VStack(spacing: 4) {
                Text(formattedZonesList)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        } else {
            // OUT OF PERMIT ZONE (single zone, invalid)
            VStack(spacing: 4) {
                Text(zoneName)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Top badge on large card (permit status or zone type indicator)
    @ViewBuilder
    private var largeCardTopBadge: some View {
        if zoneType == .metered {
            // PAID PARKING - show payment badge
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.caption)
                Text("PAID PARKING")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.15))
            .clipShape(Capsule())
        } else if isValidStyle {
            // IN PERMIT ZONE - valid
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("UNLIMITED PARKING")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.25))
            .clipShape(Capsule())
        } else if zoneType == .residentialPermit {
            // OUT OF PERMIT ZONE - show the better status (unlimited if outside enforcement, otherwise time limit)
            if isOutsideEnforcement {
                // Outside enforcement hours - show unlimited
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("UNLIMITED NOW")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
            } else if let limit = timeLimitMinutes {
                // During enforcement - show time limit
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                    Text("\(limit / 60) HOUR LIMIT")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            } else {
                Text("PERMIT REQUIRED")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func zoneCircle(size: CGFloat) -> some View {
        if isMultiPermitLocation {
            LargeMultiPermitCircleView(
                permitAreas: orderedPermitAreas,
                animationIndex: animationIndex,
                size: size
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationIndex = (animationIndex + 1) % orderedPermitAreas.count
                }
            }
        } else {
            ZStack {
                Circle()
                    .fill(circleBackground)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.1), radius: size > 100 ? 4 : 2, x: 0, y: 2)

                Text(singleZoneCode)
                    .font(.system(size: size * (isExpanded ? 0.5 : 0.6), weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
    }

    private var statusBadge: some View {
        Group {
            if let parkUntil = parkUntilText {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(parkUntil)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(isValidStyle ? .white.opacity(0.9) : .orange)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: validityStatus.iconName)
                        .font(.caption)
                    Text(validityStatus.displayText)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(isValidStyle ? .white.opacity(0.9) : Color.forValidityStatus(validityStatus))
            }
        }
    }

    private var rulesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Parking Rules")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isValidStyle ? .white : .primary)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isFlipped = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ruleSummaryLines, id: \.self) { rule in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(isValidStyle ? .white.opacity(0.7) : .secondary)
                                .padding(.top, 6)

                            Text(rule)
                                .font(.body)
                                .foregroundColor(isValidStyle ? .white : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if ruleSummaryLines.isEmpty {
                        Text("No specific rules available")
                            .font(.body)
                            .foregroundColor(isValidStyle ? .white.opacity(0.7) : .secondary)
                            .italic()
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
    }
}

// MARK: - Large Multi-Permit Circle View

private struct LargeMultiPermitCircleView: View {
    let permitAreas: [String]
    let animationIndex: Int
    let size: CGFloat

    private var offset: CGFloat { size * 0.35 }
    private var totalWidth: CGFloat { size + (CGFloat(permitAreas.count - 1) * offset) }

    private var reorderedAreas: [(area: String, index: Int)] {
        var areas = permitAreas.enumerated().map { (area: $1, index: $0) }
        if let animatedItem = areas.first(where: { $0.index == animationIndex }) {
            areas.removeAll { $0.index == animationIndex }
            areas.append(animatedItem)
        }
        return areas
    }

    var body: some View {
        ZStack(alignment: .center) {
            ForEach(reorderedAreas, id: \.index) { item in
                let isActive = item.index == animationIndex
                let xOffset = CGFloat(item.index) * offset - (totalWidth - size) / 2

                ZStack {
                    Circle()
                        .fill(ZoneColorProvider.swiftUIColor(for: item.area))
                        .frame(width: size, height: size)
                        .shadow(color: isActive ? .black.opacity(0.3) : .black.opacity(0.15),
                                radius: isActive ? 8 : 4, x: 0, y: isActive ? 4 : 2)

                    Text(item.area)
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
                .offset(x: xOffset)
                .scaleEffect(isActive ? 1.15 : 1.0)
                .zIndex(isActive ? 1 : 0)
            }
        }
        .frame(width: totalWidth, height: size * 1.2)
    }
}

// MARK: - Mini Zone Card (compact version for expanded map) - DEPRECATED, kept for reference

private struct MiniZoneCardView: View {
    let zoneName: String
    let zoneCode: String?
    let zoneType: ZoneType
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let allValidPermitAreas: [String]
    let timeLimitMinutes: Int?

    @State private var animationIndex: Int = 0

    private var isMultiPermitLocation: Bool {
        allValidPermitAreas.count > 1
    }

    private var orderedPermitAreas: [String] {
        guard isMultiPermitLocation else {
            return [zoneCode ?? "?"]
        }
        var areas = allValidPermitAreas
        if let userPermitArea = applicablePermits.first?.area,
           let index = areas.firstIndex(of: userPermitArea) {
            areas.remove(at: index)
            areas.insert(userPermitArea, at: 0)
        }
        return areas
    }

    private var isValidStyle: Bool {
        validityStatus == .valid || validityStatus == .multipleApply
    }

    private var cardBackground: Color {
        if zoneType == .metered {
            return Color(.systemBackground)
        }
        return isValidStyle ? Color.accessibleValidGreen : Color(.systemBackground)
    }

    private var circleBackground: Color {
        ZoneColorProvider.swiftUIColor(for: zoneCode)
    }

    private var currentSelectedArea: String {
        guard isMultiPermitLocation, animationIndex < orderedPermitAreas.count else {
            return zoneCode ?? "?"
        }
        return orderedPermitAreas[animationIndex]
    }

    /// Format multi-permit zones as "Zones A & B" or "Zones A, B & C"
    private var formattedZonesList: String {
        let areas = orderedPermitAreas
        switch areas.count {
        case 0: return "Zone"
        case 1: return "Zone \(areas[0])"
        case 2: return "Zones \(areas[0]) & \(areas[1])"
        default:
            let allButLast = areas.dropLast().joined(separator: ", ")
            return "Zones \(allButLast) & \(areas.last!)"
        }
    }

    /// Calculate "Park until" time
    private var parkUntilText: String? {
        guard (validityStatus == .invalid || validityStatus == .noPermitSet),
              let limit = timeLimitMinutes else { return nil }
        let parkUntil = Date().addingTimeInterval(TimeInterval(limit * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Park until \(formatter.string(from: parkUntil))"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Zone circle
            if isMultiPermitLocation {
                MiniMultiPermitCircleView(
                    permitAreas: orderedPermitAreas,
                    animationIndex: animationIndex,
                    size: 56
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationIndex = (animationIndex + 1) % orderedPermitAreas.count
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .fill(circleBackground)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                    Text(zoneCode ?? "?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }

            // Zone info
            VStack(alignment: .leading, spacing: 4) {
                if isMultiPermitLocation {
                    Text("Zone \(currentSelectedArea)")
                        .font(.headline)
                        .foregroundColor(isValidStyle ? .white : .primary)
                        .animation(.easeInOut(duration: 0.2), value: animationIndex)
                    Text(formattedZonesList)
                        .font(.caption)
                        .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
                } else {
                    HStack(spacing: 4) {
                        // Dollar icon for paid/metered zones
                        if zoneType == .metered {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.headline)
                                .foregroundColor(ZoneColorProvider.swiftUIColor(for: .metered))
                        }
                        Text(zoneName)
                            .font(.headline)
                            .foregroundColor(isValidStyle ? .white : .primary)
                    }
                }

                // Status or Park Until
                if let parkUntil = parkUntilText {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(parkUntil)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isValidStyle ? .white.opacity(0.9) : .orange)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: validityStatus.iconName)
                            .font(.caption)
                        Text(validityStatus.displayText)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isValidStyle ? .white.opacity(0.9) : Color.forValidityStatus(validityStatus))
                }
            }

            Spacer()
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Mini Multi-Permit Circle View

private struct MiniMultiPermitCircleView: View {
    let permitAreas: [String]
    let animationIndex: Int
    let size: CGFloat

    private var offset: CGFloat { size * 0.25 }
    private var totalWidth: CGFloat { size + (CGFloat(permitAreas.count - 1) * offset) }

    private var reorderedAreas: [(area: String, index: Int)] {
        var areas = permitAreas.enumerated().map { (area: $1, index: $0) }
        if let animatedItem = areas.first(where: { $0.index == animationIndex }) {
            areas.removeAll { $0.index == animationIndex }
            areas.append(animatedItem)
        }
        return areas
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(reorderedAreas, id: \.index) { item in
                let isActive = item.index == animationIndex
                ZStack {
                    Circle()
                        .fill(ZoneColorProvider.swiftUIColor(for: item.area))
                        .frame(width: size, height: size)
                        .shadow(color: isActive ? .black.opacity(0.3) : .black.opacity(0.1),
                                radius: isActive ? 4 : 2, x: 0, y: isActive ? 2 : 1)

                    Text(item.area)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
                .offset(x: CGFloat(item.index) * offset)
                .scaleEffect(isActive ? 1.1 : 1.0)
                .zIndex(isActive ? 1 : 0)
            }
        }
        .frame(width: totalWidth, height: size * 1.1)
    }
}

// MARK: - Expanded Bottom Card

private struct ExpandedBottomCard: View {
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            Spacer()

            // Settings button
            Button(action: onSettingsTap) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Tapped Spot Info Card

private struct TappedSpotInfoCard: View {
    let zone: ParkingZone
    let tappedPermitAreas: [String]?  // Specific permit areas for the tapped boundary
    let userPermits: [ParkingPermit]
    let onDismiss: () -> Void

    @State private var animationIndex: Int = 0
    @State private var ellipsisCount: Int = 0

    // Timer for ellipsis animation
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var zoneCode: String {
        zone.permitArea ?? zone.displayName
    }

    private var isMultiPermitZone: Bool {
        !zone.multiPermitBoundaries.isEmpty && zone.zoneType == .residentialPermit
    }

    private var allPermitAreas: [String] {
        // Use the specific tapped boundary's permit areas if available
        if let tappedAreas = tappedPermitAreas, !tappedAreas.isEmpty {
            return tappedAreas.sorted()
        }
        // Fallback to zone code if no multi-permit data
        return [zoneCode]
    }

    /// Check if user has valid permit for this tapped boundary
    private var hasValidPermit: Bool {
        let userPermitAreas = Set(userPermits.map { $0.area.uppercased() })
        return allPermitAreas.contains { userPermitAreas.contains($0.uppercased()) }
    }

    /// Calculate "Park Until" time based on time limit with enforcement awareness
    private var parkUntilText: String? {
        guard !hasValidPermit, zone.zoneType == .residentialPermit else { return nil }
        guard let minutes = zone.nonPermitTimeLimit else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        // Get enforcement hours from the primary rule
        let primaryRule = zone.rules.first(where: { $0.enforcementStartTime != nil })
        let startTime = primaryRule?.enforcementStartTime
        let endTime = primaryRule?.enforcementEndTime
        let enforcementDays = primaryRule?.enforcementDays

        // Check if enforcement is currently active
        if let start = startTime, let end = endTime {
            let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let startMinutes = start.totalMinutes
            let endMinutes = end.totalMinutes

            // Check if today is an enforcement day
            var isEnforcementDay = true
            var currentDayOfWeek: DayOfWeek?
            if let days = enforcementDays, !days.isEmpty,
               let weekday = components.weekday,
               let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
                currentDayOfWeek = dayOfWeek
                isEnforcementDay = days.contains(dayOfWeek)
            }

            if isEnforcementDay {
                if currentMinutes < startMinutes {
                    // Before enforcement starts today - can park until enforcement begins
                    return formatParkUntilTime(hour: start.hour, minute: start.minute, on: now)
                } else if currentMinutes >= endMinutes {
                    // After enforcement ends today - find next enforcement start
                    return findNextEnforcementStartTime(from: now, startTime: start, days: enforcementDays, currentDay: currentDayOfWeek)
                } else {
                    // During enforcement - check if time limit extends beyond enforcement end
                    let parkUntil = now.addingTimeInterval(TimeInterval(minutes * 60))

                    if let endDate = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: now) {
                        if parkUntil > endDate {
                            // Time limit extends beyond enforcement end - can park until next enforcement start!
                            return findNextEnforcementStartTime(from: now, startTime: start, days: enforcementDays, currentDay: currentDayOfWeek)
                        } else {
                            // Time limit expires during enforcement - show time limit end
                            return formatParkUntilTime(
                                hour: calendar.component(.hour, from: parkUntil),
                                minute: calendar.component(.minute, from: parkUntil),
                                on: parkUntil
                            )
                        }
                    }
                }
            } else {
                // Not an enforcement day - find next enforcement start
                return findNextEnforcementStartTime(from: now, startTime: start, days: enforcementDays, currentDay: currentDayOfWeek)
            }
        }

        // No enforcement hours defined - just use time limit
        let parkUntil = now.addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Park Until \(formatter.string(from: parkUntil))"
    }

    /// Format "Park Until" with day only when ambiguous (for TappedSpotInfoCard)
    private func formatParkUntilTime(hour: Int, minute: Int, on date: Date) -> String {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else {
            return "Park Until \(hour):\(String(format: "%02d", minute))"
        }

        let formatter = DateFormatter()
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let targetIsAM = hour < 12

        // If target is today, never show day
        if calendar.isDateInToday(targetDate) {
            formatter.dateFormat = "h:mm a"
            return "Park Until \(formatter.string(from: targetDate))"
        }

        // If target is tomorrow AND it's after noon AND target is AM, it's obvious - don't show day
        if calendar.isDateInTomorrow(targetDate) && currentHour >= 12 && targetIsAM {
            formatter.dateFormat = "h:mm a"
            return "Park Until \(formatter.string(from: targetDate))"
        }

        // Otherwise show day for clarity
        formatter.dateFormat = "EEE h:mm a"
        return "Park Until \(formatter.string(from: targetDate))"
    }

    /// Find the next enforcement start time (for TappedSpotInfoCard)
    private func findNextEnforcementStartTime(from now: Date, startTime: TimeOfDay, days: [DayOfWeek]?, currentDay: DayOfWeek?) -> String {
        let calendar = Calendar.current

        // If no specific days, enforcement is daily - next enforcement is tomorrow
        guard let enforcementDays = days, !enforcementDays.isEmpty, let current = currentDay else {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return formatParkUntilTime(hour: startTime.hour, minute: startTime.minute, on: tomorrow)
            }
            return "Park Until tomorrow"
        }

        // Find the next enforcement day
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: current) else {
            return "Park Until tomorrow"
        }

        // Look for the next enforcement day (starting from tomorrow)
        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if enforcementDays.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: now) {
                    return formatParkUntilTime(hour: startTime.hour, minute: startTime.minute, on: targetDate)
                }
                break
            }
        }

        return "Park Until tomorrow"
    }

    /// Animated ellipsis dots
    private var ellipsis: String {
        String(repeating: ".", count: ellipsisCount)
    }

    /// Time limit formatted as "X Hour Max" or "X Min Max"
    private var timeLimitText: String? {
        guard let minutes = zone.nonPermitTimeLimit else { return nil }
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours) Hour Max"
        } else {
            return "\(minutes) Min Max"
        }
    }

    /// Rule description text with zone prefix
    private var ruleDescriptionText: String? {
        let zonePrefix = isMultiPermitZone ? formattedZonesList : "Zone \(zoneCode)"

        // For users without valid permit, show custom text
        if !hasValidPermit && zone.requiresPermit && zone.zoneType == .residentialPermit {
            return "\(zonePrefix) - Permit Required for Long Term Parking"
        }
        // Otherwise use zone's default description with zone prefix
        if let ruleDesc = zone.primaryRuleDescription {
            return "\(zonePrefix) - \(ruleDesc)"
        }
        return zonePrefix
    }

    /// Format multi-permit zones as "Zones A & B" or "Zones A, B & C"
    private var formattedZonesList: String {
        let areas = allPermitAreas
        switch areas.count {
        case 0: return "Zone"
        case 1: return "Zone \(areas[0])"
        case 2: return "Zones \(areas[0]) & \(areas[1])"
        default:
            let allButLast = areas.dropLast().joined(separator: ", ")
            return "Zones \(allButLast) & \(areas.last!)"
        }
    }

    private var currentSelectedArea: String {
        guard isMultiPermitZone, animationIndex < allPermitAreas.count else { return zoneCode }
        return allPermitAreas[animationIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 12) {
                    // Text first, then circle (reordered)
                    VStack(alignment: .leading, spacing: 2) {
                        // First line: Shows different content based on permit validity
                        HStack(spacing: 4) {
                            if zone.zoneType == .metered {
                                // Paid parking: Show dollar icon + zone name
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(ZoneColorProvider.swiftUIColor(for: .metered))
                                Text(zone.displayName)
                                    .font(.headline)
                            } else if hasValidPermit {
                                // User has valid permit: Show infinity icon + "Unlimited Parking"
                                Image(systemName: "infinity")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Text("Unlimited Parking")
                                    .font(.headline)
                            } else if let parkUntil = parkUntilText {
                                // No valid permit: Show "Park Until" with timer
                                Image(systemName: "timer")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text(parkUntil + ellipsis)
                                    .font(.headline)
                                    .onReceive(timer) { _ in
                                        ellipsisCount = (ellipsisCount + 1) % 4
                                    }
                            } else if isMultiPermitZone {
                                Text("Zone \(currentSelectedArea)")
                                    .font(.headline)
                                    .animation(.easeInOut(duration: 0.2), value: animationIndex)
                            } else {
                                Text("Zone \(zoneCode)")
                                    .font(.headline)
                            }
                        }

                        // Second line: Shows permit validity or time limit
                        if hasValidPermit {
                            // User has valid permit: Show badge
                            Text("Permit Valid")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .cornerRadius(6)
                        } else if let timeLimit = timeLimitText {
                            // No valid permit: Show time limit
                            Text(timeLimit)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Circle UI hidden for now
                    // if isMultiPermitZone {
                    //     MiniMultiPermitCircleView(
                    //         permitAreas: allPermitAreas,
                    //         animationIndex: animationIndex,
                    //         size: 44
                    //     )
                    //     .onTapGesture {
                    //         withAnimation(.easeInOut(duration: 0.3)) {
                    //             animationIndex = (animationIndex + 1) % allPermitAreas.count
                    //         }
                    //     }
                    // } else {
                    //     ZStack {
                    //         Circle()
                    //             .fill(ZoneColorProvider.swiftUIColor(for: zone.permitArea))
                    //             .frame(width: 44, height: 44)
                    //         Text(zoneCode)
                    //             .font(.system(size: 18, weight: .bold))
                    //             .foregroundColor(.white)
                    //             .minimumScaleFactor(0.5)
                    //     }
                    // }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            // Rule description with custom text for invalid permits
            if let ruleDesc = ruleDescriptionText {
                Text(ruleDesc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Enforcement hours (unchanged)
            if let hours = zone.enforcementHours {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(hours)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}
*/
// END DEPRECATED COMPONENTS

// MARK: - Overlapping Zones Button (kept for compatibility)

struct OverlappingZonesButton: View {
    let zoneCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundColor(.orange)
                Text("\(zoneCount) overlapping zones at this location")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let brandColor = Color.accentColor

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(brandColor.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(reduceMotion ? 1.0 : (isAnimating ? 1.1 : 1.0))

                    Circle()
                        .fill(brandColor.opacity(0.3))
                        .frame(width: 80, height: 80)

                    Text("P")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(brandColor)
                }

                VStack(spacing: 8) {
                    Text("Hunting for a spot...")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("The eternal SF quest")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top, 8)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: AppError
    let onRetry: () -> Void
    let onDismiss: (() -> Void)?
    @State private var showTechnicalDetails = false

    init(error: AppError, onRetry: @escaping () -> Void, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: error.iconName)
                .font(.system(size: 48))
                .foregroundColor(error.iconColor)

            Text(errorTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            VStack(spacing: 12) {
                if error.canRetry {
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if error == .locationPermissionDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .frame(minWidth: 140)
                    }
                    .buttonStyle(.bordered)
                }

                // Show "Back to Map" for area-related errors
                if let onDismiss = onDismiss, (error == .unknownArea || error == .outsideCoverage) {
                    Button(action: onDismiss) {
                        HStack {
                            Image(systemName: "map")
                            Text("Back to Map")
                        }
                        .frame(minWidth: 140)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 8)

            #if DEBUG
            if case .dataLoadFailed(let dataError) = error {
                Button {
                    showTechnicalDetails.toggle()
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Technical Details")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                if showTechnicalDetails {
                    Text(dataError.debugDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var errorTitle: String {
        switch error {
        case .locationPermissionDenied:
            return "Location Access Needed"
        case .locationUnavailable:
            return "Location Unavailable"
        case .unknownArea:
            return "Unknown Parking Area"
        case .outsideCoverage:
            return "Outside San Francisco"
        case .dataLoadFailed:
            return "Data Error"
        case .unknown:
            return "Something Went Wrong"
        }
    }
}

// MARK: - Overlapping Zones Sheet

struct OverlappingZonesSheet: View {
    let zones: [ParkingZone]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(zones) { zone in
                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.displayName)
                        .font(.headline)
                    Text(zone.zoneType.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Overlapping Zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Bottom Navigation Bar

/// Fixed bottom navigation with four buttons
private struct BottomNavigationBar: View {
    let isDeveloperModeActive: Bool
    let hasActiveSession: Bool
    let onDeveloperTap: () -> Void
    let onParkTap: () -> Void
    let onSettingsTap: () -> Void
    let onExpandTap: () -> Void
    let isExpanded: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Adaptive background color for buttons based on light/dark mode
    private var buttonBackgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.85)
    }

    /// Adaptive foreground color for button icons/text
    private var buttonForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left section: Developer tools button OR Settings button
            HStack(spacing: 12) {
                if isDeveloperModeActive {
                    // Developer tools button
                    Button {
                        HapticFeedback.selection()
                        onDeveloperTap()
                    } label: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(buttonForegroundColor)
                            .frame(width: 44, height: 44)
                            .background(buttonBackgroundColor)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }

                // Settings button (always visible)
                Button {
                    HapticFeedback.selection()
                    onSettingsTap()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(buttonForegroundColor)
                        .frame(width: 44, height: 44)
                        .background(buttonBackgroundColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }

            Spacer()

            // Right section: Drive and Park buttons grouped together
            HStack(spacing: 12) {
                // Drive button (expand/collapse - driving mode toggle)
                Button {
                    HapticFeedback.light()
                    onExpandTap()
                } label: {
                    Image(systemName: "car.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isExpanded ? buttonForegroundColor : .white)
                        .frame(width: 44, height: 44)
                        .background(isExpanded ? buttonBackgroundColor : Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }

                // Park button (horizontal with label) - rightmost
                Button {
                    HapticFeedback.medium()
                    onParkTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "parkingsign.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text(hasActiveSession ? "Parked" : "Park")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(hasActiveSession ? .white : buttonForegroundColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(hasActiveSession ? Color.blue : buttonBackgroundColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .offset(y: -16)
    }
}

// MARK: - Loading Overlays

/// Subtle loading overlay for the map view (shown to regular users)
private struct MapLoadingOverlay: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ZStack {
                // Subtle semi-transparent background
                Color.black.opacity(0.1)
                    .ignoresSafeArea()

                // Simple spinner
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)

                    Text("Loading map...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 8)
                )
            }
            .transition(.opacity)
        }
    }
}

/// Detailed loading overlay for developer view (shows detailed status)
private struct DeveloperLoadingOverlay: View {
    let isLoadingZones: Bool
    let isLoadingOverlays: Bool
    let statusMessage: String

    @State private var dots = ""

    var body: some View {
        if isLoadingZones || isLoadingOverlays {
            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(isLoadingZones || isLoadingOverlays ? 360 : 0))
                            .animation(
                                isLoadingZones || isLoadingOverlays ?
                                    .linear(duration: 2).repeatForever(autoreverses: false) : .default,
                                value: isLoadingZones || isLoadingOverlays
                            )

                        Text("Developer: Loading Status")
                            .font(.headline)

                        Spacer()
                    }

                    Divider()

                    // Zone Loading Status
                    HStack(spacing: 12) {
                        if isLoadingZones {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zone Data")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(isLoadingZones ? "Loading zones\(dots)" : "Zones loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Overlay Loading Status
                    HStack(spacing: 12) {
                        if isLoadingOverlays {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Map Overlays")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(isLoadingOverlays ? "Rendering overlays\(dots)" : "Overlays rendered")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Detailed Status Message
                    if !statusMessage.isEmpty {
                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)

                            Text(statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 12)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                startDotsAnimation()
            }
        }
    }

    private func startDotsAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !isLoadingZones && !isLoadingOverlays {
                timer.invalidate()
                dots = ""
                return
            }

            if dots.count >= 3 {
                dots = ""
            } else {
                dots += "."
            }
        }
    }
}

// MARK: - Out of Coverage Banner

/// Banner shown at the top of the map when user is outside SF coverage area
private struct OutOfCoverageBanner: View {
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text("Outside Coverage Area")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("This location is outside San Francisco")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    MainResultView()
}
