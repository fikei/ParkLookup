# Regulation Types Mapping & Analysis

## Overview

This document maps parking regulation types from the **DataSF CSV** (regulation data) to the **App's BlockfaceRegulation model** (target schema) for spatial join to blockface geometries.

**⚠️ IMPORTANT: Blockfaces GeoJSON is the SOURCE OF TRUTH for geometries.**

The spatial join enriches blockface centerlines with regulation data:

```
Blockfaces GeoJSON (18,355 centerlines) ← SOURCE OF TRUTH
       ↓
   [SPATIAL JOIN]  ← Match regulations TO blockfaces
       ↓
Regulations CSV (7,784 with separate geometries)
       ↓
   RESULT: Blockfaces with populated regulations[]
```

**Data Sources:**
- **Primary:** `Blockfaces_20251128.geojson` (18,355 blockface centerlines)
- **Secondary:** `Parking_regulations_(except_non-metered_color_curb)_20251128.csv` (7,784 regulations)
- **App Model:** `Core/Models/Blockface.swift` → `BlockfaceRegulation`

---

## App's BlockfaceRegulation Types

The app currently supports these regulation types (from `Blockface.swift:56`):

```swift
let type: String  // Supported values:
```

1. **`streetCleaning`** - Street cleaning schedules
2. **`timeLimit`** - Time-limited parking (2hr, 4hr, etc.)
3. **`residentialPermit`** - RPP zones (permit required)
4. **`metered`** - Paid metered parking
5. **`towAway`** - Tow-away zones
6. **`noParking`** - No parking anytime/certain hours
7. **`loadingZone`** - Loading zones (commercial/passenger)

---

## CSV Regulation Types (Source Data)

From 7,784 regulations in the CSV:

| Regulation Type | Count | % of Total |
|----------------|-------|------------|
| **Time limited** | 6,837 | 87.8% |
| **No oversized vehicles** | 531 | 6.8% |
| **No parking any time** | 178 | 2.3% |
| **Pay or Permit** | 58 | 0.7% |
| **Government permit** | 53 | 0.7% |
| **Time Limited** (dup) | 51 | 0.7% |
| **Limited No Parking** | 27 | 0.3% |
| *(empty)* | 23 | 0.3% |
| **No overnight parking** | 17 | 0.2% |
| **Paid + Permit** | 3 | 0.04% |
| **No Parking Anytime** (dup) | 2 | 0.03% |
| **Time LImited** (typo) | 1 | 0.01% |
| **No Stopping** | 1 | 0.01% |
| **No Oversized Vehicles** (dup) | 1 | 0.01% |

**Total:** 7,783 records

---

## Regulation Type Mapping

### ✅ Direct Mappings

| CSV Type | App Type | Notes |
|----------|----------|-------|
| **Time limited** | `timeLimit` | 87.8% of data - PRIMARY type |
| **Time Limited** | `timeLimit` | Duplicate (capital L) |
| **Time LImited** | `timeLimit` | Typo in CSV |
| **No parking any time** | `noParking` | 2.3% of data |
| **No Parking Anytime** | `noParking` | Duplicate |
| **Limited No Parking** | `noParking` | Subset of no parking |
| **No overnight parking** | `noParking` | Temporal no parking (1800-600) |
| **No Stopping** | `noParking` | Even more restrictive than no parking |

### 🟡 Conditional Mappings

| CSV Type | App Type | Condition | Notes |
|----------|----------|-----------|-------|
| **Pay or Permit** | `metered` **OR** `residentialPermit` | Check if RPP area present | If RPPAREA1/2/3 populated → both types |
| **Paid + Permit** | `metered` **AND** `residentialPermit` | Create 2 regulations | Metered parking + permit exemption |
| **Government permit** | `residentialPermit` | Always | Special permit type |

### ⚠️ Unmapped / Special Cases

| CSV Type | Count | Recommended Mapping | Notes |
|----------|-------|---------------------|-------|
| **No oversized vehicles** | 531 (6.8%) | `noParking` with `specialConditions` | Size restriction - could create new type `oversizedRestriction` |
| *(empty)* | 23 | Skip or use geometry only | Invalid records |

---

## Field Mapping Details

### CSV → App Schema Mapping

```python
BlockfaceRegulation(
    type = map_regulation_type(row['REGULATION']),  # See mapping table above
    permitZone = get_first_rpp_area(row),           # RPPAREA1 or RPPAREA2 or RPPAREA3
    timeLimit = parse_time_limit(row['HRLIMIT']),   # Convert hours to minutes
    meterRate = None,                                # Not in CSV - future: join with meters dataset
    enforcementDays = parse_days(row['DAYS']),      # "M-F" → ["monday", "tuesday", ...]
    enforcementStart = format_time(row['FROM_TIME'] or row['HRS_BEGIN']),  # "9am" → "09:00"
    enforcementEnd = format_time(row['TO_TIME'] or row['HRS_END']),        # "6pm" → "18:00"
    specialConditions = row['EXCEPTIONS']           # "Yes. RPP holders are exempt..."
)
```

### Key CSV Fields

| CSV Field | Description | Example | App Field |
|-----------|-------------|---------|-----------|
| `REGULATION` | Regulation type | "Time limited" | `type` |
| `DAYS` | Days of week | "M-F", "M-Sa", "M-Su" | `enforcementDays` |
| `HOURS` | Time range (HHMM) | "900-1800" | *(parse to start/end)* |
| `HRS_BEGIN` | Start hour | "900" | `enforcementStart` |
| `HRS_END` | End hour | "1800" | `enforcementEnd` |
| `FROM_TIME` | Readable start | "9am" | `enforcementStart` |
| `TO_TIME` | Readable end | "6pm" | `enforcementEnd` |
| `HRLIMIT` | Time limit (hours) | "2" | `timeLimit` (× 60 for minutes) |
| `RPPAREA1` | Primary RPP zone | "N", "Q", "S" | `permitZone` |
| `RPPAREA2` | Secondary RPP | "AA", "HV" | *(append or create 2nd regulation)* |
| `RPPAREA3` | Tertiary RPP | *(rare)* | *(append or create 3rd regulation)* |
| `EXCEPTIONS` | Special conditions | "Yes. RPP holders are exempt..." | `specialConditions` |
| `shape` | Geometry (MULTILINESTRING) | MULTILINESTRING(...) | *(spatial join target)* |

---

## RPP Areas Analysis

**Total unique RPP areas:** ~25

### Top 15 RPP Zones (by regulation count)

| Zone | Count | Example Neighborhoods |
|------|-------|----------------------|
| S | 778 | Mission, Potrero Hill |
| A | 645 | Pacific Heights |
| G | 627 | North Beach, Telegraph Hill |
| K | 471 | Western Addition, Lower Haight |
| M | 372 | Bernal Heights |
| C | 360 | Nob Hill, Russian Hill |
| J | 327 | Inner Sunset |
| O | 317 | Outer Sunset |
| N | 300 | Inner Richmond |
| Q | 273 | Mission District |
| V | 238 | Bayview |
| Z | 236 | Outer Richmond |
| D | 230 | South of Market (SOMA) |
| L | 220 | Castro, Noe Valley |
| F | 207 | Haight-Ashbury |

---

## Time Limits Analysis

| Time Limit | Count | % | App Minutes |
|-----------|-------|---|-------------|
| **2 hours** | 5,738 | 73.7% | 120 |
| **0 hours** | 580 | 7.5% | 0 (no limit or N/A) |
| **1 hour** | 526 | 6.8% | 60 |
| **4 hours** | 445 | 5.7% | 240 |
| **3 hours** | 161 | 2.1% | 180 |
| **72 hours** | 59 | 0.8% | 4,320 |
| **12 hours** | 4 | 0.1% | 720 |
| **0.5 hours** | 1 | 0.01% | 30 |

**Note:** "0 hours" likely means "no time limit" for unrestricted parking or N/A for regulations like "No parking any time".

---

## Days Patterns Analysis

| Pattern | Count | % | App Format |
|---------|-------|---|------------|
| **M-F** | 5,462 | 70.2% | `["monday", "tuesday", "wednesday", "thursday", "friday"]` |
| **M-Sa** | 1,365 | 17.5% | `["monday", ..., "saturday"]` |
| **M-Su** | 646 | 8.3% | `["monday", ..., "sunday"]` |
| **M-S** | 11 | 0.1% | Same as M-Sa (typo?) |
| **M, TH** | 8 | 0.1% | `["monday", "thursday"]` |
| **Sa** | 1 | 0.01% | `["saturday"]` |
| *(empty)* | ~290 | 3.7% | `null` (all days or N/A) |

---

## Data Quality Issues

### 1. **Duplicate Regulation Types** (case sensitivity)
- "Time limited" vs. "Time Limited" vs. "Time LImited" (typo)
- "No parking any time" vs. "No Parking Anytime"
- "No oversized vehicles" vs. "No Oversized Vehicles"

**Solution:** Normalize to lowercase and trim before mapping

### 2. **Empty REGULATION Field**
- 23 records with empty `REGULATION`

**Solution:** Skip these or log as data quality issues

### 3. **Inconsistent Time Formats**
- Some use `HRS_BEGIN`/`HRS_END` (900, 1800)
- Some use `FROM_TIME`/`TO_TIME` ("9am", "6pm")
- Some use both

**Solution:** Prefer `FROM_TIME`/`TO_TIME`, fall back to `HRS_BEGIN`/`HRS_END`, parse both formats

### 4. **Multiple RPP Areas**
- Some regulations apply to 2-3 RPP zones (RPPAREA1, RPPAREA2, RPPAREA3)
- Example: "Time Limited" with RPP: "HV, S, " (2 zones)

**Solutions:**
- **Option A:** Create separate regulation for each RPP zone
- **Option B:** Store as array `permitZones: ["HV", "S"]`
- **Recommended:** Option A (create multiple regulations) for compatibility

### 5. **0-hour Time Limits**
- 580 records with `HRLIMIT: 0`
- Context: "No oversized vehicles", "No parking any time", "Government permit"

**Solution:** `timeLimit: null` when HRLIMIT is 0 and regulation type is not "Time limited"

---

## Conversion Algorithm

```python
def convert_csv_to_app_regulation(csv_row):
    regulations = []

    # 1. Normalize regulation type
    reg_type_raw = csv_row['REGULATION'].strip().lower()

    # 2. Map to app type
    if 'time limit' in reg_type_raw:
        app_type = 'timeLimit'
    elif 'no parking' in reg_type_raw or 'no stopping' in reg_type_raw:
        app_type = 'noParking'
    elif 'pay' in reg_type_raw and 'permit' in reg_type_raw:
        # Create both metered and permit regulations
        app_type = ['metered', 'residentialPermit']
    elif 'oversized' in reg_type_raw:
        app_type = 'noParking'  # with specialConditions
    elif 'government permit' in reg_type_raw:
        app_type = 'residentialPermit'
    else:
        app_type = 'unknown'  # Log for manual review

    # 3. Handle multiple RPP areas
    rpp_areas = [
        csv_row.get('RPPAREA1', '').strip(),
        csv_row.get('RPPAREA2', '').strip(),
        csv_row.get('RPPAREA3', '').strip()
    ]
    rpp_areas = [area for area in rpp_areas if area]

    # 4. Create regulation(s)
    if isinstance(app_type, list):
        # Pay or Permit → create multiple regulations
        for t in app_type:
            regulations.append(build_regulation(csv_row, t, rpp_areas))
    elif rpp_areas and len(rpp_areas) > 1 and app_type == 'residentialPermit':
        # Multiple RPP zones → create regulation for each
        for area in rpp_areas:
            regulations.append(build_regulation(csv_row, app_type, [area]))
    else:
        # Single regulation
        regulations.append(build_regulation(csv_row, app_type, rpp_areas))

    return regulations

def build_regulation(csv_row, app_type, rpp_areas):
    return {
        'type': app_type,
        'permitZone': rpp_areas[0] if rpp_areas else None,
        'timeLimit': parse_time_limit(csv_row.get('HRLIMIT')),
        'meterRate': None,  # Not in CSV
        'enforcementDays': parse_days(csv_row.get('DAYS')),
        'enforcementStart': parse_time(csv_row.get('FROM_TIME') or csv_row.get('HRS_BEGIN')),
        'enforcementEnd': parse_time(csv_row.get('TO_TIME') or csv_row.get('HRS_END')),
        'specialConditions': csv_row.get('EXCEPTIONS', '').strip() or None
    }
```

---

## Overlap Analysis

### CSV ↔ App Type Coverage

| App Type | CSV Sources | Coverage |
|----------|-------------|----------|
| `timeLimit` | "Time limited", "Time Limited", "Time LImited" | ✅ 87.8% of CSV |
| `noParking` | "No parking any time", "No Parking Anytime", "Limited No Parking", "No overnight parking", "No Stopping" | ✅ 2.8% of CSV |
| `residentialPermit` | RPPAREA1/2/3 fields (not REGULATION type), "Government permit" | ✅ Present in ~90% of records |
| `metered` | "Pay or Permit", "Paid + Permit" | ⚠️ 0.8% of CSV (mostly missing - needs meters CSV join) |
| `streetCleaning` | ❌ **NOT IN CSV** | ❌ Requires separate street cleaning dataset (S24) |
| `towAway` | ❌ **NOT IN CSV** | ❌ May be implied by some "No parking" regs? |
| `loadingZone` | ❌ **NOT IN CSV** | ❌ Requires separate dataset or inferred from regulation details |

### App Types **NOT** in Current CSV

1. **`streetCleaning`** - Requires **Street Sweeping Schedule** dataset (Story 24)
2. **`metered`** with rates - Requires **Parking Meters** dataset (Story 25)
3. **`towAway`** - May need manual tagging or inference
4. **`loadingZone`** - May need separate dataset or manual tagging

### CSV Types **NOT** Mapped to App

1. **"No oversized vehicles"** (6.8%) - Currently maps to `noParking` with `specialConditions`
   - **Recommendation:** Add new type `oversizedRestriction` in future

---

## Recommendations

### Immediate (Task 17.36-17.37)

1. **Normalize CSV regulation types** before mapping (lowercase, trim)
2. **Handle multiple RPP areas** by creating separate regulations
3. **Skip empty REGULATION records** (23 records)
4. **Map "No oversized vehicles" to `noParking`** with `specialConditions: "No oversized vehicles"`
5. **Parse time in both formats** (HRS_BEGIN/END and FROM_TIME/TO_TIME)
6. **Convert HRLIMIT to minutes** (multiply by 60)
7. **Parse DAYS patterns** to array of day names

### Future Enhancements

1. **Story 24:** Add `streetCleaning` regulations from Street Sweeping dataset
2. **Story 25:** Add `metered` regulations with rates from Parking Meters dataset
3. **Consider new type:** `oversizedRestriction` for vehicle size limits
4. **Consider new type:** `towAway` if identifiable in data
5. **Consider new type:** `loadingZone` if data becomes available

---

## Expected Output After Spatial Join

### Sample Blockface with Multiple Regulations

```json
{
  "id": "{809F8ECF-517E-44EA-A7C3-DEFC7F6432C5}",
  "street": "Albion Street",
  "fromStreet": "17th St",
  "toStreet": "16th St",
  "side": "ODD",
  "geometry": { ... },
  "regulations": [
    {
      "type": "residentialPermit",
      "permitZone": "S",
      "timeLimit": null,
      "meterRate": null,
      "enforcementDays": null,
      "enforcementStart": null,
      "enforcementEnd": null,
      "specialConditions": "Visitors may park with valid permit"
    },
    {
      "type": "timeLimit",
      "permitZone": "S",
      "timeLimit": 120,
      "meterRate": null,
      "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
      "enforcementStart": "09:00",
      "enforcementEnd": "18:00",
      "specialConditions": "Yes. RPP holders are exempt from time limits."
    }
  ]
}
```

---

## Statistics

**CSV Coverage:**
- ✅ **90.6%** of CSV regulations can be mapped to app types
- ⚠️ **6.8%** require special handling ("No oversized vehicles")
- ❌ **2.6%** are invalid or empty

**App Type Coverage:**
- ✅ **3/7** app types fully covered by CSV (`timeLimit`, `noParking`, `residentialPermit`)
- ⚠️ **1/7** partially covered (`metered` - only 0.8%)
- ❌ **3/7** not in CSV (`streetCleaning`, `towAway`, `loadingZone`)

**Expected Match Rate After Spatial Join:**
- Estimated **60-80%** of blockfaces will get regulations
- Blockfaces without regulations: residential streets, parks, private roads
- Blockfaces with multiple regulations: ~30-40% (time limit + permit)

---

**Last Updated:** November 2025
**Related:** `BlockfaceRegulationsMatching.md`, `Blockface.swift`
