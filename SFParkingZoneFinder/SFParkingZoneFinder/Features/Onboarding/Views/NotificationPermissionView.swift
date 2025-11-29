import SwiftUI
import UserNotifications

/// Explains why notifications are needed and requests permission
struct NotificationPermissionView: View {
    let notificationStatus: UNAuthorizationStatus
    let isRequesting: Bool
    let onRequestPermission: () -> Void
    let onContinue: () -> Void

    private var isAuthorized: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    private var isDenied: Bool {
        notificationStatus == .denied
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
                .padding(.bottom, 24)

            // Use cases
            VStack(alignment: .leading, spacing: 16) {
                NotificationUseCase(
                    icon: "timer",
                    title: "Parking Reminders",
                    description: "Get notified before your parking time expires"
                )

                NotificationUseCase(
                    icon: "car.fill",
                    title: "Active Session Alerts",
                    description: "Stay informed about your current parking status"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.orange)
                Text("Notifications are optional and can be disabled anytime")
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
                        Text("Continue Without Notifications")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    Button(action: onRequestPermission) {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor)
                                .cornerRadius(12)
                        } else {
                            Text("Enable Notifications")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(isRequesting)

                    Button(action: onContinue) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
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
            return "bell.badge.fill"
        } else if isDenied {
            return "bell.slash.fill"
        } else {
            return "bell.circle.fill"
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
            return "Notifications Enabled!"
        } else if isDenied {
            return "Notifications Disabled"
        } else {
            return "Stay Updated"
        }
    }

    private var statusDescription: String {
        if isAuthorized {
            return "You'll receive timely reminders about your parking sessions."
        } else if isDenied {
            return "Notification access was denied. You can enable it in Settings to receive parking reminders."
        } else {
            return "Get helpful reminders and alerts about your parking:"
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Notification Use Case

struct NotificationUseCase: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NotificationPermissionView(
        notificationStatus: .notDetermined,
        isRequesting: false,
        onRequestPermission: {},
        onContinue: {}
    )
}
