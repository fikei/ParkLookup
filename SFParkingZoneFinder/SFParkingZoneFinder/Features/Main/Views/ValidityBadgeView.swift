import SwiftUI

/// Color-coded badge showing permit validity status
/// Uses shapes + text for color-blind accessibility
struct ValidityBadgeView: View {
    let status: PermitValidityStatus
    let permits: [ParkingPermit]
    /// When true, uses white styling for display on colored backgrounds
    var onColoredBackground: Bool = false
    /// Time limit in minutes for non-permit holders (for "Park until" display)
    var timeLimitMinutes: Int? = nil

    // Enforcement hours for "Park Until" calculation
    var enforcementStartTime: TimeOfDay? = nil
    var enforcementEndTime: TimeOfDay? = nil
    var enforcementDays: [DayOfWeek]? = nil

    /// Whether we're currently outside enforcement hours
    private var isOutsideEnforcement: Bool {
        guard let startTime = enforcementStartTime, let endTime = enforcementEndTime else {
            return false
        }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.totalMinutes
        let endMinutes = endTime.totalMinutes

        // Check if today is an enforcement day
        if let days = enforcementDays, !days.isEmpty,
           let weekday = components.weekday,
           let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
            if !days.contains(dayOfWeek) {
                return true // Not an enforcement day
            }
        }

        // Check if outside enforcement hours
        return currentMinutes < startMinutes || currentMinutes >= endMinutes
    }

    /// Calculate "Park until" time based on enforcement hours and time limit
    /// Shows for both .invalid (wrong permit) and .noPermitSet (no permit configured)
    private var parkUntilText: String? {
        guard (status == .invalid || status == .noPermitSet),
              let _ = timeLimitMinutes else { return nil }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        // Check if enforcement is currently active
        if let startTime = enforcementStartTime, let endTime = enforcementEndTime {
            let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let startMinutes = startTime.totalMinutes
            let endMinutes = endTime.totalMinutes

            // Check if today is an enforcement day
            var isEnforcementDay = true
            var currentDayOfWeek: DayOfWeek?
            if let days = enforcementDays, !days.isEmpty,
               let weekday = components.weekday,
               let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
                currentDayOfWeek = dayOfWeek
                isEnforcementDay = days.contains(dayOfWeek)
            }

            if isEnforcementDay {
                if currentMinutes < startMinutes {
                    // Before enforcement starts today
                    return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: now)
                } else if currentMinutes >= endMinutes {
                    // After enforcement ends today - find next enforcement start
                    return findNextEnforcementStart(from: now, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
                } else {
                    // During enforcement - normal time limit applies
                    return calculateTimeLimitEnd(from: now, endTime: endTime)
                }
            } else {
                // Not an enforcement day - find next enforcement start
                return findNextEnforcementStart(from: now, startTime: startTime, days: enforcementDays, currentDay: currentDayOfWeek)
            }
        }

        // No enforcement hours defined - just use time limit
        return calculateTimeLimitEnd(from: now, endTime: nil)
    }

    /// Format "Park until" with day if not today
    private func formatParkUntil(hour: Int, minute: Int, on date: Date) -> String {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else {
            return "PARK UNTIL \(hour):\(String(format: "%02d", minute))"
        }

        let formatter = DateFormatter()
        if calendar.isDateInToday(targetDate) {
            formatter.dateFormat = "h:mm a"
            return "PARK UNTIL \(formatter.string(from: targetDate))"
        } else {
            formatter.dateFormat = "EEE h:mm a"
            return "PARK UNTIL \(formatter.string(from: targetDate))"
        }
    }

    /// Find the next enforcement start time
    private func findNextEnforcementStart(from now: Date, startTime: TimeOfDay, days: [DayOfWeek]?, currentDay: DayOfWeek?) -> String {
        let calendar = Calendar.current

        // If no specific days, enforcement is daily - next enforcement is tomorrow
        guard let enforcementDays = days, !enforcementDays.isEmpty, let current = currentDay else {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: tomorrow)
            }
            return "PARK UNTIL TOMORROW"
        }

        // Find the next enforcement day
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: current) else {
            return "PARK UNTIL TOMORROW"
        }

        // Look for the next enforcement day (starting from tomorrow)
        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if enforcementDays.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: now) {
                    return formatParkUntil(hour: startTime.hour, minute: startTime.minute, on: targetDate)
                }
                break
            }
        }

        return "PARK UNTIL TOMORROW"
    }

    /// Calculate when time limit expires (capped at enforcement end if applicable)
    private func calculateTimeLimitEnd(from now: Date, endTime: TimeOfDay?) -> String {
        guard let limit = timeLimitMinutes else { return "CHECK POSTED SIGNS" }

        let calendar = Calendar.current
        let parkUntil = now.addingTimeInterval(TimeInterval(limit * 60))

        // Cap at enforcement end time if provided
        if let end = endTime,
           let endDate = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: now) {
            let actualEnd = min(parkUntil, endDate)
            return formatParkUntil(hour: calendar.component(.hour, from: actualEnd),
                                   minute: calendar.component(.minute, from: actualEnd),
                                   on: actualEnd)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "PARK UNTIL \(formatter.string(from: parkUntil))"
    }

    /// Display text - shows "Park until" for invalid status when time limit available
    private var displayText: String {
        if let parkUntil = parkUntilText {
            return parkUntil
        }
        return status.displayText
    }

    var body: some View {
        HStack(spacing: 12) {
            // Shape indicator (accessibility: not color-only)
            // Show clock icon when displaying "Park until" time
            Image(systemName: parkUntilText != nil ? "clock" : status.iconName)
                .font(.system(size: 20, weight: .semibold))

            // Text
            Text(displayText)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(badgeBackground)
        .foregroundColor(badgeForeground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeBorder, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Badge Colors

    private var badgeBackground: Color {
        if onColoredBackground {
            // White semi-transparent background on green card
            return Color.white.opacity(0.25)
        }
        return statusColor.opacity(0.15)
    }

    private var badgeForeground: Color {
        if onColoredBackground {
            return .white
        }
        return statusColor
    }

    private var badgeBorder: Color {
        if onColoredBackground {
            return Color.white.opacity(0.5)
        }
        return statusColor
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        Color.forValidityStatus(status)
    }

    private var accessibilityText: String {
        switch status {
        case .valid:
            let permitAreas = permits.map { $0.area }.joined(separator: ", ")
            return "Permit status: Valid. Your Area \(permitAreas) permit is valid at this location."
        case .invalid:
            return "Permit status: Not valid. Your permit is not valid at this location."
        case .conditional:
            return "Permit status: Conditional. Check the rules below for restrictions."
        case .noPermitRequired:
            return "No permit required. Anyone can park here within posted limits."
        case .multipleApply:
            let permitAreas = permits.map { $0.area }.joined(separator: ", ")
            return "Multiple permits valid. Your permits for Areas \(permitAreas) are all valid here."
        case .noPermitSet:
            return "Permit required. Add a permit in settings to check validity."
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ValidityBadgeView(status: .valid, permits: [
            ParkingPermit(type: .residential, area: "Q")
        ])

        ValidityBadgeView(status: .invalid, permits: [])

        ValidityBadgeView(status: .conditional, permits: [])

        ValidityBadgeView(status: .noPermitRequired, permits: [])

        ValidityBadgeView(status: .multipleApply, permits: [
            ParkingPermit(type: .residential, area: "Q"),
            ParkingPermit(type: .residential, area: "R")
        ])
    }
    .padding()
}
