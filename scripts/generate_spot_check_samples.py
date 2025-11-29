#!/usr/bin/env python3
"""
Generate random samples of each regulation type for manual spot-checking accuracy.
Outputs addresses and regulation details for Google Street View verification.
"""

import json
import random
from typing import Dict, List

def load_blockfaces(path: str) -> List[Dict]:
    """Load blockface GeoJSON data"""
    with open(path, 'r') as f:
        data = json.load(f)
    # Handle both FeatureCollection and our custom format
    if 'features' in data:
        return data['features']
    elif 'blockfaces' in data:
        return data['blockfaces']
    else:
        return data

def get_address_range(blockface: Dict) -> str:
    """Get readable address range for a blockface"""
    # Handle both GeoJSON FeatureCollection and our custom format
    props = blockface.get('properties', blockface)
    street = props.get('street', 'Unknown Street')
    from_st = props.get('fromStreet', '')
    to_st = props.get('toStreet', '')
    side = props.get('side', '')

    if from_st and to_st:
        return f"{street} ({from_st} to {to_st}) - {side} side"
    else:
        return f"{street} - {side} side"

def get_center_coordinates(blockface: Dict) -> tuple:
    """Get approximate center coordinates of a blockface for Google Maps link"""
    coords = blockface['geometry']['coordinates']
    if not coords:
        return None, None

    # Find middle coordinate
    mid_idx = len(coords) // 2
    lon, lat = coords[mid_idx]
    return lat, lon

def collect_samples_by_type(blockfaces: List[Dict], samples_per_type: int = 5) -> Dict[str, List[Dict]]:
    """Collect random samples of each regulation type"""
    samples = {
        'streetCleaning': [],
        'metered': [],
        'timeLimit': [],
        'residentialPermit': [],
        'noParking': [],
        'towAway': []
    }

    # Collect all blockfaces with each regulation type
    for blockface in blockfaces:
        # Handle both GeoJSON FeatureCollection and our custom format
        props = blockface.get('properties', blockface)
        regulations = props.get('regulations', [])
        for reg in regulations:
            reg_type = reg.get('type')
            if reg_type in samples and len(samples[reg_type]) < 100:  # Collect pool of candidates
                samples[reg_type].append({
                    'blockface': blockface,
                    'regulation': reg
                })

    # Randomly sample from each type
    result = {}
    for reg_type, candidates in samples.items():
        if len(candidates) > samples_per_type:
            result[reg_type] = random.sample(candidates, samples_per_type)
        else:
            result[reg_type] = candidates

    return result

def format_regulation_description(reg: Dict) -> str:
    """Format regulation details for display"""
    reg_type = reg.get('type', 'unknown')

    if reg_type == 'streetCleaning':
        days = reg.get('enforcementDays', [])
        start = reg.get('enforcementStart', '')
        end = reg.get('enforcementEnd', '')
        special = reg.get('specialConditions', '')

        parts = [f"Street Cleaning"]
        if days:
            parts.append(f"Days: {', '.join(d.capitalize() for d in days)}")
        if start and end:
            parts.append(f"Hours: {start}-{end}")
        if special:
            parts.append(f"Pattern: {special}")
        return " | ".join(parts)

    elif reg_type == 'metered':
        return "Metered Parking | Check for parking meter presence"

    elif reg_type == 'timeLimit':
        limit = reg.get('timeLimit', 0)
        hours = limit // 60
        minutes = limit % 60
        time_str = f"{hours}h {minutes}m" if minutes else f"{hours} hour"

        days = reg.get('enforcementDays', [])
        start = reg.get('enforcementStart', '')
        end = reg.get('enforcementEnd', '')

        parts = [f"Time Limit: {time_str}"]
        if days:
            parts.append(f"Days: {', '.join(d.capitalize() for d in days)}")
        if start and end:
            parts.append(f"Hours: {start}-{end}")
        return " | ".join(parts)

    elif reg_type == 'residentialPermit':
        zone = reg.get('permitZone', 'Unknown')
        limit = reg.get('timeLimit')

        parts = [f"RPP Zone {zone}"]
        if limit:
            hours = limit // 60
            parts.append(f"Visitor limit: {hours} hours")
        return " | ".join(parts)

    elif reg_type == 'noParking':
        days = reg.get('enforcementDays', [])
        start = reg.get('enforcementStart', '')
        end = reg.get('enforcementEnd', '')

        parts = ["No Parking"]
        if days:
            parts.append(f"Days: {', '.join(d.capitalize() for d in days)}")
        if start and end:
            parts.append(f"Hours: {start}-{end}")
        else:
            parts.append("Anytime")
        return " | ".join(parts)

    elif reg_type == 'towAway':
        return "Tow-Away Zone"

    return reg_type

def generate_google_maps_link(lat: float, lon: float) -> str:
    """Generate Google Maps Street View link"""
    return f"https://www.google.com/maps/@{lat},{lon},3a,75y,0h,90t/data=!3m6!1e1!3m4!1s0!2e0!7i16384!8i8192"

def main():
    # Use Path for cross-platform compatibility
    from pathlib import Path
    project_root = Path(__file__).parent.parent
    blockfaces_path = project_root / "SFParkingZoneFinder" / "SFParkingZoneFinder" / "Resources" / "sample_blockfaces.json"

    print("Loading blockface data...")
    blockfaces = load_blockfaces(str(blockfaces_path))

    print("Collecting samples...")
    samples = collect_samples_by_type(blockfaces, samples_per_type=5)

    print("\n" + "="*80)
    print("SPOT CHECK SAMPLES - Manual Verification Required")
    print("="*80)
    print("\nInstructions:")
    print("1. Click the Google Maps link for each sample")
    print("2. Verify the regulation matches what you see on street signs")
    print("3. Record: CORRECT ✓ or INCORRECT ✗")
    print("4. Calculate accuracy: (correct / total) per regulation type")
    print("="*80 + "\n")

    total_samples = 0
    for reg_type, sample_list in samples.items():
        if not sample_list:
            continue

        print(f"\n{'='*80}")
        print(f"{reg_type.upper()} - {len(sample_list)} samples")
        print(f"{'='*80}\n")

        for i, sample in enumerate(sample_list, 1):
            blockface = sample['blockface']
            regulation = sample['regulation']

            address = get_address_range(blockface)
            lat, lon = get_center_coordinates(blockface)
            reg_desc = format_regulation_description(regulation)

            print(f"Sample {i}:")
            print(f"  Location: {address}")
            print(f"  Regulation: {reg_desc}")

            if lat and lon:
                gmaps_link = generate_google_maps_link(lat, lon)
                print(f"  Street View: {gmaps_link}")
            else:
                print(f"  Street View: [Coordinates not available]")

            print(f"  Verification: [ ] CORRECT  [ ] INCORRECT")
            print()

            total_samples += 1

    print(f"\n{'='*80}")
    print(f"Total samples to verify: {total_samples}")
    print(f"Target accuracy: >80% per regulation type")
    print(f"{'='*80}\n")

    # Save samples to JSON for potential automated checking later
    output_data = {}
    for reg_type, sample_list in samples.items():
        output_data[reg_type] = []
        for sample in sample_list:
            blockface = sample['blockface']
            regulation = sample['regulation']
            lat, lon = get_center_coordinates(blockface)

            output_data[reg_type].append({
                'address': get_address_range(blockface),
                'regulation': regulation,
                'coordinates': {'lat': lat, 'lon': lon},
                'street_view_link': generate_google_maps_link(lat, lon) if lat and lon else None
            })

    from pathlib import Path
    project_root = Path(__file__).parent.parent
    output_path = project_root / "data" / "validation" / "spot_check_samples.json"

    with open(output_path, 'w') as f:
        json.dump(output_data, f, indent=2)

    print(f"Samples saved to: {output_path}\n")

if __name__ == '__main__':
    random.seed(42)  # For reproducible samples
    main()
