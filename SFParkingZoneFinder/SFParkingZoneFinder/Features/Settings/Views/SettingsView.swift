import SwiftUI

/// Main Settings screen
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
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
                Section(header: Text("Map")) {
                    Toggle("Show Floating Map", isOn: $viewModel.showFloatingMap)

                    Picker("Map Position", selection: $viewModel.mapPosition) {
                        ForEach(MapPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
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
