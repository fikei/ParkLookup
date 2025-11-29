# Regulation Priority System

**Date:** November 29, 2025
**Purpose:** Define priority ordering for overlapping parking regulations on blockfaces

---

## Overview

When multiple parking regulations apply to a single blockface, they must be sorted by **restrictiveness** to ensure the most critical rules are displayed first in the UI and used for parking availability calculations.

---

## Priority Order

Regulations are sorted by the following priority (1 = highest/most restrictive):

| Priority | Type | Description | Example |
|----------|------|-------------|---------|
| **1** | `noParking` | No parking allowed at all | "No Parking Anytime" |
| **2** | `towAway` | Tow-away zones | "Tow-Away Zone 7am-9am" |
| **3** | `streetCleaning` | Street cleaning (temporary tow) | "Street Cleaning Tuesday 8am-10am" |
| **4** | `metered` | Paid parking required | "Metered Parking $4/hr" |
| **5** | `timeLimit` | Time-limited parking | "2 Hour Limit 9am-6pm M-F" |
| **6** | `residentialPermit` | Permit required | "RPP Zone S Required" |
| **7** | `loadingZone` | Loading zones | "Commercial Loading Only" |
| **8** | `other` | Miscellaneous restrictions | "No Oversized Vehicles" |

---

## Rationale

### 1. **noParking** (Highest Priority)
- Cannot park under any circumstances
- Must be shown first to prevent violations
- Examples: fire hydrants, crosswalks, bus zones

### 2. **towAway** (Very High)
- Serious consequence (vehicle tow + fees)
- Often time-sensitive
- Examples: commute hour restrictions, event zones

### 3. **streetCleaning** (High)
- Temporary but enforced with towing
- Predictable schedule (weekly)
- Must be shown prominently for tow prevention

### 4. **metered** (Medium-High)
- Financial cost (payment required)
- Often has longest enforcement hours
- Affects parking availability calculation

### 5. **timeLimit** (Medium)
- Limits duration but allows parking
- Can combine with permit exemptions
- Important for "Park Until" calculations

### 6. **residentialPermit** (Medium-Low)
- Allows parking with valid permit
- Often exempts from time limits
- User may have permit that makes this irrelevant

### 7. **loadingZone** (Low)
- Special use restrictions
- Often short duration limits
- Not absolute prohibition

### 8. **other** (Lowest)
- Miscellaneous restrictions
- Examples: size limits, vehicle type restrictions
- Usually supplementary to other regulations

---

## Implementation

### Code Location
`convert_geojson_with_regulations.py:32-41`

```python
REGULATION_PRIORITY = {
    "noParking": 1,        # Highest - can't park at all
    "towAway": 2,          # Very high - serious consequence
    "streetCleaning": 3,   # High - temporary tow-away
    "metered": 4,          # Medium-high - requires payment
    "timeLimit": 5,        # Medium - limited duration
    "residentialPermit": 6,# Medium-low - permit requirement
    "loadingZone": 7,      # Low - special use
    "other": 8             # Lowest - misc restrictions
}
```

### Sorting Function
`convert_geojson_with_regulations.py:53-58`

```python
def sort_regulations_by_priority(regulations: List[Dict]) -> List[Dict]:
    """
    Sort regulations by priority (most restrictive first).
    Secondary sort by type name for consistency.
    """
    return sorted(regulations,
                  key=lambda r: (get_regulation_priority(r), r.get('type', '')))
```

Applied during blockface construction at `convert_geojson_with_regulations.py:542`:
```python
# Sort regulations by priority (most restrictive first)
unique_regulations = sort_regulations_by_priority(unique_regulations)
```

---

## Example Output

### Before Sorting (Random Order)
```json
{
  "id": "{ABC-123}",
  "street": "Valencia Street",
  "regulations": [
    {"type": "residentialPermit", "permitZone": "S"},
    {"type": "noParking", "enforcementDays": ["tuesday"], "specialConditions": "Street Cleaning"},
    {"type": "timeLimit", "timeLimit": 120}
  ]
}
```

### After Sorting (Priority Order)
```json
{
  "id": "{ABC-123}",
  "street": "Valencia Street",
  "regulations": [
    {"type": "noParking", "enforcementDays": ["tuesday"], "specialConditions": "Street Cleaning"},
    {"type": "timeLimit", "timeLimit": 120},
    {"type": "residentialPermit", "permitZone": "S"}
  ]
}
```

---

## UI Impact

When rendering regulations in the app:
1. **First regulation** in array is most restrictive → display prominently
2. **Parking availability** should be calculated from highest-priority active regulation
3. **"Park Until" time** determined by most restrictive time-based rule

### Example UI Logic
```swift
// Get the most restrictive regulation currently active
let activeRegulations = blockface.regulations.filter { isActive($0, at: Date()) }
let primaryRegulation = activeRegulations.first  // Already sorted by priority

switch primaryRegulation.type {
case "noParking":
    displayStatus = .noParking
case "metered":
    displayStatus = .paidParking(rate: primaryRegulation.meterRate)
case "timeLimit":
    displayStatus = .timeLimit(minutes: primaryRegulation.timeLimit)
// ...
}
```

---

## Future Enhancements

### Time-Based Priority Override
Currently, priority is static. Consider adding **time-aware priority**:

```python
def get_time_aware_priority(regulation: Dict, current_time: datetime) -> int:
    base_priority = REGULATION_PRIORITY.get(regulation['type'], 99)

    # If regulation is currently active, boost priority
    if is_regulation_active(regulation, current_time):
        return base_priority  # No change
    else:
        return base_priority + 10  # Lower priority if not currently active
```

This would show "No Parking 8am-10am" at priority 11 when it's 2pm, but priority 1 when it's 9am.

### User-Specific Priority
For users with permits, adjust priority based on exemptions:

```python
def get_user_priority(regulation: Dict, user_permits: List[str]) -> int:
    base_priority = REGULATION_PRIORITY.get(regulation['type'], 99)

    # If user has permit that exempts from this regulation
    if regulation['type'] == 'residentialPermit' and
       regulation['permitZone'] in user_permits:
        return 99  # Very low priority (user can park)

    return base_priority
```

---

## Related Documentation

- `SpatialJoinResults.md` - Spatial matching algorithm
- `RegulationTypesMapping.md` - Regulation type definitions
- `Blockface.swift:56` - App's BlockfaceRegulation model

**Last Updated:** November 29, 2025
