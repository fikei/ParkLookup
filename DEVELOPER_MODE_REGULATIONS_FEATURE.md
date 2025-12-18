# Development Mode: Parking Regulations Editor

## Overview

This feature allows developers to edit parking regulations for individual blockfaces during development and testing. It's designed to help test different parking scenarios without modifying the underlying data files.

## Architecture

### Components

1. **BlockfaceOverride.swift** - Data model for storing regulation overrides
   - `BlockfaceOverride`: Container for overridden blockface regulations
   - `BlockfaceRegulationOverride`: Editable version of BlockfaceRegulation

2. **BlockfaceOverrideManager.swift** - Service for managing overrides
   - Singleton manager for loading/saving overrides
   - Persists to UserDefaults
   - Provides import/export functionality
   - Sends notifications on changes

3. **BlockfaceLoader.swift** (modified) - Applies overrides during data loading
   - Listens for override changes
   - Applies overrides only when developer mode is enabled
   - Clears cache when overrides change

4. **BlockfaceEditorView.swift** - UI for editing regulations
   - Select blockfaces from current location
   - Add/edit/delete regulations
   - Visual regulation editor with all properties

5. **BlockfaceEditorViewModel.swift** - View model for the editor
   - Manages editor state
   - Handles location loading
   - Coordinates with OverrideManager

6. **SettingsView.swift** (modified) - Access point for the editor
   - Added "Development Tools" section in developer mode
   - Shows override count badge
   - Provides "Clear All Overrides" action

## User Flow

### Accessing the Feature

1. Open **Settings**
2. Enable **Developer Mode** (in Advanced section)
3. Scroll to **Development Tools** section
4. Tap **Edit Blockface Regulations**

### Editing Regulations

1. **Select a Blockface**
   - Tap "Load from Current Location"
   - Select a blockface from the list
   - Blockfaces with existing overrides show an indicator

2. **Edit Regulations**
   - Tap a regulation to edit it
   - Swipe to delete a regulation
   - Tap "Add Regulation" to create a new one

3. **Edit Regulation Properties**
   - **Type**: metered, residentialPermit, timeLimit, streetCleaning, noParking, towAway, loadingZone
   - **Enforcement Days**: Select which days the regulation applies
   - **Enforcement Times**: Set start/end times (HH:MM format)
   - **Permit Zones**: For residential permits (comma-separated)
   - **Time Limit**: For time-limited parking (in minutes)
   - **Meter Rate**: For metered parking ($/hour)
   - **Special Conditions**: Optional notes

4. **Save/Cancel**
   - Tap "Save" to apply changes
   - Tap "Cancel" to discard changes
   - Changes take effect immediately

5. **Remove Overrides**
   - Tap "Remove Override" to delete override for current blockface
   - Or use "Clear All Overrides" in Settings to remove all

## Data Flow

```
User Edits Regulation
    ↓
BlockfaceEditorViewModel
    ↓
BlockfaceOverrideManager.saveOverride()
    ↓
UserDefaults (persisted)
    ↓
NotificationCenter.post(.blockfaceOverridesChanged)
    ↓
BlockfaceLoader.clearCache()
    ↓
Next lookup: BlockfaceLoader.applyOverrides()
    ↓
Modified regulations returned
    ↓
UI displays updated regulations
```

## Deployment Lifecycle

### Development Phase

**Purpose**: Test different parking scenarios, edge cases, and regulation combinations

**Usage**:
- Override regulations for specific test locations
- Test time limit calculations
- Verify permit zone logic
- Test multi-RPP scenarios
- Validate "Park Until" calculations

**Example Scenarios**:
```swift
// Test: 2-hour parking that becomes street cleaning at 2pm
Override Blockface "123abc" with:
  - timeLimit: 120 (2 hours)
  - streetCleaning: Mon-Fri 14:00-16:00

// Test: Multi-zone residential permit
Override Blockface "456def" with:
  - residentialPermit: zones ["Q", "HV"]
  - timeLimit: 120 (for visitors)

// Test: Metered parking with no parking during rush hour
Override Blockface "789ghi" with:
  - metered: $4.50/hr, 09:00-18:00
  - noParking: 16:00-18:00 (rush hour)
```

### Testing Phase

**Purpose**: Create reproducible test cases, validate edge cases

**Usage**:
- Export overrides as JSON test fixtures
- Share test scenarios with team
- Automated testing with predefined overrides
- Regression testing for calculation logic

**Export Example**:
```swift
let json = BlockfaceOverrideManager.shared.exportOverrides()
// Save to file or test fixtures
```

### QA Phase

**Purpose**: Verify production-like scenarios, validate fixes

**Usage**:
- Recreate reported bugs by overriding specific blockfaces
- Test fixes without waiting for data updates
- Validate edge cases found by users
- Test seasonal regulation changes

### Production Deployment

**Important**: Overrides are **ONLY active when Developer Mode is enabled**

**Safety Features**:
- Developer mode must be explicitly enabled
- Overrides stored in UserDefaults (device-local only)
- Clear visual indicators when overrides are active
- Can be cleared instantly
- Does not modify original data files

**Production Use Cases**:
- **Customer Support**: Temporarily override regulations to diagnose user-reported issues
- **Admin Tool**: Could evolve into a regulation management interface
- **Data Validation**: Compare override behavior with production data
- **Emergency Updates**: Temporarily fix incorrect regulations while waiting for data update

### Future Evolution

This feature could evolve into:

1. **Cloud-Based Overrides**
   - Store overrides on server
   - Deploy regulation updates without app update
   - A/B test different regulation interpretations

2. **Admin Dashboard**
   - Web interface for managing overrides
   - Push overrides to specific users or groups
   - Analytics on override usage

3. **Regulation Update Pipeline**
   - Export validated overrides as data patches
   - Submit overrides to data team
   - Track regulation change requests

4. **User-Reported Corrections**
   - Allow users to suggest corrections
   - Store as overrides for review
   - Crowd-source data quality improvements

## Technical Details

### Storage Format

Overrides are stored in UserDefaults as JSON:

```json
{
  "dev.blockfaceOverrides": [
    {
      "id": "blockface_123",
      "createdAt": "2025-01-15T10:30:00Z",
      "notes": "Testing 2-hour limit scenario",
      "regulations": [
        {
          "id": "uuid-1234",
          "type": "timeLimit",
          "timeLimit": 120,
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
          "enforcementStart": "08:00",
          "enforcementEnd": "18:00"
        }
      ]
    }
  ]
}
```

### Cache Invalidation

Overrides trigger cache invalidation via NotificationCenter:

```swift
// When override is saved/removed:
NotificationCenter.default.post(name: .blockfaceOverridesChanged, object: nil)

// BlockfaceLoader listens and clears cache:
NotificationCenter.default.addObserver(
    forName: .blockfaceOverridesChanged,
    object: nil,
    queue: nil
) { [weak self] _ in
    self?.clearCache()
}
```

### Performance Considerations

- Overrides are only applied when developer mode is enabled
- Cache is invalidated on override changes (triggers reload)
- Override application is O(n) where n = number of blockfaces
- Minimal performance impact in production (feature disabled)

### Security Considerations

- Overrides are device-local (UserDefaults)
- No network transmission of overrides
- Only active when developer mode explicitly enabled
- Cannot be enabled remotely
- Clear visual indicators when active

## Testing Checklist

- [ ] Enable developer mode in Settings
- [ ] Open blockface editor
- [ ] Load blockfaces from current location
- [ ] Select a blockface
- [ ] Add a new regulation
- [ ] Edit regulation properties
- [ ] Save override
- [ ] Verify regulation appears in main app
- [ ] Navigate to location and check "Park Until" calculation
- [ ] Delete a regulation
- [ ] Remove entire override
- [ ] Clear all overrides
- [ ] Verify overrides persist after app restart
- [ ] Verify overrides only apply with developer mode enabled
- [ ] Disable developer mode and verify overrides don't apply
- [ ] Test export functionality
- [ ] Test import functionality

## Known Limitations

1. **Location-based selection only**: Currently can only select blockfaces near current location. Future enhancement could add search by ID or address.

2. **No validation**: Time format and other inputs are not validated. User must enter correct format (HH:MM).

3. **No override merging**: Overrides completely replace blockface regulations, no partial updates.

4. **Local storage only**: Overrides stored in UserDefaults, not synced across devices.

5. **No audit trail**: No history of override changes or who made them.

## Future Enhancements

1. **Search by blockface ID or street address**
2. **Input validation and error handling**
3. **Partial regulation updates (merge mode)**
4. **Cloud sync for overrides**
5. **Override history and audit trail**
6. **Quick override templates (common scenarios)**
7. **Visual map-based selection**
8. **Override conflict detection**
9. **Scheduled overrides (time-based activation)**
10. **Override sharing via QR code or deep link**

## Support

For issues or questions:
- Check logs for "BlockfaceOverrideManager" and "BlockfaceLoader" messages
- Verify developer mode is enabled
- Check override count in Settings
- Export overrides for debugging
- Clear overrides to reset state
