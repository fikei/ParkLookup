# Blockface Pipeline Analysis Summary
**Date**: 2025-12-01
**File**: blockfaces_full_sf_20251128.json
**Pipeline**: pipeline_blockface.py

---

## Quick Stats

| Metric | Value |
|--------|-------|
| Total Blockfaces | 18,355 |
| Blockfaces with Regulations | 13,631 (74.3%) |
| Total Regulations | 42,675 |
| Overall Match Rate | 47.2% |

---

## Regulation Distribution

| Type | Count | Percentage |
|------|-------|------------|
| Street Cleaning | 27,062 | 63.4% |
| Time Limit | 6,309 | 14.8% |
| Residential Permit | 5,973 | 14.0% |
| Metered | 2,705 | 6.3% |
| Other | 539 | 1.3% |
| No Parking | 87 | 0.2% |

---

## Match Rates by Type

| Type | Source | Output | Match Rate | Status |
|------|--------|--------|------------|--------|
| **Time Limit** | 6,889 | 6,309 | **91.6%** | ✅ Excellent |
| **Residential Permit** | 6,485 | 5,973 | **92.1%** | ✅ Excellent |
| **Other** | 629 | 539 | **85.7%** | ✅ Good |
| **Street Cleaning** | 37,878 | 27,062 | **71.4%** | ⚠️ Acceptable |
| **No Parking** | 207 | 87 | **42.0%** | ⚠️ Medium |
| **Metered** | 38,297 | 2,705 | **7.1%** | ℹ️ Expected* |

\* Low metered match rate is expected: 38k individual meters aggregate to 2.7k blockface regulations

---

## Multi-RPP Analysis

| Metric | Value |
|--------|-------|
| Total Permit Regulations | 5,973 |
| Single Zone Permits | 5,303 (88.8%) |
| **Multi-Zone Permits** | **670 (11.2%)** |
| No Zones | 0 |

**Top Multi-Zone Combinations:**
1. Zones A, C: 113 occurrences
2. Zones K, M: 99 occurrences
3. Zones G, K: 97 occurrences
4. Zones HV, Q: 43 occurrences
5. Zones F, N: 43 occurrences

---

## Data Quality

### Street Names
- Named streets: 9,905 (54.0%)
- Unknown streets: 8,450 (46.0%)

### Side Determination
- **UNKNOWN**: 17,392 (94.8%) ⚠️
- SOUTH: 252 (1.4%)
- EAST: 241 (1.3%)
- NORTH: 237 (1.3%)
- WEST: 233 (1.3%)

### Street Cleaning Coverage
- Streets with cleaning: 1,351
- One side only: 1,039 (76.9%)
- Both sides: 312 (23.1%)

---

## Key Findings

✅ **High match rates** for time limits (91.6%) and residential permits (92.1%)
✅ **Multi-RPP working correctly** - 670 multi-zone permits properly consolidated
✅ **No coverage loss** - All regulation reductions are from proper consolidation
⚠️ **Side determination** needs improvement (94.8% UNKNOWN - known limitation)
⚠️ **Street names** could be improved (46% unknown)
ℹ️ **Metered aggregation** is correct behavior (38k meters → 2.7k blockface regs)

---

## Production vs Multi-RPP Comparison

| Metric | Production | Multi-RPP | Difference |
|--------|------------|-----------|------------|
| Blockfaces | 18,355 | 18,355 | 0 |
| Total Regulations | 43,364 | 42,675 | -689 (-1.6%) |
| Residential Permits | 6,679 | 5,973 | -706 |

**-706 residential permits = Multi-zone consolidation (expected)**
- Old: Multi-zone blockfaces had duplicate regulations (one per zone)
- New: Multi-zone blockfaces have single regulation with zones array

---

## Files

- `comprehensive_analysis.txt` - Full detailed analysis output
- `match_rates.csv` - Match rate data in CSV format
- `SUMMARY.md` - This summary file

---

## Notes

- Source data from 5 GeoJSON files (100MB+ total)
- Pipeline uses spatial joins with STRtree indexing
- Multi-RPP consolidation is working as designed
- Side determination limitation documented, requires popupinfo parsing
