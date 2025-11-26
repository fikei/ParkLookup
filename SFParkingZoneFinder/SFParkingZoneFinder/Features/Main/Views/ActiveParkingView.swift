import SwiftUI
import MapKit

/// Full-screen view showing active parking session with timer and controls
struct ActiveParkingView: View {
    let session: ParkingSession
    let onDismiss: () -> Void
    let onEndParking: () async -> Void
    let onGetDirections: () -> Void

    @State private var currentTime = Date()
    @State private var isEndingParking = false
    @Environment(\.colorScheme) private var colorScheme

    // Timer to update the countdown
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator for swipe-down gesture
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 24) {
                        // Status icon and title
                        VStack(spacing: 12) {
                            Image(systemName: "parkingsign.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                                .symbolRenderingMode(.hierarchical)

                            Text("Parked")
                                .font(.system(size: 32, weight: .bold))

                            Text(session.location.address ?? session.zoneName)
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)

                        // Countdown timer (if deadline exists)
                        if let deadline = session.parkUntil {
                            CountdownCard(
                                deadline: deadline,
                                currentTime: currentTime
                            )
                            .padding(.horizontal)
                        }

                        // Parking rules
                        if !session.rules.isEmpty {
                            RulesCard(rules: session.rules)
                                .padding(.horizontal)
                        }

                        // Action buttons
                        VStack(spacing: 12) {
                            // Get Directions button
                            Button {
                                onGetDirections()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    Text("Directions to My Car")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            // End Parking button
                            Button {
                                Task {
                                    isEndingParking = true
                                    await onEndParking()
                                    isEndingParking = false
                                }
                            } label: {
                                HStack {
                                    if isEndingParking {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .red))
                                    } else {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("End Parking Session")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                            }
                            .disabled(isEndingParking)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Parking duration
                        VStack(spacing: 4) {
                            Text("Parked Since")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatTime(session.startTime))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(formatDuration(session.duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Helper Methods

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Countdown Card

struct CountdownCard: View {
    let deadline: Date
    let currentTime: Date

    private var timeRemaining: TimeInterval {
        deadline.timeIntervalSince(currentTime)
    }

    private var hasExpired: Bool {
        timeRemaining <= 0
    }

    private var urgencyColor: Color {
        if hasExpired {
            return .red
        } else if timeRemaining < 900 { // 15 minutes
            return .orange
        } else if timeRemaining < 3600 { // 1 hour
            return .yellow
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: hasExpired ? "exclamationmark.triangle.fill" : "clock.fill")
                    .font(.title2)
                    .foregroundColor(urgencyColor)

                Text(hasExpired ? "Time Expired!" : "Move By")
                    .font(.headline)

                Spacer()
            }

            if hasExpired {
                Text("Move your car now to avoid a ticket")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(formatDeadline(deadline))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(urgencyColor)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatTimeRemaining(timeRemaining))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(urgencyColor.opacity(0.1))
        .cornerRadius(16)
    }

    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Rules Card

struct RulesCard: View {
    let rules: [SessionRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parking Rules")
                .font(.headline)

            ForEach(rules) { rule in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: rule.type.iconName)
                        .font(.body)
                        .foregroundColor(colorForRule(rule.type))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.description)
                            .font(.subheadline)

                        if let deadline = rule.deadline {
                            Text("Until \(formatDeadline(deadline))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func colorForRule(_ type: SessionRuleType) -> Color {
        switch type {
        case .timeLimit: return .orange
        case .streetCleaning: return .red
        case .enforcement: return .yellow
        case .meter: return .blue
        case .noParking: return .red
        }
    }

    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Active Session") {
    ActiveParkingView(
        session: ParkingSession(
            location: ParkingLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                address: "123 Mission St"
            ),
            zoneName: "Zone Q",
            zoneType: .residential,
            rules: [
                SessionRule(
                    type: .timeLimit,
                    description: "2-hour limit for non-permit holders",
                    deadline: Date().addingTimeInterval(3600) // 1 hour from now
                ),
                SessionRule(
                    type: .enforcement,
                    description: "Enforced Mon-Fri, 8 AM - 6 PM",
                    deadline: nil
                )
            ]
        ),
        onDismiss: {},
        onEndParking: {},
        onGetDirections: {}
    )
}

#Preview("Expired") {
    ActiveParkingView(
        session: ParkingSession(
            location: ParkingLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                address: "123 Mission St"
            ),
            zoneName: "Zone Q",
            zoneType: .residential,
            rules: [
                SessionRule(
                    type: .timeLimit,
                    description: "2-hour limit",
                    deadline: Date().addingTimeInterval(-300) // Expired 5 min ago
                )
            ]
        ),
        onDismiss: {},
        onEndParking: {},
        onGetDirections: {}
    )
}
