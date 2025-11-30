# Deprecated Zone Pipeline (Archived)

⚠️ **These files are deprecated and should not be used for new development.**

## Files in This Archive

### `pipeline_zone_DEPRECATED.py`
- **Purpose:** Original ETL pipeline that generates zone polygon boundaries
- **Data Source:** DataSF RPP Areas API
- **Output:** `sf_parking_zones.json` with zone polygons
- **Status:** Deprecated in favor of blockface pipeline
- **Issues:**
  - Zone-level granularity (not street-level)
  - No side awareness
  - Separate regulations file
  - Less accurate than blockface data

### `convert_to_ios.py`
- **Purpose:** Converts zone pipeline output to iOS format
- **Input:** `parking_data_latest.json.gz` from zone pipeline
- **Output:** `sf_parking_zones.json`
- **Status:** Deprecated
- **Replacement:** Use `pipeline_blockface.py` which outputs iOS format directly

### `update_ios_data.sh`
- **Purpose:** Automation script for zone pipeline
- **Actions:**
  1. Runs `pipeline_zone_DEPRECATED.py`
  2. Converts to iOS format
  3. Simplifies polygons
- **Status:** Deprecated
- **Replacement:** Run `pipeline_blockface.py` directly

### `simplify_zones.py`
- **Purpose:** Reduces polygon vertex count for faster rendering
- **Used by:** Zone pipeline only
- **Status:** Deprecated (blockface uses LineStrings, not polygons)

## Why Deprecated?

The zone-based pipeline was replaced by the blockface pipeline because:

1. **Granularity:** Street-level vs zone-level
2. **Accuracy:** Side-aware spatial matching
3. **Data integration:** Multiple sources (regulations, sweeping, meters)
4. **Multi-RPP support:** Blockfaces can have multiple permit zones
5. **Performance:** Better spatial indexing

## Migration Guide

If you're using zone pipeline data:

1. Switch to `pipeline_blockface.py` (see `../PIPELINE_README.md`)
2. Download required GeoJSON files from SF Open Data
3. Run blockface pipeline to generate new data
4. Update app to use `BlockfaceLoader` instead of zone loader

## Historical Context

These files were the original implementation (November 2024) when the app first launched. They worked well for initial development but were replaced when we needed:
- Street cleaning integration
- Metered parking support
- Multi-RPP zones
- Higher accuracy for side-of-street parking

## Kept for Reference

These files are preserved for:
- Historical reference
- Understanding legacy data format
- Potential backwards compatibility needs
- Learning from previous approach

---

**Do not use these files for new development.**
**Use `../pipeline_blockface.py` instead.**
