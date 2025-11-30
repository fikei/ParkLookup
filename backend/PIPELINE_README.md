# Parking Data Pipelines

This document explains the two pipelines available for generating parking data for the ParkLookup iOS app.

## 📊 Pipeline Overview

| Pipeline | Output Format | Data Source | Status | Use Case |
|----------|--------------|-------------|--------|----------|
| **pipeline_blockface.py** | Blockface polylines with embedded regulations | Local GeoJSON files | ✅ **ACTIVE** | Production use - most accurate & detailed |
| **pipeline_zone_DEPRECATED.py** | Zone polygons | DataSF API | ⚠️ **DEPRECATED** | Legacy - less accurate |

---

## ✅ Active Pipeline: `pipeline_blockface.py`

**What it creates:** Augmented blockface polylines with embedded parking regulations

### Features

- **Street-level granularity** - Each street segment (blockface) has its own regulations
- **Multi-source data integration:**
  - Blockface geometry (18,355 street centerlines)
  - Parking regulations (7,784+ regulations)
  - Street sweeping schedules
  - Metered parking data
- **Multi-RPP support** - Blockfaces can belong to multiple permit zones (e.g., Zones Q and R)
- **Side-aware spatial matching** - Uses geometry to match regulations to correct side of street
- **Advanced spatial indexing** - STRtree for 100x+ faster processing

### Data Format

```json
{
  "blockfaces": [
    {
      "id": "{globalid}",
      "street": "Valencia Street",
      "fromStreet": "17th St",
      "toStreet": "16th St",
      "side": "WEST",
      "geometry": {
        "type": "LineString",
        "coordinates": [[-122.421, 37.774], ...]
      },
      "regulations": [
        {
          "type": "residentialPermit",
          "permitZone": "Q",           // DEPRECATED: First zone only
          "permitZones": ["Q", "R"],   // Multi-RPP: All zones
          "timeLimit": 120,
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
          "enforcementStart": "08:00",
          "enforcementEnd": "18:00",
          "specialConditions": "Exempt from time limits"
        },
        {
          "type": "metered",
          "permitZone": null,
          "permitZones": null,
          "timeLimit": 120,
          "meterRate": 2.0,
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
          "enforcementStart": "09:00",
          "enforcementEnd": "18:00",
          "specialConditions": "Pay at meter or via app"
        },
        {
          "type": "streetCleaning",
          "permitZone": null,
          "permitZones": null,
          "enforcementDays": ["wednesday"],
          "enforcementStart": "08:00",
          "enforcementEnd": "10:00",
          "specialConditions": "Street cleaning every week"
        }
      ]
    }
  ]
}
```

### Input Files Required

Place these GeoJSON files in the `Data Sets/` directory:

1. **Blockfaces_YYYYMMDD.geojson** - Street centerlines (from SF Open Data)
2. **Parking_regulations_YYYYMMDD.geojson** - Parking regulations
3. **Street_Sweeping_Schedule_YYYYMMDD.geojson** - Street cleaning (optional)
4. **Metered_Blockfaces_YYYYMMDD.geojson** - Metered parking (optional)

### Usage

**Basic (Mission District only):**
```bash
python pipeline_blockface.py \
    "Data Sets/Blockfaces_20251128.geojson" \
    "Data Sets/Parking_regulations_20251128.geojson" \
    "sample_blockfaces_with_regulations.json"
```

**Full SF with all data sources:**
```bash
python pipeline_blockface.py \
    "Data Sets/Blockfaces_20251128.geojson" \
    "Data Sets/Parking_regulations_20251128.geojson" \
    "sample_blockfaces_with_regulations.json" \
    "Data Sets/Street_Sweeping_Schedule_20251128.geojson" \
    "Data Sets/Metered_Blockfaces_20251128.geojson" \
    --no-bounds
```

**Flags:**
- `--no-bounds` - Process all of San Francisco (default: Mission District only)

### Output

- File: `sample_blockfaces_with_regulations.json`
- Copy to: `SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json`

### Multi-RPP Support

The pipeline now fully supports blockfaces that belong to multiple RPP zones:

**Python Output:**
```python
{
  "type": "residentialPermit",
  "permitZone": "Q",           # Backward compatibility
  "permitZones": ["Q", "R"],   # Multi-RPP support
  ...
}
```

**Swift Model:**
```swift
struct BlockfaceRegulation {
    let permitZone: String?      // DEPRECATED
    let permitZones: [String]?   // Multi-RPP

    var allPermitZones: [String] {
        if let zones = permitZones, !zones.isEmpty {
            return zones  // Multi-RPP
        } else if let zone = permitZone {
            return [zone]  // Backward compatibility
        }
        return []
    }
}
```

**Display:**
- Single zone: "Zone Q permit"
- Multi-RPP: "Zones Q, R permit"

---

## ⚠️ Deprecated Pipeline: `pipeline_zone_DEPRECATED.py`

**What it creates:** Zone polygon boundaries with separate regulations

### Why Deprecated?

1. **Less accurate** - Zone-level data, not street-level
2. **No side awareness** - Can't distinguish different sides of street
3. **Separate data files** - Zones and regulations stored separately
4. **Limited granularity** - One zone covers many blocks
5. **No multi-source integration** - Only RPP zones from DataSF

### Data Format

```json
{
  "zones": [
    {
      "id": "rpp_Q",
      "code": "Q",
      "name": "Castro",
      "polygon": [[[lon, lat], [lon, lat], ...]]
    }
  ]
}
```

### Migration Path

If you have existing zone-based data:

1. **Download GeoJSON datasets** from SF Open Data
2. **Run pipeline_blockface.py** to generate blockface data
3. **Replace** `sf_parking_zones.json` with `sample_blockfaces.json`
4. **Update app code** to use `BlockfaceLoader` instead of zone loader

---

## 🔧 Pipeline Maintenance

### Updating Data

To refresh parking data:

1. **Download latest GeoJSON files** from SF Open Data:
   - Blockfaces: https://data.sfgov.org/Transportation/Blockfaces/
   - Regulations: https://data.sfgov.org/Transportation/Parking-regulations/
   - Street Sweeping: https://data.sfgov.org/City-Infrastructure/Street-Sweeping-Schedule/

2. **Place in Data Sets/** directory with date suffix

3. **Run pipeline_blockface.py** with new file paths

4. **Copy output** to iOS Resources:
   ```bash
   cp sample_blockfaces_with_regulations.json \
      SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json
   ```

5. **Test in app** to verify data loads correctly

### Performance Optimization

The pipeline uses several optimizations:

- **STRtree spatial indexing** - Queries only nearby blockfaces (1-10 instead of 18,355)
- **Side-aware matching** - Skips blockfaces on wrong side of street
- **Deduplication** - Removes duplicate regulations within each blockface
- **Efficient buffering** - 15-meter tolerance for spatial joins

Typical processing time: **2-5 minutes** for full SF dataset

---

## 📱 iOS App Integration

The iOS app uses the `BlockfaceLoader` service to load blockface data:

```swift
// Load blockfaces from JSON
let blockfaces = try BlockfaceLoader.shared.loadBlockfaces()

// Access regulations
for regulation in blockface.regulations {
    // Multi-RPP support
    let zones = regulation.allPermitZones  // ["Q", "R"]

    // Display
    print(regulation.description)  // "Zones Q, R permit"
}
```

### ParkingDataAdapter Compatibility

The `ParkingDataAdapter` service handles blockface data automatically:

```swift
// Lookup regulations at location
let regulations = try await adapter.getRegulations(at: coordinate)

// Works with both zone and blockface data sources
```

---

## 🆘 Troubleshooting

### "No module named 'shapely'"

Install required dependencies:
```bash
pip install shapely
```

### "File not found: Data Sets/..."

Ensure GeoJSON files are in the correct directory with proper naming.

### "Skipped X regulations (unmatched)"

This is normal - some regulations may not spatially match to blockfaces due to data quality issues. Typical match rate: **85-95%**.

### "MemoryError"

For very large datasets, try:
- Process by region (remove `--no-bounds` flag)
- Reduce buffer distance in script
- Use a machine with more RAM

---

## 📄 Files in This Directory

| File | Purpose | Status |
|------|---------|--------|
| `pipeline_blockface.py` | **Active blockface pipeline** | ✅ Use this |
| `pipeline_zone_DEPRECATED.py` | Deprecated zone pipeline | ⚠️ Do not use |
| `convert_to_ios.py` | Zone-to-iOS converter | ⚠️ Deprecated |
| `update_ios_data.sh` | Automation script for zone pipeline | ⚠️ Deprecated |
| `PIPELINE_README.md` | This documentation | 📖 Read me |

---

## 🎯 Summary

**For new development:**
- ✅ Use `pipeline_blockface.py`
- ✅ Multi-RPP support included
- ✅ Most accurate and detailed data
- ✅ Integrated with iOS app via `BlockfaceLoader`

**Legacy zone pipeline:**
- ⚠️ `pipeline_zone_DEPRECATED.py` is deprecated
- ⚠️ Use only for backward compatibility
- ⚠️ Plan migration to blockface pipeline

---

## 📞 Support

For questions or issues:
1. Check this README
2. Review pipeline source code comments
3. Test with sample data first
4. Report issues with full error output
