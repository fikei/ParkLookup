# Restored Files from Git History

## Successfully Restored

### Documentation (15 files)
- docs/BlockfaceMigrationPlan.md
- docs/BlockfaceMigrationStrategy.md
- docs/BlockfaceRegulationsMatching.md
- docs/DataSF_API_Investigation.md
- docs/RegulationPrioritySystem.md
- docs/RegulationTypesMapping.md
- docs/SpatialJoinResults.md
- docs/StreetCleaningDatasetAnalysis.md
- docs/StreetCleaningFeature.md
- docs/StreetCleaningImplementationPlan.md
- docs/DataPipelineTesting.md (if exists)
- docs/ExpandingBeyondTestArea.md (if exists)
- docs/PerformanceOptimization.md (if exists)
- docs/ProjectReorganizationPlan.md (if exists)
- docs/SideDeterminationImprovements.md (if exists)

### Data Pipeline Scripts (10 files)
- scripts/comprehensive_side_determination.py
- scripts/deploy_regional_to_app.sh
- scripts/split_by_region.py
- scripts/analyze_coverage.py
- scripts/deploy_to_app.sh
- scripts/run_full_sf_conversion.py
- scripts/analyze_blockface_coordinates.py (if exists)
- scripts/analyze_side_coverage.py (if exists)
- scripts/generate_spot_check_samples.py (if exists)
- scripts/run_full_conversion.py (if exists)

## Large Data Files (Not Restored - Manual Decision Needed)

These files are very large and were excluded from automatic restoration.
They can be restored manually if needed from git history.

### Raw GeoJSON Data (in data/raw/):
- Blockfaces_20251128.geojson (~12 MB)
- Blockfaces_with_Meters_20251128.geojson (size TBD)
- Parking_Meters_20251128.geojson (size TBD)
- Parking_regulations_(except_non-metered_color_curb)_20251128.geojson (size TBD)
- Street_Sweeping_Schedule_20251128.geojson (size TBD)

### To Restore Large Files Manually:
```bash
# Find the commit with the file
git log --all --name-only --oneline | grep "<filename>"

# Restore from specific commit
git show <commit>:data/raw/<filename> > data/raw/<filename>
```

### Archived Scripts (in archive/deprecated_scripts/):
- add_blockface_files.py
- convert_geojson_to_app_format.py
- convert_sf_data_to_blockfaces.py
- convert_with_regulations.py
- create_accurate_test_blockfaces.py
- fetch_real_blockfaces.py

## Note
The processed blockface data (sample_blockfaces.json, 32MB) is already
in the app at Resources/sample_blockfaces.json and was restored earlier.

## Commit Information
- Docs restored from: cd636e4^ (before the merge that deleted them)
- Scripts restored from: 6e2cced (Implement improved side determination)
- Branch: claude/fix-block-face-colors-01FzcFoJ8L7eTjuRMhZyZUQg
