import SwiftUI

/// Main Settings screen
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var devSettings = DeveloperSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddPermit = false
    @State private var showingPrivacyPolicy = false
    @State private var versionTapCount = 0

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Permits Section
                Section(header: Text("My Permits"), footer: permitsFooter) {
                    ForEach(viewModel.permits) { permit in
                        PermitRow(
                            permit: permit,
                            isPrimary: permit.isPrimary,
                            onSetPrimary: { viewModel.setPrimaryPermit(permit) }
                        )
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let permit = viewModel.permits[index]
                            viewModel.removePermit(permit)
                        }
                    }

                    Button {
                        showingAddPermit = true
                    } label: {
                        Label("Add Permit", systemImage: "plus.circle.fill")
                    }
                }

                // MARK: - Map Preferences Section
                Section(header: Text("Map"), footer: Text("Parking meters show individual meter locations on the map. Paid parking zones are always visible.")) {
                    Toggle("Show Floating Map", isOn: $viewModel.showFloatingMap)

                    Picker("Map Position", selection: $viewModel.mapPosition) {
                        ForEach(MapPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }

                    Toggle("Show Parking Meters", isOn: $viewModel.showParkingMeters)
                }

                // MARK: - Help Section
                Section(header: Text("Help & Support")) {
                    Button {
                        viewModel.openSupport()
                    } label: {
                        Label("Contact Support", systemImage: "envelope")
                            .foregroundColor(.primary)
                    }

                    Button {
                        viewModel.rateApp()
                    } label: {
                        Label("Rate This App", systemImage: "star")
                            .foregroundColor(.primary)
                    }
                }

                // MARK: - About Section
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTapCount += 1
                        print("🔧 DEBUG: Version tap count: \(versionTapCount)/5")
                        if versionTapCount >= 5 {
                            devSettings.developerModeUnlocked = true
                            print("✅ DEBUG: Developer mode UNLOCKED! Value: \(devSettings.developerModeUnlocked)")
                            versionTapCount = 0
                            // Haptic feedback
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                    }

                    HStack {
                        Text("Data Version")
                        Spacer()
                        Text(viewModel.dataVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Data Source")
                        Spacer()
                        Text(viewModel.dataSourceAttribution)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    Button {
                        showingPrivacyPolicy = true
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Debug Section
                #if DEBUG
                Section(header: Text("Debug")) {
                    Button("Reset Onboarding") {
                        viewModel.resetOnboarding()
                    }
                    .foregroundColor(.red)
                }
                #endif

                // MARK: - Developer Settings Sections (Hidden)
                if devSettings.developerModeUnlocked {
                    // Simplification Algorithms
                    Section(header: Text("Display Simplification"), footer: Text(DeveloperSettings.SettingInfo.douglasPeucker)) {
                        Toggle("Douglas-Peucker", isOn: $devSettings.useDouglasPeucker)
                        if devSettings.useDouglasPeucker {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tolerance: \(String(format: "%.5f", devSettings.douglasPeuckerTolerance))° (~\(Int(devSettings.douglasPeuckerTolerance * 111000))m)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(
                                    value: $devSettings.douglasPeuckerTolerance,
                                    in: 0.00001...0.001,
                                    step: 0.00001
                                )
                            }
                        }

                        Toggle("Grid Snapping", isOn: $devSettings.useGridSnapping)
                        if devSettings.useGridSnapping {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Grid: \(String(format: "%.5f", devSettings.gridSnapSize))° (~\(Int(devSettings.gridSnapSize * 111000))m)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(
                                    value: $devSettings.gridSnapSize,
                                    in: 0.00001...0.0005,
                                    step: 0.00001
                                )
                            }
                        }

                        Toggle("Convex Hull", isOn: $devSettings.useConvexHull)
                    }

                    // Curve Handling
                    Section(header: Text("Curve Handling"), footer: Text(DeveloperSettings.SettingInfo.preserveCurves)) {
                        Toggle("Preserve Curves", isOn: $devSettings.preserveCurves)
                        if devSettings.preserveCurves {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Angle Threshold: \(Int(devSettings.curveAngleThreshold))°")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(
                                    value: $devSettings.curveAngleThreshold,
                                    in: 5...45,
                                    step: 1
                                )
                            }
                        }
                    }

                    // Debug Visualization
                    Section(header: Text("Debug Visualization"), footer: Text(devSettings.simplificationDescription)) {
                        Toggle("Show Lookup Boundaries", isOn: $devSettings.showLookupBoundaries)
                        Toggle("Show Original Overlay", isOn: $devSettings.showOriginalOverlay)
                        Toggle("Show Vertex Counts", isOn: $devSettings.showVertexCounts)
                    }

                    // Performance Logging
                    Section(header: Text("Performance Logging")) {
                        Toggle("Log Simplification Stats", isOn: $devSettings.logSimplificationStats)
                        Toggle("Log Lookup Performance", isOn: $devSettings.logLookupPerformance)
                    }

                    // Actions
                    Section {
                        Button("Reset to Defaults") {
                            devSettings.resetToDefaults()
                        }
                        .foregroundColor(.orange)

                        Button("Hide Developer Settings") {
                            devSettings.developerModeUnlocked = false
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddPermit) {
                AddPermitView { area in
                    viewModel.addPermit(area: area)
                }
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
        }
    }

    @ViewBuilder
    private var permitsFooter: some View {
        if viewModel.permits.isEmpty {
            Text("Add your parking permits to see if you can park in each zone.")
        } else {
            EmptyView()
        }
    }
}

// MARK: - Permit Row

struct PermitRow: View {
    let permit: ParkingPermit
    let isPrimary: Bool
    let onSetPrimary: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(permit.displayName)
                        .font(.body)

                    if isPrimary {
                        Text("Primary")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .cornerRadius(4)
                    }
                }

                if let hint = PermitAreas.neighborhoodHint(for: permit.area) {
                    Text(hint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if permit.isExpired {
                    Text("Expired")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if permit.shouldWarnExpiration, let days = permit.daysUntilExpiration {
                    Text("Expires in \(days) days")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if !isPrimary {
                Button {
                    onSetPrimary()
                } label: {
                    Text("Set Primary")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
