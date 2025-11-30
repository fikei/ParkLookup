import SwiftUI

/// Bottom sheet drawer that displays detailed parking regulations
struct RegulationsDrawerView: View {
    // Header data (original card content)
    let zoneName: String
    let zoneType: ZoneType
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let timeLimitMinutes: Int?

    // Detailed regulations
    let regulations: [RegulationInfo]

    @Environment(\.dismiss) private var dismiss

    /// Calculate "Park Until" time considering ALL regulations
    private var parkUntilResult: ParkUntilDisplay? {
        // Extract enforcement times from regulations (use first regulation with times)
        let enforcementStartTime = regulations.first { $0.enforcementStart != nil }?.enforcementStart.flatMap { timeStr -> TimeOfDay? in
            let parts = timeStr.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return TimeOfDay(hour: parts[0], minute: parts[1])
        }

        let enforcementEndTime = regulations.first { $0.enforcementEnd != nil }?.enforcementEnd.flatMap { timeStr -> TimeOfDay? in
            let parts = timeStr.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return TimeOfDay(hour: parts[0], minute: parts[1])
        }

        let enforcementDays = regulations.first { $0.enforcementDays != nil }?.enforcementDays

        let calculator = ParkUntilCalculator(
            timeLimitMinutes: timeLimitMinutes,
            enforcementStartTime: enforcementStartTime,
            enforcementEndTime: enforcementEndTime,
            enforcementDays: enforcementDays,
            validityStatus: validityStatus,
            allRegulations: regulations
        )
        return calculator.calculateParkUntil()
    }

    /// Whether the card should use the "valid" green style
    private var isValidStyle: Bool {
        validityStatus == .valid || validityStatus == .multipleApply
    }

    /// Background color based on validity
    private var headerBackground: Color {
        if zoneType == .metered {
            return Color(.systemBackground)
        }
        return isValidStyle ? Color.green : Color(.systemBackground)
    }

    /// Zone code for display
    private var zoneCode: String {
        if zoneType == .metered {
            return "$"
        }
        if zoneName.hasPrefix("Area ") {
            return String(zoneName.dropFirst(5))
        }
        if zoneName.hasPrefix("Zone ") {
            return String(zoneName.dropFirst(5))
        }
        return zoneName
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Regulations list
                if regulations.isEmpty {
                    emptyStateView
                } else {
                    regulationsList
                }
            }
            .navigationTitle("Parking Regulations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            // Zone circle (compact)
            ZStack {
                Circle()
                    .fill(circleBackground)
                    .frame(width: 60, height: 60)

                Text(zoneCode)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(letterColor)
                    .minimumScaleFactor(0.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(zoneName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                // Validity badge
                HStack(spacing: 6) {
                    Image(systemName: validityStatus.iconName)
                        .font(.caption)
                    Text(validityStatus.shortText)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(Color.forValidityStatus(validityStatus))

                // Time limit if applicable
                if let limit = timeLimitMinutes {
                    Text("\(limit) min limit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(headerBackground)
        .cornerRadius(12)
    }

    private var circleBackground: Color {
        if zoneType == .metered {
            return Color.forZoneType(.metered).opacity(0.15)
        }
        return isValidStyle ? Color(.systemBackground) : Color.forValidityStatus(validityStatus).opacity(0.15)
    }

    private var letterColor: Color {
        if zoneType == .metered {
            return Color.forZoneType(.metered)
        }
        return Color.forValidityStatus(validityStatus)
    }

    // MARK: - Explanation Banner

    @ViewBuilder
    private func explanationBanner(for parkUntil: ParkUntilDisplay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForParkUntil(parkUntil))
                .font(.title3)
                .foregroundColor(colorForParkUntil(parkUntil))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleForParkUntil(parkUntil))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(explanationForParkUntil(parkUntil))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(backgroundColorForParkUntil(parkUntil))
        .cornerRadius(10)
    }

    private func iconForParkUntil(_ parkUntil: ParkUntilDisplay) -> String {
        switch parkUntil {
        case .restriction(let type, _):
            if type.lowercased().contains("street cleaning") {
                return "wind"
            } else {
                return "nosign"
            }
        case .timeLimit:
            return "clock"
        case .meteredEnd:
            return "dollarsign.circle"
        case .enforcementStart:
            return "bell"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func colorForParkUntil(_ parkUntil: ParkUntilDisplay) -> Color {
        switch parkUntil {
        case .restriction(let type, _):
            if type.lowercased().contains("street cleaning") {
                return .red
            } else {
                return .red
            }
        case .timeLimit:
            return .orange
        case .meteredEnd:
            return .blue
        case .enforcementStart:
            return .green
        case .unknown:
            return .gray
        }
    }

    private func backgroundColorForParkUntil(_ parkUntil: ParkUntilDisplay) -> Color {
        colorForParkUntil(parkUntil).opacity(0.1)
    }

    private func titleForParkUntil(_ parkUntil: ParkUntilDisplay) -> String {
        switch parkUntil {
        case .restriction(let type, let date):
            let timeStr = formatDate(date)
            if type.lowercased().contains("street cleaning") {
                return "Move by \(timeStr) for street cleaning"
            } else {
                return "Move by \(timeStr) - \(type)"
            }
        case .timeLimit(let date):
            return "Move by \(formatDate(date)) - time limit"
        case .meteredEnd(let date):
            return "Free parking starts at \(formatDate(date))"
        case .enforcementStart(let time, _):
            return "Enforcement starts at \(formatTime(time))"
        case .unknown:
            return "Unable to calculate park until time"
        }
    }

    private func explanationForParkUntil(_ parkUntil: ParkUntilDisplay) -> String {
        switch parkUntil {
        case .restriction(let type, _):
            if type.lowercased().contains("street cleaning") {
                return "Street cleaning applies to all vehicles, including those with valid permits."
            } else {
                return "This restriction applies to all vehicles at this location."
            }
        case .timeLimit:
            return "Your parking time limit will expire. Move your vehicle before then."
        case .meteredEnd:
            return "Meter enforcement ends and parking becomes free."
        case .enforcementStart:
            return "Parking restrictions will begin at this time."
        case .unknown:
            return "Check the regulations below for details."
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formatTime(_ time: TimeOfDay) -> String {
        let hour12 = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour)
        let period = time.hour >= 12 ? "PM" : "AM"
        if time.minute == 0 {
            return "\(hour12)\(period)"
        } else {
            return "\(hour12):\(String(format: "%02d", time.minute))\(period)"
        }
    }

    // MARK: - Regulations List

    private var regulationsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(regulations) { regulation in
                    RegulationRow(regulation: regulation)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No regulations available")
                .font(.headline)
                .foregroundColor(.primary)

            Text("This location has no specific parking regulations on file.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Regulation Row

private struct RegulationRow: View {
    let regulation: RegulationInfo

    /// Icon for regulation type
    private var regulationIcon: String {
        switch regulation.type {
        case .streetCleaning:
            return "wind"
        case .timeLimited:
            return "clock"
        case .residentialPermit:
            return "parkingsign"
        case .metered:
            return "dollarsign.circle"
        case .noParking:
            return "nosign"
        case .free:
            return "checkmark.circle"
        }
    }

    /// Color for regulation type
    private var regulationColor: Color {
        switch regulation.type {
        case .noParking, .streetCleaning:
            return .red
        case .metered:
            return .gray
        case .timeLimited, .residentialPermit:
            return .orange
        case .free:
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Heading with icon
            HStack(spacing: 10) {
                Image(systemName: regulationIcon)
                    .font(.title3)
                    .foregroundColor(regulationColor)
                    .frame(width: 28)

                Text(regulationTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Details
            VStack(alignment: .leading, spacing: 8) {
                // Enforcement time range
                if let days = regulation.enforcementDays,
                   !days.isEmpty,
                   let start = regulation.enforcementStart,
                   let end = regulation.enforcementEnd {
                    Text("\(formatDayRange(days)), \(formatTimeRange(start: start, end: end))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Permit zone if applicable
                if let permitZone = regulation.permitZone {
                    Text("Zone \(permitZone) permit required")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Time limit if applicable
                if let timeLimit = regulation.timeLimit {
                    let hours = timeLimit / 60
                    let minutes = timeLimit % 60
                    if minutes == 0 {
                        Text("\(hours) hour time limit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(hours)h \(minutes)m time limit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.leading, 38)  // Align with text after icon
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    /// Regulation title based on type
    private var regulationTitle: String {
        switch regulation.type {
        case .streetCleaning:
            return "Street Cleaning"
        case .timeLimited:
            return "Time Limited Parking"
        case .residentialPermit:
            return "Residential Permit Parking"
        case .metered:
            return "Metered Parking"
        case .noParking:
            return "No Parking"
        case .free:
            return "Free Parking"
        }
    }

    /// Format day range (e.g., "Mon-Sat", "Every day", "Weekdays")
    private func formatDayRange(_ days: [DayOfWeek]) -> String {
        if days.count == 7 {
            return "Every day"
        }

        // Check for weekdays
        let weekdays: Set<DayOfWeek> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if Set(days) == weekdays {
            return "Mon-Fri"
        }

        // Check for Mon-Sat
        let monToSat: Set<DayOfWeek> = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        if Set(days) == monToSat {
            return "Mon-Sat"
        }

        // Check for weekends
        let weekends: Set<DayOfWeek> = [.saturday, .sunday]
        if Set(days) == weekends {
            return "Sat-Sun"
        }

        // Check for consecutive days and create range
        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let sortedDays = days.sorted { day1, day2 in
            guard let idx1 = allDays.firstIndex(of: day1),
                  let idx2 = allDays.firstIndex(of: day2) else { return false }
            return idx1 < idx2
        }

        // Check if consecutive
        if sortedDays.count >= 2 {
            var isConsecutive = true
            for i in 0..<(sortedDays.count - 1) {
                guard let idx1 = allDays.firstIndex(of: sortedDays[i]),
                      let idx2 = allDays.firstIndex(of: sortedDays[i + 1]) else {
                    isConsecutive = false
                    break
                }
                if idx2 != idx1 + 1 {
                    isConsecutive = false
                    break
                }
            }

            if isConsecutive {
                return "\(sortedDays.first!.shortName)-\(sortedDays.last!.shortName)"
            }
        }

        // Otherwise list days with commas
        return sortedDays.map { $0.shortName }.joined(separator: ", ")
    }

    /// Format time range (e.g., "9am-6pm", "9-6pm")
    private func formatTimeRange(start: String, end: String) -> String {
        // Parse "HH:MM" format
        func parseTime(_ timeStr: String) -> (hour: Int, minute: Int)? {
            let parts = timeStr.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return (hour: parts[0], minute: parts[1])
        }

        func formatTime(hour: Int, minute: Int) -> String {
            let hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            let period = hour >= 12 ? "pm" : "am"
            if minute == 0 {
                return "\(hour12)\(period)"
            } else {
                return "\(hour12):\(String(format: "%02d", minute))\(period)"
            }
        }

        guard let startTime = parseTime(start),
              let endTime = parseTime(end) else {
            return "\(start)-\(end)"
        }

        let startPeriod = startTime.hour >= 12 ? "pm" : "am"
        let endPeriod = endTime.hour >= 12 ? "pm" : "am"

        let startFormatted = formatTime(hour: startTime.hour, minute: startTime.minute)
        let endFormatted = formatTime(hour: endTime.hour, minute: endTime.minute)

        // If same period, only show period on end time
        if startPeriod == endPeriod {
            let startHour = startTime.hour == 0 ? 12 : (startTime.hour > 12 ? startTime.hour - 12 : startTime.hour)
            if startTime.minute == 0 {
                return "\(startHour)-\(endFormatted)"
            } else {
                return "\(startHour):\(String(format: "%02d", startTime.minute))-\(endFormatted)"
            }
        } else {
            return "\(startFormatted)-\(endFormatted)"
        }
    }
}

// MARK: - Preview

#Preview {
    RegulationsDrawerView(
        zoneName: "Zone Q",
        zoneType: .residentialPermit,
        validityStatus: .valid,
        applicablePermits: [
            ParkingPermit(type: .residential, area: "Q")
        ],
        timeLimitMinutes: 120,
        regulations: [
            RegulationInfo(
                type: .residentialPermit,
                description: "Residential permit parking",
                enforcementDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                enforcementStart: "08:00",
                enforcementEnd: "18:00",
                permitZone: "Q",
                timeLimit: 120
            ),
            RegulationInfo(
                type: .streetCleaning,
                description: "Street cleaning",
                enforcementDays: [.tuesday, .thursday],
                enforcementStart: "09:00",
                enforcementEnd: "11:00",
                permitZone: nil,
                timeLimit: nil
            ),
            RegulationInfo(
                type: .metered,
                description: "Metered parking",
                enforcementDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                enforcementStart: "09:00",
                enforcementEnd: "18:00",
                permitZone: nil,
                timeLimit: 120
            )
        ]
    )
}
