#!/usr/bin/env python3
"""
Export blockface data with parking regulations to iOS format.

This script fetches blockface data from DataSF and converts it to the format
expected by the iOS BlockfaceLoader, including multi-RPP support.

Usage:
    python export_blockfaces.py [--limit N] [--output PATH]

Options:
    --limit N       Limit to N blockfaces (for testing, default: all)
    --output PATH   Output file path (default: ../SFParkingZoneFinder/.../sample_blockfaces.json)
"""
import asyncio
import json
import sys
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional
from datetime import datetime

from fetchers import BlockfaceFetcher
from config import OUTPUT_DIR

# iOS Resources path
IOS_RESOURCES_DIR = Path(__file__).parent.parent / "SFParkingZoneFinder" / "SFParkingZoneFinder" / "Resources"

# Local data path
DATA_RAW_DIR = Path(__file__).parent.parent / "data" / "raw"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def extract_permit_zones(record: Dict[str, Any]) -> List[str]:
    """
    Extract all RPP permit zones from a blockface record.

    Returns list of zones (e.g., ["Q", "R"]) if multi-permit, or ["Q"] if single.
    """
    zones = []
    for field in ["rpparea1", "rpparea2", "rpparea3", "RPPAREA1", "RPPAREA2", "RPPAREA3"]:
        zone = record.get(field)
        if zone:
            zone_code = str(zone).upper().strip()
            if zone_code and zone_code not in zones:
                zones.append(zone_code)

    return sorted(zones)


def parse_regulation_type(record: Dict[str, Any]) -> str:
    """Determine regulation type from blockface record"""
    # Check for street cleaning
    if record.get("regulation") and "street cleaning" in str(record.get("regulation", "")).lower():
        return "streetCleaning"

    # Check for RPP
    if extract_permit_zones(record):
        return "residentialPermit"

    # Check for metered
    if record.get("metered") or "metered" in str(record.get("regulation", "")).lower():
        return "metered"

    # Check for time limit
    if record.get("hrlimit") or record.get("time_limit"):
        return "timeLimit"

    # Default
    return "unknown"


def parse_enforcement_days(days_str: Optional[str]) -> Optional[List[str]]:
    """Parse enforcement days from string like 'M-F' or 'Mon, Wed, Fri'"""
    if not days_str:
        return None

    days_str = str(days_str).lower()

    # Map abbreviations to full day names
    day_map = {
        "m": "monday",
        "t": "tuesday",
        "w": "wednesday",
        "th": "thursday",
        "f": "friday",
        "sa": "saturday",
        "su": "sunday",
        "mon": "monday",
        "tue": "tuesday",
        "wed": "wednesday",
        "thu": "thursday",
        "fri": "friday",
        "sat": "saturday",
        "sun": "sunday",
    }

    # Handle ranges like "M-F"
    if "-" in days_str:
        # Common patterns
        if "m-f" in days_str or "mon-fri" in days_str:
            return ["monday", "tuesday", "wednesday", "thursday", "friday"]
        elif "m-sa" in days_str or "mon-sat" in days_str:
            return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    # Handle comma-separated
    if "," in days_str:
        days = []
        for part in days_str.split(","):
            part = part.strip()
            if part in day_map:
                days.append(day_map[part])
        return days if days else None

    # Single day
    if days_str in day_map:
        return [day_map[days_str]]

    return None


def extract_regulations(record: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Extract all regulations from a blockface record.

    A blockface can have multiple regulations (e.g., RPP + metered, street cleaning + time limit).
    """
    regulations = []

    # Extract common fields
    permit_zones = extract_permit_zones(record)
    time_limit_hours = record.get("hrlimit") or record.get("time_limit")
    time_limit_minutes = None
    if time_limit_hours:
        try:
            time_limit_minutes = int(float(time_limit_hours) * 60)
        except (ValueError, TypeError):
            pass

    enforcement_days = parse_enforcement_days(record.get("days"))
    enforcement_start = record.get("hrs_begin") or record.get("HRS_BEGIN")
    enforcement_end = record.get("hrs_end") or record.get("HRS_END")

    # Add RPP regulation if zones exist
    if permit_zones:
        regulations.append({
            "type": "residentialPermit",
            "permitZone": permit_zones[0],  # Backward compatibility - first zone
            "permitZones": permit_zones,    # Multi-RPP support - all zones
            "timeLimit": time_limit_minutes,  # Time limit for non-permit holders
            "meterRate": None,
            "enforcementDays": enforcement_days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": None
        })

    # Add metered regulation if indicated
    if record.get("metered") or "metered" in str(record.get("regulation", "")).lower():
        regulations.append({
            "type": "metered",
            "permitZone": None,
            "permitZones": None,
            "timeLimit": time_limit_minutes,
            "meterRate": 2.0,  # Default rate
            "enforcementDays": enforcement_days,
            "enforcementStart": enforcement_start or "09:00",
            "enforcementEnd": enforcement_end or "18:00",
            "specialConditions": "Pay at meter or via app"
        })

    # Add street cleaning if indicated
    if "street cleaning" in str(record.get("regulation", "")).lower():
        regulations.append({
            "type": "streetCleaning",
            "permitZone": None,
            "permitZones": None,
            "timeLimit": None,
            "meterRate": None,
            "enforcementDays": enforcement_days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": None
        })

    # If no specific regulations identified but has time limit, add generic time limit
    if not regulations and time_limit_minutes:
        regulations.append({
            "type": "timeLimit",
            "permitZone": None,
            "permitZones": None,
            "timeLimit": time_limit_minutes,
            "meterRate": None,
            "enforcementDays": enforcement_days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": None
        })

    return regulations


def load_local_geojson(limit: Optional[int] = None) -> List[Dict[str, Any]]:
    """Load blockface data from local geojson file"""
    # Use Parking_regulations file - it has RPP data including rpparea1/2/3 for multi-RPP
    geojson_path = DATA_RAW_DIR / "Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"

    if not geojson_path.exists():
        logger.error(f"Local geojson file not found: {geojson_path}")
        logger.info("Please restore from git: git checkout 1e8bdc5 -- data/raw/*.geojson")
        raise FileNotFoundError(f"Data source not found: {geojson_path}")

    logger.info(f"Reading from: {geojson_path}")
    logger.info(f"File size: {geojson_path.stat().st_size / (1024*1024):.1f} MB")

    with open(geojson_path, 'r') as f:
        geojson_data = json.load(f)

    # Extract features from GeoJSON
    features = geojson_data.get('features', [])
    logger.info(f"Found {len(features)} features in geojson")

    # Convert GeoJSON features to dict format expected by converter
    records = []
    for feature in features[:limit] if limit else features:
        # Combine geometry and properties into single dict
        record = feature.get('properties', {})
        if 'geometry' in feature:
            record['shape'] = feature['geometry']
        records.append(record)

    return records


def convert_blockface_to_ios(record: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Convert a raw DataSF blockface record to iOS Blockface format"""
    try:
        # Extract basic fields
        cnn_id = record.get("cnn") or record.get("CNN") or record.get(":id")
        street = record.get("street") or record.get("STREET") or "Unknown"
        from_street = record.get("from_street") or record.get("FROM_STREET")
        to_street = record.get("to_street") or record.get("TO_STREET")
        side = record.get("side") or record.get("SIDE") or "UNKNOWN"

        # Extract geometry
        geometry = record.get("shape") or record.get("the_geom") or record.get("geometry")
        if not geometry:
            logger.warning(f"Skipping blockface without geometry: {cnn_id}")
            return None

        # Convert geometry to GeoJSON LineString format
        geom_type = geometry.get("type", "")
        coordinates = geometry.get("coordinates", [])

        if geom_type == "MultiLineString":
            # Flatten MultiLineString to LineString (take first line)
            if coordinates and len(coordinates) > 0:
                coordinates = coordinates[0]

        if not coordinates:
            logger.warning(f"Skipping blockface with empty coordinates: {cnn_id}")
            return None

        # Extract regulations
        regulations = extract_regulations(record)

        # Build iOS blockface object
        return {
            "id": str(cnn_id) if cnn_id else f"unknown_{hash(str(record))}",
            "street": street,
            "fromStreet": from_street,
            "toStreet": to_street,
            "side": side.upper(),
            "geometry": {
                "type": "LineString",
                "coordinates": coordinates
            },
            "regulations": regulations
        }

    except Exception as e:
        logger.error(f"Error converting blockface: {e}")
        return None


async def fetch_and_export(limit: Optional[int] = None, output_path: Optional[Path] = None, use_local: bool = True):
    """Fetch blockface data and export to iOS format"""
    logger.info("=" * 60)
    logger.info("Blockface Export to iOS")
    logger.info("=" * 60)

    # Determine output path
    if not output_path:
        output_path = IOS_RESOURCES_DIR / "sample_blockfaces.json"

    logger.info(f"Output path: {output_path}")

    # Fetch blockface data
    if use_local:
        logger.info("\n[Step 1/3] Loading blockface data from local geojson...")
        raw_blockfaces = load_local_geojson(limit=limit)
    else:
        if limit:
            logger.info(f"Limit: {limit} blockfaces")
        else:
            logger.info("Fetching ALL blockfaces (this may take several minutes)")
        logger.info("\n[Step 1/3] Fetching blockface data from DataSF...")
        async with BlockfaceFetcher() as fetcher:
            if limit:
                raw_blockfaces = await fetcher.fetch_sample(limit=limit)
            else:
                # Fetch only RPP blockfaces (faster and more relevant)
                raw_blockfaces = await fetcher.fetch_rpp_only()

    logger.info(f"Loaded {len(raw_blockfaces)} blockface records")

    # Convert to iOS format
    logger.info("\n[Step 2/3] Converting to iOS format...")
    ios_blockfaces = []
    multi_rpp_count = 0

    for record in raw_blockfaces:
        ios_blockface = convert_blockface_to_ios(record)
        if ios_blockface:
            ios_blockfaces.append(ios_blockface)

            # Count multi-RPP blockfaces
            for reg in ios_blockface["regulations"]:
                if reg.get("permitZones") and len(reg["permitZones"]) > 1:
                    multi_rpp_count += 1
                    break

    logger.info(f"Converted {len(ios_blockfaces)} blockfaces")
    logger.info(f"Found {multi_rpp_count} multi-RPP blockfaces")

    # Build output structure
    output_data = {
        "blockfaces": ios_blockfaces
    }

    # Write to file
    logger.info("\n[Step 3/3] Writing to file...")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)

    file_size_mb = output_path.stat().st_size / (1024 * 1024)
    logger.info(f"Written to: {output_path}")
    logger.info(f"File size: {file_size_mb:.1f} MB")

    # Summary
    logger.info("\n" + "=" * 60)
    logger.info("Export Summary:")
    logger.info(f"  Total blockfaces: {len(ios_blockfaces)}")
    logger.info(f"  Multi-RPP blockfaces: {multi_rpp_count}")
    logger.info(f"  Output: {output_path}")
    logger.info("=" * 60)

    return ios_blockfaces


def main():
    """Main entry point"""
    # Parse arguments
    limit = None
    output_path = None

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == "--limit" and i + 1 < len(sys.argv):
            limit = int(sys.argv[i + 1])
            i += 2
        elif arg == "--output" and i + 1 < len(sys.argv):
            output_path = Path(sys.argv[i + 1])
            i += 2
        else:
            print(f"Unknown argument: {arg}")
            print(__doc__)
            sys.exit(1)

    # Run export
    try:
        asyncio.run(fetch_and_export(limit=limit, output_path=output_path))
        return 0
    except Exception as e:
        logger.error(f"Export failed: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
