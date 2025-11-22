import SwiftUI

/// Primary text-first view showing parking zone status and rules
struct MainResultView: View {
    @StateObject private var viewModel = MainResultViewModel()
    @State private var showingFullRules = false
    @State private var showingOverlappingZones = false
    @State private var showingExpandedMap = false
    @State private var showingSettings = false

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
                        validityStatus: viewModel.validityStatus,
                        applicablePermits: viewModel.applicablePermits
                    )

                    // Rules Summary
                    RulesSummaryView(
                        summaryLines: viewModel.ruleSummaryLines,
                        warnings: viewModel.warnings,
                        onViewFullRules: { showingFullRules = true }
                    )

                    // Overlapping zones indicator
                    if viewModel.hasOverlappingZones {
                        OverlappingZonesButton(
                            zoneCount: viewModel.overlappingZones.count,
                            onTap: { showingOverlappingZones = true }
                        )
                    }

                    // Additional info (address, refresh, report, settings)
                    AdditionalInfoView(
                        address: viewModel.currentAddress,
                        lastUpdated: viewModel.lastUpdated,
                        confidence: viewModel.lookupConfidence,
                        onRefresh: { viewModel.refreshLocation() },
                        onReportIssue: { viewModel.reportIssue() },
                        onSettings: { showingSettings = true }
                    )
                }
                .padding()
            }

            // Floating Map (top right)
            if viewModel.showFloatingMap && viewModel.error == nil && !viewModel.isLoading {
                VStack {
                    HStack {
                        Spacer()
                        FloatingMapView(
                            coordinate: viewModel.currentCoordinate,
                            zoneName: viewModel.zoneName,
                            onTap: { showingExpandedMap = true }
                        )
                        .padding(.trailing, 16)
                        .padding(.top, 60)
                    }
                    Spacer()
                }
            }

            // Loading overlay
            if viewModel.isLoading {
                LoadingOverlay()
            }

            // Error state
            if let error = viewModel.error {
                ErrorView(error: error) {
                    viewModel.refreshLocation()
                }
            }
        }
        .onAppear {
            viewModel.onAppear()
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
                zoneName: viewModel.zoneName
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
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Finding your zone...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)

            if error == .locationPermissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
