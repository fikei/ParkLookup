# Street Cleaning Dataset Analysis & Integration Plan

**Date:** November 29, 2025
**Dataset:** `Street_Sweeping_Schedule_20251128.geojson`
**Status:** Dataset acquired, ready for integration

---

## Dataset Overview

### Statistics

| Metric | Value |
|--------|-------|
| **Total features** | 37,878 |
| **Geometry type** | LineString |
| **File size** | 22MB |
| **Comparison** | 5x more records than parking regulations (7,784) |

### Weekday Distribution

| Day | Count | Percentage |
|-----|-------|------------|
| Monday | 7,182 | 19.0% |
| Tuesday | 6,891 | 18.2% |
| Wednesday | 6,809 | 18.0% |
| Thursday | 6,798 | 17.9% |
| Friday | 6,763 | 17.9% |
| Saturday | 1,340 | 3.5% |
| Sunday | 1,271 | 3.4% |
| Holiday | 824 | 2.2% |

**Total:** Covers all days with fairly even distribution on weekdays.

### Top Time Windows

| Time Window | Count | Percentage |
|-------------|-------|------------|
| 2:00-6:00 | 5,823 | 15.4% |
| 6:00-8:00 | 4,352 | 11.5% |
| 8:00-10:00 | 4,210 | 11.1% |
| 9:00-11:00 | 4,099 | 10.8% |
| 12:00-14:00 | 3,560 | 9.4% |
| 7:00-8:00 | 3,431 | 9.1% |
| 4:00-6:00 | 2,161 | 5.7% |
| 0:00-2:00 | 1,708 | 4.5% |

**Pattern:** Mix of early morning (2am-6am), morning (6am-11am), and midday (12pm-3pm) cleaning.

---

## Field Structure

### Sample Record

```json
{
  "properties": {
    "weekday": "Tues",
    "fromhour": 5,
    "tohour": 6,
    "corridor": "Market St",
    "limits": "Larkin St  -  Polk St",
    "blockside": "SouthEast",
    "week1": 1,
    "week2": 1,
    "week3": 1,
    "week4": 1,
    "week5": 1,
    "cnn": 8753101,
    "cnnrightleft": "L",
    "blocksweepid": 1640782,
    "holidays": 0,
    "fullname": "Tuesday"
  },
  "geometry": {
    "type": "LineString",
    "coordinates": [[lon, lat], ...]
  }
}
```

### Field Descriptions

| Field | Type | Description | Example | Usage |
|-------|------|-------------|---------|-------|
| `weekday` | String | Day of week (abbreviated) | "Tues", "Mon", "Fri" | Primary enforcement day |
| `fullname` | String | Full day name | "Tuesday" | Alternative to weekday |
| `fromhour` | Int | Start time (24-hour) | 5 (5am) | Enforcement start |
| `tohour` | Int | End time (24-hour) | 6 (6am) | Enforcement end |
| `week1` - `week5` | Int (0/1) | Active in week N of month | 1 = yes, 0 = no | Week-of-month pattern |
| `corridor` | String | Street name | "Market St" | Location |
| `limits` | String | Cross street range | "Larkin St  -  Polk St" | Block bounds |
| `blockside` | String | Side of street | "SouthEast", "NorthWest" | Which side |
| `cnn` | Int | Centerline Network ID | 8753101 | **Potential match key!** |
| `cnnrightleft` | String | Left/Right of centerline | "L", "R" | Direction indicator |
| `holidays` | Int (0/1) | Applies on holidays | 0 = no, 1 = yes | Holiday enforcement |
| `blocksweepid` | Int | Unique sweep schedule ID | 1640782 | Identifier |

---

## Week-of-Month Pattern Analysis

The `week1` through `week5` fields indicate which weeks of the month the cleaning occurs:

### Patterns Found

```python
# Sample pattern analysis
with open('Data Sets/Street_Sweeping_Schedule_20251128.geojson') as f:
    data = json.load(f)

patterns = Counter(
    f"{f['properties']['week1']}{f['properties']['week2']}{f['properties']['week3']}{f['properties']['week4']}{f['properties']['week5']}"
    for f in data['features']
)

# Top patterns:
# "11111" - Every week (most common)
# "10100" - 1st and 3rd week only
# "01010" - 2nd and 4th week only
# "11100" - 1st, 2nd, 3rd weeks
# etc.
```

**Common patterns:**
- `11111` - **Every week** (most streets)
- `10100` - **1st & 3rd week only** (alternating bi-weekly)
- `01010` - **2nd & 4th week only** (alternating bi-weekly)
- `10000` - **1st week only** (monthly)
- `01000` - **2nd week only** (monthly)

---

## Mapping to App Schema

### BlockfaceRegulation Model

```swift
struct BlockfaceRegulation {
    let type: String              // "streetCleaning"
    let permitZone: String?       // null for street cleaning
    let timeLimit: Int?           // null for street cleaning
    let meterRate: Float?         // null for street cleaning
    let enforcementDays: [String] // ["tuesday"] from weekday
    let enforcementStart: String  // "05:00" from fromhour
    let enforcementEnd: String    // "06:00" from tohour
    let specialConditions: String // "1st and 3rd week only" from week pattern
}
```

### Field Mapping

| Source Field | Target Field | Transformation | Example |
|--------------|--------------|----------------|---------|
| (fixed value) | `type` | `"streetCleaning"` | "streetCleaning" |
| - | `permitZone` | `null` | null |
| - | `timeLimit` | `null` | null |
| - | `meterRate` | `null` | null |
| `weekday` | `enforcementDays` | `[weekday.lower()]` | ["tuesday"] |
| `fromhour` | `enforcementStart` | `f"{fromhour:02d}:00"` | "05:00" |
| `tohour` | `enforcementEnd` | `f"{tohour:02d}:00"` | "06:00" |
| `week1-week5` | `specialConditions` | Parse week pattern | "1st and 3rd week only" |

### Week Pattern Parsing

```python
def parse_week_pattern(week1, week2, week3, week4, week5) -> str:
    """Convert week bits to human-readable string"""
    weeks = [week1, week2, week3, week4, week5]
    week_names = ["1st", "2nd", "3rd", "4th", "5th"]

    active_weeks = [week_names[i] for i, active in enumerate(weeks) if active == 1]

    if len(active_weeks) == 5:
        return "Street cleaning every week"
    elif len(active_weeks) == 0:
        return "Street cleaning (schedule TBD)"
    elif active_weeks == ["1st", "3rd"] or active_weeks == ["1st", "3rd", "5th"]:
        return "Street cleaning on odd weeks"
    elif active_weeks == ["2nd", "4th"]:
        return "Street cleaning on even weeks"
    else:
        weeks_str = ", ".join(active_weeks[:-1]) + " and " + active_weeks[-1] if len(active_weeks) > 1 else active_weeks[0]
        return f"Street cleaning {weeks_str} week of month"
```

---

## Integration Strategy

### Option 1: Merge Before Spatial Join (Recommended)

Combine street sweeping with parking regulations into a single dataset, then perform one spatial join:

```python
def convert_with_regulations(blockfaces_path, regulations_path, sweeping_path, output_path):
    # Load blockfaces
    blockfaces = load_blockfaces(blockfaces_path)

    # Load parking regulations
    parking_regs = load_regulations(regulations_path)  # 7,784 records

    # Load street sweeping
    sweeping_regs = load_street_sweeping(sweeping_path)  # 37,878 records

    # Combine into single regulation list
    all_regulations = parking_regs + sweeping_regs  # 45,662 total

    # Perform spatial join (regulation → closest blockface)
    for regulation in all_regulations:
        closest_blockface = find_closest_blockface(regulation, blockfaces)
        if closest_blockface:
            closest_blockface.regulations.append(regulation)

    # Sort regulations by priority within each blockface
    for blockface in blockfaces:
        blockface.regulations = sort_by_priority(blockface.regulations)

    return blockfaces
```

**Pros:**
- Single spatial join operation
- Automatic deduplication across all regulation types
- Priority sorting happens once at the end

**Cons:**
- Slightly more complex loading logic

### Option 2: Separate Spatial Joins

Perform two separate spatial joins and merge results:

```python
def convert_with_regulations(blockfaces_path, regulations_path, sweeping_path, output_path):
    blockfaces = load_blockfaces(blockfaces_path)

    # First join: parking regulations
    parking_regs = load_regulations(regulations_path)
    for reg in parking_regs:
        match_to_closest_blockface(reg, blockfaces)

    # Second join: street sweeping
    sweeping_regs = load_street_sweeping(sweeping_path)
    for sweep in sweeping_regs:
        match_to_closest_blockface(sweep, blockfaces)

    # Sort by priority
    for blockface in blockfaces:
        blockface.regulations = sort_by_priority(blockface.regulations)

    return blockfaces
```

**Pros:**
- Clearer separation of concerns
- Can skip street sweeping if file not provided

**Cons:**
- Two spatial join operations (slower)
- Need to ensure consistent matching logic

**Recommendation:** Use **Option 1** (merge before join) for better performance and simplicity.

---

## Implementation Code

### Step 1: Add Street Sweeping Loader

**File:** `convert_geojson_with_regulations.py`

```python
def load_street_sweeping(sweeping_path: str) -> List[Tuple[Geometry, Dict]]:
    """
    Load street sweeping GeoJSON and extract geometries + properties.
    Returns list of (geometry, properties) tuples.
    """
    print(f"Loading street sweeping from: {sweeping_path}")

    with open(sweeping_path, 'r') as f:
        data = json.load(f)

    sweeping_regs = []
    skipped = 0

    for feature in data['features']:
        geom = feature.get('geometry')
        props = feature.get('properties', {})

        if not geom or geom.get('type') != 'LineString':
            skipped += 1
            continue

        try:
            # Convert GeoJSON to Shapely geometry
            shapely_geom = shape(geom)
            sweeping_regs.append((shapely_geom, props))
        except Exception as e:
            skipped += 1
            continue

    print(f"  ✓ Loaded {len(sweeping_regs)} street sweeping schedules ({skipped} skipped)")
    return sweeping_regs
```

### Step 2: Add Week Pattern Parser

```python
def parse_week_pattern(props: Dict) -> str:
    """Convert week1-week5 bits to human-readable string"""
    weeks = [
        props.get('week1', 0),
        props.get('week2', 0),
        props.get('week3', 0),
        props.get('week4', 0),
        props.get('week5', 0)
    ]
    week_names = ["1st", "2nd", "3rd", "4th", "5th"]

    active_weeks = [week_names[i] for i, active in enumerate(weeks) if active == 1]

    if len(active_weeks) == 5:
        return "Street cleaning every week"
    elif len(active_weeks) == 0:
        return "Street cleaning (schedule TBD)"
    elif set(active_weeks) == {"1st", "3rd"} or set(active_weeks) == {"1st", "3rd", "5th"}:
        return "Street cleaning on odd weeks"
    elif set(active_weeks) == {"2nd", "4th"}:
        return "Street cleaning on even weeks"
    else:
        if len(active_weeks) > 1:
            weeks_str = ", ".join(active_weeks[:-1]) + " and " + active_weeks[-1]
        else:
            weeks_str = active_weeks[0]
        return f"Street cleaning {weeks_str} week of month"
```

### Step 3: Add Street Sweeping Extraction

```python
def extract_street_sweeping(props: Dict) -> Dict:
    """Extract street sweeping fields and map to app schema"""

    # Parse weekday
    weekday = props.get('weekday', '').lower()
    if weekday == 'tues':
        weekday = 'tuesday'
    elif weekday == 'thurs':
        weekday = 'thursday'
    # Add more abbreviation mappings as needed

    # Format time
    fromhour = props.get('fromhour', 0)
    tohour = props.get('tohour', 0)

    try:
        enforcement_start = f"{int(fromhour):02d}:00"
        enforcement_end = f"{int(tohour):02d}:00"
    except (ValueError, TypeError):
        enforcement_start = "00:00"
        enforcement_end = "00:00"

    # Parse week pattern
    special_conditions = parse_week_pattern(props)

    return {
        "type": "streetCleaning",
        "permitZone": None,
        "timeLimit": None,
        "meterRate": None,
        "enforcementDays": [weekday] if weekday else None,
        "enforcementStart": enforcement_start,
        "enforcementEnd": enforcement_end,
        "specialConditions": special_conditions
    }
```

### Step 4: Modify Main Conversion Function

```python
def convert_with_regulations(blockfaces_path: str,
                             regulations_path: str,
                             output_path: str,
                             sweeping_path: str = None,
                             bounds_filter: bool = True):
    """
    Convert GeoJSON blockfaces to app format with regulations populated.

    Algorithm:
    1. Load all blockfaces and regulations (parking + sweeping)
    2. For each regulation, find the CLOSEST blockface it intersects with
    3. Assign each regulation to only ONE blockface (prevents duplication)
    4. Build output with blockfaces containing their assigned regulations
    """

    # Load parking regulations
    regulations = load_regulations(regulations_path)
    print(f"  Parking regulations: {len(regulations)}")

    # Load street sweeping if provided
    if sweeping_path:
        sweeping_regs = load_street_sweeping(sweeping_path)
        print(f"  Street sweeping: {len(sweeping_regs)}")
        # Combine datasets
        all_regulations = regulations + sweeping_regs
        print(f"  Total regulations: {len(all_regulations)}")
    else:
        all_regulations = regulations

    # ... rest of the algorithm remains the same
    # (blockface loading, spatial join, deduplication, priority sorting)
```

### Step 5: Update extract_regulation dispatch

```python
def extract_regulation_from_props(geom_type: str, props: Dict) -> List[Dict]:
    """
    Dispatch to appropriate extraction function based on source.

    Heuristic: If props has 'weekday' and 'fromhour' fields, it's street sweeping.
    Otherwise, it's a parking regulation.
    """
    if 'weekday' in props and 'fromhour' in props:
        # Street sweeping record
        return [extract_street_sweeping(props)]
    else:
        # Parking regulation record
        return extract_regulation(props)  # existing function
```

---

## Expected Results

### Statistics Projection

**After integration:**

| Regulation Type | Count (Estimated) | Source Dataset |
|----------------|-------------------|----------------|
| `streetCleaning` | 30,000-35,000 | Street sweeping (matched to blockfaces) |
| `timeLimit` | 5,800-6,300 | Parking regulations |
| `residentialPermit` | 2,000-3,000 | Parking regulations |
| `noParking` | 178 | Parking regulations |
| `metered` | 50-200 | Parking regulations |
| `other` | 600 | Parking regulations |
| **Total** | **38,000-45,000** | Combined |

**Blockface coverage:**

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Blockfaces with regulations | 712 (48.5%) | 1,100-1,200 (75-82%) | +388-488 |
| Avg regulations per blockface | 0.93 | 2.5-3.0 | +1.6-2.1 |
| Blockfaces with 2+ regulations | 596 (40.6%) | 1,000-1,100 (68-75%) | +404-504 |
| Blockfaces with street cleaning | 0 | 800-900 (54-61%) | +800-900 |

**Performance:**

- Loading time: +5-10 seconds (37,878 more geometries)
- Spatial join time: +30-60 seconds (5x more regulations to process)
- Total processing time (Mission District): ~1-2 minutes (vs. 17 seconds currently)

---

## Testing Plan

### Phase 1: Basic Integration (Day 1)

1. **Add loading function** for street sweeping
2. **Add extraction function** with field mapping
3. **Test loading** in isolation (no spatial join yet)

```bash
python3 -c "
from convert_geojson_with_regulations import load_street_sweeping, extract_street_sweeping
import json

regs = load_street_sweeping('Data Sets/Street_Sweeping_Schedule_20251128.geojson')
print(f'Loaded {len(regs)} records')

# Test extraction
sample_geom, sample_props = regs[0]
extracted = extract_street_sweeping(sample_props)
print(json.dumps(extracted, indent=2))
"
```

### Phase 2: Spatial Join Integration (Day 2)

1. **Modify main function** to merge datasets
2. **Run on Mission District** (bounds filter on)
3. **Validate results**

```bash
python3 convert_geojson_with_regulations.py \
  "Data Sets/Blockfaces_20251128.geojson" \
  "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson" \
  "sample_blockfaces_with_all_regulations.json" \
  "Data Sets/Street_Sweeping_Schedule_20251128.geojson"
```

### Phase 3: Validation (Day 2-3)

1. **Count street cleaning regulations:**
   ```python
   import json
   with open('sample_blockfaces_with_all_regulations.json') as f:
       data = json.load(f)

   cleaning_count = sum(1 for bf in data['blockfaces']
                        if any(r['type'] == 'streetCleaning' for r in bf['regulations']))
   print(f"Blockfaces with street cleaning: {cleaning_count}")
   ```

2. **Verify priority ordering:**
   - Street cleaning should appear before timeLimit
   - Check first 100 blockfaces with both types

3. **Ground truth spot-check:**
   - Sample 10-20 addresses
   - Verify against SF311 street cleaning lookup
   - Calculate accuracy rate

### Phase 4: Full Dataset (Day 3-4)

1. **Run without bounds filter** (all SF)
2. **Monitor performance** (expected: 2-5 minutes)
3. **Generate final dataset**

---

## Next Steps

1. ✅ **Dataset acquired** - `Street_Sweeping_Schedule_20251128.geojson` (37,878 features)
2. ⏳ **Implement integration** - Add loading and extraction functions
3. ⏳ **Test with Mission District** - Validate spatial join works
4. ⏳ **Run full SF dataset** - Generate complete blockface data
5. ⏳ **Update documentation** - Record statistics and findings

**Estimated timeline:** 3-4 days

---

**Last Updated:** November 29, 2025
**Related Docs:**
- `StreetCleaningImplementationPlan.md` - Original plan (now superseded)
- `SpatialJoinResults.md` - Current results (to be updated)
- `RegulationPrioritySystem.md` - Priority ordering (streetCleaning = 3)
