#!/usr/bin/env python3
"""
Analyze coverage statistics for blockface data.
Shows breakdown by regulation type, geographic coverage, and data quality metrics.
"""

import json
import sys
from pathlib import Path
from collections import defaultdict, Counter

def analyze_coverage(json_path: str):
    """Analyze blockface coverage and generate detailed statistics"""

    with open(json_path, 'r') as f:
        data = json.load(f)

    blockfaces = data['blockfaces']
    total_blockfaces = len(blockfaces)

    print("=" * 80)
    print(f"COVERAGE ANALYSIS: {Path(json_path).name}")
    print("=" * 80)
    print(f"\nTotal Blockfaces: {total_blockfaces:,}")
    print()

    # Overall coverage metrics
    blockfaces_with_regs = sum(1 for bf in blockfaces if bf.get('regulations'))
    blockfaces_free = total_blockfaces - blockfaces_with_regs

    print("## OVERALL COVERAGE")
    print("-" * 80)
    print(f"  Blockfaces with regulations:  {blockfaces_with_regs:>6,} ({blockfaces_with_regs/total_blockfaces*100:5.1f}%)")
    print(f"  Free parking (no regulations): {blockfaces_free:>6,} ({blockfaces_free/total_blockfaces*100:5.1f}%)")
    print()

    # Regulation type breakdown
    reg_type_counts = Counter()
    total_regulations = 0

    for bf in blockfaces:
        for reg in bf.get('regulations', []):
            reg_type = reg.get('type', 'unknown')
            reg_type_counts[reg_type] += 1
            total_regulations += 1

    print("## REGULATIONS BY TYPE")
    print("-" * 80)
    print(f"  Total regulations: {total_regulations:,}\n")

    # Sort by count descending
    for reg_type, count in sorted(reg_type_counts.items(), key=lambda x: x[1], reverse=True):
        pct = count / total_regulations * 100 if total_regulations > 0 else 0
        print(f"  {reg_type:>20s}: {count:>6,} ({pct:5.1f}%)")
    print()

    # Blockfaces by regulation count
    reg_count_dist = Counter()
    for bf in blockfaces:
        reg_count = len(bf.get('regulations', []))
        reg_count_dist[reg_count] += 1

    print("## REGULATIONS PER BLOCKFACE DISTRIBUTION")
    print("-" * 80)
    for count in sorted(reg_count_dist.keys()):
        num_blockfaces = reg_count_dist[count]
        pct = num_blockfaces / total_blockfaces * 100
        if count == 0:
            label = "0 (free parking)"
        elif count == 1:
            label = "1 regulation"
        else:
            label = f"{count} regulations"
        print(f"  {label:>20s}: {num_blockfaces:>6,} blockfaces ({pct:5.1f}%)")
    print()

    # Street name quality
    named_streets = sum(1 for bf in blockfaces if bf.get('street') and bf['street'] != "Unknown Street")
    unknown_streets = total_blockfaces - named_streets

    print("## STREET NAME QUALITY")
    print("-" * 80)
    print(f"  Named streets:    {named_streets:>6,} ({named_streets/total_blockfaces*100:5.1f}%)")
    print(f"  Unknown streets:  {unknown_streets:>6,} ({unknown_streets/total_blockfaces*100:5.1f}%)")
    print()

    # Side distribution
    side_counts = Counter(bf.get('side', 'UNKNOWN') for bf in blockfaces)

    print("## BLOCKFACE SIDE DISTRIBUTION")
    print("-" * 80)
    for side, count in sorted(side_counts.items(), key=lambda x: x[1], reverse=True):
        pct = count / total_blockfaces * 100
        print(f"  {side:>10s}: {count:>6,} ({pct:5.1f}%)")
    print()

    # Top streets by regulation count
    street_reg_counts = defaultdict(int)
    for bf in blockfaces:
        street = bf.get('street', 'Unknown Street')
        street_reg_counts[street] += len(bf.get('regulations', []))

    print("## TOP 20 STREETS BY REGULATION COUNT")
    print("-" * 80)
    for street, count in sorted(street_reg_counts.items(), key=lambda x: x[1], reverse=True)[:20]:
        print(f"  {street[:50]:50s}: {count:>5,} regulations")
    print()

    # Coverage by regulation type (which blockfaces have each type)
    reg_type_blockface_coverage = defaultdict(int)
    for bf in blockfaces:
        reg_types_on_bf = set(reg.get('type') for reg in bf.get('regulations', []))
        for reg_type in reg_types_on_bf:
            reg_type_blockface_coverage[reg_type] += 1

    print("## BLOCKFACE COVERAGE BY REGULATION TYPE")
    print("-" * 80)
    for reg_type, count in sorted(reg_type_blockface_coverage.items(), key=lambda x: x[1], reverse=True):
        pct = count / total_blockfaces * 100
        print(f"  {reg_type:>20s}: {count:>6,} blockfaces ({pct:5.1f}%)")
    print()

    print("=" * 80)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_coverage.py <blockface_json_file>")
        sys.exit(1)

    json_path = sys.argv[1]
    if not Path(json_path).exists():
        print(f"Error: File not found: {json_path}")
        sys.exit(1)

    analyze_coverage(json_path)
