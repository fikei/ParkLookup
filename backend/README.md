# SF Parking Data Pipeline

ETL pipeline for fetching official San Francisco parking data and transforming it for the ParkLookup iOS app.

## Data Sources

1. **DataSF Blockface** - Map of Parking Regulations
   - RPP flags and area codes
   - Time limits and operating hours
   - Street segment geometry
   - API: https://data.sfgov.org/resource/dpvh-nd9g

2. **DataSF Meters** - Parking Meters Dataset
   - Meter locations
   - Cap colors (indicating time limits)
   - API: https://data.sfgov.org/resource/8vzz-qzz9

3. **SFMTA ArcGIS** - RPP Area Polygons
   - Official zone boundary polygons
   - Area codes and names

## Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows
pip install -r requirements.txt
```

Optional: Copy `.env.example` to `.env` and add your DataSF API token for higher rate limits.

## Usage

### Run Pipeline Once

```bash
python pipeline.py
```

For faster testing (skip meter data):
```bash
python pipeline.py --skip-meters
```

### Run Scheduled Pipeline

```bash
python scheduler.py
```

Or run once and exit:
```bash
python scheduler.py --once
```

## Output

The pipeline generates files in `output/`:

- `parking_data_YYYYMMDD.json.gz` - Full data bundle for the app
- `parking_data_latest.json.gz` - Symlink to the latest version
- `zones_only_YYYYMMDD.json` - Zones-only file for quick loading

Raw fetched data is saved in `data/` for debugging.

## Architecture

```
backend/
├── fetchers/           # Data source fetchers
│   ├── blockface_fetcher.py
│   ├── meters_fetcher.py
│   └── rpp_areas_fetcher.py
├── transformers/       # Data transformation
│   └── parking_transformer.py
├── validators/         # Data validation
│   └── data_validator.py
├── pipeline.py         # Main ETL orchestrator
├── scheduler.py        # Scheduled runs
└── config.py           # Configuration
```

## Configuration

Edit `config.py` or set environment variables:

- `DATASF_APP_TOKEN` - DataSF API token (optional)
- `UPDATE_SCHEDULE` - "daily", "weekly", or "monthly"
- `UPDATE_DAY` - Day of week for weekly schedule
- `UPDATE_HOUR` - Hour (UTC) to run updates
