import SwiftUI

/// Main Settings screen
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var devSettings = DeveloperSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddPermit = false
    @State private var showingPrivacyPolicy = false

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
                Section(header: Text("Map"), footer: Text("Zone Areas display large parking zone polygons. Parking meters show individual meter locations on the map.")) {
                    Toggle("Show Zone Areas", isOn: $devSettings.showZonePolygons)
                    Toggle("Show Parking Meters", isOn: $viewModel.showParkingMeters)
                }

                // MARK: - Blockface Data Source Section
                Section(
                    header: Text("Parking Data"),
                    footer: Text("Choose which parking dataset to use. Multi-RPP includes improved handling for zones with multiple residential permits.")
                ) {
                    ForEach(BlockfaceDataSource.allCases, id: \.self) { dataSource in
                        Button {
                            devSettings.blockfaceDataSource = dataSource
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        } label: {
                            HStack {
                                Image(systemName: devSettings.blockfaceDataSource == dataSource ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(devSettings.blockfaceDataSource == dataSource ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dataSource.displayName)
                                        .foregroundColor(.primary)
                                    if dataSource == .multiRPP20251128 {
                                        Text("Recommended: Latest data with multi-zone support")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Legacy data")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                // MARK: - Parking Notifications Section
                Section(
                    header: Text("Parking Notifications"),
                    footer: Text("Receive alerts when parking at time-limited zones. Notifications remind you to move your car before time expires.")
                ) {
                    Toggle("Enable Notifications", isOn: $viewModel.notificationsEnabled)
                        .onChange(of: viewModel.notificationsEnabled) { _, newValue in
                            if newValue {
                                Task {
                                    await viewModel.requestNotificationPermission()
                                }
                            }
                        }

                    if viewModel.notificationsEnabled {
                        Toggle("1 Hour Before", isOn: $viewModel.notify1HourBefore)
                        Toggle("15 Minutes Before", isOn: $viewModel.notify15MinBefore)
                        Toggle("When Time Expires", isOn: $viewModel.notifyAtDeadline)
                    }
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

                // MARK: - Advanced Section
                Section(header: Text("Advanced")) {
                    Toggle("Developer Mode", isOn: $devSettings.developerModeUnlocked)
                        .onChange(of: devSettings.developerModeUnlocked) { _, isEnabled in
                            if isEnabled {
                                // Haptic feedback when enabled
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                print("✅ DEBUG: Developer mode enabled")
                            }
                        }

                    Text("Enable developer tools and overlay controls in the map view")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Map Overlays Section (Developer Mode Only)
                if devSettings.developerModeUnlocked {
                    Section(
                        header: Text("Map Overlays"),
                        footer: Text("Control which parking data layers are displayed on the map. Zone polygons show large zone areas, blockfaces show individual street segments.")
                    ) {
                        Toggle("Zone Polygons", isOn: $devSettings.showZonePolygons)
                            .onChange(of: devSettings.showZonePolygons) { _, isEnabled in
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }

                        Toggle("BlockFaces", isOn: $devSettings.showBlockfaceOverlays)
                            .onChange(of: devSettings.showBlockfaceOverlays) { _, isEnabled in
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                    }

                    // MARK: - Calculations Section (Developer Mode Only)
                    Section(
                        header: Text("Calculations"),
                        footer: Text("Choose which data source to use for parking calculations and card content. Changes take effect immediately.")
                    ) {
                        Button {
                            devSettings.useBlockfaceForFeatures = false
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        } label: {
                            HStack {
                                Image(systemName: devSettings.useBlockfaceForFeatures ? "circle" : "circle.inset.filled")
                                    .foregroundColor(devSettings.useBlockfaceForFeatures ? .secondary : .accentColor)
                                Text("Use Zone Polygons")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }

                        Button {
                            devSettings.useBlockfaceForFeatures = true
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        } label: {
                            HStack {
                                Image(systemName: devSettings.useBlockfaceForFeatures ? "circle.inset.filled" : "circle")
                                    .foregroundColor(devSettings.useBlockfaceForFeatures ? .accentColor : .secondary)
                                Text("Use BlockFaces")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }

                    // MARK: - Data Source Section (Developer Mode Only)
                    Section(
                        header: Text("Blockface Data Source"),
                        footer: Text("Select which blockface dataset to load. The multi-RPP version includes improved residential permit zone handling. App will reload data when changed.")
                    ) {
                        ForEach(BlockfaceDataSource.allCases, id: \.self) { dataSource in
                            Button {
                                devSettings.blockfaceDataSource = dataSource
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                            } label: {
                                HStack {
                                    Image(systemName: devSettings.blockfaceDataSource == dataSource ? "circle.inset.filled" : "circle")
                                        .foregroundColor(devSettings.blockfaceDataSource == dataSource ? .accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dataSource.displayName)
                                            .foregroundColor(.primary)
                                        if dataSource == .multiRPP20251128 {
                                            Text("New: Multi-zone permits, 670 consolidated")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
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

                // Developer overlay controls are now only accessible via the map view's developer panel
                // This keeps Settings clean and focused on user preferences
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
