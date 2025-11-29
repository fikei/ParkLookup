#!/usr/bin/env python3
"""
Analyze blockface coordinates to understand offset and rotation issues.

This script:
1. Parses the GeoJSON blockface data
2. Calculates bearings for key streets (Mission, Valencia)
3. Checks if coordinates are correct or if there's a systematic offset/rotation
"""

import json
import math

def calculate_bearing(lat1, lon1, lat2, lon2):
    """
    Calculate the bearing between two points.
    Returns bearing in degrees (0-360, where 0 is north)
    """
    # Convert to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlon = math.radians(lon2 - lon1)

    # Calculate bearing
    x = math.sin(dlon) * math.cos(lat2_rad)
    y = math.cos(lat1_rad) * math.sin(lat2_rad) - \
        math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dlon)

    initial_bearing = math.atan2(x, y)

    # Convert to degrees and normalize to 0-360
    initial_bearing = math.degrees(initial_bearing)
    compass_bearing = (initial_bearing + 360) % 360

    return compass_bearing

def analyze_geojson(filepath):
    """Analyze GeoJSON blockface data"""
    print(f"Analyzing: {filepath}")
    print("=" * 70)

    with open(filepath, 'r') as f:
        data = json.load(f)

    print(f"\nTotal features: {len(data['features'])}")

    # Find Valencia and Mission streets in the Mission District
    valencia_blocks = []
    mission_blocks = []

    for feature in data['features']:
        props = feature['properties']
        popupinfo = props.get('popupinfo', '')

        if not popupinfo:
            continue

        coords = feature['geometry']['coordinates']
        if len(coords) < 2:
            continue

        start = coords[0]
        end = coords[-1]
        bearing = calculate_bearing(start[1], start[0], end[1], end[0])

        # Check for Mission District streets (lat 37.75-37.77, lon -122.43 to -122.41)
        if 37.75 < start[1] < 37.77 and -122.43 < start[0] < -122.41:
            if 'Valencia' in popupinfo and '16th' in popupinfo and '17th' in popupinfo:
                valencia_blocks.append({
                    'info': popupinfo,
                    'start': start,
                    'end': end,
                    'bearing': bearing,
                    'length_deg': math.sqrt((end[0]-start[0])**2 + (end[1]-start[1])**2)
                })
            elif 'Mission' in popupinfo and '16th' in popupinfo and '17th' in popupinfo:
                mission_blocks.append({
                    'info': popupinfo,
                    'start': start,
                    'end': end,
                    'bearing': bearing,
                    'length_deg': math.sqrt((end[0]-start[0])**2 + (end[1]-start[1])**2)
                })

    print("\n" + "=" * 70)
    print("VALENCIA STREET ANALYSIS (16th-17th)")
    print("=" * 70)
    print(f"Found {len(valencia_blocks)} Valencia St blockfaces")

    for block in valencia_blocks:
        print(f"\n{block['info']}")
        print(f"  Start: lon={block['start'][0]:.8f}, lat={block['start'][1]:.8f}")
        print(f"  End:   lon={block['end'][0]:.8f}, lat={block['end'][1]:.8f}")
        print(f"  Bearing: {block['bearing']:.1f}° (0°=N, 90°=E, 180°=S, 270°=W)")
        print(f"  Length: {block['length_deg']:.6f}° (~{block['length_deg']*111000:.1f}m)")

        # Valencia should run roughly north-south (around 355°-5° or 175°-185°)
        if 345 <= block['bearing'] <= 360 or 0 <= block['bearing'] <= 15:
            print(f"  ✓ Correct: Points roughly NORTH (expected for Valencia)")
        elif 175 <= block['bearing'] <= 195:
            print(f"  ✓ Correct: Points roughly SOUTH (expected for Valencia)")
        else:
            deviation = min(abs(block['bearing'] - 0), abs(block['bearing'] - 180),
                          abs(block['bearing'] - 360))
            print(f"  ✗ ERROR: Bearing off by ~{deviation:.1f}° from north-south axis")

    print("\n" + "=" * 70)
    print("MISSION STREET ANALYSIS (16th-17th)")
    print("=" * 70)
    print(f"Found {len(mission_blocks)} Mission St blockfaces")

    for block in mission_blocks:
        print(f"\n{block['info']}")
        print(f"  Start: lon={block['start'][0]:.8f}, lat={block['start'][1]:.8f}")
        print(f"  End:   lon={block['end'][0]:.8f}, lat={block['end'][1]:.8f}")
        print(f"  Bearing: {block['bearing']:.1f}° (0°=N, 90°=E, 180°=S, 270°=W)")
        print(f"  Length: {block['length_deg']:.6f}° (~{block['length_deg']*111000:.1f}m)")

        # Mission should also run roughly north-south
        if 345 <= block['bearing'] <= 360 or 0 <= block['bearing'] <= 15:
            print(f"  ✓ Correct: Points roughly NORTH (expected for Mission)")
        elif 175 <= block['bearing'] <= 195:
            print(f"  ✓ Correct: Points roughly SOUTH (expected for Mission)")
        else:
            deviation = min(abs(block['bearing'] - 0), abs(block['bearing'] - 180),
                          abs(block['bearing'] - 360))
            print(f"  ✗ ERROR: Bearing off by ~{deviation:.1f}° from north-south axis")

    # Compare Valencia vs Mission longitude to verify east-west positioning
    if valencia_blocks and mission_blocks:
        print("\n" + "=" * 70)
        print("RELATIVE POSITIONING CHECK")
        print("=" * 70)

        avg_valencia_lon = sum(b['start'][0] for b in valencia_blocks) / len(valencia_blocks)
        avg_mission_lon = sum(b['start'][0] for b in mission_blocks) / len(mission_blocks)

        print(f"Average Valencia St longitude: {avg_valencia_lon:.6f}")
        print(f"Average Mission St longitude:  {avg_mission_lon:.6f}")

        if avg_valencia_lon < avg_mission_lon:
            print(f"✓ CORRECT: Valencia ({avg_valencia_lon:.6f}) is WEST of Mission ({avg_mission_lon:.6f})")
            print(f"  Distance: {(avg_mission_lon - avg_valencia_lon) * 111000 * math.cos(math.radians(37.76)):.1f}m")
        else:
            print(f"✗ ERROR: Valencia ({avg_valencia_lon:.6f}) is EAST of Mission ({avg_mission_lon:.6f})")
            print(f"  This is wrong - they appear to be swapped!")

if __name__ == "__main__":
    analyze_geojson("Data Sets/Blockfaces_20251128.geojson")
