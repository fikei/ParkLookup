# Project Reorganization Plan

## Current Issues

1. **Scattered scripts**: 15+ Python scripts in root directory
2. **Duplicate documentation**: docs/ and "untitled folder" have same files
3. **Intermediate data files**: Multiple JSON outputs in root
4. **No clear pipeline structure**: Hard to understand data flow
5. **Mixed concerns**: Analysis scripts mixed with conversion scripts

## Files to Deprecate

### 🗑️ Deprecated Scripts (Old/Superseded)

**Keep**: `convert_geojson_with_regulations.py` (CURRENT - side-aware + backfilling)

**Deprecate** (move to `archive/deprecated/`):
- `convert_geojson_to_app_format.py` - Old basic converter (no regulations)
- `convert_sf_data_to_blockfaces.py` - Superseded by regulations version
- `convert_with_regulations.py` - Older regulations version (no side-awareness)
- `add_blockface_files.py` - One-off migration script
- `fetch_real_blockfaces.py` - One-off data fetch
- `create_accurate_test_blockfaces.py` - Old test data generator

### 🗑️ Duplicate Documentation

**Delete**: `untitled folder/` (contains duplicates of docs/)
- Backend.md
- EngineeringProjectPlan.md
- ImplementationChecklist.md
- ProductBrief.md
- SuggestedAdditionalDocs.md
- TechnicalArchitecture.md
- TestPlan.md

### 🗑️ Intermediate Data Files

**Keep**:
- `sample_blockfaces_sideaware_full.json` (CURRENT production output)
- `spot_check_samples.json` (validation data)

**Deprecate** (move to `data/archive/`):
- `sample_blockfaces_from_geojson.json` - Old format
- `sample_blockfaces_with_all_regulations.json` - Intermediate version
- `sample_blockfaces_with_regulations.json` - Non-side-aware version

### 🗑️ Other Deprecated Files

**Deprecate** (move to `archive/`):
- `SFParkingZoneFinder_2025-11-25_10-50-10.347.xcdistributionlogs copy/` - Old build logs
- `Testing/` - Move contents to proper test structure

## Proposed New Structure

```
ParkLookup/
├── README.md                          # Main project README
│
├── data/                              # All data files
│   ├── raw/                          # Source GeoJSON files (immutable)
│   │   ├── Blockfaces_20251128.geojson
│   │   ├── Parking_regulations_20251128.geojson
│   │   ├── Street_Sweeping_Schedule_20251128.geojson
│   │   └── Blockfaces_with_Meters_20251128.geojson
│   │
│   ├── processed/                    # Pipeline outputs
│   │   ├── mission_district/        # Regional outputs
│   │   │   └── sample_blockfaces_sideaware_full.json
│   │   └── full_sf/                 # Full city outputs (future)
│   │
│   ├── validation/                   # Test and validation data
│   │   └── spot_check_samples.json
│   │
│   └── archive/                      # Deprecated data files
│       └── (old JSON files)
│
├── data_pipeline/                     # Data processing pipeline
│   ├── __init__.py
│   ├── config.py                     # Configuration settings
│   ├── pipeline.py                   # Main pipeline orchestration
│   │
│   ├── converters/                   # Conversion modules
│   │   ├── __init__.py
│   │   ├── blockface_converter.py   # Main conversion logic
│   │   ├── regulation_matcher.py    # Spatial matching
│   │   ├── street_normalizer.py     # Street name normalization
│   │   └── geometry_utils.py        # Geometric calculations
│   │
│   ├── validators/                   # Validation and QA
│   │   ├── __init__.py
│   │   ├── spot_checker.py          # generate_spot_check_samples.py
│   │   ├── coverage_analyzer.py     # analyze_side_coverage.py
│   │   └── schema_validator.py      # JSON schema validation
│   │
│   ├── tests/                        # Unit and integration tests
│   │   ├── __init__.py
│   │   ├── test_spatial_matching.py
│   │   ├── test_normalization.py
│   │   ├── test_regulation_extraction.py
│   │   └── test_full_pipeline.py
│   │
│   └── utils/                        # Utility functions
│       ├── __init__.py
│       ├── geojson_loader.py
│       └── bounds_filter.py
│
├── scripts/                           # Standalone utility scripts
│   ├── run_pipeline.py               # Main entry point (was run_full_conversion.py)
│   ├── analyze_blockface_coords.py   # Analysis tools
│   └── update_app_resources.sh       # Deployment helper
│
├── docs/                              # Documentation
│   ├── README.md                     # Documentation index
│   ├── DataPipelineTesting.md        # NEW - Testing guide
│   ├── ProjectReorganizationPlan.md  # NEW - This document
│   │
│   ├── architecture/                 # Technical architecture
│   │   ├── TechnicalArchitecture.md
│   │   ├── RegulationPrioritySystem.md
│   │   └── SpatialJoinResults.md
│   │
│   ├── features/                     # Feature documentation
│   │   ├── BlockfaceMigrationPlan.md
│   │   ├── StreetCleaningFeature.md
│   │   └── RegulationTypesMapping.md
│   │
│   ├── guides/                       # Development guides
│   │   ├── DEVELOPER_OVERLAY_TOOLS.md
│   │   └── blockface_offset_strategy.md
│   │
│   └── planning/                     # Project planning
│       ├── ProductBrief.md
│       ├── EngineeringProjectPlan.md
│       └── ImplementationChecklist.md
│
├── SFParkingZoneFinder/              # iOS application (keep as-is)
│   └── ...
│
├── archive/                           # Deprecated code
│   ├── deprecated_scripts/
│   │   ├── convert_geojson_to_app_format.py
│   │   ├── convert_sf_data_to_blockfaces.py
│   │   └── ... (other deprecated scripts)
│   │
│   └── old_documentation/
│       └── ... (if needed)
│
├── backend/                           # Backend service (keep separate)
│   └── ... (existing backend code)
│
├── .gitignore                        # Git ignore rules
├── requirements.txt                   # Python dependencies (NEW)
└── pytest.ini                        # Pytest configuration (NEW)
```

## Migration Steps

### Phase 1: Create New Structure (No Breaking Changes)

```bash
# 1. Create new directories
mkdir -p data/{raw,processed/mission_district,processed/full_sf,validation,archive}
mkdir -p data_pipeline/{converters,validators,tests,utils}
mkdir -p scripts
mkdir -p archive/{deprecated_scripts,old_documentation}
mkdir -p docs/{architecture,features,guides,planning}

# 2. Move source data
mv "Data Sets"/*.geojson data/raw/

# 3. Move current outputs
mv sample_blockfaces_sideaware_full.json data/processed/mission_district/
mv spot_check_samples.json data/validation/

# 4. Archive old outputs
mv sample_blockfaces_from_geojson.json data/archive/
mv sample_blockfaces_with_all_regulations.json data/archive/
mv sample_blockfaces_with_regulations.json data/archive/
```

### Phase 2: Refactor Code into Modules

```bash
# 5. Move and refactor main converter
# Split convert_geojson_with_regulations.py into modules:
# - data_pipeline/converters/blockface_converter.py (main logic)
# - data_pipeline/converters/regulation_matcher.py (spatial matching)
# - data_pipeline/converters/street_normalizer.py (normalize_street_name)
# - data_pipeline/converters/geometry_utils.py (determine_side_of_line)

# 6. Move validation scripts
mv generate_spot_check_samples.py data_pipeline/validators/spot_checker.py
mv analyze_side_coverage.py data_pipeline/validators/coverage_analyzer.py

# 7. Move analysis scripts
mv analyze_blockface_coordinates.py scripts/analyze_blockface_coords.py

# 8. Create new pipeline entry point
mv run_full_conversion.py scripts/run_pipeline.py
```

### Phase 3: Deprecate Old Scripts

```bash
# 9. Move deprecated scripts
mv convert_geojson_to_app_format.py archive/deprecated_scripts/
mv convert_sf_data_to_blockfaces.py archive/deprecated_scripts/
mv convert_with_regulations.py archive/deprecated_scripts/
mv add_blockface_files.py archive/deprecated_scripts/
mv fetch_real_blockfaces.py archive/deprecated_scripts/
mv create_accurate_test_blockfaces.py archive/deprecated_scripts/

# 10. Remove duplicate documentation
rm -rf "untitled folder"

# 11. Remove old build logs
rm -rf "SFParkingZoneFinder_2025-11-25_10-50-10.347.xcdistributionlogs copy"
```

### Phase 4: Organize Documentation

```bash
# 12. Organize docs
mv docs/TechnicalArchitecture.md docs/architecture/
mv docs/RegulationPrioritySystem.md docs/architecture/
mv docs/SpatialJoinResults.md docs/architecture/

mv docs/BlockfaceMigrationPlan.md docs/features/
mv docs/StreetCleaningFeature.md docs/features/
mv docs/RegulationTypesMapping.md docs/features/

mv DEVELOPER_OVERLAY_TOOLS.md docs/guides/
mv blockface_offset_strategy.md docs/guides/

mv docs/ProductBrief.md docs/planning/
mv docs/EngineeringProjectPlan.md docs/planning/
mv docs/ImplementationChecklist.md docs/planning/
```

### Phase 5: Add Pipeline Infrastructure

```bash
# 13. Create Python package structure
touch data_pipeline/__init__.py
touch data_pipeline/converters/__init__.py
touch data_pipeline/validators/__init__.py
touch data_pipeline/tests/__init__.py
touch data_pipeline/utils/__init__.py

# 14. Create requirements.txt
cat > requirements.txt << 'EOF'
shapely==2.0.2
pytest==7.4.3
pytest-cov==4.1.0
EOF

# 15. Create pytest.ini
cat > pytest.ini << 'EOF'
[pytest]
testpaths = data_pipeline/tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
EOF

# 16. Update .gitignore (already done)
```

## Benefits of New Structure

### ✅ Clarity
- **Clear separation**: Data vs Code vs Docs
- **Modular code**: Easy to find and modify specific functionality
- **Test isolation**: Tests live with the code they test

### ✅ Maintainability
- **Single source of truth**: One current converter, old ones archived
- **Version control**: Clear history of what changed
- **Documentation organization**: Easy to navigate by topic

### ✅ Scalability
- **Easy to add regions**: New folders in `data/processed/`
- **Pluggable validators**: Add new validation in `validators/`
- **Testing framework**: pytest structure supports growth

### ✅ Collaboration
- **Onboarding**: New developers can understand structure quickly
- **Code review**: Smaller modules easier to review
- **Reusability**: Modules can be imported and reused

## Pipeline Configuration

### New config.py Structure

```python
"""Pipeline configuration settings"""
from pathlib import Path

# Paths
PROJECT_ROOT = Path(__file__).parent.parent
DATA_ROOT = PROJECT_ROOT / "data"
RAW_DATA = DATA_ROOT / "raw"
PROCESSED_DATA = DATA_ROOT / "processed"

# Source data files
BLOCKFACES_FILE = RAW_DATA / "Blockfaces_20251128.geojson"
REGULATIONS_FILE = RAW_DATA / "Parking_regulations_20251128.geojson"
SWEEPING_FILE = RAW_DATA / "Street_Sweeping_Schedule_20251128.geojson"
METERED_FILE = RAW_DATA / "Blockfaces_with_Meters_20251128.geojson"

# Region bounds
MISSION_DISTRICT_BOUNDS = {
    "min_lat": 37.744,
    "max_lat": 37.780,
    "min_lon": -122.426,
    "max_lon": -122.407
}

# Processing parameters
BUFFER_DISTANCE = 0.000135  # ~15 meters
LANE_WIDTH_DEGREES = 0.000054  # 6 meters
```

## Rollout Plan

**Week 1**: Phase 1-2 (structure + refactor)
- Create directories
- Move data files
- Refactor main converter into modules

**Week 2**: Phase 3-4 (deprecate + organize)
- Archive old scripts
- Organize documentation
- Update references

**Week 3**: Phase 5 (infrastructure)
- Create Python package
- Write initial tests
- Update README

**Week 4**: Testing & Documentation
- Run full test suite
- Update all documentation
- Deploy to production

## Success Criteria

- [ ] All data files organized in `data/` structure
- [ ] Main converter refactored into testable modules
- [ ] At least 3 unit tests passing
- [ ] Documentation organized by category
- [ ] Old scripts archived (not deleted)
- [ ] Pipeline runs from `scripts/run_pipeline.py`
- [ ] iOS app resources updated automatically
- [ ] README updated with new structure

## Rollback Plan

If issues occur:
1. Archive branch is available with old structure
2. Original scripts preserved in `archive/deprecated_scripts/`
3. Git history maintains all changes
4. Can revert individual migrations independently
