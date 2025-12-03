import SwiftUI
import MapKit

/// Full-screen view showing active parking session with timer and controls
struct ActiveParkingView: View {
    let session: ParkingSession
    let userLocation: CLLocationCoordinate2D?
    let onDismiss: () -> Void
    let onEndParking: () async -> Void

    @State private var currentTime = Date()
    @State private var isEndingParking = false
    @Environment(\.colorScheme) private var colorScheme

    // Timer to update the countdown
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Distance to parked car in meters (nil if user location unavailable)
    private var distanceToParkedCar: Double? {
        guard let userLoc = userLocation else { return nil }
        let userCLLocation = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        let parkedLocation = CLLocation(
            latitude: session.location.coordinate.latitude,
            longitude: session.location.coordinate.longitude
        )
        return userCLLocation.distance(from: parkedLocation)
    }

    /// Whether to show directions button (hide if within 40m)
    private var shouldShowDirections: Bool {
        guard let distance = distanceToParkedCar else { return true }
        return distance > 40  // Hide if within 40 meters
    }

    /// Apple Maps URL for sharing
    private var shareURL: URL {
        let coordinate = session.location.coordinate
        return URL(string: "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Parked%20Car")!
    }

    /// Share message with parking details
    private var shareMessage: String {
        let address = session.location.address ?? "parking spot"
        let rules = session.rules.map { $0.description }.joined(separator: "\n• ")

        var message = "📍 I'm parked at: \(address)\n"
        message += "\nZone: \(session.zoneName)"

        if !session.rules.isEmpty {
            message += "\n\nParking Rules:\n• \(rules)"
        }

        if let deadline = session.parkUntil {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            message += "\n\n⏰ Must move by: \(formatter.string(from: deadline))"
        }

        return message
    }

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
                    }
                    .padding(.bottom, 20)
                }

                // Action buttons at bottom (outside ScrollView)
                VStack(spacing: 12) {
                    // Map navigation buttons (conditionally shown)
                    if shouldShowDirections {
                        HStack(spacing: 12) {
                            // Apple Maps button
                            Button {
                                openInAppleMaps()
                            } label: {
                                HStack {
                                    Image(systemName: "map.fill")
                                    Text("Apple Maps")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            // Google Maps button
                            Button {
                                openInGoogleMaps()
                            } label: {
                                HStack {
                                    Image(systemName: "map.circle.fill")
                                    Text("Google Maps")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                    }

                    // Share Location button
                    ShareLink(item: shareURL, subject: Text("My Parking Location"), message: Text(shareMessage)) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Location")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
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
                .padding(.bottom, 20)
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

    // MARK: - Map Navigation

    private func openInAppleMaps() {
        let coordinate = session.location.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = session.location.address ?? "Parked Car"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private func openInGoogleMaps() {
        let coordinate = session.location.coordinate
        // Google Maps URL scheme for directions
        let urlString = "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=walking"

        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            // Google Maps app is installed
            UIApplication.shared.open(url)
        } else {
            // Fallback to Google Maps web
            let webURLString = "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=walking"
            if let webURL = URL(string: webURLString) {
                UIApplication.shared.open(webURL)
            }
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
                    Text(formatDeadlineWithSmartDate(deadline))
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

    /// Format deadline with smart date logic (removes "tomorrow" when obvious)
    private func formatDeadlineWithSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            // Today: just show time
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            // Tomorrow: check if current time is later than deadline time
            let nowComponents = calendar.dateComponents([.hour, .minute], from: currentTime)
            let deadlineComponents = calendar.dateComponents([.hour, .minute], from: date)
            let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
            let deadlineMinutes = (deadlineComponents.hour ?? 0) * 60 + (deadlineComponents.minute ?? 0)

            formatter.timeStyle = .short

            if nowMinutes > deadlineMinutes {
                // Current time is later than deadline time - tomorrow is obvious, just show time
                return formatter.string(from: date)
            } else {
                // Current time is earlier - include "Tomorrow" for clarity
                return "Tomorrow \(formatter.string(from: date))"
            }
        } else {
            // Further out: show day name and time
            formatter.dateFormat = "EEE h:mm a"
            return formatter.string(from: date)
        }
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
                .fontWeight(.semibold)

            ForEach(rules) { rule in
                RuleRow(rule: rule)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Rule Row

private struct RuleRow: View {
    let rule: SessionRule

    /// Icon for rule type
    private var ruleIcon: String {
        switch rule.type {
        case .streetCleaning:
            return "wind"
        case .timeLimit:
            return "clock"
        case .enforcement:
            return "parkingsign"
        case .meter:
            return "dollarsign.circle"
        case .noParking:
            return "nosign"
        }
    }

    /// Color for rule type
    private var ruleColor: Color {
        switch rule.type {
        case .noParking, .streetCleaning:
            return .red
        case .timeLimit:
            return .orange
        case .enforcement:
            return .blue
        case .meter:
            return .green
        }
    }

    /// Title for rule type
    private var ruleTitle: String {
        switch rule.type {
        case .streetCleaning:
            return "Street Cleaning"
        case .timeLimit:
            return "Time Limit"
        case .enforcement:
            return "Enforcement"
        case .meter:
            return "Paid Parking"
        case .noParking:
            return "No Parking"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack(spacing: 10) {
                Image(systemName: ruleIcon)
                    .font(.body)
                    .foregroundColor(ruleColor)
                    .frame(width: 24)

                Text(ruleTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                // Show deadline badge if applicable
                if let deadline = rule.deadline {
                    Text(formatDeadline(deadline))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(urgencyColor(for: deadline))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(urgencyColor(for: deadline).opacity(0.15))
                        .cornerRadius(6)
                }
            }

            // Description
            Text(rule.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func urgencyColor(for deadline: Date) -> Color {
        let timeRemaining = deadline.timeIntervalSince(Date())
        if timeRemaining <= 0 {
            return .red
        } else if timeRemaining < 900 { // 15 minutes
            return .orange
        } else if timeRemaining < 3600 { // 1 hour
            return .yellow
        } else {
            return .green
        }
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
            zoneType: .residentialPermit,
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
        userLocation: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195),  // 100m away
        onDismiss: {},
        onEndParking: {}
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
            zoneType: .residentialPermit,
            rules: [
                SessionRule(
                    type: .timeLimit,
                    description: "2-hour limit",
                    deadline: Date().addingTimeInterval(-300) // Expired 5 min ago
                )
            ]
        ),
        userLocation: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),  // At car (< 40m)
        onDismiss: {},
        onEndParking: {}
    )
}
