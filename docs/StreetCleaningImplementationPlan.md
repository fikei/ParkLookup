# Street Cleaning Implementation Plan

**Date:** November 29, 2025
**Status:** Planning Phase
**Based on:** DataSF_API_Investigation.md findings

---

## Current State

### Data Available
- ✅ Parking regulations dataset: `Parking_regulations_(except_non-metered_color_curb)_20251128.geojson`
- ✅ Fields include: `REGULATION`, `DAYS`, `HRS_BEGIN`, `HRS_END`, `HRLIMIT`
- ❌ **No explicit "Street Cleaning" regulation type**

### Regulation Type Analysis
From CSV analysis of 7,784 regulations:
- **6,837** "Time limited" (87.8%)
- **178** "No parking any time" (2.3%)
- **Others**: No oversized vehicles, pay/permit, etc.

**Key Finding:** Street cleaning is **hidden within** "Time limited" or "No parking any time" regulations. We need to identify them using pattern-based heuristics.

---

## Problem Statement

San Francisco street cleaning regulations appear in the parking regulations dataset but are **not explicitly labeled**. They look identical to regular time-limited parking:

```csv
REGULATION: "Time limited" or "No parking any time"
DAYS: "Mon,Thu" or "Tue,Fri" (alternating days - typical cleaning pattern)
HRS_BEGIN: "0800"
HRS_END: "1000" or "1200" (2-4 hour windows)
HRLIMIT: 0 or null (no parking allowed during cleaning)
```

---

## Solution Approach: Pattern-Based Detection

### Heuristics for Identifying Street Cleaning

Based on SF parking patterns and the investigation document, we can identify street cleaning using multiple signals:

#### 1. **Time Window Duration** (Primary Signal)
```python
# Street cleaning: SHORT windows (typically 2-4 hours)
# Regular time limits: LONGER windows (2hr+ all day)

duration_hours = parse_time_range(hrs_begin, hrs_end)

if duration_hours <= 4 and hrlimit in [0, None]:
    # Short window + no parking allowed = likely cleaning
    score += 3
```

#### 2. **Day Pattern** (Strong Signal)
```python
# Street cleaning: NON-CONTIGUOUS alternating days
# Examples: "Mon,Thu", "Tue,Fri", "2nd Tue", "1st/3rd Wed"
# Regular limits: CONTIGUOUS (M-F, M-Sa, DAILY)

days = parse_days(record['DAYS'])

if len(days) == 2 and days_are_alternating(days):
    # Two specific days (e.g., Mon & Thu) = likely cleaning
    score += 4
elif len(days) <= 3 and not is_contiguous(days):
    # Few non-contiguous days = likely cleaning
    score += 2
```

#### 3. **Time of Day** (Supporting Signal)
```python
# Street cleaning: Early morning/midday windows
# Common times: 8am-10am, 8am-12pm, 12pm-2pm

start_hour = parse_hour(hrs_begin)

if 6 <= start_hour <= 14:  # 6am to 2pm
    score += 1
```

#### 4. **HRLIMIT Value** (Supporting Signal)
```python
# Street cleaning: Usually 0 or null (no parking allowed)
# Time limits: Positive values (2, 4, etc.)

if hrlimit in [0, None, "0"]:
    score += 2
```

### Classification Logic

```python
def classify_as_street_cleaning(record: Dict) -> tuple[bool, float]:
    """
    Classify if a regulation is street cleaning using weighted heuristics.

    Returns:
        (is_cleaning, confidence_score)
    """
    score = 0
    max_score = 10

    # Parse fields
    hrs_begin = record.get('HRS_BEGIN')
    hrs_end = record.get('HRS_END')
    days_str = record.get('DAYS', '')
    hrlimit = record.get('HRLIMIT')
    regulation = record.get('REGULATION', '').lower()

    # Heuristic 1: Time window duration (0-3 points)
    if hrs_begin and hrs_end:
        duration_hours = calculate_duration(hrs_begin, hrs_end)
        if duration_hours <= 2:
            score += 3  # Very short window
        elif duration_hours <= 4:
            score += 2  # Short window

    # Heuristic 2: Day pattern (0-4 points)
    days = parse_days(days_str)
    if len(days) == 2 and are_alternating(days, interval=2):
        # E.g., Monday & Thursday (3 days apart)
        score += 4
    elif len(days) == 2 and are_alternating(days, interval=3):
        # E.g., Monday & Friday (4 days apart)
        score += 3
    elif len(days) <= 3 and not is_contiguous(days):
        # Few specific days, not contiguous
        score += 2

    # Heuristic 3: HRLIMIT value (0-2 points)
    if hrlimit in [0, None, "0", ""]:
        score += 2

    # Heuristic 4: Time of day (0-1 point)
    if hrs_begin:
        start_hour = parse_hour(hrs_begin)
        if 6 <= start_hour <= 14:
            score += 1

    # Calculate confidence
    confidence = score / max_score

    # Classify: >= 60% confidence = street cleaning
    is_cleaning = confidence >= 0.6

    return is_cleaning, confidence


def are_alternating(days: List[str], interval: int = 2) -> bool:
    """
    Check if days are alternating (e.g., Mon & Thu are 3 days apart).

    Common patterns:
    - Mon/Thu = 3 days apart (interval=2 weekdays)
    - Tue/Fri = 3 days apart
    - Mon/Wed/Fri = every other day
    """
    day_indices = [weekday_to_index(d) for d in days]
    if len(day_indices) != 2:
        return False

    diff = abs(day_indices[1] - day_indices[0])
    # Check if approximately 'interval' weekdays apart
    return diff == (interval + 1) or diff == (7 - interval - 1)
```

---

## Implementation Steps

### Phase 1: Add Classification to Conversion Script (Immediate)

**File:** `convert_geojson_with_regulations.py`

**Changes:**

1. **Add street cleaning detection function:**
```python
def classify_regulation_type(reg_props: Dict) -> str:
    """
    Enhanced regulation type detection including street cleaning.

    Returns: "streetCleaning", "timeLimit", "noParking", etc.
    """
    regulation_raw = reg_props.get("regulation", "").lower()

    # Check if it matches street cleaning patterns
    is_cleaning, confidence = is_street_cleaning(reg_props)

    if is_cleaning and confidence >= 0.7:
        return "streetCleaning"

    # Fall back to existing logic
    return map_regulation_type(regulation_raw)


def is_street_cleaning(reg_props: Dict) -> tuple[bool, float]:
    """Heuristic-based street cleaning detection"""
    # Implementation as shown above
    pass
```

2. **Update `extract_regulation()` to use new classifier:**
```python
def extract_regulation(reg_props: Dict) -> List[Dict]:
    # BEFORE: regulation_type = map_regulation_type(regulation_type_raw)
    # AFTER:
    regulation_type = classify_regulation_type(reg_props)

    # Rest remains the same
    ...
```

3. **Add logging for validation:**
```python
# Log street cleaning detections for manual review
if regulation_type == "streetCleaning":
    logger.info(f"Street cleaning detected: "
                f"days={reg_props.get('DAYS')}, "
                f"hours={reg_props.get('HRS_BEGIN')}-{reg_props.get('HRS_END')}, "
                f"confidence={confidence:.2f}")
```

### Phase 2: Test & Validate (1-2 days)

**Test Cases:**

1. **Known street cleaning patterns:**
   - Mon/Thu 8am-10am → Should classify as `streetCleaning`
   - Tue/Fri 8am-12pm → Should classify as `streetCleaning`
   - 2nd Tuesday 9am-11am → Should classify as `streetCleaning`

2. **Known time limits:**
   - M-F 9am-6pm 2hr limit → Should classify as `timeLimit`
   - Daily 8am-6pm 4hr limit → Should classify as `timeLimit`

3. **Edge cases:**
   - Thu only 8am-10am → Ambiguous (could be either)
   - M-F 8am-10am → Could be cleaning or short-term parking

**Validation:**

```bash
# Run conversion with street cleaning detection
python3 convert_geojson_with_regulations.py

# Grep for street cleaning classifications
cat sample_blockfaces_with_regulations.json | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
cleaning = [bf for bf in data['blockfaces']
            if any(r['type'] == 'streetCleaning' for r in bf['regulations'])]
print(f'Found {len(cleaning)} blockfaces with street cleaning')

# Show samples
for bf in cleaning[:5]:
    sc = [r for r in bf['regulations'] if r['type'] == 'streetCleaning'][0]
    print(f\"{bf['street']}: {sc['enforcementDays']} {sc['enforcementStart']}-{sc['enforcementEnd']}\")
"
```

### Phase 3: Ground Truth Validation (Requires manual spot-checking)

**Sample 20 blockfaces classified as street cleaning:**
1. Look up addresses on Google Street View
2. Check physical signage for "Street Cleaning" or "No Parking for Cleaning"
3. Calculate accuracy rate

**Target:** > 80% accuracy before deploying to production

### Phase 4: Update Documentation & Priority System

1. **Update `RegulationPrioritySystem.md`:**
   - Confirm `streetCleaning` priority (currently #3)
   - May need to adjust based on real data

2. **Document heuristics:**
   - Add section to `StreetCleaningImplementationPlan.md`
   - Include test results and accuracy metrics

3. **Update `RegulationTypesMapping.md`:**
   - Remove "NOT IN CSV" note for streetCleaning
   - Add "Pattern-based detection" note

---

## Expected Results

### Statistics (Estimated)

From 7,784 SF regulations:
- **Time limited:** 6,837 (87.8%)
  - → Estimated 500-1,000 are actually street cleaning (7-15%)
  - → Remaining 5,837-6,337 are true time limits (75-81%)

**After classification:**
- `streetCleaning`: 500-1,000 (6-13%)
- `timeLimit`: 5,800-6,300 (75-81%)
- `noParking`: 178 (2.3%)
- `other`: 600 (7.7%)

### Impact on Match Rates

Street cleaning regulations tend to be on **major streets** with high parking demand, so they're more likely to match blockfaces than average regulations.

**Estimated impact:**
- Current: 48.5% of blockfaces have regulations
- After adding street cleaning: 52-55% (additional blockfaces identified)
- Street cleaning specifically: 15-25% of blockfaces

---

## Alternative: Manual Dataset Acquisition

If pattern-based detection proves inaccurate, consider:

### Option A: DataSF Separate Dataset
Check if SF publishes a dedicated street sweeping schedule:
- URL: https://data.sfgov.org/browse?q=street%20sweeping
- May exist as separate dataset with explicit schedules

### Option B: SFMTA API
SF Municipal Transportation Agency may have dedicated API:
- Check: https://www.sfmta.com/getting-around/drive-park/street-sweeping
- May provide CSV/JSON download

### Option C: Scrape from SF311
SF311 website has street cleaning lookup:
- URL: https://sf311.org/information/street-cleaning-schedule
- Could scrape for validation dataset

---

## Timeline

### Week 1: Implementation
- **Day 1-2:** Implement heuristics in `convert_geojson_with_regulations.py`
- **Day 3:** Test with Mission District subset
- **Day 4:** Run on full SF dataset
- **Day 5:** Analyze results, tune thresholds

### Week 2: Validation & Deployment
- **Day 1-2:** Manual ground truth validation (20-50 samples)
- **Day 3:** Refine heuristics based on validation
- **Day 4:** Update documentation
- **Day 5:** Commit, push, generate final dataset

**Total:** 2 weeks

---

## Success Criteria

1. ✅ **Detection accuracy:** > 80% of classified street cleaning are correct
2. ✅ **Coverage:** Identify 500+ street cleaning regulations (6-10% of dataset)
3. ✅ **No false positives:** < 5% of regular time limits misclassified as cleaning
4. ✅ **Documentation:** Heuristics clearly documented with test cases
5. ✅ **Priority system:** Street cleaning correctly ordered (#3 priority)

---

## Future Enhancements

### 1. Machine Learning Classifier
Once we have validated data:
- Train classifier on labeled examples
- Features: duration, days, time, hrlimit, location
- Model: Random Forest or XGBoost
- Expected accuracy: > 95%

### 2. Geospatial Patterns
Street cleaning often follows geographic patterns:
- Major corridors: More frequent cleaning
- Residential: Less frequent, alternating days
- Commercial districts: Midday windows

Could add location-based heuristics:
```python
if is_major_corridor(street_name) and has_short_window(hrs):
    # More likely to be street cleaning on busy streets
    score += 1
```

### 3. Historical Pattern Analysis
If we track changes over time:
- Regulations that change seasonally → likely cleaning
- Regulations that are consistent → likely time limits

---

## Questions & Decisions Needed

1. **Confidence threshold:** Use 60%, 70%, or 80% for classification?
   - Recommend: 70% (balance precision/recall)

2. **Ambiguous cases:** How to handle low-confidence classifications?
   - Option A: Default to `timeLimit` (conservative)
   - Option B: Create new type `unknown` (explicit)
   - Recommend: Option A

3. **Validation scope:** How many samples to manually verify?
   - Minimum: 20 (quick validation)
   - Recommended: 50 (statistical significance)
   - Ideal: 100 (high confidence)

4. **Priority adjustment:** Keep `streetCleaning` at priority #3?
   - Current: noParking(1) → towAway(2) → **streetCleaning(3)** → metered(4)
   - Alternative: streetCleaning could be #2 (more urgent than general tow-away)
   - Recommend: Keep at #3 (temporary tow vs. permanent)

---

## Next Steps

1. ✅ **Document the plan** (this document)
2. ⏳ **Get user approval** on approach and thresholds
3. ⏳ **Implement heuristics** in conversion script
4. ⏳ **Test with Mission District** data
5. ⏳ **Validate with ground truth** samples
6. ⏳ **Run full SF dataset** if validation succeeds
7. ⏳ **Update documentation** with results

**Blocked on:** User feedback on approach

---

**Last Updated:** November 29, 2025
**Related Docs:**
- `DataSF_API_Investigation.md` - Original investigation
- `RegulationTypesMapping.md` - Field mappings
- `RegulationPrioritySystem.md` - Priority ordering
