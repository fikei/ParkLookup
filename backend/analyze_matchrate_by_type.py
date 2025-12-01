#!/usr/bin/env python3
"""
Analyze match rate by regulation type from blockface pipeline output.

This script compares the source regulation counts from the input GeoJSON files
with the output blockface regulations to determine match rates per type.
"""

import json
import sys
from pathlib import Path
from collections import Counter

def count_regulations_in_geojson(geojson_path):
    """Count regulations by type in source GeoJSON file."""
    with open(geojson_path) as f:
        data = json.load(f)

    counts = Counter()
    features = data.get('features', [])

    for feature in features:
        props = feature.get('properties', {})

        # Determine regulation type based on properties
        # This mimics the logic in the pipeline
        if 'STREET_SWEEPING' in str(props.get('CATEGORY', '')).upper():
            counts['streetCleaning'] += 1
        elif props.get('RATE_AREA'):
            counts['metered'] += 1
        elif 'RPP' in str(props.get('CATEGORY', '')).upper() or props.get('RPP_AREA'):
            counts['residentialPermit'] += 1
        elif props.get('TIME_LIMIT'):
            counts['timeLimit'] += 1
        elif 'NO PARKING' in str(props.get('CATEGORY', '')).upper():
            counts['noParking'] += 1
        else:
            counts['other'] += 1

    return counts

def count_regulations_in_blockface_output(blockface_path):
    """Count regulations by type in blockface output."""
    with open(blockface_path) as f:
        data = json.load(f)

    counts = Counter()

    for blockface in data.get('blockfaces', []):
        for reg in blockface.get('regulations', []):
            reg_type = reg.get('type', 'unknown')
            counts[reg_type] += 1

    return counts

def main():
    print("=" * 80)
    print("BLOCKFACE PIPELINE MATCH RATE BY REGULATION TYPE")
    print("=" * 80)
    print()

    # Paths
    data_dir = Path("../data/raw")
    output_file = Path("blockfaces_full_sf_20251128.json")

    # Source files
    regulations_file = data_dir / "Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"
    sweeping_file = data_dir / "Street_Sweeping_Schedule_20251128.geojson"
    meters_file = data_dir / "Parking_Meters_20251128.geojson"

    # Count source regulations
    print("Counting source regulations...")
    source_counts = Counter()

    if regulations_file.exists():
        reg_counts = count_regulations_in_geojson(regulations_file)
        print(f"  Parking regulations: {sum(reg_counts.values()):,}")
        source_counts.update(reg_counts)

    if sweeping_file.exists():
        sweep_counts = count_regulations_in_geojson(sweeping_file)
        print(f"  Street sweeping: {sum(sweep_counts.values()):,}")
        source_counts.update(sweep_counts)

    if meters_file.exists():
        meter_counts = count_regulations_in_geojson(meters_file)
        print(f"  Parking meters: {sum(meter_counts.values()):,}")
        source_counts.update(meter_counts)

    print(f"  Total source regulations: {sum(source_counts.values()):,}")
    print()

    # Count output regulations
    print("Counting output regulations...")
    if not output_file.exists():
        print(f"Error: {output_file} not found")
        sys.exit(1)

    output_counts = count_regulations_in_blockface_output(output_file)
    print(f"  Total output regulations: {sum(output_counts.values()):,}")
    print()

    # Calculate match rates
    print("MATCH RATE BY REGULATION TYPE:")
    print("=" * 80)
    print(f"{'Type':<20} {'Source':>12} {'Output':>12} {'Match Rate':>12} {'Difference':>12}")
    print("-" * 80)

    all_types = set(source_counts.keys()) | set(output_counts.keys())

    total_source = 0
    total_output = 0

    for reg_type in sorted(all_types):
        source = source_counts.get(reg_type, 0)
        output = output_counts.get(reg_type, 0)

        if source > 0:
            match_rate = (output / source) * 100
        else:
            match_rate = 0.0 if output == 0 else float('inf')

        diff = output - source

        print(f"{reg_type:<20} {source:>12,} {output:>12,} {match_rate:>11.1f}% {diff:>+12,}")

        total_source += source
        total_output += output

    print("-" * 80)

    if total_source > 0:
        overall_rate = (total_output / total_source) * 100
    else:
        overall_rate = 0.0

    total_diff = total_output - total_source
    print(f"{'TOTAL':<20} {total_source:>12,} {total_output:>12,} {overall_rate:>11.1f}% {total_diff:>+12,}")
    print("=" * 80)
    print()

    # Notes
    print("NOTES:")
    print(f"  - Negative differences indicate unmatched source regulations")
    print(f"  - Multi-RPP consolidation reduced residentialPermit count by ~706")
    print(f"  - Match rate = (Output / Source) × 100%")
    print()

    # Detailed breakdown
    print("DETAILED BREAKDOWN:")
    print("=" * 80)

    for reg_type in sorted(all_types):
        source = source_counts.get(reg_type, 0)
        output = output_counts.get(reg_type, 0)

        if source == 0 and output == 0:
            continue

        print(f"\n{reg_type.upper()}:")
        print(f"  Source regulations: {source:,}")
        print(f"  Output regulations: {output:,}")

        if source > 0:
            match_rate = (output / source) * 100
            unmatched = source - output
            print(f"  Match rate: {match_rate:.1f}%")

            if unmatched > 0:
                print(f"  Unmatched: {unmatched:,} ({(unmatched/source)*100:.1f}%)")
            elif unmatched < 0:
                print(f"  Extra in output: {abs(unmatched):,} (likely duplicates or data issues)")
        else:
            print(f"  Match rate: N/A (no source data)")
            print(f"  Note: {output:,} regulations in output without source")

if __name__ == "__main__":
    main()
