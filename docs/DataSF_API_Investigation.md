# DataSF API Investigation - Street Cleaning Data

**Date:** 2025-11-26
**Status:** Phase 1 Complete - Findings Documented
**Next Steps:** Verify with live API access or sample data

---

## Executive Summary

Investigation of the DataSF Blockface API to identify street cleaning data fields. The backend currently uses the **hi6h-neyh** dataset ("Parking regulations except non-metered color curb") which contains time-based parking restrictions that likely include street cleaning.

**Key Finding:** The existing API fields (`hrs_begin`, `hrs_end`, `days`, `hrlimit`) are already being fetched but NOT distinguished as street cleaning vs. general time limits.

---

## Current State Analysis

### Backend Architecture

**File:** `backend/fetchers/blockface_fetcher.py`
- **Dataset ID:** `hi6h-neyh`
- **API Endpoint:** `https://data.sfgov.org/resource/hi6h-neyh.json`
- **Purpose:** Fetches parking regulations for street segments (blockfaces)

**File:** `backend/transformers/parking_transformer.py`
- **Current Fields Used:**
  - `rpparea1`, `rpparea2`, `rpparea3` - Residential permit zones
  - `hrlimit` - Time limit in hours (converted to minutes)
  - `hrs_begin`, `hrs_end` - Enforcement start/end times
  - `days` - Enforcement days (e.g., "M-F", "Mon,Thu")
  - `street`, `from_street`, `to_street`, `side` - Street segment info
  - `shape`, `the_geom`, `geometry` - Line geometries

### The Problem

**Current transformer logic (lines 749-801):**
```python
# Gets time limit but doesn't distinguish if it's street cleaning
time_limit = None
hrlimit = record.get("hrlimit") or record.get("HRLIMIT")
if hrlimit:
    try:
        time_limit = int(float(hrlimit)) * 60  # Convert to minutes
    except (ValueError, TypeError):
        time_limit = self._parse_time_limit(hrlimit)

# Creates ParkingRegulation with hours/days but no rule type distinction
regulation = ParkingRegulation(
    # ... fields ...
    time_limit=time_limit,
    hours_begin=record.get("hrs_begin"),
    hours_end=record.get("hrs_end"),
    days=self._parse_days(record.get("days")),
)
```

**The data is already there** - we're just not **identifying** which records are street cleaning vs. regular time limits!

---

## DataSF Blockface Dataset Fields

### Known Fields from Code Analysis

Based on the transformer code and blockface fetcher comments:

| Field | Type | Description | Example | Used For |
|-------|------|-------------|---------|----------|
| `rpparea1` | String | Primary RPP zone | "Q", "R", "A" | Zone identification |
| `rpparea2` | String | Secondary RPP zone | "S" (for overlapping) | Multi-permit zones |
| `rpparea3` | String | Tertiary RPP zone | "I" | Multi-permit zones |
| `hrlimit` | Number | Time limit in hours | 2, 1, 0.5 | Parking time limits |
| `hrs_begin` | String | Enforcement start time | "0800", "08:00" | Time restrictions |
| `hrs_end` | String | Enforcement end time | "1800", "18:00" | Time restrictions |
| `days` | String | Days of enforcement | "M-F", "Mon,Thu" | Day restrictions |
| `street` | String | Street name | "Mission St" | Location |
| `from_street` | String | Intersection start | "24th St" | Segment bounds |
| `to_street` | String | Intersection end | "25th St" | Segment bounds |
| `side` | String | Street side | "EVEN", "ODD" | Block face side |
| `shape` | Object | Line geometry | MultiLineString | Geographic bounds |

### Suspected Additional Fields

Based on DataSF dataset naming conventions and SF street cleaning practices:

| Field | Type | Likelihood | Purpose |
|-------|------|-----------|----------|
| `streetswp_days` | String | **High** | Dedicated street cleaning days |
| `streetswp_time` | String | **High** | Street cleaning time window |
| `streetswp_from` | Time | Medium | Cleaning start time |
| `streetswp_to` | Time | Medium | Cleaning end time |
| `regulation` | String | **High** | Regulation type ("Street Cleaning", "Time Limit", etc.) |
| `regulation_type` | String | **High** | Standardized type code |
| `description` | String | Medium | Human-readable description |
| `regulation_text` | String | Medium | Full text of regulation |

---

## Investigation Findings

### 1. Data is Already Being Fetched ✅

The `hrs_begin`, `hrs_end`, `days`, and `hrlimit` fields ARE being fetched for all blockface records. This likely includes street cleaning data.

**Evidence:**
- Lines 787-789 in `parking_transformer.py` extract these fields
- Lines 25-27 in `blockface_fetcher.py` describe time limits and hours

### 2. Missing Classification Logic ❌

**The transformer doesn't distinguish between:**
- 2-hour parking limit (Mon-Fri 8AM-6PM)  ← Time limit rule
- Street cleaning (Mon, Thu 8AM-10AM)     ← Street cleaning rule

Both look identical in the current data structure!

### 3. Hypothesis: Pattern-Based Detection

**We can likely identify street cleaning by patterns:**

#### Time Duration Heuristic
```python
# Street cleaning is usually SHORT windows (1-3 hours)
# Regular time limits are longer (2hr, 4hr, all day)

if duration_hours <= 2 and has_specific_days:
    # Likely street cleaning (short window, specific days)
    rule_type = "street_cleaning"
else:
    # Likely time limit (longer window or all days)
    rule_type = "time_limit"
```

#### Day Pattern Heuristic
```python
# Street cleaning typically has NON-CONTIGUOUS days
# E.g., "Mon, Thu" or "Tue, Fri" (alternating)

days = parse_days(record['days'])
if len(days) <= 3 and not is_contiguous(days):
    # Likely street cleaning
    rule_type = "street_cleaning"
```

#### Field Name Heuristic
```python
# If there's a `regulation` or `description` field, check for keywords

regulation = record.get('regulation', '').lower()
if 'clean' in regulation or 'sweep' in regulation:
    rule_type = "street_cleaning"
```

---

## Recommended Investigation Steps

### Step 1: Sample Data Inspection (BLOCKED - API not accessible)

**Ideal approach (requires live API access):**
```bash
# Fetch 100 sample records with time restrictions
curl "https://data.sfgov.org/resource/hi6h-neyh.json?\$limit=100&\$where=hrs_begin IS NOT NULL"

# Look for patterns in:
# - hrlimit values (1, 2, vs. longer)
# - days patterns (Mon,Thu vs. M-F)
# - Any fields with "sweep", "clean", "regulation"
```

**Alternative: Use existing pipeline output**
- Run backend pipeline locally (requires DataSF API token)
- Inspect generated `sf_parking_zones.json`
- Look for time restriction patterns

### Step 2: Field Discovery

**Check DataSF API schema:**
```bash
# Get metadata about available fields
curl "https://data.sfgov.org/api/views/hi6h-neyh.json"

# This returns dataset metadata including:
# - Column names
# - Column descriptions
# - Data types
```

**Alternative: Check DataSF website**
- URL: https://data.sfgov.org/Transportation/Parking-regulations-except-non-metered-color-curb-/hi6h-neyh
- Click "API" tab to see field documentation
- Look for street cleaning specific fields

### Step 3: Verify with Known SF Addresses

**Test addresses with known street cleaning:**
1. Mission District - Heavy street cleaning (Mon, Thu 8-10 AM)
2. Pacific Heights - Varied schedules (Tue, Fri 8-10 AM)
3. SOMA - Commercial cleaning (different hours)

Query blockface data for these coordinates and examine patterns.

---

## Proposed Implementation Approach

### Option A: Pattern-Based Detection (Recommended - No API Changes Needed)

**Pros:**
- Works with existing data
- No backend changes needed initially
- Can validate and refine heuristics

**Cons:**
- May have false positives/negatives
- Requires careful testing

**Implementation:**
```python
def classify_rule_type(record: Dict[str, Any]) -> str:
    """
    Classify whether a time restriction is street cleaning or time limit.

    Uses multiple heuristics:
    1. Duration: Short windows (≤2 hours) suggest cleaning
    2. Day pattern: Non-contiguous days suggest cleaning
    3. Keyword matching: "clean", "sweep" in descriptions
    """
    hrs_begin = record.get("hrs_begin")
    hrs_end = record.get("hrs_end")
    days_str = record.get("days", "")
    hrlimit = record.get("hrlimit")

    # Parse duration
    if hrs_begin and hrs_end:
        start = parse_time(hrs_begin)
        end = parse_time(hrs_end)
        duration_hours = (end - start).total_seconds() / 3600
    else:
        duration_hours = hrlimit or 24

    # Parse days
    days = parse_days(days_str)

    # Heuristic 1: Short duration + specific days
    if duration_hours <= 2 and len(days) <= 3:
        return "street_cleaning"

    # Heuristic 2: Non-contiguous days (Mon, Thu vs. Mon-Fri)
    if len(days) >= 2 and not is_contiguous(days):
        return "street_cleaning"

    # Heuristic 3: Check for keywords (if field exists)
    description = record.get("description", "").lower()
    regulation = record.get("regulation", "").lower()
    if "clean" in description or "sweep" in description:
        return "street_cleaning"
    if "clean" in regulation or "sweep" in regulation:
        return "street_cleaning"

    # Default to time limit
    return "time_limit"
```

### Option B: Field-Based Detection (Requires Verification)

**Pros:**
- More accurate if dedicated fields exist
- Explicit data, less guessing

**Cons:**
- Requires verifying fields exist
- May need DataSF API token

**Implementation:**
```python
def classify_rule_type(record: Dict[str, Any]) -> str:
    """
    Use explicit field if available, fallback to heuristics.
    """
    # Check for explicit street cleaning fields
    if record.get("streetswp_days"):
        return "street_cleaning"

    if record.get("regulation_type") == "STREET_CLEANING":
        return "street_cleaning"

    # Fallback to pattern-based detection
    return classify_by_pattern(record)
```

---

## Next Steps & Action Items

### Immediate (Can Do Now)

1. **Document the approach** ✅ (this document)
2. **Update transformer** to add rule type classification logic
3. **Test with mock data** - Create sample records to test heuristics
4. **Code the pattern detector** - Implement `classify_rule_type()` function

### Requires External Access

5. **Verify with live API** - Query DataSF to inspect actual field names
6. **Run full pipeline** - Generate updated `sf_parking_zones.json` with classifications
7. **Test with real addresses** - Validate against known SF street cleaning schedules

### Backend Code Changes Needed

**File:** `backend/transformers/parking_transformer.py`

**Change 1: Add rule type classification (around line 760)**
```python
def transform_blockface(self, raw_blockfaces: List[Dict[str, Any]]) -> List[ParkingRegulation]:
    """Transform blockface data with rule type classification"""
    logger.info(f"Transforming {len(raw_blockfaces)} blockface records")
    regulations = []

    for record in raw_blockfaces:
        try:
            # NEW: Classify rule type
            rule_type = self._classify_rule_type(record)

            # ... existing field extraction ...

            regulation = ParkingRegulation(
                # ... existing fields ...
                rule_type=rule_type,  # NEW FIELD
            )

            regulations.append(regulation)
```

**Change 2: Add ParkingRegulation.rule_type field**
```python
@dataclass
class ParkingRegulation:
    """Represents a parking regulation on a street segment"""
    street_name: str
    from_street: str
    to_street: str
    side: str
    rpp_area: Optional[str]
    time_limit: Optional[int]
    hours_begin: Optional[str]
    hours_end: Optional[str]
    days: List[str] = field(default_factory=list)
    geometry: Optional[Dict[str, Any]] = None
    rule_type: str = "time_limit"  # NEW: "street_cleaning" or "time_limit"
```

**Change 3: Update iOS data generation (around line 1055)**
```python
regulations_by_area[area].append({
    "street": reg.street_name,
    "from": reg.from_street,
    "to": reg.to_street,
    "side": reg.side,
    "timeLimit": reg.time_limit,
    "hoursBegin": reg.hours_begin,
    "hoursEnd": reg.hours_end,
    "days": reg.days,
    "ruleType": reg.rule_type,  # NEW FIELD for iOS
})
```

---

## Questions for User/Team

1. **Do you have a DataSF API token?**
   - Would allow us to run the pipeline and inspect actual data
   - Can verify field names and classifications

2. **Do you have sample output from a previous pipeline run?**
   - Even outdated `sf_parking_zones.json` would help
   - Can inspect current data structure

3. **Are there known SF addresses we should test against?**
   - Helps validate our detection logic
   - Need addresses with confirmed street cleaning

4. **Should we prioritize pattern-based or field-based detection?**
   - Pattern-based: Works immediately, may have errors
   - Field-based: More accurate but requires API verification

---

## Estimated Timeline

### With API Access
- **Day 1:** Query API, inspect fields, confirm approach
- **Day 2:** Implement classification logic, update transformer
- **Day 3:** Run pipeline, generate new data, test iOS integration
- **Total:** 3 days

### Without API Access (Pattern-Based)
- **Day 1:** Implement heuristics, add unit tests
- **Day 2:** Create mock data, test classifications
- **Day 3:** Integrate with iOS, test with sample zones
- **Later:** Validate with real data when available
- **Total:** 3 days + validation phase

---

## Appendix: Sample DataSF Query

**Query to test (requires API access):**

```bash
# Get records with time restrictions
curl "https://data.sfgov.org/resource/hi6h-neyh.json?\
\$select=rpparea1,hrlimit,hrs_begin,hrs_end,days,regulation,description,street,from_street,to_street\
&\$where=hrs_begin IS NOT NULL\
&\$limit=20"

# Get records in Mission District (known cleaning area)
curl "https://data.sfgov.org/resource/hi6h-neyh.json?\
\$select=*\
&\$where=street='Mission St'\
&\$limit=10"
```

**Expected patterns in street cleaning records:**
- `hrlimit`: null or 0 (no parking during cleaning)
- `hrs_begin`: "0800" or "08:00"
- `hrs_end`: "1000" or "10:00" (2-hour window)
- `days`: "Mon,Thu" or "Tue,Fri" (alternating days)
- `regulation` or `description`: May contain "cleaning" or "sweeping"

---

## Conclusion

The DataSF Blockface API **already contains street cleaning data** in the form of time-based restrictions. The main task is to **classify** which restrictions are street cleaning vs. regular time limits.

**Recommended approach:**
1. Implement pattern-based detection using heuristics
2. Test with mock data and known addresses
3. Validate with live API when possible
4. Refine classification logic based on results

**Next action:** Implement `classify_rule_type()` function in transformer and add `rule_type` field to data models.
