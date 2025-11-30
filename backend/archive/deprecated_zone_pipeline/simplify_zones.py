#!/usr/bin/env python3
"""
Zone Polygon Simplification Script

This script preprocesses the SF parking zones JSON file to:
1. Simplify individual block polygons to reduce vertex count (default)
2. Optionally merge adjacent blocks within the same zone (--merge flag)

Key behaviors:
- Zone boundaries are ALWAYS preserved (Zone A never merges with Zone B)
- By default, city blocks stay as separate polygons (just simplified)
- With --merge, adjacent blocks of the SAME zone combine into larger polygons

Requirements:
    pip install shapely

Usage:
    # Simplify blocks individually (preserves block boundaries)
    python simplify_zones.py input.json output.json

    # Merge blocks within zones (creates zone-level polygons)
    python simplify_zones.py input.json output.json --merge

    # Custom tolerance (default 0.00005 ~= 5.5m)
    python simplify_zones.py input.json output.json --tolerance 0.0001
"""

import json
import argparse
import sys
from typing import List, Dict, Any, Tuple
from collections import defaultdict

try:
    from shapely.geometry import Polygon, MultiPolygon, mapping
    from shapely.ops import unary_union
    from shapely.validation import make_valid
    SHAPELY_AVAILABLE = True
except ImportError:
    SHAPELY_AVAILABLE = False
    print("Warning: Shapely not installed. Install with: pip install shapely")


def load_zones(input_path: str) -> Dict[str, Any]:
    """Load the zones JSON file."""
    with open(input_path, 'r') as f:
        return json.load(f)


def save_zones(data: Dict[str, Any], output_path: str):
    """Save the zones JSON file."""
    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)


def coords_to_polygon(coords: List[Dict[str, float]]) -> Polygon:
    """Convert a list of {latitude, longitude} dicts to a Shapely Polygon."""
    points = [(c['longitude'], c['latitude']) for c in coords]
    if len(points) < 3:
        return None
    # Ensure polygon is closed
    if points[0] != points[-1]:
        points.append(points[0])
    try:
        poly = Polygon(points)
        if not poly.is_valid:
            poly = make_valid(poly)
        return poly if poly.is_valid and not poly.is_empty else None
    except Exception as e:
        print(f"  Warning: Could not create polygon: {e}")
        return None


def polygon_to_coords(poly: Polygon) -> List[Dict[str, float]]:
    """Convert a Shapely Polygon back to {latitude, longitude} dicts."""
    if poly is None or poly.is_empty:
        return []
    coords = list(poly.exterior.coords)
    return [{'latitude': lat, 'longitude': lon} for lon, lat in coords]


def multipolygon_to_coords(geom) -> List[List[Dict[str, float]]]:
    """Convert a Shapely geometry to list of coordinate lists."""
    if geom is None or geom.is_empty:
        return []

    if isinstance(geom, Polygon):
        coords = polygon_to_coords(geom)
        return [coords] if coords else []
    elif isinstance(geom, MultiPolygon):
        result = []
        for poly in geom.geoms:
            coords = polygon_to_coords(poly)
            if coords:
                result.append(coords)
        return result
    else:
        # Handle GeometryCollection or other types
        try:
            if hasattr(geom, 'geoms'):
                result = []
                for g in geom.geoms:
                    result.extend(multipolygon_to_coords(g))
                return result
        except:
            pass
        return []


def simplify_block(boundary: List[Dict[str, float]], tolerance: float) -> List[Dict[str, float]]:
    """
    Simplify a single block polygon while preserving its shape.

    Args:
        boundary: List of {latitude, longitude} coordinates
        tolerance: Simplification tolerance in degrees (~0.00005 = 5.5m)

    Returns:
        Simplified coordinate list
    """
    if not SHAPELY_AVAILABLE:
        return boundary

    poly = coords_to_polygon(boundary)
    if poly is None:
        return boundary

    # Simplify the polygon
    if tolerance > 0:
        try:
            simplified = poly.simplify(tolerance, preserve_topology=True)
            if simplified.is_valid and not simplified.is_empty:
                poly = simplified
        except Exception as e:
            print(f"  Warning: Simplification failed: {e}")

    # Handle case where make_valid() returned a MultiPolygon or GeometryCollection
    if isinstance(poly, Polygon):
        return polygon_to_coords(poly)
    elif isinstance(poly, MultiPolygon):
        # Return the largest polygon from the MultiPolygon
        largest = max(poly.geoms, key=lambda p: p.area)
        return polygon_to_coords(largest)
    else:
        # For other geometry types, try to extract polygons
        coords_list = multipolygon_to_coords(poly)
        return coords_list[0] if coords_list else boundary


def merge_zone_polygons(boundaries: List[List[Dict[str, float]]], tolerance: float) -> List[List[Dict[str, float]]]:
    """
    Merge all block polygons for a zone into unified boundaries.
    Adjacent blocks of the SAME zone will be combined.

    Args:
        boundaries: List of boundary coordinate lists
        tolerance: Simplification tolerance in degrees (~0.0001 = 11m)

    Returns:
        List of merged/simplified boundary coordinate lists
    """
    if not SHAPELY_AVAILABLE:
        return boundaries

    # Convert all boundaries to Shapely polygons
    polygons = []
    for boundary in boundaries:
        poly = coords_to_polygon(boundary)
        if poly is not None:
            polygons.append(poly)

    if not polygons:
        return boundaries

    # Union all polygons together (merges adjacent blocks)
    try:
        merged = unary_union(polygons)
        if not merged.is_valid:
            merged = make_valid(merged)
    except Exception as e:
        print(f"  Warning: Union failed: {e}")
        return boundaries

    # Simplify the result
    if tolerance > 0:
        try:
            merged = merged.simplify(tolerance, preserve_topology=True)
        except Exception as e:
            print(f"  Warning: Simplification failed: {e}")

    # Convert back to coordinate format
    return multipolygon_to_coords(merged)


def process_zones(data: Dict[str, Any], tolerance: float, merge: bool = False, verbose: bool = True) -> Dict[str, Any]:
    """
    Process all zones in the data.

    Args:
        data: The full zones JSON data
        tolerance: Simplification tolerance in degrees
        merge: If True, merge adjacent blocks within each zone. If False, simplify blocks individually.
        verbose: Whether to print progress

    Returns:
        Modified data with simplified zones
    """
    zones = data.get('zones', [])
    total_original_points = 0
    total_simplified_points = 0
    total_original_blocks = 0
    total_simplified_blocks = 0

    mode = "MERGE" if merge else "SIMPLIFY"
    if verbose:
        print(f"\nMode: {mode} (blocks {'will be merged' if merge else 'stay separate'})\n")

    for i, zone in enumerate(zones):
        zone_id = zone.get('id', f'zone_{i}')
        permit_area = zone.get('permitArea', 'unknown')
        boundaries = zone.get('boundaries', [])

        # Count original stats
        original_blocks = len(boundaries)
        original_points = sum(len(b) for b in boundaries)
        total_original_points += original_points
        total_original_blocks += original_blocks

        if verbose:
            print(f"Processing zone {permit_area} ({zone_id}): {original_blocks} blocks, {original_points} points...", end=' ')

        if merge:
            # Merge adjacent blocks within zone, then simplify
            simplified = merge_zone_polygons(boundaries, tolerance)
        else:
            # Simplify each block individually (preserves block structure)
            simplified = []
            for boundary in boundaries:
                simplified_block = simplify_block(boundary, tolerance)
                if simplified_block and len(simplified_block) >= 3:
                    simplified.append(simplified_block)

        # Count simplified stats
        simplified_blocks = len(simplified)
        simplified_points = sum(len(b) for b in simplified)
        total_simplified_points += simplified_points
        total_simplified_blocks += simplified_blocks

        if verbose:
            point_reduction = (1 - simplified_points / original_points) * 100 if original_points > 0 else 0
            if merge:
                print(f"-> {simplified_blocks} polygons, {simplified_points} points ({point_reduction:.1f}% reduction)")
            else:
                print(f"-> {simplified_points} points ({point_reduction:.1f}% reduction)")

        # Update zone
        zone['boundaries'] = simplified

    if verbose:
        total_point_reduction = (1 - total_simplified_points / total_original_points) * 100 if total_original_points > 0 else 0
        print(f"\n{'='*60}")
        print(f"Total blocks: {total_original_blocks} -> {total_simplified_blocks}")
        print(f"Total points: {total_original_points} -> {total_simplified_points} ({total_point_reduction:.1f}% reduction)")

    return data


def main():
    parser = argparse.ArgumentParser(
        description='Simplify zone polygons for faster map rendering',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Simplify blocks individually (default - preserves block boundaries)
  python simplify_zones.py sf_parking_zones.json sf_parking_zones_simplified.json

  # Merge adjacent blocks within each zone
  python simplify_zones.py sf_parking_zones.json sf_parking_zones_merged.json --merge

  # More aggressive simplification
  python simplify_zones.py input.json output.json --tolerance 0.0002
"""
    )
    parser.add_argument('input', help='Input JSON file path')
    parser.add_argument('output', help='Output JSON file path')
    parser.add_argument(
        '--tolerance', '-t',
        type=float,
        default=0.00005,
        help='Simplification tolerance in degrees (default: 0.00005 ~= 5.5m)'
    )
    parser.add_argument(
        '--merge', '-m',
        action='store_true',
        help='Merge adjacent blocks within each zone (default: keep blocks separate)'
    )
    parser.add_argument(
        '--quiet', '-q',
        action='store_true',
        help='Suppress progress output'
    )

    args = parser.parse_args()

    if not SHAPELY_AVAILABLE:
        print("Error: Shapely is required. Install with: pip install shapely")
        sys.exit(1)

    print(f"Loading {args.input}...")
    data = load_zones(args.input)

    print(f"Processing {len(data.get('zones', []))} zones with tolerance {args.tolerance}...")
    processed = process_zones(data, args.tolerance, merge=args.merge, verbose=not args.quiet)

    print(f"\nSaving to {args.output}...")
    save_zones(processed, args.output)

    print("Done!")


if __name__ == '__main__':
    main()
