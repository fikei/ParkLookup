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


def convert_polygon_to_boundary(polygon: List[List[List[float]]]) -> List[Dict[str, float]]:
    """
    Convert pipeline polygon format to iOS boundary format.

    Pipeline: [[[lon, lat], [lon, lat], ...]]  (rings of [lon, lat] arrays)
    iOS: [{latitude: lat, longitude: lon}, ...]  (flat array of coordinate objects)
    """
    if not polygon or not polygon[0]:
        return []

    # Take first ring (exterior boundary)
    exterior_ring = polygon[0]

    boundary = []
    for coord in exterior_ring:
        if len(coord) >= 2:
            boundary.append({
                "latitude": coord[1],   # GeoJSON is [lon, lat]
                "longitude": coord[0]
            })

    return boundary


def generate_zone_id(area_code: str, index: int = 1) -> str:
    """Generate a unique zone ID"""
    return f"sf_rpp_{area_code.lower()}_{index:03d}"


def generate_default_rule(area_code: str) -> Dict[str, Any]:
    """Generate a default RPP rule for a zone"""
    return {
        "id": f"{area_code.lower()}_rule_001",
        "ruleType": "permit_required",
        "description": f"Residential Permit Area {area_code} only",
        "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
        "enforcementStartTime": {"hour": 8, "minute": 0},
        "enforcementEndTime": {"hour": 18, "minute": 0},
        "timeLimit": 120,
        "meterRate": None,
        "specialConditions": "2-hour limit for non-permit holders"
    }


def convert_zone(zone_data: Dict[str, Any], index: int) -> Optional[Dict[str, Any]]:
    """Convert a pipeline zone to iOS format"""
    code = zone_data.get("code", "")
    if not code:
        return None

    polygon = zone_data.get("polygon", [])
    boundary = convert_polygon_to_boundary(polygon)

    if not boundary:
        print(f"  Warning: Zone {code} has no boundary, skipping")
        return None

    return {
        "id": generate_zone_id(code, index),
        "cityCode": "sf",
        "displayName": f"Area {code}",
        "zoneType": "rpp",
        "permitArea": code,
        "validPermitAreas": [code],
        "requiresPermit": True,
        "restrictiveness": 8,  # RPP zones are moderately restrictive
        "boundary": boundary,
        "rules": [generate_default_rule(code)],
        "metadata": {
            "dataSource": "datasf_sfmta",
            "lastUpdated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "accuracy": "high"
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
                "name": f"Area {code}",
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

    print(f"  Pipeline version: {pipeline_version}")
    print(f"  Raw zones count: {len(raw_zones)}")

    # Convert zones
    ios_zones = []
    zone_counts = {}  # Track count per area code

    for raw_zone in raw_zones:
        code = raw_zone.get("code", "")
        zone_counts[code] = zone_counts.get(code, 0) + 1

        ios_zone = convert_zone(raw_zone, zone_counts[code])
        if ios_zone:
            ios_zones.append(ios_zone)

    print(f"  Converted zones: {len(ios_zones)}")

    # Build permit areas from zones
    permit_areas = build_permit_areas(ios_zones)
    print(f"  Permit areas: {len(permit_areas)}")

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
