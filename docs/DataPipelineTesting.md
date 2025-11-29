# Data Pipeline Testing Guide

## Overview

This document outlines the testing strategy for the SF parking data pipeline, which converts GeoJSON source data into iOS app format with comprehensive parking regulations.

## Pipeline Components

### 1. Data Conversion Pipeline
- **Script**: `convert_geojson_with_regulations.py`
- **Input**:
  - Blockfaces GeoJSON
  - Parking regulations GeoJSON
  - Street sweeping schedules GeoJSON
  - Metered parking GeoJSON
- **Output**: Consolidated blockface JSON with regulations

### 2. Key Features
- Side-aware spatial matching (EVEN/ODD addressing)
- Street name backfilling from regulation data
- Regulation priority system
- Cross product geometry for LEFT/RIGHT determination

## Test Categories

### 1. Unit Tests

#### Spatial Matching Tests
**Function**: `determine_side_of_line()`
- [ ] Test perpendicular regulation (should match RIGHT for EVEN, LEFT for ODD)
- [ ] Test regulation on wrong side (should be filtered out)
- [ ] Test regulation directly on centerline (UNKNOWN, should match both)
- [ ] Test curved streets (verify cross product at multiple points)

**Function**: `blockface_side_to_left_right()`
- [ ] EVEN → RIGHT
- [ ] ODD → LEFT
- [ ] NORTH/SOUTH → UNKNOWN
- [ ] Invalid input → UNKNOWN

#### Street Name Normalization Tests
**Function**: `normalize_street_name()`
- [ ] "Market St" → "Market Street"
- [ ] "08th Ave" → "8th Avenue"
- [ ] "Lower Great Hwy" → "Lower Great Highway"
- [ ] "Alemany Blvd" → "Alemany Boulevard"
- [ ] Empty string → "Unknown Street"
- [ ] "03rd St" → "3rd Street" (leading zero removal)

#### Regulation Extraction Tests
**Function**: `extract_street_sweeping()`
- [ ] Parse weekday abbreviations (Mon → monday, Tues → tuesday)
- [ ] Format enforcement hours (fromhour: 8 → "08:00")
- [ ] Extract corridor field as _sourceStreet
- [ ] Parse week patterns (2nd/4th week)

#### Regulation Priority Tests
**Function**: `sort_regulations_by_priority()`
- [ ] No Parking (priority 1) comes before Street Cleaning (3)
- [ ] Street Cleaning (3) comes before Metered (4)
- [ ] Metered (4) comes before RPP (6)
- [ ] Secondary sort by type name for consistency

### 2. Integration Tests

#### Full Conversion Tests
**Script**: `run_full_conversion.py`

Test Data:
- Mission District bounds (37.744-37.780 lat, -122.426 to -122.407 lon)
- Expected: ~1,469 blockfaces

**Assertions**:
- [ ] Blockface count within expected range (1400-1500)
- [ ] Regulation coverage >80% of blockfaces
- [ ] Street name backfilling >50% coverage
- [ ] All regulation types present (streetCleaning, metered, RPP, timeLimit, noParking)
- [ ] No duplicate regulations on same blockface
- [ ] All regulations sorted by priority

#### Side-Aware Matching Tests
- [ ] Verify EVEN blockfaces only match RIGHT-side regulations
- [ ] Verify ODD blockfaces only match LEFT-side regulations
- [ ] Verify UNKNOWN sides match regulations on both sides
- [ ] Test two-sided streets have regulations on both sides

#### Street Name Backfilling Tests
- [ ] Blockfaces with "Unknown Street" receive names from _sourceStreet
- [ ] Names are properly normalized (St → Street, Ave → Avenue)
- [ ] Leading zeros removed from numbered streets
- [ ] _sourceStreet metadata cleaned up before output

### 3. Data Quality Tests

#### Spot Check Validation
**Script**: `generate_spot_check_samples.py`

Sample 5 locations for each regulation type:
- [ ] Street Cleaning - verify days/times match street signs
- [ ] Metered - verify meter presence
- [ ] Time Limit - verify posted time limits
- [ ] Residential Permit - verify RPP zone signs
- [ ] No Parking - verify no parking signs

**Target Accuracy**: >80% per regulation type

#### Coverage Analysis
**Script**: `analyze_side_coverage.py`

- [ ] Named streets >50% (target: 60%+)
- [ ] Two-sided street cleaning coverage (sample streets)
- [ ] Regulation distribution matches expected patterns

### 4. Regression Tests

Run after any changes to spatial matching or regulation extraction:

- [ ] Compare regulation counts per type (should be within 5%)
- [ ] Compare named street percentage (should not decrease)
- [ ] Verify Mission District sample data unchanged
- [ ] Check output JSON schema matches iOS app requirements

## Test Data Sets

### Small Test Set (Fast)
- **Bounds**: Single block (37.760-37.762, -122.420 to -122.418)
- **Expected**: ~20 blockfaces
- **Use**: Quick validation during development

### Mission District (Medium)
- **Bounds**: 37.744-37.780, -122.426 to -122.407
- **Expected**: ~1,469 blockfaces
- **Use**: Full feature testing
- **Current Output**: `sample_blockfaces_sideaware_full.json`

### Full SF (Large)
- **Bounds**: None (full dataset)
- **Expected**: ~18,355 blockfaces
- **Use**: Production deployment validation
- **Runtime**: ~15-20 minutes

## Running Tests

### Manual Test Execution

```bash
# Unit tests (implement with pytest)
pytest tests/test_spatial_matching.py
pytest tests/test_normalization.py

# Integration test - Mission District
python3 run_full_conversion.py

# Spot check validation
python3 generate_spot_check_samples.py

# Coverage analysis
python3 analyze_side_coverage.py
```

### Expected Outputs

**Successful conversion should show**:
```
Blockfaces processed:          1469
Blockfaces with regulations:   1220 (83.0%)
Total regulations added:       5129
Named streets:                 870 (59.2%)

Regulation breakdown:
  streetCleaning:     3342 (65.2%)
  residentialPermit:   631 (12.3%)
  timeLimit:           584 (11.4%)
  metered:             460 (9.0%)
```

## Test Checklist for Pipeline Changes

Before committing changes that affect data processing:

- [ ] Run full Mission District conversion
- [ ] Verify regulation counts within 5% of baseline
- [ ] Check named street percentage ≥59%
- [ ] Generate spot check samples and verify 3-5 manually
- [ ] Run coverage analysis
- [ ] Update iOS app resources
- [ ] Test app loads data without errors

## Known Limitations

1. **Directional sides (NORTH/SOUTH)**: Cannot reliably determine LEFT/RIGHT, matches to both sides
2. **Blockface data quality**: 40.8% still have "Unknown Street" (source data limitation)
3. **Curved streets**: Cross product approximation may have edge cases on very tight curves
4. **Buffer overlap**: Regulations near intersections may match multiple blockfaces

## Future Test Improvements

1. **Automated spot checking**: Use computer vision to read street signs from Street View
2. **Geometry validation**: Verify polygon construction doesn't create self-intersections
3. **Performance benchmarks**: Track conversion time as dataset grows
4. **Schema validation**: Automated JSON schema verification
5. **Visual regression**: Compare map rendering before/after changes

## Contact

For questions about testing or to report issues:
- Check existing issues in GitHub
- Review conversion logs in `conversion_*.log` files
- Compare with baseline outputs in `Data Sets/` folder
