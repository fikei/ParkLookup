#!/usr/bin/env python3
"""
Fetch real blockface data from SF Open Data Portal for the Mission/Valencia test area.

This script downloads parking regulation blockface data from San Francisco's
open data portal and filters it to the Mission/Valencia corridor around 22nd-25th Streets
to replace the sample test data with real coordinates.
"""

import json
import urllib.request
import urllib.parse
from typing import List, Dict, Any

# SF Open Data Socrata API endpoint for parking regulations
# Dataset: "Parking regulations (except non-metered color curb)"
# ID: hi6h-neyh
BASE_URL = "https://data.sfgov.org/resource/hi6h-neyh.geojson"

# Test area bounds (Mission/Valencia between roughly 22nd and 25th)
# These are approximate bounds for filtering
BOUNDS = {
    "min_lat": 37.751,   # South of 25th
    "max_lat": 37.758,   # North of 22nd
    "min_lon": -122.422, # East of Mission
    "max_lon": -122.419  # West of Valencia
}

def fetch_blockfaces(limit=1000):
    """Fetch blockface data from SF Open Data"""

    # Build query parameters
    params = {
        "$limit": limit,
        "$where": f"latitude > {BOUNDS['min_lat']} AND latitude < {BOUNDS['max_lat']} "
                  f"AND longitude > {BOUNDS['min_lon']} AND longitude < {BOUNDS['max_lon']}"
    }

    url = f"{BASE_URL}?{urllib.parse.urlencode(params)}"

    print(f"Fetching blockface data from SF Open Data...")
    print(f"URL: {url}")

    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            data = json.loads(response.read())
            print(f"✓ Downloaded {len(data.get('features', []))} blockfaces")
            return data
    except Exception as e:
        print(f"✗ Error fetching data: {e}")
        print(f"\nAlternative: Download manually from:")
        print(f"https://data.sfgov.org/Transportation/Parking-regulations-except-non-metered-color-curb-/hi6h-neyh/data")
        print(f"Export as GeoJSON and save to sf_blockfaces_raw.geojson")
        return None

def filter_mission_valencia(geojson_data: Dict) -> List[Dict]:
    """Filter to Mission and Valencia Street blockfaces"""

    if not geojson_data or 'features' not in geojson_data:
        return []

    mission_valencia = []

    for feature in geojson_data['features']:
        props = feature.get('properties', {})
        street = props.get('street', '').upper()

        # Filter for Mission and Valencia streets
        if 'MISSION' in street or 'VALENCIA' in street:
            mission_valencia.append(feature)

    print(f"✓ Filtered to {len(mission_valencia)} Mission/Valencia blockfaces")
    return mission_valencia

def convert_to_app_format(geojson_features: List[Dict]) -> Dict:
    """Convert GeoJSON features to app's blockface format"""

    blockfaces = []

    for idx, feature in enumerate(geojson_features):
        props = feature.get('properties', {})
        geom = feature.get('geometry', {})

        # Extract coordinates (GeoJSON uses [lon, lat] order)
        coords = geom.get('coordinates', [])
        if geom.get('type') == 'LineString' and coords:

            # Determine side based on street address patterns if available
            # This is a simplified heuristic - real data may have explicit side field
            side = props.get('side', 'UNKNOWN')

            blockface = {
                "id": props.get('cnn', f"blockface_{idx}"),
                "street": props.get('street', 'Unknown St'),
                "fromStreet": props.get('from_street', 'Unknown'),
                "toStreet": props.get('to_street', 'Unknown'),
                "side": side,
                "geometry": {
                    "type": "LineString",
                    "coordinates": coords  # Keep [lon, lat] format
                },
                "regulations": []
            }

            # Add any regulation data if available
            if props.get('permit_area'):
                blockface['regulations'].append({
                    "type": "residentialPermit",
                    "permitZone": props.get('permit_area')
                })

            blockfaces.append(blockface)

    return {"blockfaces": blockfaces}

def main():
    print("=" * 60)
    print("SF Blockface Data Fetcher")
    print("=" * 60)
    print()

    # Try to fetch data
    geojson_data = fetch_blockfaces()

    # If fetch failed, try to load from manually downloaded file
    if not geojson_data:
        try:
            print("\nAttempting to load from sf_blockfaces_raw.geojson...")
            with open('sf_blockfaces_raw.geojson', 'r') as f:
                geojson_data = json.load(f)
            print(f"✓ Loaded {len(geojson_data.get('features', []))} features from file")
        except FileNotFoundError:
            print("✗ File not found")
            print("\nPlease download the data manually:")
            print("1. Go to: https://data.sfgov.org/Transportation/Parking-regulations-except-non-metered-color-curb-/hi6h-neyh/data")
            print("2. Click 'Export' → 'GeoJSON'")
            print("3. Save as 'sf_blockfaces_raw.geojson' in this directory")
            print("4. Run this script again")
            return

    # Filter to Mission/Valencia
    mission_valencia = filter_mission_valencia(geojson_data)

    if not mission_valencia:
        print("✗ No Mission/Valencia blockfaces found")
        return

    # Show sample
    print("\nSample blockfaces found:")
    for feature in mission_valencia[:5]:
        props = feature.get('properties', {})
        geom = feature.get('geometry', {})
        coords = geom.get('coordinates', [])
        print(f"  - {props.get('street', 'Unknown')}: {len(coords)} points")

    # Convert to app format
    app_data = convert_to_app_format(mission_valencia)

    # Save output
    output_file = "SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces_REAL.json"
    with open(output_file, 'w') as f:
        json.dump(app_data, f, indent=2)

    print(f"\n✓ Saved {len(app_data['blockfaces'])} blockfaces to {output_file}")
    print("\nNext steps:")
    print("1. Review the generated file")
    print("2. Replace sample_blockfaces.json with real data")
    print("3. Test in the app to verify alignment")

if __name__ == "__main__":
    main()
