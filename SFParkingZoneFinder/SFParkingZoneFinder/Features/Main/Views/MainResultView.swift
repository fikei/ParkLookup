import SwiftUI
import UIKit

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

/// Primary text-first view showing parking zone status and rules
struct MainResultView: View {
    @StateObject private var viewModel = MainResultViewModel()
    @State private var showingFullRules = false
    @State private var showingOverlappingZones = false
    @State private var showingExpandedMap = false
    @State private var showingSettings = false
    @State private var contentAppeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            // Main content
            ScrollView {
                VStack(spacing: 16) {
                    // Zone Status Card (prominent at top)
                    ZoneStatusCardView(
                        zoneName: viewModel.zoneName,
                        zoneType: viewModel.zoneType,
                        validityStatus: viewModel.validityStatus,
                        applicablePermits: viewModel.applicablePermits,
                        allValidPermitAreas: viewModel.allValidPermitAreas,
                        meteredSubtitle: viewModel.meteredSubtitle,
                        timeLimitMinutes: viewModel.timeLimitMinutes
                    )
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 20)

                    // Map Card (full-width below zone card)
                    if viewModel.error == nil && !viewModel.isLoading {
                        MapCardView(
                            coordinate: viewModel.currentCoordinate,
                            zoneName: viewModel.zoneName,
                            onTap: {
                                HapticFeedback.light()
                                showingExpandedMap = true
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Rules Summary
                    RulesSummaryView(
                        summaryLines: viewModel.ruleSummaryLines,
                        warnings: viewModel.warnings,
                        onViewFullRules: {
                            HapticFeedback.light()
                            showingFullRules = true
                        }
                    )
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 20)

                    // Overlapping zones indicator
                    if viewModel.hasOverlappingZones {
                        OverlappingZonesButton(
                            zoneCount: viewModel.overlappingZones.count,
                            onTap: {
                                HapticFeedback.light()
                                showingOverlappingZones = true
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Additional info (address, refresh, report, settings)
                    AdditionalInfoView(
                        address: viewModel.currentAddress,
                        lastUpdated: viewModel.lastUpdated,
                        confidence: viewModel.lookupConfidence,
                        onRefresh: {
                            HapticFeedback.medium()
                            viewModel.refreshLocation()
                        },
                        onReportIssue: {
                            HapticFeedback.light()
                            viewModel.reportIssue()
                        },
                        onSettings: {
                            HapticFeedback.selection()
                            showingSettings = true
                        }
                    )
                    .opacity(contentAppeared ? 1 : 0)
                }
                .padding()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: viewModel.hasOverlappingZones)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.error != nil)
        .onAppear {
            viewModel.onAppear()
            // Animate content in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.1)) {
                contentAppeared = true
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.zoneName) { _, _ in
            // Haptic when zone changes (user moved to new zone)
            if !viewModel.isLoading && viewModel.error == nil {
                HapticFeedback.success()
            }
        }
        .sheet(isPresented: $showingFullRules) {
            FullRulesSheet(
                zoneName: viewModel.zoneName,
                ruleSummaryLines: viewModel.ruleSummaryLines
            )
        }
        .sheet(isPresented: $showingOverlappingZones) {
            OverlappingZonesSheet(zones: viewModel.overlappingZones)
        }
        .sheet(isPresented: $showingExpandedMap) {
            ExpandedMapView(
                coordinate: viewModel.currentCoordinate,
                zoneName: viewModel.zoneName,
                validityStatus: viewModel.validityStatus,
                applicablePermits: viewModel.applicablePermits,
                allValidPermitAreas: viewModel.allValidPermitAreas,
                zones: viewModel.allLoadedZones,
                currentZoneId: viewModel.currentZoneId
            )
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - Overlapping Zones Button

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
            // Solid background for visibility
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated parking icon
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
            // Error icon with contextual color
            Image(systemName: error.iconName)
                .font(.system(size: 48))
                .foregroundColor(error.iconColor)

            // Error title
            Text(errorTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Error description
            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            // Action buttons
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

            // Technical details for data errors (debug builds)
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

// MARK: - Full Rules Sheet

struct FullRulesSheet: View {
    let zoneName: String
    let ruleSummaryLines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(zoneName)
                        .font(.title)
                        .fontWeight(.bold)

                    ForEach(Array(ruleSummaryLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1).")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(line)
                                .font(.body)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Full Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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
