#!/usr/bin/env python3
"""
Convert SF GeoJSON blockfaces to app's JSON format.

Converts from DataSF's GeoJSON FeatureCollection format to the app's
simplified blockface format with proper field mapping.
"""

import json
import sys
from typing import List, Dict, Optional

# Mission District bounds for filtering
BOUNDS = {
    "min_lat": 37.744,   # South: Cesar Chavez (~26th St)
    "max_lat": 37.780,   # North: Market St
    "min_lon": -122.426, # West: Dolores St
    "max_lon": -122.407  # East: Potrero Ave
}

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

def convert_geojson_to_app_format(geojson_path: str, output_path: str, bounds_filter: bool = True):
    """Convert GeoJSON blockfaces to app format"""

    print(f"Reading GeoJSON: {geojson_path}")
    with open(geojson_path, 'r') as f:
        data = json.load(f)

    print(f"Total features in GeoJSON: {len(data['features'])}")

    blockfaces = []
    skipped_out_of_bounds = 0
    skipped_invalid = 0

    for idx, feature in enumerate(data['features']):
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

        # Create blockface in app format
        blockface = {
            "id": globalid,
            "street": street_info['street'],
            "fromStreet": street_info['from'],
            "toStreet": street_info['to'],
            "side": side,
            "geometry": {
                "type": "LineString",
                "coordinates": coords  # Already in [lon, lat] format
            },
            "regulations": []  # Empty for now - will be populated by spatial join
        }

        blockfaces.append(blockface)

    print(f"\nConversion complete:")
    print(f"  ✓ Converted: {len(blockfaces)} blockfaces")
    print(f"  Skipped (out of bounds): {skipped_out_of_bounds}")
    print(f"  Skipped (invalid geometry): {skipped_invalid}")

    # Show sample
    if blockfaces:
        print(f"\nSample blockfaces:")
        for bf in blockfaces[:3]:
            coords = bf['geometry']['coordinates']
            print(f"  {bf['street']} ({bf['fromStreet']} → {bf['toStreet']}) {bf['side']}")
            print(f"    {len(coords)} points: [{coords[0][0]:.6f}, {coords[0][1]:.6f}] → [{coords[-1][0]:.6f}, {coords[-1][1]:.6f}]")

    # Save output
    output = {"blockfaces": blockfaces}
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n✓ Saved to: {output_path}")
    print(f"\nNext steps:")
    print(f"  1. Review the generated file")
    print(f"  2. Copy to app resources:")
    print(f"     cp {output_path} SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json")
    print(f"  3. Reset transformation settings in DeveloperSettings")
    print(f"  4. Test in the app")

def main():
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    else:
        input_file = "Data Sets/Blockfaces_20251128.geojson"

    if len(sys.argv) > 2:
        output_file = sys.argv[2]
    else:
        output_file = "sample_blockfaces_from_geojson.json"

    # Check for --no-bounds flag
    bounds_filter = "--no-bounds" not in sys.argv

    print("=" * 70)
    print("GeoJSON → App Format Converter")
    print("=" * 70)
    print(f"Input:  {input_file}")
    print(f"Output: {output_file}")
    print(f"Bounds filter: {'ON (Mission District only)' if bounds_filter else 'OFF (all SF)'}")
    print("=" * 70)
    print()

    convert_geojson_to_app_format(input_file, output_file, bounds_filter)

if __name__ == "__main__":
    main()
