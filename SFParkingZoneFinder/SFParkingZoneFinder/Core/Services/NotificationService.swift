import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "Notifications")

protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func scheduleSessionNotifications(for session: ParkingSession) async
    func cancelNotifications(for sessionId: String)
    func cancelAllNotifications()
    func getNotificationSettings() async -> UNNotificationSettings
}

final class NotificationService: NotificationServiceProtocol {

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    func getNotificationSettings() async -> UNNotificationSettings {
        await center.notificationSettings()
    }

    // MARK: - Schedule Notifications

    func scheduleSessionNotifications(for session: ParkingSession) async {
        logger.info("Scheduling notifications for session: \(session.id)")

        guard let deadline = session.parkUntil else {
            logger.warning("No deadline for session \(session.id) - skipping notifications")
            return
        }

        // Check if notifications are enabled
        let settings = await getNotificationSettings()
        guard settings.authorizationStatus == .authorized else {
            logger.warning("Notifications not authorized - skipping")
            return
        }

        // Get enabled notification timings from UserDefaults
        let enabledTimings = getEnabledNotificationTimings()

        for timing in enabledTimings {
            let notificationDate = deadline.addingTimeInterval(timing.timeInterval)

            // Only schedule if in the future
            guard notificationDate > Date() else {
                logger.info("Skipping \(timing.displayName) - already passed")
                continue
            }

            let identifier = "\(session.id)_\(timing.rawValue)"

            let content = UNMutableNotificationContent()
            content.title = getTitle(for: timing)
            content.body = getBody(for: timing, session: session, deadline: deadline)
            content.sound = .default
            content.categoryIdentifier = "PARKING_ALERT"
            content.userInfo = [
                "sessionId": session.id,
                "timing": timing.rawValue,
                "latitude": session.location.latitude,
                "longitude": session.location.longitude
            ]

            // Create trigger
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: notificationDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                logger.info("Scheduled notification: \(identifier) at \(notificationDate)")
            } catch {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cancel Notifications

    func cancelNotifications(for sessionId: String) {
        logger.info("Cancelling notifications for session: \(sessionId)")

        // Cancel all notifications matching the session ID
        let identifiers = NotificationTiming.allCases.map { "\(sessionId)_\($0.rawValue)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAllNotifications() {
        logger.info("Cancelling all notifications")
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Helper Methods

    private func getEnabledNotificationTimings() -> [NotificationTiming] {
        // Check UserDefaults for enabled notifications
        // Default: all enabled
        var enabled: [NotificationTiming] = []

        for timing in NotificationTiming.allCases {
            let key = "notification_\(timing.rawValue)_enabled"
            let isEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            if isEnabled {
                enabled.append(timing)
            }
        }

        return enabled
    }

    private func getTitle(for timing: NotificationTiming) -> String {
        switch timing {
        case .oneHour:
            return "⏰ Move Your Car Soon"
        case .fifteenMinutes:
            return "⚠️ Move Your Car in 15 Minutes"
        case .atDeadline:
            return "🚨 Move Your Car Now!"
        }
    }

    private func getBody(
        for timing: NotificationTiming,
        session: ParkingSession,
        deadline: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let locationText = session.location.address ?? "\(session.zoneName)"
        let deadlineText = formatter.string(from: deadline)

        switch timing {
        case .oneHour:
            return "You need to move your car at \(locationText) by \(deadlineText)"
        case .fifteenMinutes:
            return "Your parking at \(locationText) expires at \(deadlineText)"
        case .atDeadline:
            return "Your parking time at \(locationText) has expired. Move your car to avoid a ticket."
        }
    }
}

// MARK: - Notification Settings Extension

extension UNNotificationSettings {
    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
}
