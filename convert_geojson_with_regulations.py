#!/usr/bin/env python3
"""
Convert SF GeoJSON blockfaces to app's JSON format WITH parking regulations.

This script performs a spatial join between:
- Blockfaces_20251128.geojson (18,355 street centerlines)
- Parking_regulations_20251128.geojson (7,784 regulations)

It uses Shapely for spatial matching and populates the regulations[] field
on each blockface with matched parking rules.
"""

import json
import sys
from typing import List, Dict, Optional, Tuple
from shapely.geometry import LineString, MultiLineString, shape
from shapely.ops import unary_union
from collections import defaultdict

# Mission District bounds for filtering
BOUNDS = {
    "min_lat": 37.744,   # South: Cesar Chavez (~26th St)
    "max_lat": 37.780,   # North: Market St
    "min_lon": -122.426, # West: Dolores St
    "max_lon": -122.407  # East: Potrero Ave
}

# Buffer distance for spatial matching (meters converted to degrees, ~10m)
BUFFER_DISTANCE = 0.0001  # ~11 meters at SF latitude


def parse_side_from_popupinfo(popupinfo: str) -> str:
    """
    Extract side from popupinfo field.
    Format: "Street between From and To, side"
    Example: "Valencia Street between 17th St and 16th St, west side"
    """
    if not popupinfo:
        return "UNKNOWN"

    popupinfo_lower = popupinfo.lower()

    # Look for side indicators
    if "west side" in popupinfo_lower:
        return "EVEN"  # West side typically has even addresses
    elif "east side" in popupinfo_lower:
        return "ODD"   # East side typically has odd addresses
    elif "north side" in popupinfo_lower:
        return "NORTH"
    elif "south side" in popupinfo_lower:
        return "SOUTH"

    return "UNKNOWN"


def parse_street_info(popupinfo: str) -> Dict[str, str]:
    """
    Parse popupinfo to extract street, from, to.
    Format: "Street between From and To, side"
    """
    if not popupinfo:
        return {
            'street': 'Unknown Street',
            'from': 'Unknown',
            'to': 'Unknown'
        }

    # Try to parse "Street between From and To, side" format
    if " between " in popupinfo and " and " in popupinfo:
        parts = popupinfo.split(" between ")
        if len(parts) == 2:
            street = parts[0].strip()
            rest = parts[1]

            # Split on ", " to remove side info
            if ", " in rest:
                rest = rest.split(", ")[0]

            # Split on " and " to get from/to
            if " and " in rest:
                from_to = rest.split(" and ")
                if len(from_to) == 2:
                    return {
                        'street': street,
                        'from': from_to[0].strip(),
                        'to': from_to[1].strip()
                    }

    # Fallback: use the whole thing as street name
    return {
        'street': popupinfo.split(',')[0].strip() if ',' in popupinfo else popupinfo.strip(),
        'from': 'Unknown',
        'to': 'Unknown'
    }


def is_in_bounds(coords: List[List[float]]) -> bool:
    """Check if coordinates are within Mission District bounds"""
    if not coords or len(coords) < 1:
        return False

    lon, lat = coords[0]
    return (BOUNDS['min_lat'] <= lat <= BOUNDS['max_lat'] and
            BOUNDS['min_lon'] <= lon <= BOUNDS['max_lon'])


def parse_days_to_array(days_str: str) -> List[str]:
    """
    Convert days string to array of weekday names.
    Examples:
      "M-F" -> ["monday", "tuesday", "wednesday", "thursday", "friday"]
      "M-Sa" -> ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
      "DAILY" -> ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
      "Tu/Th" -> ["tuesday", "thursday"]
    """
    if not days_str:
        return None

    days_str = days_str.strip().upper()

    if days_str == "DAILY" or days_str == "M-SU":
        return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    elif days_str == "M-F":
        return ["monday", "tuesday", "wednesday", "thursday", "friday"]
    elif days_str == "M-SA":
        return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    # Handle day codes (M, Tu, W, Th, F, Sa, Su)
    day_map = {
        "M": "monday",
        "TU": "tuesday",
        "W": "wednesday",
        "TH": "thursday",
        "F": "friday",
        "SA": "saturday",
        "SU": "sunday"
    }

    # Try to parse patterns like "Tu/Th" or "M/W/F"
    days = []
    for code in days_str.replace("/", " ").split():
        if code in day_map:
            days.append(day_map[code])

    return days if days else None


def parse_time_to_format(time_str: str) -> Optional[str]:
    """
    Convert time string to HH:MM format.
    Examples:
      "900" -> "09:00"
      "1800" -> "18:00"
      "2400" -> "00:00"
    """
    if not time_str:
        return None

    # Handle string numbers like "900", "1800"
    time_str = str(time_str).strip()

    # Pad to 4 digits if needed
    if len(time_str) <= 2:
        time_str = time_str.zfill(2) + "00"
    elif len(time_str) == 3:
        time_str = "0" + time_str

    # Extract hours and minutes
    if len(time_str) >= 4:
        hours = int(time_str[:-2])
        minutes = int(time_str[-2:])

        # Handle 2400 as midnight
        if hours >= 24:
            hours = 0

        return f"{hours:02d}:{minutes:02d}"

    return None


def map_regulation_type(regulation: str) -> str:
    """
    Map DataSF regulation types to app's BlockfaceRegulation types.
    """
    if not regulation:
        return "other"

    regulation = regulation.strip().lower()

    mapping = {
        "time limited": "timeLimit",
        "residential permit": "residentialPermit",
        "no parking any time": "noParking",
        "no parking anytime": "noParking",
        "street cleaning": "streetCleaning",
        "metered parking": "metered",
        "pay or permit": "metered",  # Will also create residentialPermit
        "tow-away zone": "towAway",
        "tow away": "towAway",
        "loading zone": "loadingZone",
        "no oversized vehicles": "other",  # Not a standard type
    }

    return mapping.get(regulation, "other")


def extract_regulation(reg_props: Dict) -> List[Dict]:
    """
    Extract regulation data from GeoJSON properties and map to app schema.

    Returns a list because some regulation types (e.g., "Pay or Permit")
    should create multiple regulations.
    """
    regulation_type_raw = reg_props.get("regulation", "") or ""
    regulation_type = map_regulation_type(regulation_type_raw)

    # Parse time fields
    days = parse_days_to_array(reg_props.get("days"))
    enforcement_start = parse_time_to_format(reg_props.get("hrs_begin"))
    enforcement_end = parse_time_to_format(reg_props.get("hrs_end"))

    # Extract RPP zones (can have multiple)
    permit_zones = []
    for rpp_field in ["rpparea1", "rpparea2", "rpparea3"]:
        zone = reg_props.get(rpp_field)
        if zone and zone.strip():
            permit_zones.append(zone.strip())

    # Parse time limit (convert hours to minutes)
    time_limit = None
    hrlimit = reg_props.get("hrlimit")
    if hrlimit:
        try:
            hours = float(hrlimit)
            time_limit = int(hours * 60)
        except (ValueError, TypeError):
            pass

    # Get exceptions
    exceptions = reg_props.get("exceptions")

    regulations = []

    # Handle "Pay or Permit" - create both metered and residentialPermit
    if regulation_type_raw.lower() == "pay or permit":
        # Create metered regulation
        regulations.append({
            "type": "metered",
            "permitZone": None,
            "timeLimit": time_limit,
            "meterRate": None,  # Not in current dataset
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

        # Create residentialPermit regulation for each zone
        for zone in permit_zones:
            regulations.append({
                "type": "residentialPermit",
                "permitZone": zone,
                "timeLimit": None,
                "meterRate": None,
                "enforcementDays": days,
                "enforcementStart": enforcement_start,
                "enforcementEnd": enforcement_end,
                "specialConditions": exceptions
            })

    # Handle time limit with RPP zone - create both regulations
    elif regulation_type == "timeLimit" and permit_zones:
        # Create time limit regulation
        regulations.append({
            "type": "timeLimit",
            "permitZone": None,
            "timeLimit": time_limit,
            "meterRate": None,
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

        # Create residentialPermit regulation for each zone
        for zone in permit_zones:
            regulations.append({
                "type": "residentialPermit",
                "permitZone": zone,
                "timeLimit": None,
                "meterRate": None,
                "enforcementDays": days,
                "enforcementStart": enforcement_start,
                "enforcementEnd": enforcement_end,
                "specialConditions": f"Exempt from time limits. {exceptions}" if exceptions else "Exempt from time limits"
            })

    # Standard single regulation
    else:
        # Use first permit zone if available
        permit_zone = permit_zones[0] if permit_zones else None

        regulations.append({
            "type": regulation_type,
            "permitZone": permit_zone,
            "timeLimit": time_limit,
            "meterRate": None,
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

    return regulations


def load_regulations(regulations_path: str) -> List[Tuple[MultiLineString, Dict]]:
    """
    Load regulations GeoJSON and extract geometries + properties.
    Returns list of (geometry, properties) tuples.
    """
    print(f"Loading regulations from: {regulations_path}")

    with open(regulations_path, 'r') as f:
        data = json.load(f)

    regulations = []
    skipped = 0

    for feature in data['features']:
        geom = feature.get('geometry')
        props = feature.get('properties', {})

        if not geom or geom.get('type') != 'MultiLineString':
            skipped += 1
            continue

        try:
            # Convert GeoJSON to Shapely geometry
            shapely_geom = shape(geom)
            regulations.append((shapely_geom, props))
        except Exception as e:
            skipped += 1
            continue

    print(f"  ✓ Loaded {len(regulations)} regulations ({skipped} skipped)")
    return regulations


def find_matching_regulations(blockface_geom: LineString,
                             regulations: List[Tuple[MultiLineString, Dict]],
                             buffer_distance: float = BUFFER_DISTANCE) -> List[Dict]:
    """
    Find all regulations that spatially intersect with the blockface.
    Uses a buffer around the blockface to catch nearby regulations.
    """
    # Create buffer around blockface centerline
    buffered_blockface = blockface_geom.buffer(buffer_distance)

    matching_regs = []

    for reg_geom, reg_props in regulations:
        # Check if regulation geometry intersects with buffered blockface
        if buffered_blockface.intersects(reg_geom):
            # Extract regulation data
            extracted = extract_regulation(reg_props)
            matching_regs.extend(extracted)

    return matching_regs


def convert_with_regulations(blockfaces_path: str,
                             regulations_path: str,
                             output_path: str,
                             bounds_filter: bool = True):
    """
    Convert GeoJSON blockfaces to app format with regulations populated.
    """

    # Load regulations first
    regulations = load_regulations(regulations_path)

    if not regulations:
        print("ERROR: No regulations loaded. Aborting.")
        return

    # Load blockfaces
    print(f"\nReading blockfaces from: {blockfaces_path}")
    with open(blockfaces_path, 'r') as f:
        blockfaces_data = json.load(f)

    print(f"Total blockface features: {len(blockfaces_data['features'])}")

    blockfaces = []
    skipped_out_of_bounds = 0
    skipped_invalid = 0
    blockfaces_with_regulations = 0
    total_regulations_added = 0

    for idx, feature in enumerate(blockfaces_data['features']):
        if (idx + 1) % 1000 == 0:
            print(f"  Processing blockface {idx + 1}/{len(blockfaces_data['features'])}...")

        props = feature['properties']
        geom = feature['geometry']

        # Validate geometry
        if geom['type'] != 'LineString' or not geom.get('coordinates'):
            skipped_invalid += 1
            continue

        coords = geom['coordinates']

        # Apply bounds filter if enabled
        if bounds_filter and not is_in_bounds(coords):
            skipped_out_of_bounds += 1
            continue

        # Extract identifiers
        globalid = props.get('globalid', f'blockface_{idx}')

        # Parse street info from popupinfo
        popupinfo = props.get('popupinfo', '')
        street_info = parse_street_info(popupinfo)
        side = parse_side_from_popupinfo(popupinfo)

        # Convert to Shapely geometry for spatial matching
        try:
            blockface_geom = LineString(coords)
        except Exception as e:
            skipped_invalid += 1
            continue

        # Find matching regulations
        matched_regulations = find_matching_regulations(blockface_geom, regulations)

        # Deduplicate regulations (same regulation may match multiple times)
        # Create unique key based on all fields except None values
        seen = set()
        unique_regulations = []
        for reg in matched_regulations:
            # Create tuple of all non-None values for comparison
            # Convert lists to tuples for hashing
            key_parts = []
            for k, v in sorted(reg.items()):
                if v is not None and k != 'meterRate':
                    if isinstance(v, list):
                        key_parts.append((k, tuple(v)))
                    else:
                        key_parts.append((k, v))
            key = tuple(key_parts)
            if key not in seen:
                seen.add(key)
                unique_regulations.append(reg)

        matched_regulations = unique_regulations

        if matched_regulations:
            blockfaces_with_regulations += 1
            total_regulations_added += len(matched_regulations)

        # Create blockface in app format
        blockface = {
            "id": globalid,
            "street": street_info['street'],
            "fromStreet": street_info['from'],
            "toStreet": street_info['to'],
            "side": side,
            "geometry": {
                "type": "LineString",
                "coordinates": coords
            },
            "regulations": matched_regulations
        }

        blockfaces.append(blockface)

    # Print statistics
    print(f"\n{'='*70}")
    print("CONVERSION STATISTICS")
    print(f"{'='*70}")
    print(f"Blockfaces processed:          {len(blockfaces)}")
    print(f"Blockfaces with regulations:   {blockfaces_with_regulations} ({100*blockfaces_with_regulations/max(len(blockfaces),1):.1f}%)")
    print(f"Blockfaces without regulations: {len(blockfaces) - blockfaces_with_regulations}")
    print(f"Total regulations added:       {total_regulations_added}")
    print(f"Avg regulations per blockface: {total_regulations_added/max(len(blockfaces),1):.2f}")
    print(f"\nSkipped (out of bounds):       {skipped_out_of_bounds}")
    print(f"Skipped (invalid geometry):    {skipped_invalid}")
    print(f"{'='*70}")

    # Regulation type breakdown
    reg_types = defaultdict(int)
    for bf in blockfaces:
        for reg in bf['regulations']:
            reg_types[reg['type']] += 1

    if reg_types:
        print("\nREGULATION TYPE BREAKDOWN:")
        for reg_type, count in sorted(reg_types.items(), key=lambda x: -x[1]):
            print(f"  {reg_type:20s} {count:5d} ({100*count/total_regulations_added:.1f}%)")

    # Show sample blockfaces with regulations
    print(f"\nSAMPLE BLOCKFACES WITH REGULATIONS:")
    sample_count = 0
    for bf in blockfaces:
        if bf['regulations'] and sample_count < 3:
            sample_count += 1
            print(f"\n  {bf['street']} ({bf['fromStreet']} → {bf['toStreet']}) {bf['side']}")
            for reg in bf['regulations'][:2]:  # Show first 2 regulations
                print(f"    • {reg['type']}", end="")
                if reg.get('permitZone'):
                    print(f" (Zone {reg['permitZone']})", end="")
                if reg.get('timeLimit'):
                    print(f" - {reg['timeLimit']} min limit", end="")
                if reg.get('enforcementDays'):
                    days_str = ", ".join(reg['enforcementDays'][:3])
                    if len(reg['enforcementDays']) > 3:
                        days_str += "..."
                    print(f" - {days_str}", end="")
                if reg.get('enforcementStart') and reg.get('enforcementEnd'):
                    print(f" {reg['enforcementStart']}-{reg['enforcementEnd']}", end="")
                print()

    # Save output
    output = {"blockfaces": blockfaces}
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n✓ Saved to: {output_path}")
    print(f"\nNext steps:")
    print(f"  1. Review the statistics above")
    print(f"  2. Check sample blockfaces for accuracy")
    print(f"  3. Copy to app resources:")
    print(f"     cp {output_path} SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json")
    print(f"  4. Test in the app")


def main():
    # Parse command-line arguments
    if len(sys.argv) > 1:
        blockfaces_file = sys.argv[1]
    else:
        blockfaces_file = "Data Sets/Blockfaces_20251128.geojson"

    if len(sys.argv) > 2:
        regulations_file = sys.argv[2]
    else:
        regulations_file = "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"

    if len(sys.argv) > 3:
        output_file = sys.argv[3]
    else:
        output_file = "sample_blockfaces_with_regulations.json"

    # Check for --no-bounds flag
    bounds_filter = "--no-bounds" not in sys.argv

    print("=" * 70)
    print("BLOCKFACE + REGULATIONS SPATIAL JOIN")
    print("=" * 70)
    print(f"Blockfaces:  {blockfaces_file}")
    print(f"Regulations: {regulations_file}")
    print(f"Output:      {output_file}")
    print(f"Bounds filter: {'ON (Mission District only)' if bounds_filter else 'OFF (all SF)'}")
    print(f"Buffer distance: {BUFFER_DISTANCE} degrees (~{BUFFER_DISTANCE * 111000:.0f}m)")
    print("=" * 70)
    print()

    convert_with_regulations(blockfaces_file, regulations_file, output_file, bounds_filter)


if __name__ == "__main__":
    main()
