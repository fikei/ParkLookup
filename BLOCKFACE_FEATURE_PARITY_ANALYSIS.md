# Blockface Feature Parity Analysis

**Goal**: Ensure the app functions identically whether using Zone Polygons or Blockfaces. Only the data source and calculation methods should differ.

**Date**: 2025-11-29
**Branch**: `claude/fix-block-face-colors-01FzcFoJ8L7eTjuRMhZyZUQg`
**Status**: ~60% Complete (UI integration done, feature parity incomplete)

---

## Current Implementation Status

### ✅ Implemented Features

1. **Basic Data Mapping**
   - Location name display (zone name or street name)
   - Primary regulation type detection
   - Permit area extraction
   - Time limit extraction
   - Enforcement hours extraction
   - Basic permit validity determination

2. **UI Integration**
   - Blockface data flows to spot card when feature flag enabled
   - Fallback to zone data if blockface lookup fails
   - Rule summary generation from regulations
   - Map visualization with colored blockface overlays

3. **Basic Warnings**
   - Street cleaning active warning
   - No parking warning

---

## 🔴 Missing Features for Complete Parity

### 1. **Comprehensive Warning System**

**Current Zone Implementation** (RuleInterpreter.swift):
- Street cleaning warnings when active
- Tow-away zone warnings
- Generated based on rule type and time

**What's Missing for Blockfaces**:
```swift
// Need to add to updateStateFromBlockface():

// Time limit warnings
if let timeLimit = result.timeLimitMinutes, timeLimit <= 120 {
    warnings.append(ParkingWarning(
        type: .timeLimit,
        message: "\(timeLimit/60)-hour time limit applies",
        severity: .medium
    ))
}

// Upcoming street cleaning
if let nextRestriction = result.nextRestriction,
   nextRestriction.type == .streetCleaning {
    let hoursUntil = nextRestriction.startsAt.timeIntervalSinceNow / 3600
    if hoursUntil > 0 && hoursUntil <= 24 {
        warnings.append(ParkingWarning(
            type: .streetCleaning,
            message: "Street cleaning in \(Int(hoursUntil)) hours",
            severity: hoursUntil <= 2 ? .high : .medium
        ))
    }
}

// Tow-away/no parking warnings (already have basic version)
```

**File to Modify**: `MainResultViewModel.swift:553-664` (updateStateFromBlockface)

---

### 2. **Conditional Flags**

**Current Zone Implementation** (RuleInterpreter.swift:81-103):
- Time of day restrictions
- Meter required flags

**What's Missing for Blockfaces**:
```swift
// Add to updateStateFromBlockface():

// Time-based restrictions
if let enforcement = result.allRegulations.first(where: {
    $0.enforcementDays != nil || $0.enforcementStart != nil
}) {
    conditionalFlags.append(ConditionalFlag(
        type: .timeOfDayRestriction,
        description: "Time restrictions apply",
        requiresImplementation: false
    ))
}

// Meter required
if result.primaryRegulationType == .metered {
    conditionalFlags.append(ConditionalFlag(
        type: .meterRequired,
        description: "Meter payment required during enforcement hours",
        requiresImplementation: false
    ))
}

// Day of week restrictions
if let regulation = result.allRegulations.first(where: {
    !($0.enforcementDays?.isEmpty ?? true)
}) {
    if let days = regulation.enforcementDays, days.count < 7 {
        let dayList = days.map { $0.abbreviation }.joined(separator: ", ")
        conditionalFlags.append(ConditionalFlag(
            type: .dayOfWeekRestriction,
            description: "Restrictions apply: \(dayList)",
            requiresImplementation: false
        ))
    }
}
```

**File to Modify**: `MainResultViewModel.swift:644-646`

---

### 3. **Metered Zone Details**

**Current Implementation**:
```swift
meteredSubtitle = "$2/hr • 2hr max"  // TODO: Get from blockface data
```

**What's Needed**:
Extract actual rate and time limit from metered regulation:
```swift
if result.primaryRegulationType == .metered {
    // Find metered regulation
    if let meteredReg = result.allRegulations.first(where: {
        $0.type == .metered
    }) {
        var parts: [String] = []

        // Extract rate (need to add to BlockfaceRegulation model)
        // For now, use default
        parts.append("$2/hr")

        // Extract time limit
        if let limit = meteredReg.timeLimit {
            let hours = limit / 60
            parts.append("\(hours)hr max")
        }

        meteredSubtitle = parts.joined(separator: " • ")
    } else {
        meteredSubtitle = "Metered parking"
    }
}
```

**Files to Modify**:
- `MainResultViewModel.swift:563` (updateStateFromBlockface)
- `Blockface.swift` - Add `rate` field to `BlockfaceRegulation` if not present

---

### 4. **Park Until Calculation**

**Current Implementation**:
- Park Until calculated in MainResultView based on ViewModel properties
- Complex logic for enforcement hours, time limits, day of week

**What's Needed**:
The adapter already has `calculateParkUntil()` - we need to call it and store the result.

Add to MainResultViewModel:
```swift
@Published private(set) var parkUntilTime: Date? = nil
@Published private(set) var parkUntilReason: String? = nil
```

Update in `updateStateFromBlockface()`:
```swift
// Calculate Park Until time using adapter
if validityStatus == .invalid || validityStatus == .noPermitSet {
    let userPermitSet = Set(userPermits.map { $0.area })
    if let parkUntilResult = ParkingDataAdapter.shared.calculateParkUntil(
        for: result,
        userPermits: userPermitSet,
        parkingStartTime: Date()
    ) {
        parkUntilTime = parkUntilResult.parkUntilTime
        parkUntilReason = parkUntilResult.reason
    }
}
```

Update MainResultView to use `parkUntilTime` when available:
```swift
private var parkUntilText: String? {
    // If blockface mode and we have a calculated time, use it
    if DeveloperSettings.shared.useBlockfaceForFeatures,
       let until = viewModel.parkUntilTime {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Park until \(formatter.string(from: until))"
    }

    // Otherwise use existing zone-based calculation
    guard (validityStatus == .invalid || validityStatus == .noPermitSet),
          let _ = timeLimitMinutes else { return nil }
    // ... existing logic
}
```

**Files to Modify**:
- `MainResultViewModel.swift` - Add properties and calculation
- `MainResultView.swift:484-533` - Use blockface Park Until when available

---

### 5. **Next Restriction Display**

**Current Implementation**: None in zone system

**Adapter Provides**: `result.nextRestriction` (RestrictionWindow)

**What's Needed**:
```swift
// Add to MainResultViewModel
@Published private(set) var nextRestriction: RestrictionWindow? = nil

// In updateStateFromBlockface():
nextRestriction = result.nextRestriction

// Create UI component to display next restriction
// Show countdown: "Street cleaning in 3 hours" or "Meter enforcement starts in 2 hours"
```

**Files to Modify**:
- `MainResultViewModel.swift` - Add nextRestriction property
- `MainResultView.swift` - Add UI to display next restriction
- Consider adding to warnings section or as separate card

---

### 6. **Parking Session Management**

**Current Implementation**: `createSessionRules()` uses zone data

**What's Needed**:
Create blockface-aware version:
```swift
private func createSessionRulesFromBlockface(_ result: ParkingLookupResult) -> [SessionRule] {
    var rules: [SessionRule] = []

    // Add time limit rule
    if let parkUntilResult = ParkingDataAdapter.shared.calculateParkUntil(
        for: result,
        userPermits: Set(userPermits.map { $0.area }),
        parkingStartTime: Date()
    ) {
        rules.append(SessionRule(
            type: .timeLimit,
            description: parkUntilResult.reason,
            deadline: parkUntilResult.parkUntilTime
        ))
    }

    // Add next restriction rule
    if let nextRestriction = result.nextRestriction {
        rules.append(SessionRule(
            type: nextRestriction.type == .streetCleaning ? .streetCleaning : .timeLimit,
            description: nextRestriction.description,
            deadline: nextRestriction.startsAt
        ))
    }

    // Add enforcement hours info
    if let reg = result.allRegulations.first(where: {
        $0.enforcementStart != nil
    }) {
        if let start = reg.enforcementStart, let end = reg.enforcementEnd {
            let enforcementText = "\(start) - \(end)"
            if let days = reg.enforcementDays {
                let dayText = days.map { $0.abbreviation }.joined(separator: ", ")
                rules.append(SessionRule(
                    type: .enforcement,
                    description: "Enforced \(dayText) \(enforcementText)",
                    deadline: nil
                ))
            }
        }
    }

    return rules
}
```

Update `startParkingSession()`:
```swift
func startParkingSession() async {
    // ... existing coordinate check ...

    let rules: [SessionRule]

    if DeveloperSettings.shared.useBlockfaceForFeatures {
        // Get blockface result
        if let blockfaceResult = await ParkingDataAdapter.shared.lookupParking(at: coordinate) {
            rules = createSessionRulesFromBlockface(blockfaceResult)
        } else {
            rules = createSessionRules() // Fallback to zone
        }
    } else {
        rules = createSessionRules()
    }

    await parkingSessionManager.startSession(
        location: coordinate,
        address: currentAddress != "Locating..." ? currentAddress : nil,
        zoneName: zoneName,
        zoneType: zoneType,
        rules: rules
    )
}
```

**Files to Modify**:
- `MainResultViewModel.swift:283-302` (startParkingSession)
- `MainResultViewModel.swift:589-650` (add createSessionRulesFromBlockface)

---

### 7. **Overlapping Zones Equivalent**

**Zone System**: Shows overlapping zones when multiple zones cover same location

**Blockface System**: Multiple blockfaces can be nearby

**What's Needed**:
```swift
// In updateStateFromBlockface():
// Instead of overlapping zones, show nearby blockface options

// This requires modifying BlockfaceDataAdapter.lookupParking() to return
// not just the selected blockface, but also nearby alternatives

// For now, set to empty since blockfaces are more precise
overlappingZones = []
hasOverlappingZones = false

// Alternative: Store nearby blockfaces in adapter result
// and display them as "Nearby streets" instead of "Overlapping zones"
```

**Decision Needed**:
- Do we want to show nearby blockfaces as alternatives?
- Or is the single blockface selection sufficient?
- If showing nearby, need UI redesign

**Files to Consider**:
- `ParkingDataAdapter.swift:130-159` (lookupParking)
- `ParkingLookupResult.swift` - Add nearbyAlternatives field?
- `MainResultView.swift` - Update overlapping zones section

---

### 8. **All Valid Permit Areas**

**Zone System**: Collects all permit areas from overlapping RPP zones

**Blockface System**: Currently only shows permit areas from selected blockface

**What's Needed**:
```swift
// If showing nearby blockfaces:
allValidPermitAreas = [selected blockface permits] + [nearby blockface permits]

// Current implementation (selected only):
allValidPermitAreas = result.permitAreas ?? []  // ✅ Already correct
```

**Status**: ✅ Adequate for single blockface selection

---

### 9. **Rule Summary Formatting**

**Current Implementation**: Basic formatting with days/times

**Zone System Equivalent** (RuleInterpreter.swift:105-142):
```
Zone Q
Residential permit Zone Q required
2-hour limit without permit
No limit with Zone Q permit
Enforced Mon-Fri 8AM-6PM
Street cleaning: Wed 10AM-12PM
```

**What's Needed**:
Enhance rule summary to match zone format:
```swift
// In updateStateFromBlockface():
var summaryLines: [String] = []

// 1. Location name
summaryLines.append(result.locationName)

// 2. Permit requirement
if let permitAreas = result.permitAreas, !permitAreas.isEmpty {
    let hasMatching = !applicablePermits.isEmpty
    if hasMatching {
        summaryLines.append("Residential permit Zone \(permitAreas[0]) required")
    } else {
        summaryLines.append("Residential Permit Required for Long Term Parking")
    }
}

// 3. Time limits
if let timeLimit = result.timeLimitMinutes {
    let hours = timeLimit / 60
    let limitText = hours > 0 ? "\(hours)-hour" : "\(timeLimit)-minute"

    if let permitArea = result.permitAreas?.first {
        summaryLines.append("\(limitText) limit without permit")
        summaryLines.append("No limit with Zone \(permitArea) permit")
    } else {
        summaryLines.append("\(limitText) parking limit")
    }
}

// 4. Enforcement hours
if let reg = result.allRegulations.first(where: {
    $0.enforcementStart != nil
}) {
    var enforcementText = ""
    if let days = reg.enforcementDays, !days.isEmpty, days.count < 7 {
        enforcementText += days.map { $0.abbreviation }.joined(separator: ", ") + " "
    }
    if let start = reg.enforcementStart, let end = reg.enforcementEnd {
        enforcementText += "\(start)-\(end)"
    }
    if !enforcementText.isEmpty {
        summaryLines.append("Enforced \(enforcementText)")
    }
}

// 5. Street cleaning schedule
if let cleaningReg = result.allRegulations.first(where: {
    $0.type == .streetCleaning
}) {
    var cleaningText = "Street cleaning: "
    if let days = cleaningReg.enforcementDays {
        cleaningText += days.map { $0.rawValue }.joined(separator: ", ") + " "
    }
    if let start = cleaningReg.enforcementStart,
       let end = cleaningReg.enforcementEnd {
        cleaningText += "\(start)-\(end)"
    }
    summaryLines.append(cleaningText)
}

// 6. Regulation descriptions (for other types)
for reg in result.allRegulations {
    if reg.type != .streetCleaning &&
       reg.type != .residentialPermit &&
       reg.type != .metered {
        summaryLines.append(reg.description)
    }
}

ruleSummaryLines = summaryLines
ruleSummary = summaryLines.joined(separator: "\n")
```

**Files to Modify**:
- `MainResultViewModel.swift:629-642` (updateStateFromBlockface)

---

## 📊 Implementation Priority

### Priority 1: Critical for Basic Parity (1-2 days)
1. ✅ Metered zone details extraction
2. ✅ Enhanced rule summary formatting
3. ✅ Comprehensive warnings
4. ✅ Conditional flags

### Priority 2: Important for Full Parity (2-3 days)
5. ✅ Park Until calculation
6. ✅ Parking session management with blockface rules
7. ✅ Next restriction display

### Priority 3: Nice to Have (1 day)
8. ⚪ Nearby blockfaces (overlapping zones equivalent)
9. ⚪ Enhanced metered regulation data (add rate field)

---

## 📝 Implementation Plan

### Phase 1: Complete Core Features (Today)
- [ ] Add comprehensive warnings to updateStateFromBlockface
- [ ] Add conditional flags to updateStateFromBlockface
- [ ] Enhance rule summary formatting
- [ ] Extract metered zone details properly
- [ ] Test with various blockface scenarios

### Phase 2: Park Until & Sessions (Next)
- [ ] Add parkUntilTime and parkUntilReason properties
- [ ] Call calculateParkUntil in updateStateFromBlockface
- [ ] Update MainResultView to use blockface Park Until
- [ ] Create createSessionRulesFromBlockface method
- [ ] Update startParkingSession to use blockface rules
- [ ] Test parking sessions with blockface data

### Phase 3: Next Restriction & Polish (Final)
- [ ] Add nextRestriction property
- [ ] Create UI to display next restriction
- [ ] Add countdown timer for upcoming restrictions
- [ ] Test all UI states (valid permit, invalid, metered, etc.)
- [ ] Compare zone vs blockface results side-by-side

### Phase 4: Validation (Before Release)
- [ ] Enable useBlockfaceForFeatures flag
- [ ] Walk through all test scenarios:
  - RPP zone with valid permit
  - RPP zone without permit
  - Metered zone
  - Street cleaning active
  - Time limited parking
  - No parking zones
  - Free parking areas
- [ ] Verify UI matches exactly between zone/blockface modes
- [ ] Verify Park Until times are accurate
- [ ] Verify parking sessions work correctly
- [ ] Performance test with 18,355 blockfaces

---

## 🔍 Testing Checklist

### Zone Feature → Blockface Equivalent

| Feature | Zone System | Blockface System | Status |
|---------|-------------|------------------|--------|
| Location name | Zone code (Q, X, etc.) | Street name or Zone X | ✅ |
| Permit validity | Check permit areas | Check permit areas | ✅ |
| Time limits | nonPermitTimeLimit | regulation.timeLimit | ✅ |
| Enforcement hours | zone.enforcementHours | regulation.enforcement* | ✅ |
| Street cleaning | zone.streetCleaning | regulation type="streetCleaning" | ⚠️ |
| Metered details | zone.meteredSubtitle | regulation type="metered" | ❌ |
| Park Until | Calculated in view | calculateParkUntil() | ❌ |
| Warnings | RuleInterpreter | updateStateFromBlockface | ⚠️ |
| Conditional flags | RuleInterpreter | updateStateFromBlockface | ❌ |
| Session rules | createSessionRules() | Need blockface version | ❌ |
| Overlapping zones | Multiple zones | N/A (single blockface) | ⚪ |
| Rule summary | generateRuleSummary() | Enhanced formatting | ⚠️ |
| Next restriction | N/A | RestrictionWindow | ❌ |

**Legend**: ✅ Complete | ⚠️ Partial | ❌ Missing | ⚪ Not Applicable

---

## 📄 Files Requiring Changes

### MainResultViewModel.swift
- Line 553-678: `updateStateFromBlockface()` - enhance with all missing features
- Line 283-302: `startParkingSession()` - add blockface support
- Line 589-650: Add `createSessionRulesFromBlockface()`
- Add new properties: `parkUntilTime`, `parkUntilReason`, `nextRestriction`

### MainResultView.swift
- Line 484-533: `parkUntilText` - use blockface Park Until when available
- Add UI for next restriction display (new section)

### Blockface.swift (if needed)
- Add `rate` field to `BlockfaceRegulation` for metered zones

### ParkingDataAdapter.swift (optional)
- Line 130-159: Consider returning nearby blockfaces for "overlapping" display

---

## 🎯 Success Criteria

**The migration is complete when:**
1. ✅ User cannot tell difference between zone/blockface mode (except data shown)
2. ✅ All UI elements display correctly in both modes
3. ✅ Park Until times are accurate for both modes
4. ✅ Parking sessions work identically in both modes
5. ✅ Warnings and flags appear correctly in both modes
6. ✅ Rule summaries are formatted consistently
7. ✅ Performance is acceptable with full blockface dataset

**Test**: Enable feature flag, compare same location with both modes. Should be visually identical with different underlying data.

---

## 💡 Key Insights

**Why This Matters**:
- Users should experience NO difference in functionality
- Only developers/PM should know which data source is active
- Allows A/B testing and gradual migration
- Provides safe rollback if blockface data has issues

**Design Philosophy**:
- Blockface adapter provides richer data (next restriction, regulation details)
- UI should leverage this while maintaining zone compatibility
- View Model acts as translation layer between data sources
- View logic remains unchanged (reads same published properties)

**Next Session**: Implement Priority 1 items (warnings, flags, rule summary, metered details)
