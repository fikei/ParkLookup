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
                Section(header: Text("Map"), footer: Text("Parking meters show individual meter locations on the map. Paid parking zones are always visible.")) {
                    Toggle("Show Parking Meters", isOn: $viewModel.showParkingMeters)
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
                        footer: Text("Control which parking data layers are displayed on the map. Zone overlays show parking zones, blockface overlays show street-level parking segments (experimental).")
                    ) {
                        Toggle("Zone Overlays", isOn: $devSettings.showZoneOverlays)
                            .onChange(of: devSettings.showZoneOverlays) { _, isEnabled in
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }

                        Toggle("Blockface Overlays (PoC)", isOn: $devSettings.showBlockfaceOverlays)
                            .onChange(of: devSettings.showBlockfaceOverlays) { _, isEnabled in
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }

                        Text("Use the developer overlay on the map to fine-tune overlay appearance and behavior.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
