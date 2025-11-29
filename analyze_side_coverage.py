#!/usr/bin/env python3
"""
Analyze street cleaning coverage on both sides of streets.
"""

import json
from collections import defaultdict

# Load the side-aware data
with open('sample_blockfaces_sideaware_full.json', 'r') as f:
    data = json.load(f)

blockfaces = data['blockfaces']

# Group by street name and count which sides have street cleaning
street_sides = defaultdict(lambda: {'EVEN': 0, 'ODD': 0, 'other': {}})

for bf in blockfaces:
    street = bf['street']
    side = bf['side']
    has_cleaning = sum(1 for reg in bf.get('regulations', []) if reg['type'] == 'streetCleaning')

    if has_cleaning > 0:
        if side == 'EVEN':
            street_sides[street]['EVEN'] += has_cleaning
        elif side == 'ODD':
            street_sides[street]['ODD'] += has_cleaning
        else:
            street_sides[street]['other'][side] = street_sides[street]['other'].get(side, 0) + has_cleaning

# Analyze coverage
one_sided_streets = []
two_sided_streets = []
named_streets = []  # Streets with actual names (not "Unknown Street")

for street, sides in street_sides.items():
    even_count = sides['EVEN']
    odd_count = sides['ODD']
    other_count = sum(sides['other'].values())

    total_sides = (1 if even_count > 0 else 0) + (1 if odd_count > 0 else 0) + (1 if other_count > 0 else 0)

    # Skip Unknown Street for detailed analysis
    if street != "Unknown Street":
        named_streets.append(street)

        if total_sides == 1:
            which_side = 'EVEN' if even_count > 0 else ('ODD' if odd_count > 0 else list(sides['other'].keys())[0])
            one_sided_streets.append((street, which_side, even_count + odd_count + other_count))
        elif total_sides >= 2:
            two_sided_streets.append((street, even_count, odd_count, other_count))

print(f"STREET CLEANING SIDE COVERAGE ANALYSIS")
print(f"=" * 70)
print(f"\nNamed streets with street cleaning: {len(named_streets)}")
print(f"Streets with ONE side only: {len(one_sided_streets)} ({len(one_sided_streets)/len(named_streets)*100 if named_streets else 0:.1f}%)")
print(f"Streets with BOTH sides: {len(two_sided_streets)} ({len(two_sided_streets)/len(named_streets)*100 if named_streets else 0:.1f}%)")

print(f"\nFirst 20 one-sided streets:")
for street, side, count in sorted(one_sided_streets)[:20]:
    print(f"  {street} - {side} side only ({count} regulations)")

print(f"\nSample two-sided streets:")
for street, even, odd, other in sorted(two_sided_streets)[:15]:
    sides_str = []
    if even > 0:
        sides_str.append(f"EVEN({even})")
    if odd > 0:
        sides_str.append(f"ODD({odd})")
    if other > 0:
        sides_str.append(f"OTHER({other})")
    print(f"  {street} - {', '.join(sides_str)}")

# Check Unknown Street separately
if "Unknown Street" in street_sides:
    unknown = street_sides["Unknown Street"]
    print(f"\n'Unknown Street' blockfaces:")
    print(f"  EVEN side: {unknown['EVEN']} regulations")
    print(f"  ODD side: {unknown['ODD']} regulations")
    print(f"  Other sides: {sum(unknown['other'].values())} regulations")
