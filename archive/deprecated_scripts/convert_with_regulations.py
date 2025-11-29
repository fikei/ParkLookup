#!/usr/bin/env python3
"""
Convert GeoJSON blockfaces and link parking regulations via spatial joining.

This script:
1. Converts blockfaces from GeoJSON to app format
2. Spatially joins parking regulations to blockfaces
3. Outputs complete blockface data with regulations
"""

import json
import sys
from typing import List, Dict, Tuple, Optional
from shapely.geometry import LineString, MultiLineString, shape
from shapely.ops import nearest_points

# Mission District bounds for filtering
BOUNDS = {
    "min_lat": 37.744,   # South: Cesar Chavez (~26th St)
    "max_lat": 37.780,   # North: Market St
    "min_lon": -122.426, # West: Dolores St
    "max_lon": -122.407  # East: Potrero Ave
}

def parse_side_from_popupinfo(popupinfo: str) -> str:
    """Extract side from popupinfo field"""
    if not popupinfo:
        return "UNKNOWN"

    popupinfo_lower = popupinfo.lower()

    if "west side" in popupinfo_lower:
        return "EVEN"
    elif "east side" in popupinfo_lower:
        return "ODD"
    elif "north side" in popupinfo_lower:
        return "NORTH"
    elif "south side" in popupinfo_lower:
        return "SOUTH"

    return "UNKNOWN"

def parse_street_info(popupinfo: str) -> Dict[str, str]:
    """Parse popupinfo to extract street, from, to"""
    if not popupinfo:
        return {
            'street': 'Unknown Street',
            'from': 'Unknown',
            'to': 'Unknown'
        }

    if " between " in popupinfo and " and " in popupinfo:
        parts = popupinfo.split(" between ")
        if len(parts) == 2:
            street = parts[0].strip()
            rest = parts[1]

            if ", " in rest:
                rest = rest.split(", ")[0]

            if " and " in rest:
                from_to = rest.split(" and ")
                if len(from_to) == 2:
                    return {
                        'street': street,
                        'from': from_to[0].strip(),
                        'to': from_to[1].strip()
                    }

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

def convert_regulation_to_app_format(reg_props: Dict) -> Optional[Dict]:
    """
    Convert a parking regulation to app format.

    Regulations can be:
    - Time limited (2hr, 4hr, etc.)
    - Residential permit (RPP)
    - Street cleaning
    - No parking
    - Metered
    """
    if not reg_props:
        return None

    regulation_type = (reg_props.get('regulation') or '').lower()

    # Map regulation types
    if 'time limited' in regulation_type:
        reg_type = 'timeLimit'
    elif 'residential permit' in regulation_type or 'rpp' in regulation_type:
        reg_type = 'residentialPermit'
    elif 'street cleaning' in regulation_type or 'street sweeping' in regulation_type:
        reg_type = 'streetCleaning'
    elif 'no parking' in regulation_type:
        reg_type = 'noParking'
    elif 'metered' in regulation_type or 'meter' in regulation_type:
        reg_type = 'metered'
    elif 'tow' in regulation_type:
        reg_type = 'towAway'
    elif 'loading' in regulation_type:
        reg_type = 'loadingZone'
    else:
        return None  # Unknown regulation type

    # Parse time limit (in hours, convert to minutes)
    time_limit = None
    hrlimit = reg_props.get('hrlimit')
    if hrlimit:
        try:
            time_limit = int(hrlimit) * 60  # Convert hours to minutes
        except (ValueError, TypeError):
            pass

    # Parse enforcement days
    days_str = reg_props.get('days', '')
    enforcement_days = None
    if days_str:
        # Parse "M-F", "M-Su", etc.
        if 'M-F' in days_str.upper():
            enforcement_days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
        elif 'M-SU' in days_str.upper():
            enforcement_days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
        # Could add more parsing for specific days

    # Parse enforcement times
    hrs_begin = reg_props.get('hrs_begin')
    hrs_end = reg_props.get('hrs_end')

    enforcement_start = None
    enforcement_end = None

    if hrs_begin:
        # Convert "900" to "09:00"
        hrs_begin_str = str(hrs_begin).zfill(4)
        enforcement_start = f"{hrs_begin_str[:2]}:{hrs_begin_str[2:]}"

    if hrs_end:
        hrs_end_str = str(hrs_end).zfill(4)
        enforcement_end = f"{hrs_end_str[:2]}:{hrs_end_str[2:]}"

    # Get RPP area
    permit_zone = reg_props.get('rpparea1')

    return {
        'type': reg_type,
        'permitZone': permit_zone,
        'timeLimit': time_limit,
        'meterRate': None,  # Not in this dataset
        'enforcementDays': enforcement_days,
        'enforcementStart': enforcement_start,
        'enforcementEnd': enforcement_end,
        'specialConditions': reg_props.get('exceptions')
    }

def spatial_join_regulations(blockfaces_geojson: Dict, regulations_geojson: Dict) -> List[Tuple[str, Dict]]:
    """
    Spatially join regulations to blockfaces.
    Returns list of (blockface_globalid, regulation) tuples.
    """
    print("\n" + "=" * 70)
    print("SPATIAL JOINING REGULATIONS TO BLOCKFACES")
    print("=" * 70)

    # Build spatial index of blockfaces
    blockface_geoms = {}
    for feature in blockfaces_geojson['features']:
        globalid = feature['properties'].get('globalid')
        if not globalid:
            continue

        coords = feature['geometry']['coordinates']
        if is_in_bounds(coords):
            geom = LineString(coords)
            blockface_geoms[globalid] = geom

    print(f"Indexed {len(blockface_geoms)} blockfaces in Mission District")

    # Process regulations
    regulation_geoms = []
    for feature in regulations_geojson['features']:
        geom_data = feature.get('geometry')
        props = feature['properties']

        # Skip if no geometry
        if not geom_data or not geom_data.get('coordinates'):
            continue

        # Parse geometry (MultiLineString)
        if geom_data['type'] == 'MultiLineString':
            # Flatten MultiLineString to single LineString for matching
            all_coords = []
            for line in geom_data['coordinates']:
                all_coords.extend(line)
            if len(all_coords) >= 2:
                geom = LineString(all_coords)
            else:
                continue
        elif geom_data['type'] == 'LineString':
            geom = LineString(geom_data['coordinates'])
        else:
            continue

        # Only consider regulations in bounds
        centroid = geom.centroid
        if not is_in_bounds([[centroid.x, centroid.y]]):
            continue

        regulation_geoms.append((geom, props))

    print(f"Found {len(regulation_geoms)} regulations in Mission District")

    # Match regulations to blockfaces
    matches = []
    matched_count = 0

    DISTANCE_THRESHOLD = 0.00005  # ~5 meters in degrees

    for reg_geom, reg_props in regulation_geoms:
        best_match = None
        best_distance = float('inf')

        # Find closest blockface
        for globalid, bf_geom in blockface_geoms.items():
            # Calculate distance between regulation and blockface
            distance = reg_geom.distance(bf_geom)

            if distance < best_distance:
                best_distance = distance
                best_match = globalid

        # If close enough, add the match
        if best_match and best_distance < DISTANCE_THRESHOLD:
            regulation = convert_regulation_to_app_format(reg_props)
            if regulation:
                matches.append((best_match, regulation))
                matched_count += 1

    print(f"Matched {matched_count} regulations to blockfaces")
    print(f"Distance threshold: {DISTANCE_THRESHOLD}° (~{DISTANCE_THRESHOLD * 111000:.1f}m)")

    return matches

def main():
    print("=" * 70)
    print("GeoJSON Converter with Spatial Regulation Joining")
    print("=" * 70)
    print()

    blockfaces_path = "Data Sets/Blockfaces_20251128.geojson"
    regulations_path = "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"
    output_path = "sample_blockfaces_with_regulations.json"

    # Load GeoJSON files
    print(f"Loading blockfaces: {blockfaces_path}")
    with open(blockfaces_path, 'r') as f:
        blockfaces_geojson = json.load(f)

    print(f"Loading regulations: {regulations_path}")
    with open(regulations_path, 'r') as f:
        regulations_geojson = json.load(f)

    # Convert blockfaces
    print(f"\nConverting {len(blockfaces_geojson['features'])} blockfaces...")

    blockfaces = []
    skipped_out_of_bounds = 0

    for idx, feature in enumerate(blockfaces_geojson['features']):
        props = feature['properties']
        geom = feature['geometry']

        if geom['type'] != 'LineString' or not geom.get('coordinates'):
            continue

        coords = geom['coordinates']

        if not is_in_bounds(coords):
            skipped_out_of_bounds += 1
            continue

        globalid = props.get('globalid', f'blockface_{idx}')
        popupinfo = props.get('popupinfo', '')
        street_info = parse_street_info(popupinfo)
        side = parse_side_from_popupinfo(popupinfo)

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
            "regulations": []
        }

        blockfaces.append(blockface)

    print(f"  ✓ Converted: {len(blockfaces)} blockfaces")
    print(f"  Skipped (out of bounds): {skipped_out_of_bounds}")

    # Spatial join regulations
    regulation_matches = spatial_join_regulations(blockfaces_geojson, regulations_geojson)

    # Add regulations to blockfaces
    regulation_map = {}
    for globalid, regulation in regulation_matches:
        if globalid not in regulation_map:
            regulation_map[globalid] = []
        regulation_map[globalid].append(regulation)

    for blockface in blockfaces:
        if blockface['id'] in regulation_map:
            blockface['regulations'] = regulation_map[blockface['id']]

    # Count blockfaces with regulations
    with_regs = sum(1 for bf in blockfaces if bf['regulations'])
    print(f"\n✓ {with_regs} blockfaces have regulations ({with_regs/len(blockfaces)*100:.1f}%)")

    # Save output
    output = {"blockfaces": blockfaces}
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n✓ Saved to: {output_path}")

    # Show sample
    print(f"\nSample blockfaces with regulations:")
    sample_count = 0
    for bf in blockfaces:
        if bf['regulations'] and sample_count < 3:
            print(f"\n  {bf['street']} ({bf['fromStreet']} → {bf['toStreet']}) {bf['side']}")
            for reg in bf['regulations'][:2]:  # Show first 2 regulations
                print(f"    - {reg['type']}", end='')
                if reg.get('timeLimit'):
                    print(f", {reg['timeLimit']//60}hr limit", end='')
                if reg.get('permitZone'):
                    print(f", Zone {reg['permitZone']}", end='')
                print()
            sample_count += 1

    print(f"\nNext steps:")
    print(f"  cp {output_path} SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json")

if __name__ == "__main__":
    # Check if shapely is available
    try:
        import shapely
    except ImportError:
        print("ERROR: shapely library required for spatial joining")
        print("Install with: pip install shapely")
        sys.exit(1)

    main()
