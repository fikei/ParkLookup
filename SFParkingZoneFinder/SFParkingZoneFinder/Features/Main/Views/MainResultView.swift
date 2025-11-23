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
    @State private var showingSettings = false
    @State private var contentAppeared = false
    @State private var isMapExpanded = false
    @State private var selectedZone: ParkingZone?
    @State private var searchedCoordinate: CLLocationCoordinate2D?
    @State private var showOutsideCoverageAlert = false

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

    var body: some View {
        ZStack {
            // Layer 1: Fullscreen Map (always visible as background)
            if viewModel.error == nil && !viewModel.isLoading {
                ZoneMapView(
                    zones: viewModel.allLoadedZones,
                    currentZoneId: viewModel.currentZoneId,
                    userCoordinate: activeCoordinate,
                    onZoneTapped: { zone in
                        if isMapExpanded {
                            selectedZone = zone
                        }
                    },
                    // When collapsed, shift user location below the card
                    // A bias of 0.5 places the user indicator well below the large card
                    verticalBias: isMapExpanded ? 0.0 : 0.5,
                    // Hide zone overlays on home screen, show when expanded
                    showOverlays: isMapExpanded,
                    // Collapsed: 0.65, Expanded: 0.5
                    zoomMultiplier: isMapExpanded ? 0.5 : 0.65
                )
                .ignoresSafeArea()
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            // Layer 2: Card overlays
            if !viewModel.isLoading && viewModel.error == nil {
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
                                viewModel.refreshLocation()
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
                        ruleSummaryLines: viewModel.ruleSummaryLines
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 20)

                    Spacer()

                    // Bottom section
                    VStack(spacing: 12) {
                        // Tapped zone info (only in expanded mode)
                        if isMapExpanded, let selected = selectedZone {
                            TappedZoneInfoCard(zone: selected) {
                                selectedZone = nil
                            }
                            .padding(.horizontal)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Bottom info card (only in expanded mode)
                        if isMapExpanded {
                            ExpandedBottomCard(
                                onSettingsTap: {
                                    HapticFeedback.selection()
                                    showingSettings = true
                                }
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }

                // Expand/Collapse button (bottom right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            HapticFeedback.light()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isMapExpanded.toggle()
                                if !isMapExpanded {
                                    selectedZone = nil
                                    // Reset to current location when minimizing
                                    if searchedCoordinate != nil {
                                        searchedCoordinate = nil
                                        viewModel.refreshLocation()
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: isMapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, isMapExpanded ? 180 : 16)
                    }
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

    private var parkUntilText: String? {
        guard (validityStatus == .invalid || validityStatus == .noPermitSet),
              let limit = timeLimitMinutes else { return nil }
        let parkUntil = Date().addingTimeInterval(TimeInterval(limit * 60))
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
                        Text("No Parking Restrictions")
                            .font(.headline)
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
                        // OUT OF PERMIT ZONE (invalid)
                        Text(zoneName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        if let limit = timeLimitMinutes {
                            Text("\(limit / 60)hr limit")
                                .font(.caption)
                                .foregroundColor(.orange)
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
                // IN PERMIT ZONE - valid
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("PERMIT VALID")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white.opacity(0.9))
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
                        timeLimitMinutes: timeLimitMinutes
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
                Text("No Parking Restrictions")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        } else if isMultiPermitLocation {
            // MULTI-PERMIT ZONE (invalid permit)
            VStack(spacing: 4) {
                Text(formattedZonesList)
                    .font(.headline)
                    .foregroundColor(.secondary)
                if let limit = timeLimitMinutes {
                    Text("\(limit / 60)-hour limit without permit")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
        } else {
            // OUT OF PERMIT ZONE (single zone, invalid)
            VStack(spacing: 4) {
                Text(zoneName)
                    .font(.headline)
                    .foregroundColor(.secondary)
                if let limit = timeLimitMinutes {
                    Text("\(limit / 60)-hour limit without permit")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
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
            Text("PERMIT VALID")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.25))
                .clipShape(Capsule())
        } else if zoneType == .residentialPermit {
            // OUT OF PERMIT ZONE - invalid
            Text("PERMIT INVALID")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
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

// MARK: - Tapped Zone Info Card

private struct TappedZoneInfoCard: View {
    let zone: ParkingZone
    let onDismiss: () -> Void

    @State private var animationIndex: Int = 0

    private var zoneCode: String {
        zone.permitArea ?? zone.displayName
    }

    private var isMultiPermitZone: Bool {
        !zone.multiPermitBoundaries.isEmpty && zone.zoneType == .residentialPermit
    }

    private var allPermitAreas: [String] {
        guard isMultiPermitZone else { return [zoneCode] }
        var areas = Set<String>()
        if let permitArea = zone.permitArea { areas.insert(permitArea) }
        for boundary in zone.multiPermitBoundaries {
            areas.formUnion(boundary.validPermitAreas)
        }
        return areas.sorted()
    }

    private var currentSelectedArea: String {
        guard isMultiPermitZone, animationIndex < allPermitAreas.count else { return zoneCode }
        return allPermitAreas[animationIndex]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 12) {
                    if isMultiPermitZone {
                        MiniMultiPermitCircleView(
                            permitAreas: allPermitAreas,
                            animationIndex: animationIndex,
                            size: 44
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                animationIndex = (animationIndex + 1) % allPermitAreas.count
                            }
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(ZoneColorProvider.swiftUIColor(for: zone.permitArea))
                                .frame(width: 44, height: 44)
                            Text(zoneCode)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if isMultiPermitZone {
                            Text("Zone \(currentSelectedArea)")
                                .font(.headline)
                                .animation(.easeInOut(duration: 0.2), value: animationIndex)
                            Text(formattedZonesList)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(zone.displayName)
                                .font(.headline)
                            Text(zone.zoneType.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            if let ruleDesc = zone.primaryRuleDescription {
                Text(ruleDesc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

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

// MARK: - Preview

#Preview {
    MainResultView()
}
