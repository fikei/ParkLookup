# Expanding Beyond the Mission District Test Area

## Current Status

**Test Area (Mission District)**
- Coverage: 37.744° to 37.780° lat, -122.426° to -122.407° lon
- Blockfaces: 1,469
- File size: 2.8MB
- Processing time: ~2 minutes
- Status: ✅ Deployed to app

**Full San Francisco**
- Coverage: Entire city
- Blockfaces: 18,355 (12.5x larger)
- Estimated file size: ~35MB
- Estimated processing time: ~15-20 minutes
- Status: ⏸️ Not yet generated

## Why Start with Test Area?

The Mission District test area allows for:
1. **Faster iteration** - 2 min vs 15+ min processing
2. **Easier debugging** - Smaller dataset to validate
3. **Spot checking** - Can manually verify regulations on Google Street View
4. **Performance testing** - Reasonable app bundle size for initial testing

## Expanding to Full SF

### Step 1: Generate Full Dataset

```bash
# Generate full SF blockfaces with all regulations
python3 scripts/run_full_sf_conversion.py
```

This will:
- Process all 18,355 SF blockfaces
- Apply side-aware spatial matching
- Include street sweeping, metered, RPP, time limits, etc.
- Output to: `data/processed/full_sf/blockfaces_full_sf.json`
- Runtime: ~15-20 minutes

### Step 2: Deploy to App

```bash
# Deploy full SF data to app resources
./scripts/deploy_to_app.sh full
```

Or manually:
```bash
cp data/processed/full_sf/blockfaces_full_sf.json \
   SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json
```

### Step 3: Test App Performance

After deploying full data, test:

1. **App Launch Time**
   - Current: ~1-2 seconds with 1,469 blockfaces
   - Expected: ~3-5 seconds with 18,355 blockfaces
   - JSON parsing is fast, should not be a bottleneck

2. **Memory Usage**
   - Current: ~20MB for 1,469 blockfaces in memory
   - Expected: ~250MB for 18,355 blockfaces
   - iOS devices should handle this easily

3. **Map Rendering**
   - Test zooming, panning with full dataset
   - Verify polygon rendering performance
   - Check that regulations display correctly across SF

4. **Bundle Size**
   - Current: +2.8MB in app bundle
   - Expected: +35MB in app bundle
   - Still acceptable for App Store distribution

## Considerations

### Performance Optimizations (if needed)

If full SF data causes performance issues:

**Option 1: Regional Lazy Loading**
```
data/processed/
├── northeast/
├── northwest/
├── southeast/
└── southwest/
```
Load only visible region based on map bounds.

**Option 2: Simplified Geometry**
```python
# Reduce coordinate precision
coords = [(round(lat, 5), round(lon, 5)) for lat, lon in coords]
```
Can reduce file size by ~30-40%.

**Option 3: Binary Format**
Convert JSON to MessagePack or Protocol Buffers for smaller size and faster parsing.

**Option 4: Backend API**
Move data to backend, fetch on-demand. Better for frequent updates.

### App Store Guidelines

- 35MB is well within limits (max ~4GB)
- Consider on-demand resources if size becomes an issue
- Asset catalog compression can help

### Update Frequency

**When to regenerate data:**
- SF updates parking regulations (check DataSF monthly)
- New street sweeping schedules (seasonal changes)
- Major infrastructure changes (new streets, zones)

**Automation:**
```bash
# Add to cron or GitHub Actions
0 0 1 * * /path/to/run_full_sf_conversion.py
```

## Testing Full SF Data

### Validation Checklist

Before deploying to production:

- [ ] Run full conversion successfully
- [ ] Verify blockface count: ~18,355
- [ ] Spot check 5-10 locations across different neighborhoods
- [ ] Test app launch time on target devices
- [ ] Verify map rendering across all SF neighborhoods
- [ ] Check memory usage doesn't exceed limits
- [ ] Test regulations display correctly
- [ ] Validate street sweeping schedules
- [ ] Confirm RPP zones match actual zones

### Spot Check Locations

Generate samples across full SF:
```bash
# Modify generate_spot_check_samples.py to use full data
python3 scripts/generate_spot_check_samples.py
```

Check diverse neighborhoods:
- Financial District (downtown)
- Richmond (west side)
- Bayview (southeast)
- Marina (north)
- Sunset (west)

## Rollback Plan

If full SF data causes issues:

```bash
# Revert to Mission District test data
./scripts/deploy_to_app.sh mission
```

This immediately restores the working 1,469 blockface dataset.

## Regional Expansion (Alternative Approach)

Instead of jumping straight to full SF, expand incrementally:

1. **Mission District** (current) - 1,469 blockfaces ✅
2. **Mission + SOMA** - ~3,000 blockfaces
3. **Central SF** - ~8,000 blockfaces
4. **Full SF** - 18,355 blockfaces

Create bounds for each region in `convert_geojson_with_regulations.py`:

```python
REGION_BOUNDS = {
    "mission": {"min_lat": 37.744, "max_lat": 37.780, ...},
    "soma": {"min_lat": 37.770, "max_lat": 37.795, ...},
    "central": {"min_lat": 37.755, "max_lat": 37.805, ...},
}
```

## Next Steps

**Recommended path forward:**

1. ✅ Validate Mission District data accuracy (spot checks)
2. ⏭️ Generate full SF data when ready for production
3. ⏭️ Test full SF data on multiple devices
4. ⏭️ Monitor performance metrics
5. ⏭️ Deploy to TestFlight for beta testing
6. ⏭️ Launch with full SF coverage

**Current best practice:**
- Keep Mission District for rapid development/testing
- Generate full SF for production releases
- Use deployment script to switch between them
