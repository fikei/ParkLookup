#!/usr/bin/env python3
"""
Convert pipeline output to iOS-compatible JSON format.

Usage:
    python convert_to_ios.py [input_file] [output_file]

If no arguments provided:
    - Input: output/parking_data_latest.json.gz (or zones_only_*.json)
    - Output: ../SFParkingZoneFinder/SFParkingZoneFinder/Resources/sf_parking_zones.json
"""
import json
import gzip
import sys
from pathlib import Path
from datetime import datetime
from typing import Any, Dict, List, Optional


# SF city bounds
SF_BOUNDS = {
    "north": 37.8324,
    "south": 37.6398,
    "east": -122.3281,
    "west": -122.5274
}

# Known permit area neighborhoods (from SFMTA data)
PERMIT_AREA_NEIGHBORHOODS = {
    "A": ["Telegraph Hill", "North Beach"],
    "B": ["Marina", "Cow Hollow"],
    "C": ["Russian Hill"],
    "D": ["Fisherman's Wharf"],
    "E": ["Pacific Heights"],
    "F": ["Presidio Heights"],
    "G": ["Inner Richmond"],
    "H": ["Outer Richmond"],
    "I": ["Inner Sunset"],
    "J": ["Outer Sunset"],
    "K": ["Glen Park", "Diamond Heights"],
    "L": ["Noe Valley"],
    "M": ["Excelsior"],
    "N": ["Potrero Hill"],
    "O": ["Bernal Heights"],
    "P": ["Bayview"],
    "Q": ["Castro", "Upper Market", "Mission Dolores"],
    "R": ["Haight-Ashbury", "Cole Valley"],
    "S": ["Lower Haight"],
    "T": ["SOMA"],
    "U": ["Mission"],
    "V": ["Dogpatch"],
    "W": ["West Portal"],
    "X": ["Forest Hill"],
    "Y": ["St. Francis Wood"],
    "Z": ["Parkside"],
    "AA": ["Visitacion Valley"],
    "BB": ["Oceanview"],
    "CC": ["Ingleside"],
    "DD": ["Sunnyside"],
    "EE": ["Miraloma Park"],
    "FF": ["Mt. Davidson"],
    "GG": ["Westwood Park"],
    "HH": ["Monterey Heights"],
}


def convert_polygon_to_boundary(polygon: List[List[List[float]]]) -> List[List[Dict[str, float]]]:
    """
    Convert pipeline polygon format to iOS boundary format.

    Pipeline format (from parcels): list of polygon rings, one per parcel
        [[lon, lat], [lon, lat], ...]  - parcel 1
        [[lon, lat], [lon, lat], ...]  - parcel 2
        ...

    iOS format: list of boundaries (MultiPolygon support)
        [[{latitude, longitude}, ...], [{latitude, longitude}, ...], ...]
    """
    if not polygon:
        return []

    boundaries = []
    for ring in polygon:
        if not ring or not isinstance(ring, list):
            continue

        # Check if this is a ring of coordinates or a nested structure
        if isinstance(ring[0], (int, float)):
            # This is a single coordinate [lon, lat], not a ring
            continue

        boundary = []
        for coord in ring:
            # Handle both list [lon, lat] and tuple (lon, lat) formats
            if isinstance(coord, (list, tuple)) and len(coord) >= 2:
                boundary.append({
                    "latitude": coord[1],   # GeoJSON is [lon, lat]
                    "longitude": coord[0]
                })

        if boundary:
            boundaries.append(boundary)

    return boundaries


def generate_zone_id(area_code: str, index: int = 1) -> str:
    """Generate a unique zone ID"""
    return f"sf_rpp_{area_code.lower()}_{index:03d}"


def generate_default_rule(area_code: str) -> Dict[str, Any]:
    """Generate a default RPP rule for a zone"""
    return {
        "id": f"{area_code.lower()}_rule_001",
        "ruleType": "permit_required",
        "description": f"Residential permit Zone {area_code} only",
        "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
        "enforcementStartTime": {"hour": 8, "minute": 0},
        "enforcementEndTime": {"hour": 18, "minute": 0},
        "timeLimit": 120,
        "meterRate": None,
        "specialConditions": "2-hour limit for non-permit holders"
    }


def generate_metered_rule(zone_data: Dict[str, Any]) -> Dict[str, Any]:
    """Generate a metered parking rule for a zone"""
    zone_id = zone_data.get("code", "unknown")
    time_limit = zone_data.get("avgTimeLimit") or 60
    cap_colors = zone_data.get("capColors", [])

    # Determine description based on cap colors
    if "GREEN" in cap_colors:
        description = "Short-term metered parking (15-30 min)"
    elif "YELLOW" in cap_colors:
        description = "Commercial loading zone"
    else:
        description = f"Metered parking ({time_limit} min limit)"

    return {
        "id": f"{zone_id.lower()}_rule_001",
        "ruleType": "metered",
        "description": description,
        "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
        "enforcementStartTime": {"hour": 9, "minute": 0},
        "enforcementEndTime": {"hour": 18, "minute": 0},
        "timeLimit": time_limit,
        "meterRate": 2.0,  # Default rate, varies by area
        "specialConditions": "Pay at meter or via app"
    }


def convert_zone(zone_data: Dict[str, Any], index: int) -> Optional[Dict[str, Any]]:
    """Convert a pipeline zone to iOS format"""
    code = zone_data.get("code", "")
    if not code:
        return None

    polygon = zone_data.get("polygon", [])
    boundaries = convert_polygon_to_boundary(polygon)

    if not boundaries:
        print(f"  Warning: Zone {code} has no boundaries, skipping")
        return None

    # Process multi-permit polygon data
    # multi_permit_polygons: Dict[polygon_index -> List[all_valid_areas]]
    multi_permit_polygons = zone_data.get("multiPermitPolygons", {})
    multi_permit_boundaries = []
    all_valid_areas = {code}  # Start with zone's own permit area

    for idx_str, valid_areas in multi_permit_polygons.items():
        idx = int(idx_str)
        if idx < len(boundaries):
            multi_permit_boundaries.append({
                "boundaryIndex": idx,
                "validPermitAreas": valid_areas
            })
            # Collect all valid permit areas from multi-permit boundaries
            all_valid_areas.update(valid_areas)

    return {
        "id": generate_zone_id(code, index),
        "cityCode": "sf",
        "displayName": f"Zone {code}",
        "zoneType": "rpp",
        "permitArea": code,
        "validPermitAreas": sorted(list(all_valid_areas)),  # All valid permits for this zone
        "requiresPermit": True,
        "restrictiveness": 8,  # RPP zones are moderately restrictive
        "boundaries": boundaries,  # MultiPolygon: list of polygon boundaries
        "multiPermitBoundaries": multi_permit_boundaries,  # Boundaries that accept multiple permits
        "rules": [generate_default_rule(code)],
        "metadata": {
            "dataSource": "datasf_sfmta",
            "lastUpdated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "accuracy": "high",
            "polygonCount": len(boundaries),
            "multiPermitCount": len(multi_permit_boundaries)
        }
    }


def convert_metered_zone(zone_data: Dict[str, Any], index: int) -> Optional[Dict[str, Any]]:
    """Convert a metered zone from pipeline to iOS format"""
    code = zone_data.get("code", "")
    if not code:
        return None

    polygon = zone_data.get("polygon", [])
    boundaries = convert_polygon_to_boundary(polygon)

    if not boundaries:
        print(f"  Warning: Metered zone {code} has no boundaries, skipping")
        return None

    meter_count = zone_data.get("meterCount", 0)
    avg_time_limit = zone_data.get("avgTimeLimit") or 120  # Default 2hr
    rate_area = zone_data.get("rateArea")

    # Determine hourly rate based on rate area (SF meter rates vary by area)
    hourly_rate = 2.0  # Default rate
    if rate_area:
        # SF has different rate areas with varying prices
        rate_map = {"1": 3.0, "2": 2.5, "3": 2.0, "4": 1.5, "5": 1.0}
        hourly_rate = rate_map.get(str(rate_area), 2.0)

    return {
        "id": f"sf_metered_{code.lower()}_{index:03d}",
        "cityCode": "sf",
        "displayName": "Paid Parking",
        "zoneType": "metered",
        "permitArea": None,  # No permit required for metered zones
        "validPermitAreas": [],
        "requiresPermit": False,
        "restrictiveness": 5,  # Metered zones are less restrictive than RPP
        "boundaries": boundaries,
        "rules": [generate_metered_rule(zone_data)],
        "metadata": {
            "dataSource": "datasf_meters",
            "lastUpdated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "accuracy": "medium",
            "polygonCount": len(boundaries),
            "meterCount": meter_count,
            "avgTimeLimit": avg_time_limit,
            "hourlyRate": hourly_rate
        }
    }


def build_permit_areas(zones: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Build permit areas list from zones"""
    seen_codes = set()
    permit_areas = []

    for zone in zones:
        code = zone.get("permitArea")
        if code and code not in seen_codes:
            seen_codes.add(code)
            permit_areas.append({
                "code": code,
                "name": f"Zone {code}",
                "neighborhoods": PERMIT_AREA_NEIGHBORHOODS.get(code, [])
            })

    # Sort alphabetically
    permit_areas.sort(key=lambda x: x["code"])
    return permit_areas


def convert_pipeline_to_ios(input_data: Dict[str, Any]) -> Dict[str, Any]:
    """Convert pipeline output to iOS format"""
    print("Converting pipeline output to iOS format...")

    # Extract pipeline data
    pipeline_version = input_data.get("version", datetime.utcnow().strftime("%Y%m%d"))
    generated = input_data.get("generated", datetime.utcnow().isoformat())
    raw_zones = input_data.get("zones", [])
    raw_metered_zones = input_data.get("meteredZones", [])

    print(f"  Pipeline version: {pipeline_version}")
    print(f"  Raw RPP zones count: {len(raw_zones)}")
    print(f"  Raw metered zones count: {len(raw_metered_zones)}")

    # Convert RPP zones
    ios_zones = []
    zone_counts = {}  # Track count per area code

    for raw_zone in raw_zones:
        code = raw_zone.get("code", "")
        zone_counts[code] = zone_counts.get(code, 0) + 1

        ios_zone = convert_zone(raw_zone, zone_counts[code])
        if ios_zone:
            ios_zones.append(ios_zone)

    print(f"  Converted RPP zones: {len(ios_zones)}")

    # Convert metered zones
    metered_zone_counts = {}
    for raw_mz in raw_metered_zones:
        code = raw_mz.get("code", "")
        metered_zone_counts[code] = metered_zone_counts.get(code, 0) + 1

        ios_mz = convert_metered_zone(raw_mz, metered_zone_counts[code])
        if ios_mz:
            ios_zones.append(ios_mz)

    print(f"  Total zones (RPP + metered): {len(ios_zones)}")

    # Build permit areas from zones (only from RPP zones)
    rpp_zones = [z for z in ios_zones if z.get('zoneType') == 'rpp']
    permit_areas = build_permit_areas(rpp_zones)
    print(f"  Permit areas: {len(permit_areas)}")

    # RPP Zone summary
    print("\nRPP Zone Summary:")
    print("-" * 50)
    total_boundaries = 0
    total_points = 0
    for zone in sorted(rpp_zones, key=lambda z: z.get('permitArea', '') or ''):
        code = zone.get('permitArea', '?')
        boundaries = zone.get('boundaries', [])
        num_boundaries = len(boundaries)
        num_points = sum(len(b) for b in boundaries)
        total_boundaries += num_boundaries
        total_points += num_points
        print(f"  {code:4s}: {num_boundaries:,} parcels, {num_points:,} points")
    print("-" * 50)
    print(f"  Total: {total_boundaries:,} parcels, {total_points:,} points across {len(rpp_zones)} RPP zones")

    # Metered Zone summary
    metered_zones = [z for z in ios_zones if z.get('zoneType') == 'metered']
    if metered_zones:
        print("\nMetered Zone Summary:")
        print("-" * 50)
        metered_boundaries = 0
        metered_points = 0
        for zone in metered_zones[:5]:  # Show first 5
            name = zone.get('displayName', '?')[:35]
            boundaries = zone.get('boundaries', [])
            num_boundaries = len(boundaries)
            meter_count = zone.get('metadata', {}).get('meterCount', 0)
            print(f"  {name}: {num_boundaries} polys, {meter_count} meters")
        if len(metered_zones) > 5:
            print(f"  ... and {len(metered_zones) - 5} more metered zones")
        for zone in metered_zones:
            boundaries = zone.get('boundaries', [])
            metered_boundaries += len(boundaries)
            metered_points += sum(len(b) for b in boundaries)
        print("-" * 50)
        print(f"  Total: {metered_boundaries:,} polygons, {metered_points:,} points across {len(metered_zones)} metered zones")

    # Build iOS output structure
    return {
        "version": pipeline_version,
        "generatedAt": generated if "T" in generated else f"{generated}T00:00:00Z",
        "city": {
            "code": "sf",
            "name": "San Francisco",
            "state": "CA",
            "bounds": SF_BOUNDS
        },
        "permitAreas": permit_areas,
        "zones": ios_zones
    }


def load_input(input_path: Path) -> Dict[str, Any]:
    """Load input file (supports .json and .json.gz)"""
    print(f"Loading: {input_path}")

    if input_path.suffix == ".gz":
        with gzip.open(input_path, "rt", encoding="utf-8") as f:
            return json.load(f)
    else:
        with open(input_path, "r", encoding="utf-8") as f:
            return json.load(f)


def save_output(data: Dict[str, Any], output_path: Path):
    """Save output to JSON file"""
    print(f"Saving: {output_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    print(f"  Written {len(data.get('zones', []))} zones")


def find_latest_input(output_dir: Path) -> Optional[Path]:
    """Find the latest pipeline output file"""
    # Try compressed latest
    latest_gz = output_dir / "parking_data_latest.json.gz"
    if latest_gz.exists():
        return latest_gz

    # Try uncompressed latest
    latest = output_dir / "parking_data_latest.json"
    if latest.exists():
        return latest

    # Try zones-only files
    zones_files = sorted(output_dir.glob("zones_only_*.json"), reverse=True)
    if zones_files:
        return zones_files[0]

    # Try any parking data file
    data_files = sorted(output_dir.glob("parking_data_*.json*"), reverse=True)
    if data_files:
        return data_files[0]

    return None


def main():
    # Determine paths
    script_dir = Path(__file__).parent
    output_dir = script_dir / "output"
    ios_resources = script_dir.parent / "SFParkingZoneFinder" / "SFParkingZoneFinder" / "Resources"

    # Parse arguments
    if len(sys.argv) >= 2:
        input_path = Path(sys.argv[1])
    else:
        input_path = find_latest_input(output_dir)
        if not input_path:
            print("Error: No pipeline output found in output/")
            print("Run the pipeline first: python pipeline.py")
            sys.exit(1)

    if len(sys.argv) >= 3:
        output_path = Path(sys.argv[2])
    else:
        output_path = ios_resources / "sf_parking_zones.json"

    # Validate input exists
    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}")
        sys.exit(1)

    # Load and convert
    input_data = load_input(input_path)
    ios_data = convert_pipeline_to_ios(input_data)

    # Save output
    save_output(ios_data, output_path)

    print()
    print("Conversion complete!")
    print(f"  Input:  {input_path}")
    print(f"  Output: {output_path}")
    print(f"  Zones:  {len(ios_data['zones'])}")


if __name__ == "__main__":
    main()
