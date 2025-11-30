import SwiftUI

// MARK: - Display Mode

/// Determines how the parking location card is displayed
enum CardDisplayMode {
    case primary      // Large card for current location (map collapsed)
    case compact      // Mini card when map is expanded
    case spotDetail   // Card for user-tapped locations
}

// MARK: - Location Card Data

/// Data model for displaying parking location information
struct LocationCardData {
    // Location identification
    let locationName: String           // "Zone Q", "Mission St", "Metered Parking"
    let locationCode: String?          // "Q", "$", nil
    let locationType: ZoneType         // .residentialPermit, .metered, etc.

    // Parking status
    let validityStatus: PermitValidityStatus
    let applicablePermits: [ParkingPermit]
    let allValidPermitAreas: [String]  // All permits valid at this location

    // Regulations
    let timeLimitMinutes: Int?
    let detailedRegulations: [RegulationInfo]
    let ruleSummaryLines: [String]

    // Enforcement hours
    let enforcementStartTime: TimeOfDay?
    let enforcementEndTime: TimeOfDay?
    let enforcementDays: [DayOfWeek]?

    // Metered zones
    let meteredSubtitle: String?       // "$3/hr • 2hr max"

    // Context
    let isCurrentLocation: Bool        // true = GPS location, false = tapped location
}

// MARK: - Parking Location Card

/// Unified card component for displaying parking location information
/// Replaces AnimatedZoneCard and TappedSpotInfoCard
struct ParkingLocationCard: View {
    let data: LocationCardData
    let displayMode: CardDisplayMode
    let screenHeight: CGFloat
    var namespace: Namespace.ID?       // For matched geometry in primary mode

    @State private var animationIndex: Int = 0
    @State private var isFlipped: Bool = false
    @State private var showRegulationsDrawer = false

    // MARK: - Computed Properties

    private var isMultiPermitLocation: Bool {
        data.allValidPermitAreas.count > 1
    }

    /// Calculate "Park Until" time considering ALL regulations
    private var parkUntilResult: ParkUntilDisplay? {
        let calculator = ParkUntilCalculator(
            timeLimitMinutes: data.timeLimitMinutes,
            enforcementStartTime: data.enforcementStartTime,
            enforcementEndTime: data.enforcementEndTime,
            enforcementDays: data.enforcementDays,
            validityStatus: data.validityStatus,
            allRegulations: data.detailedRegulations
        )
        return calculator.calculateParkUntil()
    }

    /// Check if currently outside enforcement hours (for showing "unlimited" state)
    private var isOutsideEnforcement: Bool {
        let calculator = ParkUntilCalculator(
            timeLimitMinutes: data.timeLimitMinutes,
            enforcementStartTime: data.enforcementStartTime,
            enforcementEndTime: data.enforcementEndTime,
            enforcementDays: data.enforcementDays,
            validityStatus: data.validityStatus,
            allRegulations: data.detailedRegulations
        )
        return calculator.isOutsideEnforcement()
    }

    /// Check if this is an "always no parking" zone (no parking anytime)
    private var isAlwaysNoParking: Bool {
        // Check if there's a no parking regulation with no specific enforcement days/times
        data.detailedRegulations.contains { regulation in
            regulation.type == .noParking &&
            (regulation.enforcementDays == nil || regulation.enforcementDays?.isEmpty == true) &&
            regulation.enforcementStart == nil &&
            regulation.enforcementEnd == nil
        }
    }

    /// Find when enforcement starts for valid permit holders (outside enforcement hours)
    private func findNextEnforcementForValidPermit() -> ParkUntilDisplay? {
        guard let startTime = data.enforcementStartTime,
              let endTime = data.enforcementEndTime else {
            return nil
        }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinutes = startTime.totalMinutes

        // Check if enforcement starts later today
        var currentDayOfWeek: DayOfWeek?
        var isEnforcementDay = true
        if let days = data.enforcementDays, !days.isEmpty,
           let weekday = components.weekday,
           let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday) {
            currentDayOfWeek = dayOfWeek
            isEnforcementDay = days.contains(dayOfWeek)
        }

        if isEnforcementDay && currentMinutes < startMinutes {
            // Enforcement starts later today
            return .enforcementStart(time: startTime, date: now)
        }

        // Find next enforcement day
        guard let days = data.enforcementDays, !days.isEmpty, let current = currentDayOfWeek else {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return .enforcementStart(time: startTime, date: tomorrow)
            }
            return nil
        }

        let allDays: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let currentIndex = allDays.firstIndex(of: current) else {
            return nil
        }

        for offset in 1...7 {
            let nextIndex = (currentIndex + offset) % 7
            let nextDay = allDays[nextIndex]
            if days.contains(nextDay) {
                if let targetDate = calendar.date(byAdding: .day, value: offset, to: now) {
                    return .enforcementStart(time: startTime, date: targetDate)
                }
                break
            }
        }

        return nil
    }

    private var orderedPermitAreas: [String] {
        guard isMultiPermitLocation else {
            return data.allValidPermitAreas.isEmpty ? [singleLocationCode] : data.allValidPermitAreas
        }
        var areas = data.allValidPermitAreas
        if let userPermitArea = data.applicablePermits.first?.area,
           let index = areas.firstIndex(of: userPermitArea) {
            areas.remove(at: index)
            areas.insert(userPermitArea, at: 0)
        }
        return areas
    }

    private var singleLocationCode: String {
        if data.locationType == .metered {
            return "$"
        }
        if let code = data.locationCode {
            return code
        }
        // Extract from location name
        if data.locationName.hasPrefix("Area ") {
            return String(data.locationName.dropFirst(5))
        }
        if data.locationName.hasPrefix("Zone ") {
            return String(data.locationName.dropFirst(5))
        }
        return data.locationName
    }

    private var formattedLocationsList: String {
        let areas = orderedPermitAreas
        switch areas.count {
        case 0: return "Location"
        case 1: return "Zone \(areas[0])"
        case 2: return "Zones \(areas[0]) & \(areas[1])"
        default:
            let allButLast = areas.dropLast().joined(separator: ", ")
            return "Zones \(allButLast) & \(areas.last!)"
        }
    }

    private var displaySubtitle: String? {
        if data.locationType == .metered {
            return data.meteredSubtitle ?? "$2/hr • 2hr max"
        }
        if isMultiPermitLocation {
            return formattedLocationsList
        }
        return nil
    }

    private var isValidStyle: Bool {
        data.validityStatus == .valid || data.validityStatus == .multipleApply
    }

    private var cardBackground: Color {
        if data.locationType == .metered {
            return Color(.systemBackground)
        }
        return isValidStyle ? Color.accessibleValidGreen : Color(.systemBackground)
    }

    private var circleBackground: Color {
        // Use ZoneColorProvider for consistent zone colors
        ZoneColorProvider.swiftUIColor(for: data.locationCode)
    }

    private var letterColor: Color {
        .white  // Letters are always white on colored circles
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch displayMode {
            case .primary:
                primaryCard
            case .compact:
                compactCard
            case .spotDetail:
                spotDetailCard
            }
        }
        .sheet(isPresented: $showRegulationsDrawer) {
            RegulationsDrawerView(
                zoneName: data.locationName,
                zoneType: data.locationType,
                validityStatus: data.validityStatus,
                applicablePermits: data.applicablePermits,
                timeLimitMinutes: data.timeLimitMinutes,
                regulations: data.detailedRegulations
            )
        }
    }

    // MARK: - Primary Card (Large, for current location)

    private var primaryCard: some View {
        ZStack {
            // Animated background
            if let ns = namespace {
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .matchedGeometryEffect(id: "cardBackground", in: ns)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
            }

            // Content
            if !isFlipped {
                primaryFrontContent
            } else {
                primaryBackContent
            }
        }
        .frame(height: primaryCardHeight)
        .rotation3DEffect(
            .degrees(isFlipped ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.8
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isFlipped)
    }

    private var primaryCardHeight: CGFloat {
        let safeAreaTop: CGFloat = 59
        let safeAreaBottom: CGFloat = 34
        let padding: CGFloat = 32
        let mapCardHeight: CGFloat = 120
        let rulesHeaderPeek: CGFloat = 20
        let spacing: CGFloat = 32

        let availableHeight = screenHeight - safeAreaTop - safeAreaBottom - padding - mapCardHeight - rulesHeaderPeek - spacing
        return min(max(availableHeight, 300), 520)
    }

    private var primaryFrontContent: some View {
        ZStack {
            // Center content
            VStack(spacing: 8) {
                locationCircle(size: 160)

                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundColor(isValidStyle ? .white.opacity(0.9) : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }

            // Top-right info button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isFlipped = true
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
                    }
                }
                .padding(16)
                Spacer()
            }

            // Bottom section
            VStack {
                Spacer()

                // "See regulations" button - always show (drawer handles empty state)
                Button {
                    showRegulationsDrawer = true
                } label: {
                    Text("See regulations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isValidStyle ? .white.opacity(0.9) : .blue)
                        .underline()
                }
                .padding(.bottom, 8)

                ValidityBadgeView(
                    status: data.validityStatus,
                    permits: data.applicablePermits,
                    onColoredBackground: isValidStyle,
                    timeLimitMinutes: data.timeLimitMinutes,
                    enforcementStartTime: data.enforcementStartTime,
                    enforcementEndTime: data.enforcementEndTime,
                    enforcementDays: data.enforcementDays
                )
                .padding(.bottom, 24)
            }
        }
    }

    private var primaryBackContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Parking Rules")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isValidStyle ? .white : .primary)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isFlipped = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(isValidStyle ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Rules list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(data.ruleSummaryLines, id: \.self) { rule in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(isValidStyle ? .white.opacity(0.7) : .secondary)
                                .padding(.top, 6)

                            Text(rule)
                                .font(.body)
                                .foregroundColor(isValidStyle ? .white : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if data.ruleSummaryLines.isEmpty {
                        Text("No specific rules available")
                            .font(.body)
                            .foregroundColor(isValidStyle ? .white.opacity(0.7) : .secondary)
                            .italic()
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            HStack {
                Spacer()
                Text("Tap X to flip back")
                    .font(.caption)
                    .foregroundColor(isValidStyle ? .white.opacity(0.5) : .secondary.opacity(0.7))
                Spacer()
            }
            .padding(.bottom, 16)
        }
        .background(cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Compact Card (Mini strip when map expanded)

    private var compactCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)

            HStack(spacing: 12) {
                locationCircle(size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    compactMainText
                    compactSubtext
                }

                Spacer()

                // "See regulations" button - compact icon version
                Button {
                    showRegulationsDrawer = true
                } label: {
                    Image(systemName: "list.bullet.circle")
                        .font(.title3)
                        .foregroundColor(isValidStyle ? .white.opacity(0.9) : .blue)
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 70)
    }

    @ViewBuilder
    private var compactMainText: some View {
        // PRIORITY ORDER:
        // 1. Always no parking zones → "No Parking"
        // 2. Park Until (street cleaning, time limits, etc.) → "Until [time]"
        // 3. Valid permit with no restrictions → "Unlimited parking"
        // 4. Other cases → Location name or type
        if isAlwaysNoParking {
            // Always no parking - parking never allowed
            HStack(spacing: 6) {
                Image(systemName: "nosign")
                    .font(.headline)
                Text("No Parking")
                    .font(.headline)
            }
            .foregroundColor(.red)
        } else if let parkUntil = parkUntilResult {
            // Show "Park Until" for ANY restriction (street cleaning, time limits, etc.)
            // This ensures street cleaning is always displayed, even for valid permit holders
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.headline)
                Text(parkUntil.shortFormatted())
                    .font(.headline)
            }
            .foregroundColor(.primary)
        } else if isValidStyle {
            // Valid permit with no restrictions - show "Unlimited parking" or enforcement start time
            if isOutsideEnforcement, let nextEnforcement = findNextEnforcementForValidPermit() {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                    Text(nextEnforcement.shortFormatted())
                        .font(.headline)
                }
                .foregroundColor(.white)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                    Text("Unlimited parking")
                        .font(.headline)
                }
                .foregroundColor(.white)
            }
        } else if data.locationType == .metered {
            Text("Paid Parking")
                .font(.headline)
                .foregroundColor(.primary)
        } else {
            Text(data.locationName)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private var compactSubtext: some View {
        if isAlwaysNoParking {
            // Always no parking - show "Anytime"
            Text("Anytime")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if parkUntilResult != nil {
            // Show location name when Park Until is the main title
            Text(data.locationName)
                .font(.caption)
                .foregroundColor(.secondary)
        } else if data.locationType == .metered {
            Text(data.meteredSubtitle ?? "$2/hr • 2hr max")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if isValidStyle {
            // For valid permits with no restrictions, keep the location name visible
            if isOutsideEnforcement {
                Text(isMultiPermitLocation ? formattedLocationsList : data.locationName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text(isMultiPermitLocation ? formattedLocationsList : data.locationName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        } else if isMultiPermitLocation {
            Text(formattedLocationsList)
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Text(data.validityStatus.shortText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Spot Detail Card (For tapped locations)

    private var spotDetailCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                locationCircle(size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    if isAlwaysNoParking {
                        // Always no parking zone
                        HStack(spacing: 6) {
                            Image(systemName: "nosign")
                                .font(.headline)
                            Text("No Parking")
                                .font(.headline)
                        }
                        .foregroundColor(.red)

                        Text("Anytime")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let parkUntil = parkUntilResult {
                        // Show "Park Until" for any restriction
                        // Includes street cleaning (applies to everyone, even valid permit holders)
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.headline)
                            Text(parkUntil.shortFormatted())
                                .font(.headline)
                        }
                        .foregroundColor(.primary)

                        // Location name on second line
                        Text(data.locationName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // Original layout
                        Text(data.locationName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack(spacing: 6) {
                            Image(systemName: data.validityStatus.iconName)
                                .font(.caption)
                            Text(data.validityStatus.shortText)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(Color.forValidityStatus(data.validityStatus))
                    }
                }

                Spacer()
            }

            // Regulations button - always show (drawer handles empty state)
            Button {
                showRegulationsDrawer = true
            } label: {
                HStack {
                    Text("See regulations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Location Circle

    @ViewBuilder
    private func locationCircle(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(circleBackgroundForCurrentZone)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            Text(currentDisplayCode)
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .onTapGesture {
            if isMultiPermitLocation {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationIndex = (animationIndex + 1) % orderedPermitAreas.count
                }
            }
        }
    }

    /// Get the zone code to display (cycles through multi-permit zones)
    private var currentDisplayCode: String {
        if isMultiPermitLocation {
            return orderedPermitAreas[animationIndex]
        }
        return singleLocationCode
    }

    /// Get circle background color for current zone (handles animation)
    private var circleBackgroundForCurrentZone: Color {
        if isMultiPermitLocation {
            return ZoneColorProvider.swiftUIColor(for: orderedPermitAreas[animationIndex])
        }
        return circleBackground
    }
}

// MARK: - Multi-Permit Circle View

private struct MultiPermitCircleView: View {
    let permitAreas: [String]
    let animationIndex: Int
    let size: CGFloat

    private var offset: CGFloat {
        size * 0.35
    }

    private var totalWidth: CGFloat {
        size + (CGFloat(permitAreas.count - 1) * offset)
    }

    private var reorderedAreas: [(area: String, index: Int)] {
        var areas = permitAreas.enumerated().map { (area: $1, index: $0) }
        if let animatedItem = areas.first(where: { $0.index == animationIndex }) {
            areas.removeAll { $0.index == animationIndex }
            areas.append(animatedItem)
        }
        return areas
    }

    var body: some View {
        ZStack(alignment: .center) {
            ForEach(reorderedAreas, id: \.index) { item in
                let isActive = item.index == animationIndex
                let xOffset = CGFloat(item.index) * offset - (totalWidth - size) / 2

                ZStack {
                    Circle()
                        .fill(ZoneColorProvider.swiftUIColor(for: item.area))
                        .frame(width: size, height: size)
                        .shadow(
                            color: isActive ? .black.opacity(0.3) : .black.opacity(0.15),
                            radius: isActive ? 8 : 4,
                            x: 0,
                            y: isActive ? 4 : 2
                        )

                    Text(item.area)
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                }
                .offset(x: xOffset)
                .scaleEffect(isActive ? 1.15 : 1.0)
                .zIndex(isActive ? 1 : 0)
            }
        }
        .frame(width: totalWidth, height: size * 1.2)
    }
}

// MARK: - Previews

#Preview("Primary Mode - Valid") {
    ParkingLocationCard(
        data: LocationCardData(
            locationName: "Zone Q",
            locationCode: "Q",
            locationType: .residentialPermit,
            validityStatus: .valid,
            applicablePermits: [ParkingPermit(type: .residential, area: "Q")],
            allValidPermitAreas: ["Q"],
            timeLimitMinutes: 120,
            detailedRegulations: [],
            ruleSummaryLines: ["Zone Q permit required", "2-hour limit without permit"],
            enforcementStartTime: TimeOfDay(hour: 8, minute: 0),
            enforcementEndTime: TimeOfDay(hour: 18, minute: 0),
            enforcementDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            meteredSubtitle: nil,
            isCurrentLocation: true
        ),
        displayMode: .primary,
        screenHeight: 844
    )
    .padding()
}

#Preview("Compact Mode") {
    ParkingLocationCard(
        data: LocationCardData(
            locationName: "Zone Q",
            locationCode: "Q",
            locationType: .residentialPermit,
            validityStatus: .valid,
            applicablePermits: [ParkingPermit(type: .residential, area: "Q")],
            allValidPermitAreas: ["Q"],
            timeLimitMinutes: 120,
            detailedRegulations: [],
            ruleSummaryLines: [],
            enforcementStartTime: nil,
            enforcementEndTime: nil,
            enforcementDays: nil,
            meteredSubtitle: nil,
            isCurrentLocation: true
        ),
        displayMode: .compact,
        screenHeight: 844
    )
    .padding()
}

#Preview("Spot Detail Mode") {
    ParkingLocationCard(
        data: LocationCardData(
            locationName: "Mission St",
            locationCode: nil,
            locationType: .residentialPermit,
            validityStatus: .invalid,
            applicablePermits: [],
            allValidPermitAreas: ["R"],
            timeLimitMinutes: 120,
            detailedRegulations: [],
            ruleSummaryLines: ["Zone R permit required"],
            enforcementStartTime: nil,
            enforcementEndTime: nil,
            enforcementDays: nil,
            meteredSubtitle: nil,
            isCurrentLocation: false
        ),
        displayMode: .spotDetail,
        screenHeight: 844
    )
    .padding()
}
