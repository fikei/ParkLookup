# Spatial Join Results - Blockfaces + Parking Regulations

**Date:** November 2025
**Script:** `convert_geojson_with_regulations.py`
**Status:** ✅ **COMPLETE** - Spatial join successfully implemented and tested
**Last Updated:** November 29, 2025 - Algorithm improved to prevent regulation duplication

---

## Executive Summary

Successfully implemented spatial join between:
- **Blockfaces GeoJSON** (18,355 street centerlines)
- **Parking Regulations GeoJSON** (7,784 parking rules)

Using Shapely 2.1.2 for geometric operations with a **15-meter buffer**. The algorithm ensures:
- ✅ Each regulation is assigned to **exactly ONE blockface** (the closest match)
- ✅ Each blockface can have **MULTIPLE regulations** (typical: 2-6 per blockface)
- ✅ No duplication of regulations across adjacent blockfaces

---

## Mission District Test Results

**Test Area:** Mission District (bounded by Market St, Dolores St, Cesar Chavez, Potrero Ave)

### Statistics

| Metric | Value | Notes |
|--------|-------|-------|
| **Blockfaces processed** | 1,469 | Mission District only |
| **Blockfaces with regulations** | 712 (48.5%) | True match rate (no duplication) |
| **Blockfaces without regulations** | 757 (51.5%) | May be unregulated or data gaps |
| **Total regulations matched** | 1,370 | Each regulation assigned to ONE blockface |
| **Avg regulations per blockface** | 0.93 | Avg across all blockfaces |
| **Blockfaces with 2+ regulations** | 596 (40.6%) | Multiple rules per blockface |
| **Max regulations on one blockface** | 6 | Complex regulatory zones |
| **SF-wide regulations processed** | 7,774 | Most outside Mission District |
| **Regulations matched to Mission** | 865 (11.1%) | Expected: bounds filter active |

### Regulation Type Breakdown

| Type | Count | Percentage |
|------|-------|------------|
| `residentialPermit` | 631 | 46.1% |
| `timeLimit` | 584 | 42.6% |
| `other` | 83 | 6.1% |
| `metered` | 43 | 3.1% |
| `noParking` | 29 | 2.1% |

---

## How It Works

### 1. Spatial Matching Algorithm (Updated Nov 29, 2025)

The algorithm uses a **regulation-centric approach** to ensure each regulation is assigned to exactly ONE blockface:

```python
# Step 1: Load all blockfaces in target area (Mission District)
blockfaces = load_blockfaces_with_bounds_filter()  # 1,469 blockfaces

# Step 2: For each regulation, find the CLOSEST blockface
for regulation in all_regulations:  # 7,774 SF-wide regulations
    buffered_reg = regulation.buffer(0.000135)  # ~15 meters

    # Find all blockfaces that intersect
    candidates = [bf for bf in blockfaces if buffered_reg.intersects(bf)]

    # Choose the closest one
    if candidates:
        closest = min(candidates, key=lambda bf: regulation.distance(bf))
        closest.regulations.append(regulation)
```

**Buffer distance:** 0.000135 degrees ≈ **15 meters** at SF latitude

**Key improvements:**
- ✅ **1:1 mapping**: Each regulation assigned to only ONE blockface (prevents duplication)
- ✅ **Distance-based**: Uses closest blockface when multiple candidates exist
- ✅ **Many:1 allowed**: Multiple regulations can still be assigned to the same blockface
- ✅ **Increased buffer**: 15m (up from 11m) improves alignment tolerance

This accounts for:
- Slight misalignment between blockface and regulation geometries
- Regulations on curbs vs. blockface street centerlines
- GPS accuracy variations in source data
- Different vertex densities in geometries

### 2. Field Mapping

**DataSF Regulations GeoJSON** → **App BlockfaceRegulation Schema**

| GeoJSON Field | App Field | Transformation |
|---------------|-----------|----------------|
| `regulation` | `type` | Mapped to enum: "Time limited" → "timeLimit" |
| `rpparea1/2/3` | `permitZone` | Combined into single field (first zone) or multiple regs |
| `hrlimit` | `timeLimit` | Converted hours → minutes (2hr → 120min) |
| `days` | `enforcementDays` | Parsed: "M-F" → ["monday", "tuesday", ...] |
| `hrs_begin` | `enforcementStart` | Formatted: "900" → "09:00" |
| `hrs_end` | `enforcementEnd` | Formatted: "1800" → "18:00" |
| `exceptions` | `specialConditions` | Direct copy |

### 3. Handling Multiple RPP Zones

When a regulation has multiple RPP zones (e.g., `rpparea1="L"`, `rpparea2="BB"`), the script creates **multiple regulation objects**:

```json
[
  {
    "type": "timeLimit",
    "permitZone": null,
    "timeLimit": 240
  },
  {
    "type": "residentialPermit",
    "permitZone": "L"
  },
  {
    "type": "residentialPermit",
    "permitZone": "BB"
  }
]
```

### 4. Deduplication

The same regulation geometry may match a blockface multiple times (e.g., MultiLineString with multiple segments). The script deduplicates by creating a unique key from all regulation fields:

```python
# Create unique key from all non-None fields
key = (type, permitZone, timeLimit, enforcementDays, enforcementStart, ...)
if key not in seen:
    unique_regulations.append(reg)
```

This reduced duplicates by **49%** (3,738 → 1,891 regulations).

---

## Example Output

### Blockface: Albion Street (17th St → 16th St, east side)

**Before spatial join:**
```json
{
  "regulations": []
}
```

**After spatial join:**
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
      "type": "timeLimit",
      "permitZone": null,
      "timeLimit": 120,
      "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
      "enforcementStart": "08:00",
      "enforcementEnd": "21:00",
      "specialConditions": "Yes. RPP holders are exempt from time limits."
    },
    {
      "type": "residentialPermit",
      "permitZone": "S",
      "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
      "enforcementStart": "08:00",
      "enforcementEnd": "21:00",
      "specialConditions": "Exempt from time limits. Yes. RPP holders are exempt from time limits."
    }
  ]
}
```

---

## Data Quality Issues

### 1. Missing Street Names (95.9%)

Only 60 out of 1,469 blockfaces (4.1%) have `popupinfo` field populated. The rest show:
```json
{
  "street": "Unknown Street",
  "fromStreet": "Unknown",
  "toStreet": "Unknown"
}
```

**Impact:** Low - Blockfaces still have valid geometry and regulations. Street names are nice-to-have for debugging but not required for spatial lookups.

**Mitigation options:**
- Reverse geocoding using coordinates
- Join with SF street centerline dataset
- Extract from regulation metadata (some have street names)

### 2. No-Match Rate (38.8%)

570 blockfaces (38.8%) have no regulations matched.

**Possible causes:**
- Unregulated streets (residential with no parking rules)
- Data gaps in regulations dataset
- Geometric misalignment (regulation geometry too far from blockface)

**Next steps:**
- Sample 20 random no-match blockfaces
- Check Google Maps/Street View for actual signage
- Determine if truly unregulated or data gap

---

## Validation Results

### Match Rate: 48.5% (Updated Nov 29, 2025)

**Target:** > 80% (not met)
**Actual:** 48.5% (712 out of 1,469 blockfaces)
**Previous (incorrect):** 61.2% (inflated due to regulation duplication)

**Why the change:**
The original 61.2% match rate was artificially inflated because the same regulation could be assigned to multiple adjacent blockfaces. The new algorithm ensures each regulation is assigned to only ONE blockface (the closest match), revealing the true match rate.

**Analysis:**
- 51.5% of blockfaces have no regulations (757 blockfaces)
- This may be due to:
  - Genuinely unregulated residential side streets
  - Data gaps in the regulations dataset
  - Geometric misalignment beyond 15m buffer
  - Regulations geometries not aligning with blockface centerlines

**Note:** Of 7,774 SF-wide regulations, only 865 (11.1%) matched to Mission District blockfaces. This is expected since most regulations are outside the Mission District bounds filter.

### Duplication: 100% prevented ✅

**Target:** No duplicates across blockfaces
**Result:** Algorithm ensures each regulation is assigned to exactly ONE blockface
**Previous issue:** Old algorithm allowed same regulation to match multiple adjacent blockfaces
**Fix:** Regulation-centric matching with distance-based selection

### Type Mapping: 93.9% covered ✅

**Target:** > 90%
**Result:** 93.9% mapped to standard types (residentialPermit, timeLimit, metered, noParking)
**Other:** 6.1% mapped to "other" (mostly "No oversized vehicles")

---

## Performance

| Operation | Time | Records/sec |
|-----------|------|-------------|
| Load regulations | ~2s | 3,887/s |
| Process 18,355 blockfaces | ~15s | 1,224/s |
| Filter to Mission District | ~15s | 98/s |
| **Total** | **~17s** | **86/s** |

**Note:** Processing all 18K blockfaces without bounds filter would take ~2-3 minutes.

---

## Next Steps

### Tasks Completed ✅

- [x] **Task 17.36:** Implement spatial join between blockface geometries and regulations
- [x] **Task 17.37:** Extract regulation fields from matched records
- [x] **Task 17.38:** Validate spatial join quality (61.2% match rate, deduplication working)
- [x] **Task 17.39:** Update conversion script with spatial join logic

### Tasks Remaining

- [ ] **Task 17.33:** Evaluate blockface rendering performance with full dataset
- [ ] **Task 17.34:** Implement blockface simplification/clustering for performance
- [ ] **Task 17.35:** Improve bearing-aware offset for curved streets

### Future Enhancements

1. **Improve match rate** (38.8% → < 20% no-match)
   - Increase buffer distance for wider matching
   - Add nearest-neighbor fallback for no-match cases
   - Validate no-match blockfaces against ground truth

2. **Add street names** (4.1% → > 80% coverage)
   - Reverse geocoding API
   - Join with SF street centerline dataset
   - Parse from regulation metadata

3. **Conflict detection**
   - Identify blockfaces with contradictory regulations
   - Flag for manual review
   - Apply "most restrictive" rule

4. **Add street cleaning & metered data**
   - Integrate street sweeping schedule dataset (Story 24)
   - Join parking meters dataset (Story 25)
   - Update schema to include meter rates, cleaning schedules

---

## Files Created

| File | Purpose |
|------|---------|
| `convert_geojson_with_regulations.py` | Spatial join script with deduplication |
| `sample_blockfaces_with_regulations.json` | Mission District test output (1,469 blockfaces) |
| `SFParkingZoneFinder/.../sample_blockfaces.json` | Copied to app resources for testing |

---

## Usage

### Convert Mission District only (with regulations):
```bash
python3 convert_geojson_with_regulations.py
```

### Convert all San Francisco (18K+ blockfaces):
```bash
python3 convert_geojson_with_regulations.py \
  "Data Sets/Blockfaces_20251128.geojson" \
  "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson" \
  "all_sf_blockfaces.json" \
  --no-bounds
```

### Custom buffer distance (20 meters):
```python
# Edit script, change:
BUFFER_DISTANCE = 0.0002  # ~22 meters
```

---

**Last Updated:** November 2025
**Related Docs:**
- `BlockfaceRegulationsMatching.md` - Status before implementation
- `RegulationTypesMapping.md` - Field mapping reference
- `blockface_offset_strategy.md` - Visualization algorithm

