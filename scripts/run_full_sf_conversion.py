#!/usr/bin/env python3
"""
Convert ALL San Francisco blockfaces (not just Mission District test area).

This script generates the full production dataset for the entire city.
Expected output: ~18,355 blockfaces (~35MB JSON file)
Processing time: ~15-20 minutes
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
output = str(data_dir / "processed" / "full_sf" / "blockfaces_full_sf.json")

print("=" * 70)
print("RUNNING FULL SAN FRANCISCO CONVERSION")
print("=" * 70)
print(f"⚠️  WARNING: This will process ALL 18,355 SF blockfaces")
print(f"⏱️  Expected runtime: 15-20 minutes")
print(f"💾 Expected output size: ~35MB")
print("=" * 70)
print(f"Blockfaces:      {blockfaces}")
print(f"Regulations:     {regulations}")
print(f"Street Sweeping: {sweeping}")
print(f"Metered:         {metered}")
print(f"Output:          {output}")
print("=" * 70)
print()

# Run conversion WITHOUT bounds filter (full city)
convert_with_regulations(
    blockfaces_path=blockfaces,
    regulations_path=regulations,
    output_path=output,
    sweeping_path=sweeping,
    metered_path=metered,
    bounds_filter=False  # ← KEY CHANGE: Process entire city
)

print("\n✅ Full SF conversion complete!")
print(f"Output saved to: {output}")
print(f"\n📱 To deploy to app, run:")
print(f"cp {output} SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json")
