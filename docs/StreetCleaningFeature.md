# Street Cleaning Feature - Design Document

**Status:** In Progress - Park Feature MVP Complete ✅
**Last Updated:** 2025-11-26
**Owner:** Engineering Team

---

## Product Status

### ✅ Completed: Park Feature MVP (Prerequisite)

Before implementing street cleaning features, we completed the foundational **Park Feature MVP** which provides the infrastructure needed for parking session tracking and notifications.

**Completed Components:**
- ✅ Parking session model and lifecycle management
- ✅ iOS notification service with UserNotifications framework
- ✅ ActiveParkingView full-screen UI with countdown timer
- ✅ Park button in bottom navigation
- ✅ Settings integration for notification preferences
- ✅ Walking directions to parked car via Apple Maps
- ✅ Session persistence across app launches

**Next Step:** Use this notification and session infrastructure to add street cleaning-specific features (Phase 1 & Phase 2 below).

### Completed Stories & Tasks

#### Story 1: Parking Session Data Model ✅
**As a** developer
**I want** a robust data model for parking sessions
**So that** the app can track when and where users are parked

**Tasks Completed:**
- ✅ Created `ParkingSession.swift` model with location, zone, rules, and timestamps
- ✅ Added `ParkingLocation` struct with coordinate and address
- ✅ Implemented `SessionRule` with deadline calculations
- ✅ Created `SessionRuleType` enum (timeLimit, streetCleaning, enforcement, meter, noParking)
- ✅ Added `NotificationTiming` enum (1 hour, 15 minutes, at deadline)
- ✅ Implemented `parkUntil` computed property for earliest deadline
- ✅ Added `timeRemaining` calculation for countdown display

**Files Created:**
- `SFParkingZoneFinder/Core/Models/ParkingSession.swift`

---

#### Story 2: iOS Notification Service ✅
**As a** user
**I want** to receive timely notifications about my parking
**So that** I don't forget to move my car and get ticketed

**Tasks Completed:**
- ✅ Implemented `NotificationService.swift` using UserNotifications framework
- ✅ Added `requestPermission()` method for iOS notification authorization
- ✅ Created `scheduleSessionNotifications()` with calendar-based triggers
- ✅ Implemented smart notification timing (1h before, 15min before, at deadline)
- ✅ Added notification cancellation for session IDs
- ✅ Created notification content with title, body, and user info payload
- ✅ Implemented `getEnabledNotificationTimings()` respecting user preferences
- ✅ Added urgency-based notification titles and messages

**Files Created:**
- `SFParkingZoneFinder/Core/Services/NotificationService.swift`

---

#### Story 3: Parking Session Manager ✅
**As a** developer
**I want** centralized parking session lifecycle management
**So that** sessions persist across app launches and integrate with notifications

**Tasks Completed:**
- ✅ Created `ParkingSessionManager.swift` with @MainActor for UI thread safety
- ✅ Implemented `startSession()` method creating sessions from current zone data
- ✅ Added `endSession()` method with notification cancellation
- ✅ Implemented session persistence using UserDefaults with JSONEncoder
- ✅ Added `loadActiveSession()` with stale session validation (1 hour past deadline)
- ✅ Created session history tracking (max 50 sessions)
- ✅ Integrated with NotificationService for automatic notification scheduling
- ✅ Added Combine publisher for reactive session updates
- ✅ Implemented `createSessionRules()` in MainResultViewModel
- ✅ Added smart `calculateParkingDeadline()` with enforcement window awareness

**Files Created:**
- `SFParkingZoneFinder/Core/Services/ParkingSessionManager.swift`

**Files Modified:**
- `SFParkingZoneFinder/Features/Main/ViewModels/MainResultViewModel.swift`
- `SFParkingZoneFinder/App/DependencyContainer.swift`

---

#### Story 4: ActiveParkingView UI ✅
**As a** user
**I want** a clear, full-screen view of my active parking session
**So that** I can easily see how much time I have left and navigate back to my car

**Tasks Completed:**
- ✅ Created `ActiveParkingView.swift` with SwiftUI
- ✅ Implemented countdown timer updating every second
- ✅ Added `CountdownCard` with color-coded urgency (green → yellow → orange → red)
- ✅ Created "Parked Since" display with duration formatting
- ✅ Added `RulesCard` showing all active parking rules with icons
- ✅ Implemented "Directions to My Car" button with walking mode
- ✅ Added "End Parking Session" button with loading state
- ✅ Created drag indicator for swipe-down dismissal (iOS standard)
- ✅ Added rule-specific icons and color coding
- ✅ Implemented time expiration warnings with exclamation icon
- ✅ Created SwiftUI previews for active and expired states

**Files Created:**
- `SFParkingZoneFinder/Features/Main/Views/ActiveParkingView.swift`

---

#### Story 5: Park Button & Navigation Integration ✅
**As a** user
**I want** an easily accessible Park button
**So that** I can quickly start tracking my parking session

**Tasks Completed:**
- ✅ Added Park button to `BottomNavigationBar` with 4-button layout
- ✅ Positioned Park button centrally with prominent styling (52x52, accent color)
- ✅ Used `parkingsign.circle.fill` icon for brand consistency
- ✅ Integrated with MainResultView state management
- ✅ Added `showingActiveParkingView` state variable
- ✅ Implemented sheet presentation for ActiveParkingView
- ✅ Created `openDirectionsToParking()` helper using MKMapItem
- ✅ Connected Park button to `startParkingSession()` async method
- ✅ Added haptic feedback on button tap
- ✅ Handled button visibility based on developer mode toggle

**Files Modified:**
- `SFParkingZoneFinder/Features/Main/Views/MainResultView.swift`

---

#### Story 6: Settings Integration ✅
**As a** user
**I want** to control my notification preferences
**So that** I can customize when I receive parking reminders

**Tasks Completed:**
- ✅ Added notification settings to `SettingsViewModel.swift`
- ✅ Created 4 @Published properties with UserDefaults persistence:
  - `notificationsEnabled` (master toggle)
  - `notify1HourBefore`
  - `notify15MinBefore`
  - `notifyAtDeadline`
- ✅ Implemented `requestNotificationPermission()` async method
- ✅ Added automatic disabling on permission denial
- ✅ Injected `NotificationService` into SettingsViewModel
- ✅ Updated DependencyContainer with new services
- ✅ Created "Parking Notifications" section in SettingsView
- ✅ Added conditional toggles (only show when master toggle is on)
- ✅ Implemented onChange handler for permission requests
- ✅ Added helpful footer text explaining notification purpose

**Files Modified:**
- `SFParkingZoneFinder/Features/Settings/ViewModels/SettingsViewModel.swift`
- `SFParkingZoneFinder/Features/Settings/Views/SettingsView.swift`
- `SFParkingZoneFinder/App/DependencyContainer.swift`

---

#### Story 7: Git Integration & Deployment ✅
**As a** developer
**I want** clean, organized commits
**So that** the feature history is clear and can be reviewed/reverted if needed

**Tasks Completed:**
- ✅ Created feature branch `claude/add-street-cleaning-feature-01TWeFkVoCP9hhfZ55Un4Lxm`
- ✅ Broke work into 7 logical commits:
  1. Add parking session and notification foundations
  2. Add ActiveParkingView and parking session support
  3. Add Park button to bottom navigation bar
  4. Replace close button with swipe-down gesture
  5. Wire up Park button to show ActiveParkingView
- ✅ Rebased onto main branch (resolved conflicts with driving mode UI changes)
- ✅ Force-pushed rebased commits
- ✅ All commits include detailed messages following conventional commit format

**Branch:** `claude/add-street-cleaning-feature-01TWeFkVoCP9hhfZ55Un4Lxm`

---

### Technical Architecture Decisions

**Decision 1: UserNotifications Framework**
- **Rationale:** Native iOS framework, supports calendar-based repeating notifications
- **Tradeoff:** Limited to local notifications (no remote push), but sufficient for MVP

**Decision 2: UserDefaults for Session Persistence**
- **Rationale:** Simple, synchronous, sufficient for single active session + history
- **Tradeoff:** Not suitable for large datasets, but max 50 sessions is manageable

**Decision 3: @MainActor for ParkingSessionManager**
- **Rationale:** Ensures all UI updates happen on main thread, prevents race conditions
- **Tradeoff:** Less flexible for background work, but session operations are fast

**Decision 4: Protocol-Based Dependency Injection**
- **Rationale:** Enables testing, follows existing app architecture patterns
- **Tradeoff:** More boilerplate, but better separation of concerns

**Decision 5: SwiftUI Sheet Presentation**
- **Rationale:** Native iOS modal pattern, supports standard swipe-down dismissal
- **Tradeoff:** Less customization than custom modals, but more familiar to users

---

## Overview

This document outlines the end-to-end implementation plan for adding street cleaning support to the SF Parking Zone Finder app. Street cleaning is a critical parking restriction in San Francisco that helps users avoid tickets and plan their parking accordingly.

### Goals

**P0 (Must Have - MVP):**
- Display street cleaning schedules in parking rules cards
- Integrate street cleaning into "Park Until" feature
- Show active street cleaning warnings
- Help users avoid tickets with early context on moving their car

**P1 (Enhanced Experience):**
- Calendar view showing upcoming street cleaning days
- Local notifications reminding users before street cleaning
- Map visualization of active/upcoming street cleaning zones

**P2 (Advanced Features):**
- Parking scheduling feature (set desired parking duration)
- Smart parking suggestions avoiding street cleaning conflicts
- Multi-day parking planning

---

## Architecture Overview

### Current State ✅

The app architecture is **remarkably well-prepared** for street cleaning:

1. **Data Model:** `ParkingRule` fully supports street cleaning
   - `RuleType.streetCleaning` enum case (line 91 in ParkingRule.swift)
   - Enforcement days/times (`enforcementDays`, `enforcementStartTime`, `enforcementEndTime`)
   - Active rule checking: `isInEffect(at: Date)` method

2. **Warning System:** Complete infrastructure exists
   - `ParkingWarning` with `.streetCleaning` type
   - `RuleInterpreter.generateWarnings()` checks street cleaning rules (lines 142-151)
   - High severity warnings for active cleaning

3. **"Park Until" Feature:** Fully implemented in `ValidityBadgeView`
   - Calculates next enforcement period
   - Shows "Park until Tue 8:00 AM" for enforcement gaps
   - Handles multi-day gaps (weekends → Monday)
   - Already integrated in zone cards

4. **UI Components:** Ready for display
   - Zone cards with flipable rules display
   - Map overlay system for zone visualization
   - Badge system for status indicators

### Missing Pieces ❌

- **No street cleaning data** in `sf_parking_zones.json`
- **Backend doesn't fetch** street cleaning from DataSF
- **No notification system** (iOS push notifications not implemented)
- **No calendar view** for upcoming cleanings
- **No specific map visualization** for active street cleaning

---

## Implementation Plan

### Phase 1: Backend Data Integration (P0)

**Priority:** CRITICAL
**Estimated Effort:** 2-3 days

#### 1.1 Data Source Investigation

**Task:** Identify street cleaning data in DataSF

**Known fields to investigate:**
```python
# DataSF Blockface API likely contains:
{
    "hrs_begin": "0800",        # Start time
    "hrs_end": "1000",          # End time
    "hrs_days": "Mon,Thu",      # Days of week
    "streetswp_days": "...",    # Street sweeping specific?
    "streetswp_time": "...",    # Street sweeping time?
}
```

**Approach:**
1. Query DataSF Blockface API for sample records
2. Identify which fields indicate street cleaning vs. general time limits
3. Determine heuristics for classification (e.g., "2-hour limit" vs. "street cleaning")
4. Document data quality and coverage

**Files to explore:**
- DataSF API documentation
- Existing `backend/fetchers/blockface_fetcher.py`

#### 1.2 Backend Pipeline Updates

**Files to modify:**
- `backend/fetchers/blockface_fetcher.py` - Add street cleaning field extraction
- `backend/transformers/parking_data_transformer.py` - Transform to ParkingRule format

**Pseudocode:**
```python
# In parking_data_transformer.py

def extract_street_cleaning_rule(blockface_record):
    """Extract street cleaning rule from blockface data"""

    # Identify street cleaning (vs. time limits)
    if not is_street_cleaning_record(blockface_record):
        return None

    # Parse enforcement schedule
    days = parse_enforcement_days(blockface_record['hrs_days'])
    start_time = parse_time(blockface_record['hrs_begin'])
    end_time = parse_time(blockface_record['hrs_end'])

    return {
        "id": generate_rule_id(),
        "ruleType": "street_cleaning",
        "description": f"Street cleaning {format_schedule(days, start_time, end_time)}",
        "enforcementDays": days,
        "enforcementStartTime": {"hour": start_time.hour, "minute": start_time.minute},
        "enforcementEndTime": {"hour": end_time.hour, "minute": end_time.minute},
        "timeLimit": None,
        "meterRate": None,
        "specialConditions": None
    }

def is_street_cleaning_record(record):
    """Heuristic to identify street cleaning vs. time limits"""
    # Option 1: Explicit field exists
    if 'streetswp_days' in record and record['streetswp_days']:
        return True

    # Option 2: Pattern matching on description
    desc = record.get('description', '').lower()
    if 'cleaning' in desc or 'sweeping' in desc:
        return True

    # Option 3: Time pattern (cleaning is usually short windows)
    duration_hours = calculate_duration(record['hrs_begin'], record['hrs_end'])
    if duration_hours <= 2 and record['hrs_days']:
        return True  # Likely cleaning

    return False
```

#### 1.3 Zone Association Strategy

**Challenge:** Street cleaning rules apply to specific street segments, which may span multiple parking zones.

**Approach:**
1. **Spatial Join:** Match street segments to parking zones by geographic overlap
2. **Multiple Zones:** If a street segment overlaps multiple zones, add the cleaning rule to all
3. **Validation:** Ensure each zone has consistent cleaning schedules

**Data Flow:**
```
DataSF Blockface API
    ↓
BlockfaceFetcher (extract street cleaning fields)
    ↓
ParkingDataTransformer (create ParkingRule objects)
    ↓
Zone Association (spatial join to ParkingZones)
    ↓
sf_parking_zones.json (with street cleaning rules)
    ↓
iOS App (display to users)
```

---

### Phase 2: UI/UX Integration (P0)

**Priority:** HIGH
**Estimated Effort:** 2 days

#### 2.1 Parking Rules Cards

**Current:** Rules displayed in `ZoneStatusCardView` and `AnimatedZoneCard`

**Changes needed:**

**File:** `SFParkingZoneFinder/Core/Services/RuleInterpreter.swift`

```swift
// Update generateRuleSummary() around line 105
private func generateRuleSummary(zone: ParkingZone, status: PermitValidityStatus) -> String {
    var lines: [String] = []

    // Zone type
    lines.append(zone.displayName)

    // Permit requirement
    if zone.requiresPermit, let area = zone.permitArea {
        lines.append("Residential permit Zone \(area) required")
    }

    // Time limits
    if let limit = zone.nonPermitTimeLimit {
        let hours = limit / 60
        let limitText = hours > 0 ? "\(hours)-hour" : "\(limit)-minute"
        lines.append("\(limitText) limit without permit")
        if let area = zone.permitArea {
            lines.append("No limit with Zone \(area) permit")
        }
    }

    // Enforcement hours
    if let hours = zone.enforcementHours {
        lines.append("Enforced \(hours)")
    }

    // ✅ NEW: Street cleaning
    let cleaningRules = zone.rules.filter { $0.ruleType == .streetCleaning }
    for rule in cleaningRules {
        if let schedule = rule.enforcementHoursDescription {
            lines.append("🧹 Street cleaning: \(schedule)")
        }
    }

    return lines.joined(separator: "\n")
}
```

**Expected Output:**
```
Zone Q
Residential permit Zone Q required
2-hour limit without permit
No limit with Zone Q permit
Enforced Mon-Fri, 8 AM - 6 PM
🧹 Street cleaning: Mon & Thu, 8:00 AM - 10:00 AM
```

#### 2.2 "Park Until" Feature Enhancement

**Current:** Already calculates enforcement gaps in `ValidityBadgeView.swift` (lines 44-160)

**Enhancement:** Add explicit street cleaning messaging

**File:** `SFParkingZoneFinder/Features/Main/Views/ValidityBadgeView.swift`

```swift
// Add after line 89 in parkUntilText computed property
private var parkUntilText: String? {
    guard (status == .invalid || status == .noPermitSet) else { return nil }

    // Check for active/upcoming street cleaning FIRST
    if let nextCleaning = getNextStreetCleaning() {
        return formatStreetCleaningWarning(nextCleaning)
    }

    // Then handle time limits (existing logic)
    guard let _ = timeLimitMinutes else { return nil }
    // ... existing logic ...
}

private func getNextStreetCleaning() -> ParkingRule? {
    // Find street cleaning rules in zone
    let cleaningRules = zone.rules.filter { $0.ruleType == .streetCleaning }

    // Check if any are active now
    let now = Date()
    if let active = cleaningRules.first(where: { $0.isInEffect(at: now) }) {
        return active
    }

    // Find next upcoming (within 24 hours)
    let tomorrow = now.addingTimeInterval(24 * 60 * 60)
    if let upcoming = cleaningRules.first(where: {
        $0.isInEffect(at: tomorrow)
    }) {
        return upcoming
    }

    return nil
}

private func formatStreetCleaningWarning(_ rule: ParkingRule) -> String {
    if rule.isInEffect(at: Date()) {
        return "MOVE NOW - STREET CLEANING ACTIVE"
    } else if let startTime = rule.enforcementStartTime {
        return "MOVE BY \(startTime.formatted) - STREET CLEANING"
    }
    return "STREET CLEANING UPCOMING"
}
```

#### 2.3 Warning Banners

**New Component:** `WarningBannerView.swift`

**File:** Create `SFParkingZoneFinder/Features/Main/Views/WarningBannerView.swift`

```swift
import SwiftUI

/// Prominent banner for critical parking warnings
struct WarningBannerView: View {
    let warning: ParkingWarning

    private var backgroundColor: Color {
        switch warning.severity {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    private var icon: String {
        switch warning.type {
        case .streetCleaning: return "leaf.fill"
        case .towAway: return "exclamationmark.triangle.fill"
        case .timeLimit: return "clock.fill"
        case .meterExpiring: return "dollarsign.circle.fill"
        case .specialEvent: return "calendar.badge.exclamationmark"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)

            Text(warning.message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
```

**Integration in MainResultView:**

```swift
// Add to MainResultView around line 140, before AnimatedZoneCard
if !viewModel.warnings.isEmpty {
    VStack(spacing: 8) {
        ForEach(viewModel.warnings) { warning in
            WarningBannerView(warning: warning)
        }
    }
    .padding(.horizontal)
    .padding(.top, 8)
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

---

### Phase 3: Map Visualization (P1)

**Priority:** MEDIUM
**Estimated Effort:** 2 days

#### 3.1 Active Street Cleaning Overlay

**Approach:** Add visual indicator to zones with active/upcoming street cleaning

**File:** `SFParkingZoneFinder/Features/Map/Services/ZoneColorProvider.swift`

```swift
// Add new zone category
enum ZoneCategory {
    case currentZone
    case myPermitZones
    case freeTimedZones
    case paidZones
    case activeStreetCleaning  // NEW
}

// Update color logic
func color(for zone: ParkingZone, category: ZoneCategory) -> UIColor {
    switch category {
    case .activeStreetCleaning:
        return UIColor.systemRed
    // ... existing cases
    }
}

// Add helper method
func hasActiveStreetCleaning(_ zone: ParkingZone, at date: Date = Date()) -> Bool {
    return zone.rules.contains { rule in
        rule.ruleType == .streetCleaning && rule.isInEffect(at: date)
    }
}
```

**File:** `SFParkingZoneFinder/Features/Map/Views/ZoneMapView.swift`

```swift
// Update polygon rendering to check for active street cleaning
private func addZoneOverlay(_ zone: ParkingZone) {
    let category: ZoneCategory

    // Priority 1: Active street cleaning (highest priority visual)
    if ZoneColorProvider.hasActiveStreetCleaning(zone) {
        category = .activeStreetCleaning
    }
    // Priority 2: Current zone
    else if zone.id == currentZoneId {
        category = .currentZone
    }
    // ... existing priority logic

    let fillColor = colorProvider.fillColor(for: zone, category: category)
    let strokeColor = colorProvider.strokeColor(for: zone, category: category)

    // Add dashed stroke for street cleaning
    if category == .activeStreetCleaning {
        polygon.strokePattern = [8, 4]  // Dashed line
    }
}
```

#### 3.2 Developer Settings Integration

**File:** `SFParkingZoneFinder/Features/Main/Views/DeveloperMapOverlay.swift`

Add controls for street cleaning visualization:

```swift
// In colorSettings section, add:
Divider()
    .padding(.vertical, 4)

// Active Street Cleaning
zoneColorGroup(
    label: "Active St. Cleaning",
    colorHex: $devSettings.streetCleaningColorHex,
    previewColor: devSettings.streetCleaningColor,
    fillOpacity: $devSettings.streetCleaningFillOpacity,
    strokeOpacity: $devSettings.streetCleaningStrokeOpacity
)
```

**File:** `SFParkingZoneFinder/Core/Services/DeveloperSettings.swift`

Add new properties:

```swift
@Published var streetCleaningColorHex: String = "FF3B30"  // iOS red
@Published var streetCleaningFillOpacity: Double = 0.2
@Published var streetCleaningStrokeOpacity: Double = 0.8

var streetCleaningColor: UIColor {
    UIColor(hex: streetCleaningColorHex) ?? .systemRed
}
```

---

### Phase 4: Calendar & Notifications (P1)

**Priority:** MEDIUM
**Estimated Effort:** 5 days

#### 4.1 Street Cleaning Calendar View

**New Component:** `StreetCleaningCalendarView.swift`

**File:** Create `SFParkingZoneFinder/Features/Main/Views/StreetCleaningCalendarView.swift`

```swift
import SwiftUI

/// Weekly calendar showing street cleaning schedule
struct StreetCleaningCalendarView: View {
    let zone: ParkingZone
    @State private var currentWeekOffset = 0  // 0 = this week, 1 = next week, etc.

    private var cleaningRules: [ParkingRule] {
        zone.rules.filter { $0.ruleType == .streetCleaning }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let offset = currentWeekOffset * 7

        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day + offset, to: weekStart)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Street Cleaning Schedule")
                    .font(.headline)

                Spacer()

                // Week navigation
                HStack {
                    Button {
                        currentWeekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentWeekOffset <= 0)

                    Text(weekLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        currentWeekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentWeekOffset >= 4)  // Max 4 weeks ahead
                }
            }

            // Calendar grid
            HStack(spacing: 4) {
                ForEach(weekDays, id: \.self) { date in
                    DayCell(
                        date: date,
                        hasStartCleaning: hasStreetCleaning(on: date),
                        cleaningTime: getCleaningTime(on: date)
                    )
                }
            }

            // Next cleaning banner
            if let next = nextCleaningDate {
                NextCleaningBanner(date: next)
            }

            // Add to Calendar button
            Button {
                addToCalendar()
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                    Text("Add to Calendar")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    private var weekLabel: String {
        if currentWeekOffset == 0 {
            return "This Week"
        } else if currentWeekOffset == 1 {
            return "Next Week"
        } else {
            return "\(currentWeekOffset) weeks ahead"
        }
    }

    private func hasStreetCleaning(on date: Date) -> Bool {
        cleaningRules.contains { $0.isInEffect(at: date) }
    }

    private func getCleaningTime(on date: Date) -> String? {
        guard let rule = cleaningRules.first(where: { $0.isInEffect(at: date) }),
              let startTime = rule.enforcementStartTime else {
            return nil
        }
        return startTime.formatted
    }

    private var nextCleaningDate: Date? {
        let now = Date()
        let twoWeeks = now.addingTimeInterval(14 * 24 * 60 * 60)

        var checkDate = now
        while checkDate < twoWeeks {
            if hasStreetCleaning(on: checkDate) {
                return checkDate
            }
            checkDate = checkDate.addingTimeInterval(24 * 60 * 60)
        }
        return nil
    }

    private func addToCalendar() {
        // TODO: Integrate with EventKit to add reminders
        print("Add to calendar tapped")
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let hasCleaning: Bool
    let cleaningTime: String?

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayName)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(dayNumber)
                .font(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isToday ? .blue : .primary)

            if hasCleaning {
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundColor(.red)

                if let time = cleaningTime {
                    Text(time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isToday ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Next Cleaning Banner

private struct NextCleaningBanner: View {
    let date: Date

    private var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private var daysUntil: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days == 0 {
            return "today"
        } else if days == 1 {
            return "tomorrow"
        } else {
            return "in \(days) days"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Next cleaning: \(formattedDate)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("(\(daysUntil))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }
}
```

**Integration:**
Add to `MainResultView` as an expandable section below the zone card.

#### 4.2 Notification Service

**New Service:** `NotificationService.swift`

**File:** Create `SFParkingZoneFinder/Core/Services/NotificationService.swift`

```swift
import Foundation
import UserNotifications
import CoreLocation

protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func scheduleStreetCleaningReminder(for zone: ParkingZone, rule: ParkingRule, location: CLLocation)
    func cancelAllReminders()
    func cancelReminder(for ruleId: String)
}

final class NotificationService: NotificationServiceProtocol {

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func scheduleStreetCleaningReminder(
        for zone: ParkingZone,
        rule: ParkingRule,
        location: CLLocation
    ) {
        guard let startTime = rule.enforcementStartTime,
              let days = rule.enforcementDays else {
            return
        }

        // Schedule two notifications:
        // 1. Night before (8 PM)
        // 2. Morning of (1 hour before)

        for day in days {
            // Night before notification
            scheduleNotification(
                id: "cleaning_\(rule.id)_\(day.rawValue)_evening",
                title: "🧹 Street Cleaning Tomorrow",
                body: "Move your car by \(startTime.formatted) on \(zone.displayName)",
                weekday: day.calendarWeekday,
                hour: 20,  // 8 PM
                minute: 0
            )

            // Morning of notification (1 hour before)
            let reminderHour = max(startTime.hour - 1, 6)  // At least 6 AM
            scheduleNotification(
                id: "cleaning_\(rule.id)_\(day.rawValue)_morning",
                title: "⚠️ Street Cleaning in 1 Hour",
                body: "Move your car on \(zone.displayName) by \(startTime.formatted)",
                weekday: day.calendarWeekday,
                hour: reminderHour,
                minute: startTime.minute
            )
        }
    }

    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        weekday: Int,
        hour: Int,
        minute: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "STREET_CLEANING"

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }

    func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func cancelReminder(for ruleId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.contains(ruleId) }
                .map { $0.identifier }

            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: identifiers
            )
        }
    }
}
```

**Settings Integration:**

Add to `SettingsView.swift`:

```swift
Section("Notifications") {
    Toggle("Street Cleaning Reminders", isOn: $notificationsEnabled)
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    let granted = await notificationService.requestPermission()
                    if granted {
                        scheduleRemindersForCurrentLocation()
                    } else {
                        notificationsEnabled = false
                    }
                }
            } else {
                notificationService.cancelAllReminders()
            }
        }

    if notificationsEnabled {
        Text("Get reminders before street cleaning in your saved locations")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

---

### Phase 5: Parking Scheduler (P2 - Future)

**Priority:** LOW
**Estimated Effort:** 5 days

*(Deferred to future iteration - see separate design doc when prioritized)*

---

## Data Model Extensions

### ParkingZone Extensions

**File:** `SFParkingZoneFinder/Core/Models/ParkingZone.swift`

Add computed properties:

```swift
extension ParkingZone {
    /// All street cleaning rules for this zone
    var streetCleaningRules: [ParkingRule] {
        rules.filter { $0.ruleType == .streetCleaning }
    }

    /// Whether zone has street cleaning
    var hasStreetCleaning: Bool {
        !streetCleaningRules.isEmpty
    }

    /// Human-readable street cleaning schedule
    var streetCleaningSchedule: String? {
        guard !streetCleaningRules.isEmpty else { return nil }

        let schedules = streetCleaningRules.compactMap { $0.enforcementHoursDescription }
        return schedules.joined(separator: " and ")
    }

    /// Next street cleaning event
    func nextStreetCleaning(from date: Date = Date()) -> (rule: ParkingRule, date: Date)? {
        var checkDate = date
        let maxDays = 14  // Check next 2 weeks

        for _ in 0..<maxDays {
            for rule in streetCleaningRules {
                if rule.isInEffect(at: checkDate) {
                    return (rule, checkDate)
                }
            }
            checkDate = checkDate.addingTimeInterval(24 * 60 * 60)
        }

        return nil
    }
}
```

---

## Testing Strategy

### Unit Tests

**File:** Create `SFParkingZoneFinderTests/StreetCleaningTests.swift`

```swift
import XCTest
@testable import SFParkingZoneFinder

final class StreetCleaningTests: XCTestCase {

    func testStreetCleaningRuleDetection() {
        // Given: A zone with street cleaning
        let cleaningRule = ParkingRule(
            id: "test_cleaning",
            ruleType: .streetCleaning,
            description: "Street cleaning Mon & Thu 8-10 AM",
            enforcementDays: [.monday, .thursday],
            enforcementStartTime: TimeOfDay(hour: 8, minute: 0),
            enforcementEndTime: TimeOfDay(hour: 10, minute: 0),
            timeLimit: nil,
            meterRate: nil,
            specialConditions: nil
        )

        // When: Checking if in effect on Monday at 9 AM
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 2  // Monday
        components.hour = 9
        components.minute = 0
        let testDate = calendar.date(from: components)!

        // Then: Rule should be in effect
        XCTAssertTrue(cleaningRule.isInEffect(at: testDate))
    }

    func testParkUntilCalculationWithCleaning() {
        // Test that "Park until" correctly shows cleaning deadline
    }

    func testMultipleCleaningDays() {
        // Test zones with cleaning multiple days per week
    }

    func testNextCleaningCalculation() {
        // Test finding next cleaning event
    }
}
```

### Integration Tests

1. **Backend Pipeline Test:**
   - Load sample DataSF Blockface data
   - Verify street cleaning rules extracted correctly
   - Validate JSON output format

2. **UI Display Test:**
   - Zone card shows street cleaning in rules
   - "Park until" displays cleaning deadline
   - Warning banners appear for active cleaning

3. **Notification Test:**
   - Notifications schedule correctly for weekly recurring events
   - Cancellation works properly

### Manual Testing Checklist

- [ ] Load known SF addresses with street cleaning
- [ ] Verify cleaning schedule displays in card
- [ ] Test "park until" at different times (before/during/after enforcement)
- [ ] Test warning banners show/hide correctly
- [ ] Test calendar view shows correct days
- [ ] Test notifications fire at correct times
- [ ] Test map overlay highlights active cleaning zones

**Known SF Test Addresses:**
- Mission District (heavy street cleaning)
- Pacific Heights (varied schedules)
- SOMA (commercial cleaning)

---

## Performance Considerations

### Data Size Impact

- Estimated 5,000-10,000 additional ParkingRule objects for SF
- JSON file size increase: +200-500 KB
- Memory impact: Minimal (rules loaded on demand per zone)

### Optimization Strategies

1. **Lazy Loading:** Only load street cleaning rules when zone is active
2. **Caching:** Cache next cleaning calculation results
3. **Indexing:** Index rules by day of week for faster lookup

---

## Success Metrics

### User Engagement
- % of users viewing street cleaning info
- % of users enabling notifications
- Calendar view interactions

### Ticket Avoidance
- User feedback on avoiding tickets
- Notification effectiveness (open rate)

### Technical Metrics
- Data coverage: % of SF streets with cleaning data
- Data accuracy: User-reported errors
- Performance: Rule lookup time < 50ms

---

## Future Enhancements (Beyond P2)

1. **Multi-City Support:** Expand to other cities with street cleaning
2. **Historical Data:** "Last cleaned X days ago"
3. **Crowdsourced Updates:** Users report cleaning schedule changes
4. **Smart Parking Finder:** "Find parking without cleaning this week"
5. **Integration with City APIs:** Real-time cleaning schedule updates

---

## Appendix

### Data Sources

- **DataSF Blockface API:** https://data.sfgov.org/Transportation/Blockface-parking/...
- **SFMTA Street Sweeping:** https://www.sfmta.com/getting-around/drive-park/street-sweeping

### Related Documentation

- `TechnicalArchitecture.md` - Overall app architecture
- `Backend.md` - ETL pipeline details
- `EngineeringProjectPlan.md` - Development phases

### Questions & Decisions Log

| Date | Question | Decision | Rationale |
|------|----------|----------|-----------|
| 2025-11-26 | Use embedded JSON vs. live API? | Embedded for V1 | Matches current architecture, simpler deployment |
| TBD | Notification timing strategy? | TBD | Need user research on preferences |
| TBD | Map visualization complexity? | TBD | Balance utility vs. visual clutter |

---

**Last Updated:** 2025-11-26
**Next Review:** After Phase 1 completion
