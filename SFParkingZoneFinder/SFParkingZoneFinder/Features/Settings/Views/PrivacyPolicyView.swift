import SwiftUI

/// In-app privacy policy view
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy Policy")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Last updated: November 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Introduction
                    PolicySection(title: "Introduction") {
                        Text("SF Parking Zone Finder (\"the App\") is designed to help you determine parking permit requirements in San Francisco. This Privacy Policy explains how we collect, use, and protect your information.")
                    }

                    // Data We Collect
                    PolicySection(title: "Information We Collect") {
                        VStack(alignment: .leading, spacing: 12) {
                            PolicyBullet(
                                title: "Location Data",
                                description: "We access your device's location only when you actively use the App to check parking zones. Location data is processed on your device and is not transmitted to our servers."
                            )

                            PolicyBullet(
                                title: "Permit Information",
                                description: "Your parking permit areas are stored locally on your device using iOS secure storage. This data never leaves your device."
                            )

                            PolicyBullet(
                                title: "App Preferences",
                                description: "Settings like map preferences and onboarding status are stored locally on your device."
                            )
                        }
                    }

                    // How We Use Data
                    PolicySection(title: "How We Use Your Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your location is used solely to:")

                            BulletPoint("Determine which parking zone you are currently in")
                            BulletPoint("Check if your permits are valid for that zone")
                            BulletPoint("Display your position on the map")

                            Text("We do not:")
                                .padding(.top, 8)

                            BulletPoint("Track your location history")
                            BulletPoint("Share your location with third parties")
                            BulletPoint("Use your location for advertising")
                            BulletPoint("Store your location on any server")
                        }
                    }

                    // Data Storage
                    PolicySection(title: "Data Storage & Security") {
                        Text("All personal data (permits, preferences) is stored locally on your device using iOS secure storage mechanisms. Parking zone data is bundled with the App and sourced from official San Francisco government datasets (DataSF and SFMTA).")
                    }

                    // Third-Party Services
                    PolicySection(title: "Third-Party Services") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The App uses the following third-party services:")

                            BulletPoint("Apple Maps / MapKit for map display")
                            BulletPoint("Apple's Core Location for GPS positioning")

                            Text("These services are subject to Apple's privacy policy.")
                                .padding(.top, 4)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Data Retention
                    PolicySection(title: "Data Retention") {
                        Text("Since all data is stored locally on your device, you have full control over it. Deleting the App will remove all stored data. You can also reset your data through the App's settings.")
                    }

                    // Children's Privacy
                    PolicySection(title: "Children's Privacy") {
                        Text("The App does not knowingly collect information from children under 13. The App is intended for drivers who need to understand parking regulations.")
                    }

                    // Your Rights
                    PolicySection(title: "Your Rights") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You have the right to:")

                            BulletPoint("Access all data stored by the App (visible in Settings)")
                            BulletPoint("Delete your data by removing the App")
                            BulletPoint("Revoke location permissions in iOS Settings")
                            BulletPoint("Use the App without location access (with limited functionality)")
                        }
                    }

                    // Changes to Policy
                    PolicySection(title: "Changes to This Policy") {
                        Text("We may update this Privacy Policy from time to time. Any changes will be reflected in the \"Last updated\" date above. Continued use of the App after changes constitutes acceptance of the updated policy.")
                    }

                    // Contact
                    PolicySection(title: "Contact Us") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you have questions about this Privacy Policy, please contact us at:")

                            Link("support@sfparkingzone.app", destination: URL(string: "mailto:support@sfparkingzone.app")!)
                                .foregroundColor(.accentColor)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

private struct PolicyBullet: View {
    let title: String
    let description: String

    init(title: String, description: String) {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

private struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

// MARK: - Preview

#Preview {
    PrivacyPolicyView()
}
