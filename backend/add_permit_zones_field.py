#!/usr/bin/env python3
"""
Add permitZones array field to existing sample_blockfaces.json file.

This script updates the existing blockface data to include the multi-RPP
permitZones array alongside the existing permitZone field for backward compatibility.

Usage:
    python add_permit_zones_field.py [input_file] [output_file]
"""
import json
import sys
from pathlib import Path

# iOS Resources path
IOS_RESOURCES_DIR = Path(__file__).parent.parent / "SFParkingZoneFinder" / "SFParkingZoneFinder" / "Resources"


def update_blockface_regulations(blockface: dict) -> dict:
    """
    Update regulations in a blockface to include permitZones array.

    For each regulation:
    - If it has permitZone but not permitZones, add permitZones: [permitZone]
    - If it has neither, set permitZones: null
    """
    for regulation in blockface.get("regulations", []):
        # Get existing permitZone
        permit_zone = regulation.get("permitZone")

        # Check if permitZones already exists
        if "permitZones" not in regulation:
            # Add permitZones array
            if permit_zone:
                regulation["permitZones"] = [permit_zone]
            else:
                regulation["permitZones"] = None

    return blockface


def main():
    # Determine input and output paths
    if len(sys.argv) >= 2:
        input_path = Path(sys.argv[1])
    else:
        input_path = IOS_RESOURCES_DIR / "sample_blockfaces.json"

    if len(sys.argv) >= 3:
        output_path = Path(sys.argv[2])
    else:
        output_path = input_path  # Overwrite in place

    # Validate input exists
    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}")
        return 1

    print(f"Reading: {input_path}")

    # Load existing data
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    blockfaces = data.get("blockfaces", [])
    print(f"Found {len(blockfaces)} blockfaces")

    # Update each blockface
    updated_count = 0
    for blockface in blockfaces:
        original_regs = json.dumps(blockface.get("regulations", []))
        update_blockface_regulations(blockface)
        updated_regs = json.dumps(blockface.get("regulations", []))

        if original_regs != updated_regs:
            updated_count += 1

    print(f"Updated {updated_count} blockfaces with permitZones field")

    # Write back
    print(f"Writing: {output_path}")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    file_size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"File size: {file_size_mb:.1f} MB")
    print("Done!")

    return 0


if __name__ == "__main__":
    sys.exit(main())
