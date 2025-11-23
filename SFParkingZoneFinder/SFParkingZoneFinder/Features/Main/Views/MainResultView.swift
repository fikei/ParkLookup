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
    @State private var showingOverlappingZones = false
    @State private var showingSettings = false
    @State private var contentAppeared = false
    @State private var isMapExpanded = false
    @State private var selectedZone: ParkingZone?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    userCoordinate: viewModel.currentCoordinate,
                    onZoneTapped: { zone in
                        if isMapExpanded {
                            selectedZone = zone
                        }
                    }
                )
                .ignoresSafeArea()
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            // Layer 2: Card overlays
            if !viewModel.isLoading && viewModel.error == nil {
                VStack {
                    if isMapExpanded {
                        // Expanded mode: Mini card at top
                        MiniZoneCardView(
                            zoneName: viewModel.zoneName,
                            zoneCode: currentPermitArea,
                            zoneType: viewModel.zoneType,
                            validityStatus: viewModel.validityStatus,
                            applicablePermits: viewModel.applicablePermits,
                            allValidPermitAreas: viewModel.allValidPermitAreas,
                            timeLimitMinutes: viewModel.timeLimitMinutes
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    } else {
                        // Collapsed mode: Large zone card
                        ZoneStatusCardView(
                            zoneName: viewModel.zoneName,
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
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }

                    Spacer()

                    // Bottom section
                    VStack(spacing: 12) {
                        // Collapsed mode: Center location button
                        if !isMapExpanded {
                            Button {
                                HapticFeedback.light()
                                viewModel.refreshLocation()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Center on Location")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .padding(.bottom, 24)
                            .transition(.opacity)
                        }

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
                                address: viewModel.currentAddress,
                                hasOverlappingZones: viewModel.hasOverlappingZones,
                                overlappingZoneCount: viewModel.overlappingZones.count,
                                onOverlappingZonesTap: {
                                    HapticFeedback.light()
                                    showingOverlappingZones = true
                                },
                                onSettingsTap: {
                                    HapticFeedback.selection()
                                    showingSettings = true
                                },
                                onRefresh: {
                                    HapticFeedback.medium()
                                    viewModel.refreshLocation()
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
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isMapExpanded.toggle()
                                if !isMapExpanded {
                                    selectedZone = nil
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
                ErrorView(error: error) {
                    HapticFeedback.medium()
                    viewModel.refreshLocation()
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                .onAppear {
                    HapticFeedback.error()
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isMapExpanded)
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
        .sheet(isPresented: $showingOverlappingZones) {
            OverlappingZonesSheet(zones: viewModel.overlappingZones)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - Mini Zone Card (compact version for expanded map)

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
                    Text("Multi Permit Zone")
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
    let address: String?
    let hasOverlappingZones: Bool
    let overlappingZoneCount: Int
    let onOverlappingZonesTap: () -> Void
    let onSettingsTap: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Address
            if let addr = address {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(addr)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }
            }

            // Overlapping zones
            if hasOverlappingZones {
                Button(action: onOverlappingZonesTap) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.orange)
                        Text("\(overlappingZoneCount) overlapping zones")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onRefresh) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }

                Spacer()

                Button(action: onSettingsTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
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
                            Text("Multi Permit Zone")
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
    @State private var showTechnicalDetails = false

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
