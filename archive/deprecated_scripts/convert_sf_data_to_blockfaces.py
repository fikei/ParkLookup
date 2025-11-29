#!/usr/bin/env python3
"""
Convert SF Open Data Portal blockface CSV to app blockface format.

This script processes the Blockfaces_20251128.csv file from SF Open Data Portal
and converts it to the format used by the SFParkingZoneFinder app.

The CSV has columns:
- POPUPINFO: "{Street} between {FromStreet} and {ToStreet}, {side}"
- shape: WKT LINESTRING geometry

Usage:
    python convert_sf_data_to_blockfaces.py Blockfaces_20251128.csv
"""

import json
import csv
import sys
import os
import re
from typing import List, Dict, Optional, Tuple

# Mission District bounds: Market to Cesar Chavez, Dolores to Potrero
BOUNDS = {
    "min_lat": 37.744,   # South: Cesar Chavez (~26th St)
    "max_lat": 37.780,   # North: Market St
    "min_lon": -122.426, # West: Dolores St
    "max_lon": -122.407  # East: Potrero Ave
}

def parse_popup_info(popup_info: str) -> Optional[Dict[str, str]]:
    """
    Parse POPUPINFO field to extract street information.

    Format: "{Street} between {FromStreet} and {ToStreet}, {side}"
    Example: "Mission Street between 22nd St and 23rd St, east side"

    Returns dict with: street, from_street, to_street, side
    """
    if not popup_info:
        return None

    # Pattern: "Street between From and To, side"
    pattern = r'^(.+?)\s+between\s+(.+?)\s+and\s+(.+?),\s+(.+?)\s+side$'
    match = re.match(pattern, popup_info, re.IGNORECASE)

    if match:
        street = match.group(1).strip()
        from_street = match.group(2).strip()
        to_street = match.group(3).strip()
        side_raw = match.group(4).strip().upper()

        # Normalize side
        if 'EAST' in side_raw:
            side = 'ODD'  # East side typically has odd numbers
        elif 'WEST' in side_raw:
            side = 'EVEN'  # West side typically has even numbers
        elif 'NORTH' in side_raw:
            side = 'NORTH'
        elif 'SOUTH' in side_raw:
            side = 'SOUTH'
        else:
            side = 'UNKNOWN'

        return {
            'street': street,
            'from_street': from_street,
            'to_street': to_street,
            'side': side
        }

    return None

def parse_wkt_linestring(wkt: str) -> Optional[List[List[float]]]:
    """
    Parse WKT LINESTRING to coordinates array.

    Format: "LINESTRING (lon1 lat1, lon2 lat2, ...)"
    Returns: [[lon1, lat1], [lon2, lat2], ...] in GeoJSON format
    """
    if not wkt or not wkt.startswith('LINESTRING'):
        return None

    try:
        # Extract coordinate pairs from parentheses
        coords_str = wkt[wkt.index('(') + 1:wkt.rindex(')')]

        # Split by commas to get individual points
        points = coords_str.split(',')

        coordinates = []
        for point in points:
            # Split by space to get lon, lat
            parts = point.strip().split()
            if len(parts) >= 2:
                lon = float(parts[0])
                lat = float(parts[1])
                coordinates.append([lon, lat])

        return coordinates if coordinates else None

    except (ValueError, IndexError):
        return None

def process_csv_file(csv_path: str) -> List[Dict]:
    """Process SF Open Data CSV file"""
    print(f"Reading CSV file: {csv_path}")

    blockfaces = []
    skipped = 0
    no_popup = 0
    out_of_bounds = 0

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        for idx, row in enumerate(reader):
            # Parse geometry first (required for all blockfaces)
            wkt = row.get('shape', '')
            coords = parse_wkt_linestring(wkt)
            if not coords:
                skipped += 1
                continue

            # Check if within Mission District bounds
            lon, lat = coords[0]
            if not (BOUNDS['min_lat'] <= lat <= BOUNDS['max_lat'] and
                   BOUNDS['min_lon'] <= lon <= BOUNDS['max_lon']):
                out_of_bounds += 1
                continue

            # Parse POPUPINFO if available
            popup_info = row.get('POPUPINFO', '').strip()
            if popup_info:
                info = parse_popup_info(popup_info)
                if info:
                    street = info['street']
                    from_street = info['from_street']
                    to_street = info['to_street']
                    side = info['side']
                else:
                    # POPUPINFO exists but couldn't parse
                    street = "Unknown Street"
                    from_street = "Unknown"
                    to_street = "Unknown"
                    side = "UNKNOWN"
            else:
                # No POPUPINFO - create with unknown info
                no_popup += 1
                street = "Unknown Street"
                from_street = "Unknown"
                to_street = "Unknown"
                side = "UNKNOWN"

            # Create blockface
            globalid = row.get('GLOBALID', f'blockface_{idx}')

            blockface = {
                "id": globalid,
                "street": street,
                "fromStreet": from_street,
                "toStreet": to_street,
                "side": side,
                "geometry": {
                    "type": "LineString",
                    "coordinates": coords
                },
                "regulations": []
            }

            blockfaces.append(blockface)

    print(f"✓ Processed {len(blockfaces)} blockfaces")
    print(f"  Skipped: {skipped} (parse errors)")
    print(f"  No popup info: {no_popup}")
    print(f"  Out of bounds: {out_of_bounds}")

    return blockfaces

def verify_coordinates(blockfaces: List[Dict]) -> bool:
    """Verify that coordinates are correct (Valencia west of Mission)"""
    print("\nVerifying coordinates...")

    mission_lons = []
    valencia_lons = []

    for bf in blockfaces:
        street = bf['street'].upper()
        coords = bf['geometry']['coordinates']
        if coords:
            lon = coords[0][0]  # First coordinate longitude

            if 'MISSION' in street:
                mission_lons.append(lon)
            elif 'VALENCIA' in street:
                valencia_lons.append(lon)

    if mission_lons and valencia_lons:
        avg_mission = sum(mission_lons) / len(mission_lons)
        avg_valencia = sum(valencia_lons) / len(valencia_lons)

        min_mission = min(mission_lons)
        max_mission = max(mission_lons)
        min_valencia = min(valencia_lons)
        max_valencia = max(valencia_lons)

        print(f"  Mission St:")
        print(f"    Average longitude: {avg_mission:.6f}")
        print(f"    Range: {min_mission:.6f} to {max_mission:.6f}")
        print(f"  Valencia St:")
        print(f"    Average longitude: {avg_valencia:.6f}")
        print(f"    Range: {min_valencia:.6f} to {max_valencia:.6f}")

        if avg_valencia < avg_mission:
            print("  ✓ CORRECT: Valencia is WEST of Mission (more negative longitude)")
            return True
        else:
            print("  ✗ ERROR: Valencia is EAST of Mission (coordinates inverted)")
            return False

    print("  ⚠ Could not verify (missing Mission or Valencia data)")
    return False

def main():
    print("=" * 70)
    print("SF Open Data → App Blockface Format Converter")
    print("=" * 70)
    print()

    # Get input file
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    else:
        input_file = "Blockfaces_20251128.csv"

    if not os.path.exists(input_file):
        print(f"✗ File not found: {input_file}")
        print("\nUsage: python convert_sf_data_to_blockfaces.py <csv_file>")
        return

    # Process CSV
    blockfaces = process_csv_file(input_file)

    if not blockfaces:
        print("✗ No blockfaces found in the specified area")
        return

    # Verify coordinates
    verify_coordinates(blockfaces)

    # Show summary
    print(f"\nSummary:")
    print(f"  Total blockfaces: {len(blockfaces)}")

    mission_count = sum(1 for bf in blockfaces if 'MISSION' in bf['street'].upper())
    valencia_count = sum(1 for bf in blockfaces if 'VALENCIA' in bf['street'].upper())
    print(f"  Mission St: {mission_count}")
    print(f"  Valencia St: {valencia_count}")

    # Group by cross street
    from_streets = {}
    for bf in blockfaces:
        from_st = bf['fromStreet']
        from_streets[from_st] = from_streets.get(from_st, 0) + 1

    print(f"\nCross streets found:")
    for street in sorted(from_streets.keys()):
        print(f"  {street}: {from_streets[street]} blockfaces")

    # Show sample
    print("\nSample blockfaces:")
    for bf in blockfaces[:8]:
        coords = bf['geometry']['coordinates']
        print(f"  {bf['street']} ({bf['fromStreet']} → {bf['toStreet']}) {bf['side']}")
        print(f"    {len(coords)} points: [{coords[0][0]:.6f}, {coords[0][1]:.6f}] → [{coords[-1][0]:.6f}, {coords[-1][1]:.6f}]")

    # Save output
    output = {"blockfaces": blockfaces}
    output_file = "SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces_REAL.json"

    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n✓ Saved {len(blockfaces)} blockfaces to {output_file}")
    print("\nNext steps:")
    print("  1. Review the generated file")
    print("  2. If coordinates look correct, replace sample_blockfaces.json:")
    print(f"     cp {output_file} SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json")
    print("  3. Test in the app to verify alignment")

if __name__ == "__main__":
    main()
