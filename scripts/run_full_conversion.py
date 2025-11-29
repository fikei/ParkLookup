#!/usr/bin/env python3
"""
Simple wrapper to run full blockface + regulation conversion with side-aware matching.
"""

import sys
import os
from pathlib import Path

# Add project root to path to import converter
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from convert_geojson_with_regulations import convert_with_regulations

# File paths (new organized structure)
data_dir = project_root / "data"
blockfaces = str(data_dir / "raw" / "Blockfaces_20251128.geojson")
regulations = str(data_dir / "raw" / "Parking_regulations_(except_non-metered_color_curb)_20251128.geojson")
sweeping = str(data_dir / "raw" / "Street_Sweeping_Schedule_20251128.geojson")
metered = str(data_dir / "raw" / "Blockfaces_with_Meters_20251128.geojson")
output = str(data_dir / "processed" / "mission_district" / "sample_blockfaces_sideaware_full.json")

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
