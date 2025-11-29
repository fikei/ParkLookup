#!/usr/bin/env python3
"""
Simple wrapper to run full blockface + regulation conversion with side-aware matching.
"""

import sys
sys.path.insert(0, '.')

from convert_geojson_with_regulations import convert_with_regulations

# File paths
blockfaces = "Data Sets/Blockfaces_20251128.geojson"
regulations = "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"
sweeping = "Data Sets/Street_Sweeping_Schedule_20251128.geojson"
metered = "Data Sets/Blockfaces_with_Meters_20251128.geojson"
output = "sample_blockfaces_sideaware_full.json"

print("=" * 70)
print("RUNNING FULL CONVERSION WITH SIDE-AWARE MATCHING")
print("=" * 70)
print(f"Blockfaces:     {blockfaces}")
print(f"Regulations:    {regulations}")
print(f"Street Sweeping: {sweeping}")
print(f"Metered:        {metered}")
print(f"Output:         {output}")
print("=" * 70)
print()

# Run conversion
convert_with_regulations(
    blockfaces_path=blockfaces,
    regulations_path=regulations,
    output_path=output,
    sweeping_path=sweeping,
    metered_path=metered,
    bounds_filter=True  # Mission District only
)

print("\n✅ Conversion complete!")
print(f"Output saved to: {output}")
