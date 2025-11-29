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
                // Header - Original card content (compact)
                headerCard
                    .padding(.horizontal)
                    .padding(.top, 16)

                Divider()
                    .padding(.vertical, 16)

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

    // MARK: - Regulations List

    private var regulationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(regulations) { regulation in
                    RegulationRow(regulation: regulation)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
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
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: regulationIcon)
                .font(.title3)
                .foregroundColor(regulationColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                // Description
                Text(regulation.description)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Enforcement details
                if let days = regulation.enforcementDays,
                   !days.isEmpty,
                   let start = regulation.enforcementStart,
                   let end = regulation.enforcementEnd {

                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(formatDays(days))
                            .font(.caption)

                        Spacer().frame(width: 8)

                        Image(systemName: "clock")
                            .font(.caption)
                        Text("\(start) - \(end)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                // Permit zone if applicable
                if let permitZone = regulation.permitZone {
                    HStack(spacing: 4) {
                        Image(systemName: "p.circle")
                            .font(.caption)
                        Text("Zone \(permitZone) permit required")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                // Time limit if applicable
                if let timeLimit = regulation.timeLimit {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text("\(timeLimit) minute limit")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private func formatDays(_ days: [DayOfWeek]) -> String {
        if days.count == 7 {
            return "Every day"
        }

        // Check for weekdays
        let weekdays: Set<DayOfWeek> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if Set(days) == weekdays {
            return "Weekdays"
        }

        // Check for weekends
        let weekends: Set<DayOfWeek> = [.saturday, .sunday]
        if Set(days) == weekends {
            return "Weekends"
        }

        // Otherwise list days
        return days.map { $0.shortName }.joined(separator: ", ")
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
