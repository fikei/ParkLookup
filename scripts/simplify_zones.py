#!/usr/bin/env python3
"""
Zone Polygon Simplification Script

This script preprocesses the SF parking zones JSON file to:
1. Merge all block-level polygons into unified zone boundaries
2. Simplify the resulting polygons to reduce point count
3. Extract just the outer boundary (street-facing edges)

Requirements:
    pip install shapely

Usage:
    python simplify_zones.py input.json output.json [--tolerance 0.0001]
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


def merge_zone_polygons(boundaries: List[List[Dict[str, float]]], tolerance: float) -> List[List[Dict[str, float]]]:
    """
    Merge all polygons for a zone into unified boundaries.

    Args:
        boundaries: List of boundary coordinate lists
        tolerance: Simplification tolerance in degrees (~0.0001 = 11m)

    Returns:
        List of simplified boundary coordinate lists
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

    # Union all polygons together
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


def process_zones(data: Dict[str, Any], tolerance: float, verbose: bool = True) -> Dict[str, Any]:
    """
    Process all zones in the data, merging and simplifying polygons.

    Args:
        data: The full zones JSON data
        tolerance: Simplification tolerance in degrees
        verbose: Whether to print progress

    Returns:
        Modified data with simplified zones
    """
    zones = data.get('zones', [])
    total_original_points = 0
    total_simplified_points = 0

    for i, zone in enumerate(zones):
        zone_id = zone.get('id', f'zone_{i}')
        permit_area = zone.get('permitArea', 'unknown')
        boundaries = zone.get('boundaries', [])

        # Count original points
        original_points = sum(len(b) for b in boundaries)
        total_original_points += original_points

        if verbose:
            print(f"Processing zone {permit_area} ({zone_id}): {len(boundaries)} boundaries, {original_points} points...", end=' ')

        # Merge and simplify
        simplified = merge_zone_polygons(boundaries, tolerance)

        # Count simplified points
        simplified_points = sum(len(b) for b in simplified)
        total_simplified_points += simplified_points

        if verbose:
            reduction = (1 - simplified_points / original_points) * 100 if original_points > 0 else 0
            print(f"-> {len(simplified)} boundaries, {simplified_points} points ({reduction:.1f}% reduction)")

        # Update zone
        zone['boundaries'] = simplified

    if verbose:
        total_reduction = (1 - total_simplified_points / total_original_points) * 100 if total_original_points > 0 else 0
        print(f"\nTotal: {total_original_points} -> {total_simplified_points} points ({total_reduction:.1f}% reduction)")

    return data


def main():
    parser = argparse.ArgumentParser(
        description='Simplify and merge zone polygons for faster map rendering'
    )
    parser.add_argument('input', help='Input JSON file path')
    parser.add_argument('output', help='Output JSON file path')
    parser.add_argument(
        '--tolerance', '-t',
        type=float,
        default=0.0001,
        help='Simplification tolerance in degrees (default: 0.0001 ≈ 11m)'
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
    processed = process_zones(data, args.tolerance, verbose=not args.quiet)

    print(f"Saving to {args.output}...")
    save_zones(processed, args.output)

    print("Done!")


if __name__ == '__main__':
    main()
