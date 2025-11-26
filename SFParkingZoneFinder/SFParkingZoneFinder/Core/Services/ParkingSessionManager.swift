import Foundation
import CoreLocation
import Combine
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "ParkingSession")

protocol ParkingSessionManagerProtocol {
    var activeSession: ParkingSession? { get }
    var activeSessionPublisher: AnyPublisher<ParkingSession?, Never> { get }
    var sessionHistory: [ParkingSession] { get }

    func startSession(
        location: CLLocationCoordinate2D,
        address: String?,
        zoneName: String,
        zoneType: ZoneType,
        rules: [SessionRule]
    ) async
    func endSession() async
    func getActiveSession() -> ParkingSession?
    func loadSessionHistory() -> [ParkingSession]
}

@MainActor
final class ParkingSessionManager: ObservableObject, ParkingSessionManagerProtocol {

    // MARK: - Published Properties

    @Published private(set) var activeSession: ParkingSession?
    @Published private(set) var sessionHistory: [ParkingSession] = []

    var activeSessionPublisher: AnyPublisher<ParkingSession?, Never> {
        $activeSession.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let notificationService: NotificationServiceProtocol

    // MARK: - Storage Keys

    private let activeSessionKey = "activeSession"
    private let sessionHistoryKey = "sessionHistory"
    private let maxHistoryCount = 50

    // MARK: - Initialization

    init(notificationService: NotificationServiceProtocol = NotificationService()) {
        self.notificationService = notificationService
        loadActiveSession()
        loadSessionHistoryFromStorage()
    }

    // MARK: - Session Management

    func startSession(
        location: CLLocationCoordinate2D,
        address: String?,
        zoneName: String,
        zoneType: ZoneType,
        rules: [SessionRule]
    ) async {
        logger.info("Starting parking session at \(zoneName)")

        // End any existing active session first
        if activeSession != nil {
            await endSession()
        }

        // Create new session
        let session = ParkingSession(
            startTime: Date(),
            location: ParkingLocation(coordinate: location, address: address),
            zoneName: zoneName,
            zoneType: zoneType,
            rules: rules,
            isActive: true
        )

        // Save as active session
        activeSession = session
        saveActiveSession()

        // Schedule notifications
        await notificationService.scheduleSessionNotifications(for: session)

        logger.info("Parking session started: \(session.id)")
    }

    func endSession() async {
        logger.info("Ending parking session")

        guard var session = activeSession else {
            logger.warning("No active session to end")
            return
        }

        // Cancel notifications
        notificationService.cancelNotifications(for: session.id)

        // Mark session as ended
        session.endTime = Date()
        session.isActive = false

        // Add to history
        addToHistory(session)

        // Clear active session
        activeSession = nil
        clearActiveSession()

        logger.info("Parking session ended: \(session.id)")
    }

    func getActiveSession() -> ParkingSession? {
        activeSession
    }

    func loadSessionHistory() -> [ParkingSession] {
        sessionHistory
    }

    // MARK: - Persistence

    private func saveActiveSession() {
        guard let session = activeSession else {
            clearActiveSession()
            return
        }

        if let encoded = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(encoded, forKey: activeSessionKey)
            logger.debug("Active session saved")
        } else {
            logger.error("Failed to encode active session")
        }
    }

    private func clearActiveSession() {
        UserDefaults.standard.removeObject(forKey: activeSessionKey)
        logger.debug("Active session cleared")
    }

    private func loadActiveSession() {
        guard let data = UserDefaults.standard.data(forKey: activeSessionKey),
              let session = try? JSONDecoder().decode(ParkingSession.self, from: data) else {
            logger.debug("No active session to load")
            return
        }

        // Check if session is still valid (not expired more than 1 hour ago)
        if let deadline = session.parkUntil {
            let hourPastDeadline = deadline.addingTimeInterval(3600)
            if Date() > hourPastDeadline {
                logger.info("Active session expired - clearing")
                clearActiveSession()
                return
            }
        }

        activeSession = session
        logger.info("Loaded active session: \(session.id)")
    }

    private func addToHistory(_ session: ParkingSession) {
        var history = sessionHistory

        // Add new session at beginning
        history.insert(session, at: 0)

        // Trim to max count
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }

        sessionHistory = history
        saveHistoryToStorage()
    }

    private func saveHistoryToStorage() {
        if let encoded = try? JSONEncoder().encode(sessionHistory) {
            UserDefaults.standard.set(encoded, forKey: sessionHistoryKey)
            logger.debug("Session history saved (\(sessionHistory.count) sessions)")
        } else {
            logger.error("Failed to encode session history")
        }
    }

    private func loadSessionHistoryFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: sessionHistoryKey),
              let history = try? JSONDecoder().decode([ParkingSession].self, from: data) else {
            logger.debug("No session history to load")
            return
        }

        sessionHistory = history
        logger.info("Loaded \(history.count) sessions from history")
    }
}
