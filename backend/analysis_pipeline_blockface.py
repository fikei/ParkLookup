#!/usr/bin/env python3
"""
Comprehensive Blockface Pipeline Analysis

This script provides detailed analysis of the blockface pipeline output including:
- Overall coverage statistics
- Regulation type breakdown
- Street name quality
- Side determination accuracy
- Multi-RPP permit distribution
- Match rates by regulation type (comparing source to output)

Usage:
    python analysis_pipeline_blockface.py [blockface_output.json]
"""

import json
import sys
from pathlib import Path
from collections import Counter, defaultdict

def analyze_coverage(blockface_data):
    """Analyze overall coverage and regulation distribution."""
    blockfaces = blockface_data.get("blockfaces", [])

    total_blockfaces = len(blockfaces)
    blockfaces_with_regulations = sum(1 for bf in blockfaces if len(bf.get("regulations", [])) > 0)
    blockfaces_without_regulations = total_blockfaces - blockfaces_with_regulations

    # Count regulations by type
    regulation_counts = Counter()
    for bf in blockfaces:
        for reg in bf.get("regulations", []):
            regulation_counts[reg.get("type", "unknown")] += 1

    # Street name quality
    named_streets = sum(1 for bf in blockfaces if bf.get("street") and bf["street"] != "Unknown Street")
    unknown_streets = total_blockfaces - named_streets

    # Side distribution
    side_counts = Counter()
    for bf in blockfaces:
        side_counts[bf.get("side", "UNKNOWN")] += 1

    # Top streets by regulation count
    street_reg_counts = defaultdict(int)
    for bf in blockfaces:
        street = bf.get("street", "Unknown Street")
        street_reg_counts[street] += len(bf.get("regulations", []))

    top_streets = sorted(street_reg_counts.items(), key=lambda x: -x[1])[:10]

    return {
        "total_blockfaces": total_blockfaces,
        "blockfaces_with_regulations": blockfaces_with_regulations,
        "blockfaces_without_regulations": blockfaces_without_regulations,
        "coverage_percent": (blockfaces_with_regulations / total_blockfaces * 100) if total_blockfaces > 0 else 0,
        "regulation_counts": regulation_counts,
        "total_regulations": sum(regulation_counts.values()),
        "named_streets": named_streets,
        "unknown_streets": unknown_streets,
        "side_counts": side_counts,
        "top_streets": top_streets
    }


def analyze_street_cleaning_sides(blockface_data):
    """Analyze street cleaning side coverage."""
    blockfaces = blockface_data.get("blockfaces", [])

    # Group by street name and collect cleaning regulations
    streets = defaultdict(lambda: {"sides": set(), "regulations": []})

    for bf in blockfaces:
        street = bf.get("street", "Unknown")
        side = bf.get("side", "UNKNOWN")

        # Check if has street cleaning
        cleaning_regs = [r for r in bf.get("regulations", []) if r.get("type") == "streetCleaning"]

        if cleaning_regs:
            streets[street]["sides"].add(side)
            streets[street]["regulations"].extend(cleaning_regs)

    # Categorize streets
    one_sided_streets = {}
    both_sided_streets = {}

    for street, data in streets.items():
        num_regulations = len(data["regulations"])
        if len(data["sides"]) == 1:
            one_sided_streets[street] = {
                "side": list(data["sides"])[0],
                "count": num_regulations
            }
        elif len(data["sides"]) > 1:
            both_sided_streets[street] = {
                "sides": list(data["sides"]),
                "count": num_regulations
            }

    return {
        "total_streets_with_cleaning": len(streets),
        "one_sided_count": len(one_sided_streets),
        "both_sided_count": len(both_sided_streets),
        "one_sided_streets": one_sided_streets,
        "both_sided_streets": both_sided_streets
    }


def count_source_regulations():
    """Count regulations by type in source GeoJSON files."""
    data_dir = Path("../data/raw")

    # Define source files
    source_files = {
        "regulations": data_dir / "Parking_regulations_(except_non-metered_color_curb)_20251128.geojson",
        "sweeping": data_dir / "Street_Sweeping_Schedule_20251128.geojson",
        "meters": data_dir / "Parking_Meters_20251128.geojson"
    }

    source_counts = Counter()
    file_counts = {}

    # Parking regulations - map using the same logic as pipeline
    if source_files["regulations"].exists():
        try:
            with open(source_files["regulations"]) as f:
                data = json.load(f)

            reg_type_counts = Counter()
            for feature in data.get("features", []):
                props = feature.get("properties", {})
                regulation = (props.get("regulation") or "").strip().lower()
                exceptions = (props.get("exceptions") or "").lower()

                # Map using same logic as pipeline (map_regulation_type + extract_regulation)
                if "time limited" in regulation or "time limit" in regulation:
                    reg_type_counts["timeLimit"] += 1
                    # Check if it also creates residentialPermit (RPP exemption)
                    if "rpp" in exceptions:
                        reg_type_counts["residentialPermit"] += 1
                elif "residential permit" in regulation:
                    reg_type_counts["residentialPermit"] += 1
                elif "no parking" in regulation:
                    reg_type_counts["noParking"] += 1
                elif "metered" in regulation:
                    reg_type_counts["metered"] += 1
                elif "pay or permit" in regulation:
                    # Creates both metered and residentialPermit
                    reg_type_counts["metered"] += 1
                    reg_type_counts["residentialPermit"] += 1
                else:
                    reg_type_counts["other"] += 1

            file_counts["regulations"] = len(data.get("features", []))
            source_counts.update(reg_type_counts)
        except Exception as e:
            print(f"Warning: Could not load regulations file: {e}")

    # Street sweeping
    if source_files["sweeping"].exists():
        try:
            with open(source_files["sweeping"]) as f:
                data = json.load(f)
            count = len(data.get("features", []))
            file_counts["sweeping"] = count
            source_counts["streetCleaning"] += count
        except Exception as e:
            print(f"Warning: Could not load sweeping file: {e}")

    # Parking meters
    if source_files["meters"].exists():
        try:
            with open(source_files["meters"]) as f:
                data = json.load(f)
            count = len(data.get("features", []))
            file_counts["meters"] = count
            source_counts["metered"] += count
        except Exception as e:
            print(f"Warning: Could not load meters file: {e}")

    return source_counts, file_counts


def analyze_multi_rpp(blockface_data):
    """Analyze multi-RPP permit distribution."""
    blockfaces = blockface_data.get("blockfaces", [])

    single_zone = 0
    multi_zone = 0
    no_zone = 0
    multi_zone_examples = []
    zone_combinations = Counter()

    for bf in blockfaces:
        for reg in bf.get("regulations", []):
            if reg.get("type") == "residentialPermit":
                zones = reg.get("permitZones", [])
                if not zones or len(zones) == 0:
                    no_zone += 1
                elif len(zones) == 1:
                    single_zone += 1
                else:
                    multi_zone += 1
                    # Track zone combinations
                    zone_key = tuple(sorted(zones))
                    zone_combinations[zone_key] += 1

                    if len(multi_zone_examples) < 10:
                        multi_zone_examples.append({
                            "street": bf.get("street"),
                            "zones": zones,
                            "side": bf.get("side")
                        })

    total = single_zone + multi_zone + no_zone

    # Top zone combinations
    top_combinations = sorted(zone_combinations.items(), key=lambda x: -x[1])[:5]

    return {
        "total_permit_regulations": total,
        "single_zone": single_zone,
        "multi_zone": multi_zone,
        "no_zone": no_zone,
        "multi_zone_percent": (multi_zone / total * 100) if total > 0 else 0,
        "examples": multi_zone_examples,
        "top_combinations": top_combinations
    }


def print_analysis(blockface_path):
    """Print comprehensive analysis of blockface data."""
    # Load blockface output
    with open(blockface_path) as f:
        blockface_data = json.load(f)

    print("=" * 80)
    print("COMPREHENSIVE BLOCKFACE PIPELINE ANALYSIS")
    print("=" * 80)
    print(f"File: {blockface_path}")
    print()

    # Overall coverage
    print("=" * 80)
    print("OVERALL COVERAGE")
    print("=" * 80)
    coverage = analyze_coverage(blockface_data)
    print(f"Total blockfaces: {coverage['total_blockfaces']:,}")
    print(f"Blockfaces with regulations: {coverage['blockfaces_with_regulations']:,} ({coverage['coverage_percent']:.1f}%)")
    print(f"Blockfaces without regulations: {coverage['blockfaces_without_regulations']:,}")
    print(f"Total regulations: {coverage['total_regulations']:,}")
    print()

    # Regulation type breakdown
    print("REGULATION TYPE BREAKDOWN:")
    print("-" * 80)
    for reg_type, count in sorted(coverage['regulation_counts'].items(), key=lambda x: -x[1]):
        percent = (count / coverage['total_regulations'] * 100) if coverage['total_regulations'] > 0 else 0
        print(f"  {reg_type:<20} {count:>8,} ({percent:>5.1f}%)")
    print()

    # Street name quality
    print("STREET NAME QUALITY:")
    print("-" * 80)
    total_streets = coverage['named_streets'] + coverage['unknown_streets']
    named_pct = (coverage['named_streets'] / total_streets * 100) if total_streets > 0 else 0
    unknown_pct = (coverage['unknown_streets'] / total_streets * 100) if total_streets > 0 else 0
    print(f"  Named streets: {coverage['named_streets']:,} ({named_pct:.1f}%)")
    print(f"  Unknown streets: {coverage['unknown_streets']:,} ({unknown_pct:.1f}%)")
    print()

    # Side distribution
    print("SIDE DISTRIBUTION:")
    print("-" * 80)
    for side, count in sorted(coverage['side_counts'].items(), key=lambda x: -x[1]):
        percent = (count / coverage['total_blockfaces'] * 100) if coverage['total_blockfaces'] > 0 else 0
        print(f"  {side:<15} {count:>8,} ({percent:>5.1f}%)")
    print()

    # Top streets
    if coverage['top_streets']:
        print("TOP STREETS BY REGULATION COUNT:")
        print("-" * 80)
        for street, count in coverage['top_streets']:
            print(f"  {street:<40} {count:>6,} regulations")
        print()

    # Street cleaning sides
    print("=" * 80)
    print("STREET CLEANING SIDE COVERAGE")
    print("=" * 80)
    cleaning = analyze_street_cleaning_sides(blockface_data)
    print(f"Streets with street cleaning: {cleaning['total_streets_with_cleaning']:,}")
    one_pct = (cleaning['one_sided_count'] / cleaning['total_streets_with_cleaning'] * 100) if cleaning['total_streets_with_cleaning'] > 0 else 0
    both_pct = (cleaning['both_sided_count'] / cleaning['total_streets_with_cleaning'] * 100) if cleaning['total_streets_with_cleaning'] > 0 else 0
    print(f"Streets with ONE side only: {cleaning['one_sided_count']:,} ({one_pct:.1f}%)")
    print(f"Streets with BOTH sides: {cleaning['both_sided_count']:,} ({both_pct:.1f}%)")
    print()

    if cleaning['one_sided_streets']:
        print("Sample one-sided streets:")
        for street, data in list(cleaning['one_sided_streets'].items())[:10]:
            print(f"  {street} - {data['side']} side only ({data['count']} regulations)")

    if cleaning['both_sided_streets']:
        print()
        print("Sample both-sided streets:")
        for street, data in list(cleaning['both_sided_streets'].items())[:5]:
            print(f"  {street} - {', '.join(data['sides'])} sides ({data['count']} regulations)")
    print()

    # Multi-RPP analysis
    print("=" * 80)
    print("MULTI-RPP PERMIT ANALYSIS")
    print("=" * 80)
    multi_rpp = analyze_multi_rpp(blockface_data)
    print(f"Total residential permit regulations: {multi_rpp['total_permit_regulations']:,}")
    if multi_rpp['total_permit_regulations'] > 0:
        single_pct = (multi_rpp['single_zone'] / multi_rpp['total_permit_regulations'] * 100)
        multi_pct = (multi_rpp['multi_zone'] / multi_rpp['total_permit_regulations'] * 100)
        print(f"Single zone permits: {multi_rpp['single_zone']:,} ({single_pct:.1f}%)")
        print(f"Multi-zone permits: {multi_rpp['multi_zone']:,} ({multi_pct:.1f}%)")
        print(f"No zones: {multi_rpp['no_zone']:,}")

        if multi_rpp['top_combinations']:
            print()
            print("Top multi-zone combinations:")
            for zones, count in multi_rpp['top_combinations']:
                print(f"  Zones {', '.join(zones)}: {count:,} occurrences")

        if multi_rpp['examples']:
            print()
            print("Sample multi-zone permits:")
            for ex in multi_rpp['examples'][:5]:
                print(f"  {ex['street']} ({ex['side']}): Zones {', '.join(ex['zones'])}")
    print()

    # Match rate analysis
    print("=" * 80)
    print("MATCH RATE BY REGULATION TYPE")
    print("=" * 80)

    try:
        source_counts, file_counts = count_source_regulations()

        if file_counts:
            print("Source regulation counts:")
            for file_type, count in file_counts.items():
                print(f"  {file_type}: {count:,}")
            print(f"  Total raw features: {sum(file_counts.values()):,}")
            print()

        output_counts = coverage['regulation_counts']

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
                match_rate = 100.0 if output == 0 else 0.0

            diff = output - source

            print(f"{reg_type:<20} {source:>12,} {output:>12,} {match_rate:>11.1f}% {diff:>+12,}")

            total_source += source
            total_output += output

        print("-" * 80)
        if total_source > 0:
            overall_rate = (total_output / total_source) * 100
            total_diff = total_output - total_source
            print(f"{'TOTAL':<20} {total_source:>12,} {total_output:>12,} {overall_rate:>11.1f}% {total_diff:>+12,}")
        else:
            print(f"{'TOTAL':<20} {total_source:>12,} {total_output:>12,} {'N/A':>12} {0:>+12,}")
        print("=" * 80)
        print()

        print("NOTES:")
        print("  - Match rate = (Output / Source) × 100%")
        print("  - Negative differences indicate unmatched source regulations (spatial join miss)")
        print("  - Positive differences for RPP indicate multi-source creation (time limit + RPP exemption)")
        print("  - Multi-RPP consolidation reduced residentialPermit by ~706 (duplicate zones merged)")
        print("  - 'Pay or Permit' regulations create both metered and residentialPermit")
        print("  - Side determination is ~95% UNKNOWN (known limitation, requires popupinfo parsing)")
        print()

    except Exception as e:
        print(f"Could not perform match rate analysis: {e}")
        print("(Source GeoJSON files may not be available)")
        print()


def main():
    if len(sys.argv) > 1:
        blockface_path = sys.argv[1]
    else:
        blockface_path = "blockfaces_full_sf_20251128.json"

    if not Path(blockface_path).exists():
        print(f"Error: File not found: {blockface_path}")
        print(f"Usage: python {sys.argv[0]} <blockface_json_file>")
        sys.exit(1)

    print_analysis(blockface_path)


if __name__ == "__main__":
    main()
