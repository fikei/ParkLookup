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
    @State private var isMapExpanded = false
    @State private var selectedZone: ParkingZone?
    @State private var tappedPermitAreas: [String]?  // Specific permit areas for the tapped boundary
    @State private var searchedCoordinate: CLLocationCoordinate2D?
    @State private var showOutsideCoverageAlert = false
    @State private var developerPanelExpanded = false
    @State private var isLoadingOverlays = false
    @State private var overlayLoadingMessage = ""

    @Namespace private var cardAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var body: some View {
        let _ = print("🔧 DEBUG: MainResultView body - devMode: \(devSettings.developerModeUnlocked), expanded: \(isMapExpanded), panel: \(developerPanelExpanded)")
        ZStack {
            // Layer 1: Fullscreen Map (always visible as background)
            if viewModel.error == nil && !viewModel.isLoading {
                ZStack {
                    ZoneMapView(
                        zones: viewModel.allLoadedZones,
                        currentZoneId: viewModel.currentZoneId,
                        userCoordinate: activeCoordinate,
                        onZoneTapped: { zone, permitAreas in
                            if isMapExpanded {
                                selectedZone = zone
                                tappedPermitAreas = permitAreas
                            }
                        },
                        userPermitAreas: userPermitAreaCodes,
                        devSettingsHash: devSettings.settingsHash,
                        // When collapsed, shift user location below the card
                        // A bias of 0.5 places the user indicator well below the large card
                        verticalBias: isMapExpanded ? 0.0 : 0.5,
                        // Show zone overlays when expanded OR when developer panel is open
                        showOverlays: isMapExpanded || developerPanelExpanded,
                        // Collapsed: 0.65, Expanded: 0.5
                        zoomMultiplier: isMapExpanded ? 0.5 : 0.65,
                        // Show pin for searched address
                        searchedCoordinate: searchedCoordinate
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
                .onChange(of: viewModel.allLoadedZones.count) { newCount in
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

            // Layer 2: Card overlays (hidden when developer panel is open)
            if !viewModel.isLoading && viewModel.error == nil && !developerPanelExpanded {
                VStack {
                    // Address search card (only in expanded mode)
                    if isMapExpanded {
                        AddressSearchCard(
                            currentAddress: viewModel.currentAddress,
                            onAddressSelected: { coordinate in
                                searchedCoordinate = coordinate
                                // Trigger zone lookup for the new coordinate
                                viewModel.lookupZone(at: coordinate)
                            },
                            onResetToCurrentLocation: {
                                searchedCoordinate = nil
                                viewModel.returnToGPSLocation()
                            },
                            onOutsideCoverage: {
                                showOutsideCoverageAlert = true
                            }
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Animated zone card that morphs between large and mini states
                    AnimatedZoneCard(
                        isExpanded: isMapExpanded,
                        namespace: cardAnimation,
                        zoneName: viewModel.zoneName,
                        zoneCode: currentPermitArea,
                        zoneType: viewModel.zoneType,
                        validityStatus: viewModel.validityStatus,
                        applicablePermits: viewModel.applicablePermits,
                        allValidPermitAreas: viewModel.allValidPermitAreas,
                        meteredSubtitle: viewModel.meteredSubtitle,
                        timeLimitMinutes: viewModel.timeLimitMinutes,
                        ruleSummaryLines: viewModel.ruleSummaryLines,
                        enforcementStartTime: viewModel.enforcementStartTime,
                        enforcementEndTime: viewModel.enforcementEndTime,
                        enforcementDays: viewModel.enforcementDays
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 20)

                    Spacer()

                    // Bottom section - Tapped zone info (only in expanded mode)
                    if isMapExpanded, let selected = selectedZone {
                        TappedSpotInfoCard(
                            zone: selected,
                            tappedPermitAreas: tappedPermitAreas,
                            userPermits: viewModel.userPermits
                        ) {
                            selectedZone = nil
                            tappedPermitAreas = nil
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 80) // Padding to avoid overlap with bottom navigation
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
                        onDeveloperTap: {
                            print("🔧 DEBUG: Developer button tapped! Panel will expand")
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                developerPanelExpanded.toggle()
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

            // Error state
            if let error = viewModel.error {
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
        .alert("Outside Coverage Area", isPresented: $showOutsideCoverageAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That address is outside San Francisco. We currently only support SF parking zones.")
        }
    }
}

// MARK: - Animated Zone Card (morphs between large and mini states)

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

    // Enforcement hours for "Park Until" calculation
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let enforcementDays: [DayOfWeek]?

    @State private var animationIndex: Int = 0
    @State private var isFlipped: Bool = false

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
        return isValidStyle ? Color.green : Color(.systemBackground)
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
                    // During enforcement - normal time limit applies
                    return calculateTimeLimitEnd(from: now, endTime: endTime)
                }
            } else {
                // Not an enforcement day - find next enforcement start
                return findNextEnforcementStart(from: now, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
            }
        }

        // No enforcement hours defined - just use time limit
        return calculateTimeLimitEnd(from: now, endTime: nil)
    }

    /// Format "Park until" with day if not today
    private func formatParkUntil(hour: Int, minute: Int, on date: Date) -> String {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else {
            return "Park until \(hour):\(String(format: "%02d", minute))"
        }

        let formatter = DateFormatter()
        if calendar.isDateInToday(targetDate) {
            formatter.dateFormat = "h:mm a"
            return "Park until \(formatter.string(from: targetDate))"
        } else {
            formatter.dateFormat = "EEE h:mm a"
            return "Park until \(formatter.string(from: targetDate))"
        }
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

    /// Responsive card height for large mode
    private var largeCardHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
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
                        if isOutsideEnforcement {
                            // Outside enforcement - show unlimited
                            Text("Unlimited Now")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(zoneName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let limit = timeLimitMinutes {
                            // During enforcement - show time limit
                            Text("\(limit / 60) Hour Limit")
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
            } else if let parkUntil = parkUntilText {
                // OUT OF PERMIT - show time limit
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(parkUntil)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
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

                // Bottom badge
                VStack {
                    Spacer()
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
        return isValidStyle ? Color.green : Color(.systemBackground)
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
                    Text(zoneName)
                        .font(.headline)
                        .foregroundColor(isValidStyle ? .white : .primary)
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

    /// Calculate "Park Until" time based on time limit
    private var parkUntilText: String? {
        guard !hasValidPermit, zone.zoneType == .residentialPermit else { return nil }
        guard let minutes = zone.nonPermitTimeLimit else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let parkUntil = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Park Until \(formatter.string(from: parkUntil))"
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
                        // First line: "Park Until" with timer icon or zone name
                        HStack(spacing: 4) {
                            if let parkUntil = parkUntilText {
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

                        // Second line: Time limit for both single and multi-permit zones
                        if let timeLimit = timeLimitText {
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
                    Text("Finding your zone...")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("Checking your location")
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

/// Fixed bottom navigation with three evenly distributed buttons
private struct BottomNavigationBar: View {
    let isDeveloperModeActive: Bool
    let onDeveloperTap: () -> Void
    let onSettingsTap: () -> Void
    let onExpandTap: () -> Void
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Left: Developer tools button (only when developer mode is unlocked)
            Button {
                HapticFeedback.selection()
                onDeveloperTap()
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .opacity(isDeveloperModeActive ? 1.0 : 0.0)
            .disabled(!isDeveloperModeActive)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center: Settings button
            Button {
                HapticFeedback.selection()
                onSettingsTap()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Right: Expand/collapse button
            Button {
                HapticFeedback.light()
                onExpandTap()
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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

// MARK: - Preview

#Preview {
    MainResultView()
}
