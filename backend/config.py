"""Configuration for SF Parking Data Pipeline"""
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Base paths
BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "output"
LOGS_DIR = BASE_DIR / "logs"

# Create directories if they don't exist
DATA_DIR.mkdir(exist_ok=True)
OUTPUT_DIR.mkdir(exist_ok=True)
LOGS_DIR.mkdir(exist_ok=True)

# DataSF API endpoints
DATASF_BASE_URL = "https://data.sfgov.org/resource"
BLOCKFACE_DATASET_ID = "hi6h-neyh"  # Parking regulations (except non-metered color curb)
METERS_DATASET_ID = "8vzz-qzz9"     # Parking Meters
RPP_PARCELS_DATASET_ID = "i886-hxz9"  # Residential Parking Permit Eligibility Parcels (polygons!)

# SFMTA ArcGIS endpoints - SF Gov Enterprise GIS
# Note: RPP boundaries may not be published as a separate layer
# The blockface data includes RPP area info per street segment
SFMTA_ARCGIS_BASE = "https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services"
RPP_AREAS_SERVICE = "RPP_Areas/FeatureServer/0"  # May need to be updated if service exists

# API settings
DATASF_APP_TOKEN = os.getenv("DATASF_APP_TOKEN", "")  # Optional but recommended
REQUEST_TIMEOUT = 60
MAX_RETRIES = 3
RETRY_DELAY = 5

# Data limits (DataSF paginates at 1000 by default)
DATASF_PAGE_SIZE = 50000  # Max allowed with SoQL
ARCGIS_PAGE_SIZE = 2000

# Output settings
OUTPUT_FORMAT = "json"  # json or geojson
COMPRESS_OUTPUT = True

# Schedule settings (cron-like)
UPDATE_SCHEDULE = "weekly"  # daily, weekly, monthly
UPDATE_DAY = "sunday"
UPDATE_HOUR = 3  # 3 AM
