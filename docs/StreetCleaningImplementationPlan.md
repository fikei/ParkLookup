# Street Cleaning Implementation Plan

**Date:** November 29, 2025
**Status:** Planning Phase
**Based on:** DataSF_API_Investigation.md findings

---

## Current State

### Data Available
- ✅ Parking regulations dataset: `Parking_regulations_(except_non-metered_color_curb)_20251128.geojson`
- ✅ Fields include: `REGULATION`, `DAYS`, `HRS_BEGIN`, `HRS_END`, `HRLIMIT`
- ❌ **Street cleaning data NOT in this dataset**

### Regulation Type Analysis
From CSV analysis of 7,784 regulations:
- **6,837** "Time limited" (87.8%)
- **178** "No parking any time" (2.3%)
- **Others**: No oversized vehicles, pay/permit, etc.
- **0** Street cleaning or sweeping mentions

**Critical Finding:** The dataset name "Parking_regulations_(except_non-metered_color_curb)" indicates it **excludes** certain regulation types. Street cleaning data is NOT included in this dataset.

### Data Verification Results
Searched the current dataset for street cleaning patterns:
- ❌ No mentions of "clean" or "sweep" in REGULATION field
- ❌ No typical street cleaning patterns (short daytime windows with alternating days)
- ❌ All regulations are either M-F continuous or overnight parking restrictions

**Conclusion:** We need a **separate street cleaning dataset** from DataSF.

---

## Problem Statement

San Francisco street cleaning regulations are **NOT included** in the current parking regulations dataset (`Parking_regulations_(except_non-metered_color_curb)`). We need to:

1. Identify the correct DataSF street cleaning/sweeping dataset
2. Download the data in GeoJSON format
3. Perform spatial join with blockfaces (same as parking regulations)
4. Integrate street cleaning regulations into the blockface data structure

---

## Solution Approach: Acquire Separate Dataset

### Step 1: Identify DataSF Street Cleaning Dataset

**Potential DataSF datasets:**

1. **Street Sweeping Schedules**
   - Likely dataset ID format: `xxxx-yyyy` (4-4 alphanumeric)
   - URL pattern: `https://data.sfgov.org/resource/{dataset-id}.json`
   - Search: https://data.sfgov.org/browse?q=street+sweeping

2. **Possible dataset names:**
   - "Street Sweeping Schedules"
   - "Street Cleaning Routes"
   - "Street Sweeping Routes and Schedules"
   - "Parking Regulations - Street Cleaning"

**How to find:**
```bash
# Search DataSF catalog
curl "https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&search_context=data.sfgov.org&q=street+sweeping"

# Or check SFMTA data portal
# https://www.sfmta.com/reports/street-sweeping-schedule
```

### Step 2: Download Dataset

Once identified, download in GeoJSON format:

```bash
# Example (replace with actual dataset ID)
DATASET_ID="xxxx-yyyy"
OUTPUT_FILE="Data Sets/Street_sweeping_schedules_$(date +%Y%m%d).geojson"

# Download from DataSF Socrata API
curl "https://data.sfgov.org/resource/${DATASET_ID}.geojson?\$limit=50000" \
  -o "$OUTPUT_FILE"
```

**Expected fields in street cleaning dataset:**

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `street` or `street_name` | String | Street name | "Mission St" |
| `from_street` | String | Starting intersection | "24th St" |
| `to_street` | String | Ending intersection | "25th St" |
| `side` | String | Side of street | "EVEN", "ODD", "BOTH" |
| `weekday` or `days` | String | Cleaning days | "Monday", "Mon,Thu", "1st Tuesday" |
| `fromhour` or `start_time` | String/Int | Start time | "0800", "08:00", 8 |
| `tohour` or `end_time` | String/Int | End time | "1000", "10:00", 10 |
| `corridor_name` | String | Route/corridor name | "Mission Street Corridor" |
| `shape` or `geometry` | Geometry | LineString geometry | MULTILINESTRING(...) |

**Alternative:** Dataset may use week-of-month patterns:
- `week_of_month`: "1st", "3rd", "2nd/4th"
- `weekday`: "Tuesday", "Friday"

### Step 3: Spatial Join with Blockfaces

Use the same spatial matching algorithm as parking regulations:

```python
# In convert_geojson_with_regulations.py

def load_street_cleaning(cleaning_path: str) -> List[Tuple[Geometry, Dict]]:
    """Load street cleaning GeoJSON and extract geometries + properties"""
    with open(cleaning_path, 'r') as f:
        data = json.load(f)

    cleaning_regs = []
    for feature in data['features']:
        geom = shape(feature['geometry'])
        props = feature['properties']
        cleaning_regs.append((geom, props))

    return cleaning_regs


def extract_street_cleaning_regulation(props: Dict) -> Dict:
    """Extract street cleaning fields and map to app schema"""
    return {
        "type": "streetCleaning",
        "permitZone": None,
        "timeLimit": None,
        "meterRate": None,
        "enforcementDays": parse_days(props.get('weekday') or props.get('days')),
        "enforcementStart": parse_time(props.get('fromhour') or props.get('start_time')),
        "enforcementEnd": parse_time(props.get('tohour') or props.get('end_time')),
        "specialConditions": f"Street cleaning on {props.get('weekday', 'designated days')}"
    }
```

---

## Implementation Steps

### Phase 1: Identify and Download Dataset (Week 1)

**Tasks:**

1. **Search DataSF for street cleaning dataset (Day 1):**
   ```bash
   # Search Socrata catalog
   curl "https://api.us.socrata.com/api/catalog/v1?domains=data.sfgov.org&search_context=data.sfgov.org&q=street+sweeping" | \
     python3 -m json.tool

   # Check SFMTA website for direct links
   # https://www.sfmta.com/reports/street-sweeping-schedule
   ```

2. **Identify dataset ID and fields (Day 1-2):**
   - Browse DataSF: https://data.sfgov.org/browse?q=street+sweeping
   - Note the dataset ID (format: `xxxx-yyyy`)
   - Review field schema in API documentation
   - Check data quality with sample queries

3. **Download dataset (Day 2):**
   ```bash
   # Replace DATASET_ID with actual ID found
   DATASET_ID="xxxx-yyyy"
   DATE=$(date +%Y%m%d)

   # Download GeoJSON
   curl "https://data.sfgov.org/resource/${DATASET_ID}.geojson?\$limit=50000" \
     -o "Data Sets/Street_sweeping_schedules_${DATE}.geojson"

   # Download CSV for inspection
   curl "https://data.sfgov.org/resource/${DATASET_ID}.csv?\$limit=50000" \
     -o "Data Sets/Street_sweeping_schedules_${DATE}.csv"
   ```

4. **Inspect data quality (Day 2-3):**
   ```python
   import json

   with open('Data Sets/Street_sweeping_schedules_YYYYMMDD.geojson') as f:
       data = json.load(f)

   print(f"Total features: {len(data['features'])}")

   # Check field names
   if data['features']:
       print("Sample fields:", data['features'][0]['properties'].keys())
       print("Sample record:", data['features'][0]['properties'])
   ```

### Phase 2: Extend Conversion Script (Week 1-2)

**File:** `convert_geojson_with_regulations.py`

**Changes:**

1. **Add command-line argument for street cleaning dataset:**
   ```python
   def main():
       # ... existing args ...

       if len(sys.argv) > 4:
           cleaning_file = sys.argv[4]
       else:
           cleaning_file = None  # Optional
   ```

2. **Add street cleaning loading function:**
   ```python
   def load_street_cleaning(cleaning_path: str) -> List[Tuple[Geometry, Dict]]:
       """Load street cleaning GeoJSON"""
       print(f"Loading street cleaning from: {cleaning_path}")

       with open(cleaning_path, 'r') as f:
           data = json.load(f)

       cleaning_regs = []
       for feature in data['features']:
           geom = shape(feature['geometry'])
           props = feature['properties']
           cleaning_regs.append((geom, props))

       print(f"  ✓ Loaded {len(cleaning_regs)} street cleaning regulations")
       return cleaning_regs
   ```

3. **Add street cleaning field extraction:**
   ```python
   def extract_street_cleaning_regulation(props: Dict) -> Dict:
       """Map street cleaning fields to app schema"""
       # Adapt field names based on actual dataset structure
       return {
           "type": "streetCleaning",
           "permitZone": None,
           "timeLimit": None,
           "meterRate": None,
           "enforcementDays": parse_days(props.get('weekday') or props.get('days')),
           "enforcementStart": parse_time(props.get('fromhour') or props.get('start_time')),
           "enforcementEnd": parse_time(props.get('tohour') or props.get('end_time')),
           "specialConditions": f"Street cleaning on {props.get('weekday', 'designated days')}"
       }
   ```

4. **Modify main conversion function to merge both datasets:**
   ```python
   def convert_with_regulations(blockfaces_path, regulations_path,
                                output_path, cleaning_path=None, bounds_filter=True):
       # Load parking regulations
       regulations = load_regulations(regulations_path)

       # Load street cleaning if provided
       if cleaning_path:
           cleaning_regs = load_street_cleaning(cleaning_path)
           # Combine with parking regulations
           all_regulations = regulations + cleaning_regs
       else:
           all_regulations = regulations

       # Rest of the algorithm remains the same
       # (spatial join, deduplication, priority sorting)
       ...
   ```

### Phase 3: Test & Validate (Week 2)

**Test with Mission District first:**

```bash
# Run conversion with both datasets
python3 convert_geojson_with_regulations.py \
  "Data Sets/Blockfaces_20251128.geojson" \
  "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson" \
  "Data Sets/Street_sweeping_schedules_YYYYMMDD.geojson" \
  "sample_blockfaces_with_all_regulations.json"
```

**Validation checks:**

1. **Street cleaning extraction:**
   ```python
   import json

   with open('sample_blockfaces_with_all_regulations.json') as f:
       data = json.load(f)

   # Count blockfaces with street cleaning
   cleaning_count = sum(1 for bf in data['blockfaces']
                        if any(r['type'] == 'streetCleaning' for r in bf['regulations']))

   print(f"Blockfaces with street cleaning: {cleaning_count}")

   # Show samples
   for bf in data['blockfaces']:
       sc_regs = [r for r in bf['regulations'] if r['type'] == 'streetCleaning']
       if sc_regs:
           print(f"\n{bf['street']} ({bf['fromStreet']} → {bf['toStreet']}):")
           for sc in sc_regs[:2]:
               print(f"  - {sc['enforcementDays']} {sc['enforcementStart']}-{sc['enforcementEnd']}")
           if len(sc_regs) > 5:
               break
   ```

2. **Priority ordering verification:**
   ```python
   # Check that streetCleaning appears before timeLimit when both exist
   for bf in data['blockfaces'][:100]:
       types = [r['type'] for r in bf['regulations']]
       if 'streetCleaning' in types and 'timeLimit' in types:
           sc_idx = types.index('streetCleaning')
           tl_idx = types.index('timeLimit')
           assert sc_idx < tl_idx, f"Priority error in {bf['id']}"
   print("✓ Priority ordering correct")
   ```

3. **Data quality checks:**
   - No duplicate regulations on same blockface
   - All streetCleaning regs have enforcementDays
   - Time ranges are valid (start < end)

### Phase 4: Ground Truth Validation

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
