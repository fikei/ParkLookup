import Foundation

/// Helper for calculating "Park Until" times based on ALL regulations
/// Considers time limits, street cleaning, metered enforcement, and permit enforcement
/// Works with data from both zones and blockfaces
struct ParkUntilCalculator {
    let timeLimitMinutes: Int?
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let enforcementDays: [DayOfWeek]?
    let validityStatus: PermitValidityStatus
    let allRegulations: [RegulationInfo]  // All regulations to consider

    /// Calculate when parking expires, considering ALL regulations
    /// Returns the earliest restriction (time limit, street cleaning, metered end, etc.)
    /// Returns nil if user has valid permit and no other restrictions apply
    func calculateParkUntil(at date: Date = Date()) -> ParkUntilDisplay? {
        var earliestRestriction: ParkUntilDisplay?
        var earliestDate: Date?

        let calendar = Calendar.current

        // 1. Check for upcoming street cleaning
        for regulation in allRegulations {
            if regulation.type == .streetCleaning || regulation.type == .towAway {
                if let nextOccurrence = findNextOccurrence(of: regulation, from: date) {
                    if earliestDate == nil || nextOccurrence < earliestDate! {
                        earliestDate = nextOccurrence
                        earliestRestriction = .restriction(
                            type: regulation.type == .streetCleaning ? "Street cleaning" : "Tow-away zone",
                            date: nextOccurrence
                        )
                    }
                }
            }
        }

        // 2. Check time limit (only for users without valid permits)
        if validityStatus == .invalid || validityStatus == .noPermitSet {
            if let limit = timeLimitMinutes {
                // Calculate when time limit expires
                if let startTime = enforcementStartTime, let endTime = enforcementEndTime {
                    // Time limit only applies during enforcement
                    let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
                    let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    let startMinutes = startTime.totalMinutes
                    let endMinutes = endTime.totalMinutes

                    var currentDayOfWeek: DayOfWeek?
                    var isEnforcementDay = true
                    if let days = enforcementDays, !days.isEmpty,
                       let weekday = components.weekday,
                       let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
                        currentDayOfWeek = dayOfWeek
                        isEnforcementDay = days.contains(dayOfWeek)
                    }

                    if isEnforcementDay && currentMinutes >= startMinutes && currentMinutes < endMinutes {
                        // During enforcement - calculate time limit end
                        let timeLimitEnd = date.addingTimeInterval(TimeInterval(limit * 60))
                        if earliestDate == nil || timeLimitEnd < earliestDate! {
                            earliestDate = timeLimitEnd
                            earliestRestriction = .timeLimit(date: timeLimitEnd)
                        }
                    } else {
                        // Outside enforcement - find when enforcement starts
                        let enforcementStartResult: ParkUntilDisplay
                        if isEnforcementDay && currentMinutes < startMinutes {
                            enforcementStartResult = .enforcementStart(time: startTime, date: date)
                        } else {
                            enforcementStartResult = findNextEnforcementStart(
                                from: date,
                                startTime: startTime,
                                days: enforcementDays,
                                currentDay: currentDayOfWeek
                            )
                        }
                        if let enforcementDate = enforcementStartResult.date {
                            if earliestDate == nil || enforcementDate < earliestDate! {
                                earliestDate = enforcementDate
                                earliestRestriction = enforcementStartResult
                            }
                        }
                    }
                } else {
                    // No enforcement hours - time limit always applies
                    let timeLimitEnd = date.addingTimeInterval(TimeInterval(limit * 60))
                    if earliestDate == nil || timeLimitEnd < earliestDate! {
                        earliestDate = timeLimitEnd
                        earliestRestriction = .timeLimit(date: timeLimitEnd)
                    }
                }
            }
        }

        // 3. Check for metered enforcement ending (user needs to move or pay again)
        for regulation in allRegulations {
            if regulation.type == .metered {
                if let endTime = regulation.enforcementEnd,
                   let days = regulation.enforcementDays,
                   let endTimeOfDay = parseTimeString(endTime) {
                    let components = calendar.dateComponents([.weekday], from: date)
                    if let weekday = components.weekday,
                       let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday),
                       days.contains(dayOfWeek) {
                        if let endDate = calendar.date(
                            bySettingHour: endTimeOfDay.hour,
                            minute: endTimeOfDay.minute,
                            second: 0,
                            of: date
                        ), endDate > date {
                            if earliestDate == nil || endDate < earliestDate! {
                                earliestDate = endDate
                                earliestRestriction = .meteredEnd(date: endDate)
                            }
                        }
                    }
                }
            }
        }

        return earliestRestriction
    }

    // MARK: - Regulation Occurrence Finder

    /// Find the next occurrence of a regulation (for street cleaning, tow-away, etc.)
    private func findNextOccurrence(of regulation: RegulationInfo, from date: Date) -> Date? {
        guard let days = regulation.enforcementDays,
              let startTime = regulation.enforcementStart,
              let timeOfDay = parseTimeString(startTime) else {
            return nil
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let currentWeekday = components.weekday,
              let currentDayOfWeek = DayOfWeek.from(calendarWeekday: currentWeekday) else {
            return nil
        }

        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let targetMinutes = timeOfDay.hour * 60 + timeOfDay.minute

        // Check if it's today and hasn't happened yet
        if days.contains(currentDayOfWeek) && currentMinutes < targetMinutes {
            return calendar.date(
                bySettingHour: timeOfDay.hour,
                minute: timeOfDay.minute,
                second: 0,
                of: date
            )
        }

        // Find next occurrence
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: currentDayOfWeek) else {
            return nil
        }

        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if days.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: date) {
                    return calendar.date(
                        bySettingHour: timeOfDay.hour,
                        minute: timeOfDay.minute,
                        second: 0,
                        of: targetDate
                    )
                }
                break
            }
        }

        return nil
    }

    /// Parse time string like "08:00" into TimeOfDay
    private func parseTimeString(_ timeStr: String) -> TimeOfDay? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return TimeOfDay(hour: parts[0], minute: parts[1])
    }

    /// Check if currently outside enforcement hours (for unlimited parking)
    func isOutsideEnforcement(at date: Date = Date()) -> Bool {
        guard let startTime = enforcementStartTime,
              let endTime = enforcementEndTime else {
            return false
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
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

    // MARK: - Private Helpers

    private func calculateTimeLimitWithEnforcement(
        from date: Date,
        limit: Int,
        endTime: TimeOfDay,
        startTime: TimeOfDay,
        days: [DayOfWeek]?,
        currentDay: DayOfWeek?
    ) -> ParkUntilResult {
        let calendar = Calendar.current
        let parkUntil = date.addingTimeInterval(TimeInterval(limit * 60))

        // Get enforcement end time for today
        guard let endDate = calendar.date(
            bySettingHour: endTime.hour,
            minute: endTime.minute,
            second: 0,
            of: date
        ) else {
            return .timeLimit(date: parkUntil)
        }

        // Check if time limit extends beyond enforcement end
        if parkUntil > endDate {
            // Time limit would expire after enforcement ends - can park until next enforcement!
            return findNextEnforcementStart(
                from: date,
                startTime: startTime,
                days: days,
                currentDay: currentDay
            )
        } else {
            // Time limit expires during enforcement
            return .timeLimit(date: parkUntil)
        }
    }

    private func findNextEnforcementStart(
        from date: Date,
        startTime: TimeOfDay,
        days: [DayOfWeek]?,
        currentDay: DayOfWeek?
    ) -> ParkUntilResult {
        let calendar = Calendar.current

        // If no specific days, enforcement is daily - next enforcement is tomorrow
        guard let enforcementDays = days, !enforcementDays.isEmpty, let current = currentDay else {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
                return .enforcementStart(time: startTime, date: tomorrow)
            }
            return .unknown
        }

        // Find the next enforcement day
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: current) else {
            return .unknown
        }

        // Look for the next enforcement day (starting from tomorrow)
        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if enforcementDays.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: date) {
                    return .enforcementStart(time: startTime, date: targetDate)
                }
                break
            }
        }

        return .unknown
    }
}

// MARK: - Display Type

/// Display format for "Park Until" calculation
enum ParkUntilDisplay {
    case timeLimit(date: Date)                          // Expires at specific time due to time limit
    case enforcementStart(time: TimeOfDay, date: Date)  // Can park until enforcement starts
    case restriction(type: String, date: Date)          // Restriction starts (street cleaning, tow-away)
    case meteredEnd(date: Date)                         // Metered enforcement ends
    case unknown                                        // Unable to calculate

    /// Get the underlying date for comparison
    var date: Date? {
        switch self {
        case .timeLimit(let date), .restriction(_, let date), .meteredEnd(let date):
            return date
        case .enforcementStart(_, let targetDate):
            let calendar = Calendar.current
            // Try to get the date - this is approximate since we might need to combine time + date
            return targetDate
        case .unknown:
            return nil
        }
    }

    /// Format for display (e.g., "Park until 3:00 PM", "Park until Mon 8:00 AM (street cleaning)")
    func formatted() -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        switch self {
        case .timeLimit(let date):
            // Simple time format for time limit
            formatter.dateFormat = calendar.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
            return "Park until \(formatter.string(from: date))"

        case .restriction(let type, let date):
            // Show restriction type with time
            formatter.dateFormat = calendar.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
            return "Park until \(formatter.string(from: date)) (\(type.lowercased()))"

        case .meteredEnd(let date):
            // Metered enforcement ending
            formatter.dateFormat = calendar.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
            return "Park until \(formatter.string(from: date)) (meter free)"

        case .enforcementStart(let time, let targetDate):
            let now = Date()
            let currentHour = calendar.component(.hour, from: now)
            let targetIsAM = time.hour < 12

            // If target is today, never show day
            if calendar.isDateInToday(targetDate) {
                formatter.dateFormat = "h:mm a"
                guard let dateAtTime = calendar.date(
                    bySettingHour: time.hour,
                    minute: time.minute,
                    second: 0,
                    of: targetDate
                ) else {
                    return "Park until \(time.hour):\(String(format: "%02d", time.minute))"
                }
                return "Park until \(formatter.string(from: dateAtTime))"
            }

            // If target is tomorrow AND it's after noon AND target is AM, it's obvious - don't show day
            if calendar.isDateInTomorrow(targetDate) && currentHour >= 12 && targetIsAM {
                formatter.dateFormat = "h:mm a"
                guard let dateAtTime = calendar.date(
                    bySettingHour: time.hour,
                    minute: time.minute,
                    second: 0,
                    of: targetDate
                ) else {
                    return "Park until \(time.hour):\(String(format: "%02d", time.minute))"
                }
                return "Park until \(formatter.string(from: dateAtTime))"
            }

            // Otherwise show day for clarity
            formatter.dateFormat = "EEE h:mm a"
            guard let dateAtTime = calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: targetDate
            ) else {
                return "Park until tomorrow"
            }
            return "Park until \(formatter.string(from: dateAtTime))"

        case .unknown:
            return "Check posted signs"
        }
    }

    /// Short format for compact display (e.g., "Until 3:00 PM")
    func shortFormatted() -> String {
        formatted().replacingOccurrences(of: "Park until ", with: "Until ")
    }
}
