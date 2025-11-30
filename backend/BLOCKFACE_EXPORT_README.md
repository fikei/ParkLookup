# Blockface Data Export & Multi-RPP Support

This document describes how to export fresh blockface data from DataSF with multi-RPP (multi-zone) support and how to roll back if needed.

## Current Status

**✅ Multi-RPP Ready**: All 43,364 regulations in `sample_blockfaces.json` have the `permitZones` field.

**📊 Current Data**:
- Total blockfaces: 18,355
- Total regulations: 43,364
- Regulations with `permitZones` field: 43,364 (100%)
- Multi-RPP regulations (2+ zones): 0 (will be populated on next full export)

**💾 Backup Created**: `sample_blockfaces.backup.json` (34MB)

## Data Format

### Multi-RPP Structure

Each regulation supports both single-zone and multi-zone permit areas:

```json
{
  "type": "residentialPermit",
  "permitZone": "Q",              // DEPRECATED: First zone only (backward compatibility)
  "permitZones": ["Q", "R"],      // NEW: All applicable zones
  "timeLimit": 120,
  "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
  "enforcementStart": "08:00",
  "enforcementEnd": "18:00"
}
```

### Backward Compatibility

- `permitZone` (string): Maintained for backward compatibility, contains first zone
- `permitZones` (array): New field, contains all zones for multi-RPP blockfaces
- iOS code uses `allPermitZones` computed property to handle both formats

## Exporting Fresh Data

### 1. Full Export from DataSF (Recommended)

Fetches ALL blockface data from DataSF with multi-RPP extraction:

```bash
cd backend
python export_blockfaces.py
```

This will:
- Fetch RPP-only blockfaces from DataSF (hi6h-neyh dataset)
- Extract zones from `rpparea1`, `rpparea2`, `rpparea3` fields
- Create multi-RPP blockfaces with `permitZones: ["Q", "R"]`
- Output to `../SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json`

**Options**:
```bash
# Export with limit (for testing)
python export_blockfaces.py --limit 100

# Export to custom location
python export_blockfaces.py --output /path/to/output.json
```

### 2. Update Existing File (Quick)

Updates existing file to add `permitZones` field:

```bash
python add_permit_zones_field.py
```

**Note**: This only adds the field structure, it won't fetch new multi-RPP data from DataSF.

## Expected Multi-RPP Data

When running the full export, you should see multi-RPP blockfaces in overlapping zones:

**Common Multi-RPP Zones in SF**:
- Q/R overlap (Castro/Haight area)
- I/S overlap (Sunset area)
- Other zone boundaries where blockfaces belong to multiple permit areas

**Example Log Output**:
```
Fetched 18,355 blockface records
Converted 18,355 blockfaces
Found 247 multi-RPP blockfaces
```

## Rolling Back

If the new data causes issues, you can easily roll back:

### Option 1: Automatic Rollback Script

```bash
cd backend
./rollback_blockfaces.sh
```

This will:
1. Confirm the rollback action
2. Save current file to `.temp.json`
3. Restore from `.backup.json`

### Option 2: Manual Rollback

```bash
cd SFParkingZoneFinder/SFParkingZoneFinder/Resources
cp sample_blockfaces.backup.json sample_blockfaces.json
```

### Option 3: Git Rollback

```bash
git checkout HEAD -- SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json
```

## Validation

After exporting, validate the data:

```bash
python -c "
import json
with open('../SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json') as f:
    data = json.load(f)
    multi_rpp = sum(1 for bf in data['blockfaces']
                    for reg in bf['regulations']
                    if reg.get('permitZones') and len(reg['permitZones']) > 1)
    print(f'Total blockfaces: {len(data[\"blockfaces\"])}')
    print(f'Multi-RPP regulations: {multi_rpp}')
"
```

## iOS Runtime Compatibility

The iOS app automatically handles both formats:

```swift
// BlockfaceRegulation.swift
var allPermitZones: [String] {
    if let zones = permitZones, !zones.isEmpty {
        return zones  // Multi-RPP: use array
    } else if let zone = permitZone {
        return [zone]  // Backward compatibility: convert to array
    }
    return []
}
```

## Troubleshooting

### Network Issues

If `export_blockfaces.py` fails with network errors:

```
ClientConnectorDNSError: Cannot connect to host data.sfgov.org:443
```

**Solutions**:
1. Check internet connection
2. Try again later (DataSF may be down)
3. Use existing data with `add_permit_zones_field.py`

### File Size Issues

If the exported file is too large:

```bash
# Check file size
ls -lh sample_blockfaces.json

# Expected size: ~30-35 MB
```

If > 50MB, there may be duplicate data.

## Next Steps

After successful export:

1. ✅ Validate multi-RPP data (check for 2+ zones)
2. ✅ Test in iOS app with multi-zone locations
3. ✅ Verify permit validation works correctly
4. ✅ Check UI displays "Zones Q, R" format
5. ✅ Commit changes to git

## Files

- `export_blockfaces.py` - Full export script (DataSF → iOS)
- `add_permit_zones_field.py` - Quick update for existing data
- `rollback_blockfaces.sh` - Rollback script
- `sample_blockfaces.json` - Current data (iOS Resources)
- `sample_blockfaces.backup.json` - Backup for rollback
