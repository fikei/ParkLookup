import SwiftUI
import CoreLocation

/// Explains why location is needed and requests permission
struct LocationPermissionView: View {
    let locationStatus: CLAuthorizationStatus
    let isRequesting: Bool
    let onRequestPermission: () -> Void
    let onContinue: () -> Void

    private var isAuthorized: Bool {
        locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
    }

    private var isDenied: Bool {
        locationStatus == .denied || locationStatus == .restricted
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: statusIcon)
                    .font(.system(size: 56))
                    .foregroundColor(statusColor)
            }
            .padding(.bottom, 32)

            // Title
            Text(statusTitle)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Description
            Text(statusDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("Your location is only used on-device and never shared")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Action Button
            if isAuthorized {
                Button(action: onContinue) {
                    Label("Continue", systemImage: "arrow.right")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
            } else if isDenied {
                VStack(spacing: 12) {
                    Button(action: openSettings) {
                        Text("Open Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }

                    Button(action: onContinue) {
                        Text("Continue Without Location")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                Button(action: onRequestPermission) {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    } else {
                        Text("Enable Location")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                }
                .disabled(isRequesting)
                .padding(.horizontal, 24)
            }

            Spacer()
                .frame(height: 32)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Computed Properties

    private var statusIcon: String {
        if isAuthorized {
            return "location.fill.viewfinder"
        } else if isDenied {
            return "location.slash.fill"
        } else {
            return "location.circle.fill"
        }
    }

    private var statusColor: Color {
        if isAuthorized {
            return .green
        } else if isDenied {
            return .red
        } else {
            return .accentColor
        }
    }

    private var statusTitle: String {
        if isAuthorized {
            return "Location Enabled!"
        } else if isDenied {
            return "Location Disabled"
        } else {
            return "Enable Location"
        }
    }

    private var statusDescription: String {
        if isAuthorized {
            return "We can now find parking zones near you and check your permit validity."
        } else if isDenied {
            return "Location access was denied. You can enable it in Settings to use all features."
        } else {
            return "We need your location to find which parking zone you're in and check if your permit is valid."
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    LocationPermissionView(
        locationStatus: .notDetermined,
        isRequesting: false,
        onRequestPermission: {},
        onContinue: {}
    )
}
