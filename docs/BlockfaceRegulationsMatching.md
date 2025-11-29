# Blockface to Regulations Matching - Current Status

## Summary

**Status:** ❌ **NOT IMPLEMENTED** - Blockfaces and regulations are currently in separate datasets and have **not been joined**.

**Impact:** All blockfaces currently have `regulations: []` (empty array).

---

## Current Data Architecture

### Dataset 1: Blockface Geometries (GeoJSON)
- **File:** `Data Sets/Blockfaces_20251128.geojson`
- **Records:** 18,355 blockface features
- **Content:** Street centerline geometries (LineString coordinates)
- **Properties:**
  - `globalid`: Unique identifier
  - `popupinfo`: Optional description (e.g., "Valencia Street between 17th St and 16th St, west side")
  - `street_nam`, `blockface_`, `cnn_id`, etc.
- **Regulations:** **NONE** - Most have `popupinfo: null`, a few have location descriptions only

### Dataset 2: Parking Regulations (CSV)
- **File:** `Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.csv`
- **Records:** 7,784 regulation records
- **Content:** Parking rules with separate geometry
- **Key Fields:**
  - `shape`: MULTILINESTRING geometry (separate from blockface geometries!)
  - `REGULATION`: "Time limited", "RPP", "No parking", etc.
  - `DAYS`: "M-F", "DAILY", "Tu/Th", etc.
  - `HOURS`: "900-1800", "0-2400", etc.
  - `HRS_BEGIN`, `HRS_END`: Enforcement start/end times
  - `RPPAREA1`, `RPPAREA2`, `RPPAREA3`: Permit areas (e.g., "Q", "R", "A")
  - `HRLIMIT`: Time limit in hours (e.g., "2", "4")
  - `EXCEPTIONS`: "Yes. RPP holders are exempt from time limits."
  - `GLOBALID`: Unique identifier

---

## The Problem

**Two datasets with separate geometries that need to be spatially joined:**

```
Blockface GeoJSON                          Parking Regulations CSV
┌────────────────────┐                    ┌────────────────────────┐
│ globalid: {...}    │                    │ objectid: "7445"       │
│ geometry:          │                    │ shape: MULTILINESTRING │
│   LineString [...]  │    SPATIAL JOIN  │   (coords...)          │
│ popupinfo: null    │   ────────────►   │ REGULATION: "Time..."  │
│ regulations: []    │    (NOT DONE)     │ RPPAREA1: "N"          │
│                    │                    │ HRLIMIT: "2"           │
└────────────────────┘                    │ DAYS: "M-F"            │
                                          │ HOURS: "900-1800"      │
                                          └────────────────────────┘
```

**The join hasn't been implemented**, so:
- 18,355 blockfaces exist with centerline geometry
- 7,784 regulation records exist with separate geometry
- **Zero blockfaces** currently have parking regulations populated

---

## Why Some Blockfaces "Appear" to Have Regulations

Looking at the GeoJSON, some blockfaces have descriptive text:

```json
{
  "popupinfo": "Valencia Street between 17th St and 16th St, west side"
}
```

**This is NOT a parking regulation!** It's just:
- Street name
- Cross streets (from/to)
- Side of street (north/south/east/west)

The actual regulations (time limits, RPP areas, enforcement hours) are in the separate CSV file.

---

## What Gets Extracted Today

The `convert_geojson_to_app_format.py` script extracts:

```python
{
  "id": "{globalid}",
  "street": "Valencia Street",           # From popupinfo parsing
  "fromStreet": "17th St",                # From popupinfo parsing
  "toStreet": "16th St",                  # From popupinfo parsing
  "side": "EVEN",                         # From "west side" → EVEN mapping
  "geometry": {
    "type": "LineString",
    "coordinates": [[-122.42188, 37.76344], ...]
  },
  "regulations": []  # ❌ EMPTY - needs spatial join!
}
```

---

## What Needs to Happen (Tasks 17.36-17.39)

### Task 17.36: Spatial Join Implementation

Implement spatial matching between:
- Blockface centerline geometries (18,355 LineStrings)
- Regulation geometries (7,784 MULTILINESTRING records)

**Matching Options:**
1. **Buffer intersect:** Create 5m buffer around regulation geometry, find blockfaces that intersect
2. **Nearest neighbor:** For each blockface, find closest regulation geometry
3. **Exact match:** Match by globalid if available, spatial fallback

**Challenges:**
- One blockface may match multiple regulations (e.g., RPP + time limit + street cleaning)
- One regulation may apply to multiple blockfaces (long street segment)
- Geometries may not align perfectly (slight offsets, different vertex counts)
- Need to handle no-match cases (blockfaces without regulations)

### Task 17.37: Regulation Field Extraction

Map CSV fields to app schema:

```python
regulation = {
  "type": row['REGULATION'],                # "Time limited", "RPP", etc.
  "days": row['DAYS'],                      # "M-F", "DAILY", etc.
  "hours": row['HOURS'],                    # "900-1800"
  "hoursBegin": row['HRS_BEGIN'],           # 900
  "hoursEnd": row['HRS_END'],               # 1800
  "rppAreas": [                             # ["N", "Q"]
    row['RPPAREA1'],
    row['RPPAREA2'],
    row['RPPAREA3']
  ],
  "timeLimit": row['HRLIMIT'],              # "2" (hours)
  "exceptions": row['EXCEPTIONS'],          # "RPP holders exempt..."
  "enforcementStart": row['FROM_TIME'],     # "9am"
  "enforcementEnd": row['TO_TIME']          # "6pm"
}
```

### Task 17.38: Validation

Quality checks:
- **Match rate:** What % of blockfaces get regulations?
  - Target: > 80% of blockfaces have at least 1 regulation
  - Identify blockfaces with no match (unregulated streets, data gaps)
- **Multi-match handling:** How to combine multiple regulations?
  - Example: Blockface has both "2hr limit" AND "RPP Area Q"
  - Solution: Store as array, display both in UI
- **Conflict detection:** Same blockface with contradictory rules
  - Example: "No parking" AND "2hr parking"
  - Solution: Flag for manual review, use most restrictive
- **Ground truth:** Spot-check sample against street signs
  - Select 50 random blockfaces
  - Compare app regulations to physical signage
  - Target: > 95% accuracy

### Task 17.39: Updated Conversion Script

Modify `convert_geojson_to_app_format.py`:

```python
def convert_with_regulations(blockface_geojson, regulations_csv):
    # 1. Load both datasets
    blockfaces = load_geojson(blockface_geojson)
    regulations = load_csv_with_geometry(regulations_csv)

    # 2. Build spatial index for regulations
    regulation_index = build_rtree(regulations)

    # 3. For each blockface, find matching regulations
    for bf in blockfaces:
        matches = find_regulations(bf.geometry, regulation_index)
        bf['regulations'] = [
            extract_regulation_fields(reg)
            for reg in matches
        ]

    # 4. Validate and export
    validate_matches(blockfaces)
    export_json(blockfaces)
```

---

## Expected Output After Implementation

```json
{
  "id": "{globalid}",
  "street": "Valencia Street",
  "fromStreet": "17th St",
  "toStreet": "16th St",
  "side": "EVEN",
  "geometry": { ... },
  "regulations": [
    {
      "type": "RPP",
      "rppAreas": ["Q"],
      "days": "DAILY",
      "hours": "0-2400",
      "exceptions": "Visitors may park with valid permit"
    },
    {
      "type": "Time limited",
      "timeLimit": "2",
      "days": "M-F",
      "hours": "900-1800",
      "hoursBegin": 900,
      "hoursEnd": 1800,
      "exceptions": "RPP holders are exempt from time limits"
    }
  ]
}
```

---

## Impact on App Features

**Blocked features until regulations are joined:**
- ✅ **Blockface visualization:** Works (PoC complete)
- ❌ **"Park Until" calculation:** Needs time limits from regulations
- ❌ **RPP zone detection:** Needs RPPAREA fields from regulations
- ❌ **Enforcement hours:** Needs HOURS/HRS_BEGIN/HRS_END from regulations
- ❌ **User permit matching:** Needs rppAreas to compare against user permits
- ❌ **Street cleaning warnings:** Needs separate street cleaning data (S24)
- ❌ **Meter integration:** Needs meter CSV join (S25)

**Current workaround:**
- Blockfaces render with placeholder color coding (free/permit valid/invalid/paid)
- Colors are based on mock data, not actual regulations

---

## Timeline

**Priority:** High - Blocks S23 (Location-Based Lookups) and S26 (Migration)

**Estimated effort:** 1-2 weeks
- Week 1: Implement spatial join (17.36), field extraction (17.37)
- Week 2: Validation (17.38), update conversion script (17.39), testing

**Dependencies:**
- None (can start immediately)
- Blocks: S23 (needs regulations for lookup), S26 (migration)

---

## Related Documents
- `blockface_offset_strategy.md` - Offset visualization algorithm
- `ImplementationChecklist.md` - Tasks 17.36-17.39
- `BlockfaceMigrationStrategy.md` - Migration plan (S26)

**Last Updated:** November 2025
