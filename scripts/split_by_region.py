#!/usr/bin/env python3
"""
Split full SF blockface data into geographic regions for faster loading.

Instead of loading 18,355 blockfaces (32MB), the app loads only 2,000-4,000
blockfaces (~3-7MB) for the region containing the user's location.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List

# SF region boundaries (9 regions for ~2,000 blockfaces each)
REGIONS = {
    "downtown": {
        "name": "Downtown/Financial District",
        "bounds": {"min_lat": 37.775, "max_lat": 37.805, "min_lon": -122.420, "max_lon": -122.390}
    },
    "mission": {
        "name": "Mission District",
        "bounds": {"min_lat": 37.744, "max_lat": 37.775, "min_lon": -122.426, "max_lon": -122.407}
    },
    "richmond": {
        "name": "Richmond District",
        "bounds": {"min_lat": 37.770, "max_lat": 37.790, "min_lon": -122.510, "max_lon": -122.450}
    },
    "sunset": {
        "name": "Sunset District",
        "bounds": {"min_lat": 37.744, "max_lat": 37.770, "min_lon": -122.510, "max_lon": -122.470}
    },
    "haight": {
        "name": "Haight/Western Addition",
        "bounds": {"min_lat": 37.765, "max_lat": 37.785, "min_lon": -122.450, "max_lon": -122.420}
    },
    "nob_hill": {
        "name": "Nob Hill/Russian Hill",
        "bounds": {"min_lat": 37.785, "max_lat": 37.808, "min_lon": -122.430, "max_lon": -122.400}
    },
    "north_beach": {
        "name": "North Beach/Marina",
        "bounds": {"min_lat": 37.795, "max_lat": 37.812, "min_lon": -122.450, "max_lon": -122.400}
    },
    "soma": {
        "name": "SOMA/Potrero",
        "bounds": {"min_lat": 37.760, "max_lat": 37.785, "min_lon": -122.420, "max_lon": -122.385}
    },
    "bayview": {
        "name": "Bayview/Dogpatch",
        "bounds": {"min_lat": 37.715, "max_lat": 37.760, "min_lon": -122.407, "max_lon": -122.380}
    },
}

def get_blockface_center(blockface: Dict) -> tuple:
    """Get approximate center lat/lon of blockface"""
    coords = blockface['geometry']['coordinates']
    if not coords:
        return None, None

    mid_idx = len(coords) // 2
    lon, lat = coords[mid_idx]
    return lat, lon

def blockface_in_region(blockface: Dict, bounds: Dict) -> bool:
    """Check if blockface center is within region bounds"""
    lat, lon = get_blockface_center(blockface)
    if lat is None:
        return False

    return (bounds["min_lat"] <= lat <= bounds["max_lat"] and
            bounds["min_lon"] <= lon <= bounds["max_lon"])

def split_into_regions(input_file: str, output_dir: str):
    """Split blockface data into regional files"""

    print(f"Loading full SF data from: {input_file}")
    with open(input_file, 'r') as f:
        data = json.load(f)

    blockfaces = data['blockfaces']
    print(f"Total blockfaces: {len(blockfaces)}")

    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Split into regions
    region_data = {region_id: [] for region_id in REGIONS.keys()}
    region_data["other"] = []  # For blockfaces outside defined regions

    for bf in blockfaces:
        assigned = False
        for region_id, region_info in REGIONS.items():
            if blockface_in_region(bf, region_info["bounds"]):
                region_data[region_id].append(bf)
                assigned = True
                break  # Assign to first matching region

        if not assigned:
            region_data["other"].append(bf)

    # Write regional files
    print("\nWriting regional files:")
    print("-" * 70)

    for region_id, blockfaces_list in region_data.items():
        if not blockfaces_list:
            continue

        output_file = output_path / f"blockfaces_{region_id}.json"

        regional_data = {
            "region": REGIONS.get(region_id, {}).get("name", "Other/Outlying"),
            "blockfaces": blockfaces_list
        }

        with open(output_file, 'w') as f:
            json.dump(regional_data, f, separators=(',', ':'))

        file_size = output_file.stat().st_size / 1024 / 1024  # MB
        print(f"  {region_id:15s}: {len(blockfaces_list):5,} blockfaces, {file_size:5.1f} MB")

    print("-" * 70)
    print(f"\nRegional files saved to: {output_dir}")

    # Create region index
    index = {
        "regions": {
            region_id: {
                "name": info["name"],
                "bounds": info["bounds"],
                "file": f"blockfaces_{region_id}.json",
                "blockface_count": len(region_data[region_id])
            }
            for region_id, info in REGIONS.items()
            if region_data[region_id]
        }
    }

    index_file = output_path / "region_index.json"
    with open(index_file, 'w') as f:
        json.dump(index, f, indent=2)

    print(f"Region index saved to: {index_file}")

if __name__ == '__main__':
    project_root = Path(__file__).parent.parent
    input_file = project_root / "data" / "processed" / "full_sf" / "blockfaces_full_sf.json"
    output_dir = project_root / "data" / "processed" / "regional"

    split_into_regions(str(input_file), str(output_dir))
