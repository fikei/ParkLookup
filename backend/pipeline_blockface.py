#!/usr/bin/env python3
"""
Convert SF GeoJSON blockfaces to app's JSON format WITH parking regulations.

This script performs a spatial join between:
- Blockfaces_20251128.geojson (18,355 street centerlines)
- Parking_regulations_20251128.geojson (7,784 regulations)

It uses Shapely for spatial matching and populates the regulations[] field
on each blockface with matched parking rules.
"""

import json
import re
import sys
from typing import List, Dict, Optional, Tuple
from shapely.geometry import LineString, MultiLineString, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree  # Spatial index for fast lookups
from collections import defaultdict

# Mission District bounds for filtering
BOUNDS = {
    "min_lat": 37.744,   # South: Cesar Chavez (~26th St)
    "max_lat": 37.780,   # North: Market St
    "min_lon": -122.426, # West: Dolores St
    "max_lon": -122.407  # East: Potrero Ave
}

# Buffer distance for spatial matching (meters converted to degrees, ~15m)
BUFFER_DISTANCE = 0.000135  # ~15 meters at SF latitude

# Priority order for regulations (lower number = higher priority / more restrictive)
REGULATION_PRIORITY = {
    "noParking": 1,        # Highest - can't park at all
    "towAway": 2,          # Very high - serious consequence
    "streetCleaning": 3,   # High - temporary tow-away
    "metered": 4,          # Medium-high - requires payment
    "timeLimit": 5,        # Medium - limited duration
    "residentialPermit": 6,# Medium-low - permit requirement
    "loadingZone": 7,      # Low - special use
    "other": 8             # Lowest - misc restrictions
}


def get_regulation_priority(regulation: Dict) -> int:
    """
    Get priority value for a regulation. Lower number = higher priority.
    Used to sort regulations by restrictiveness.
    """
    reg_type = regulation.get('type', 'other')
    return REGULATION_PRIORITY.get(reg_type, 99)


def sort_regulations_by_priority(regulations: List[Dict]) -> List[Dict]:
    """
    Sort regulations by priority (most restrictive first).
    Secondary sort by type name for consistency.
    """
    return sorted(regulations, key=lambda r: (get_regulation_priority(r), r.get('type', '')))


def normalize_street_name(name: str) -> str:
    """
    Normalize street name from abbreviated format (corridor) to full format (blockface).

    Examples:
        "Market St" → "Market Street"
        "08th Ave" → "8th Avenue"
        "Lower Great Hwy" → "Lower Great Highway"
        "Alemany Blvd" → "Alemany Boulevard"
    """
    if not name or not name.strip():
        return "Unknown Street"

    # Strip whitespace
    name = name.strip()

    # Remove leading zeros from numbered streets (e.g., "08th" → "8th", "03rd" → "3rd")
    name = re.sub(r'\b0+(\d)', r'\1', name)

    # Expand common abbreviations at end of street name
    abbreviations = {
        r'\bSt\b': 'Street',
        r'\bAve\b': 'Avenue',
        r'\bBlvd\b': 'Boulevard',
        r'\bDr\b': 'Drive',
        r'\bRd\b': 'Road',
        r'\bLn\b': 'Lane',
        r'\bCt\b': 'Court',
        r'\bPl\b': 'Place',
        r'\bTer\b': 'Terrace',
        r'\bHwy\b': 'Highway',
        r'\bPkwy\b': 'Parkway',
        r'\bCir\b': 'Circle',
        r'\bWay\b': 'Way',
    }

    for abbrev, full in abbreviations.items():
        name = re.sub(abbrev + r'$', full, name)

    return name


def parse_side_from_popupinfo(popupinfo: str) -> str:
    """
    Extract side from popupinfo field using explicit source data.

    Format: "Street between From and To, side"
    Example: "Valencia Street between 17th St and 16th St, west side" → "WEST"

    Returns cardinal directions (NORTH, SOUTH, EAST, WEST) directly from source data.
    This is more accurate than geometric calculation and works for curved streets.

    Coverage: ~95% of blockfaces have explicit side information in popupinfo.
    Accuracy: 100% when present (authoritative source data).
    """
    if not popupinfo:
        return "UNKNOWN"

    popupinfo_lower = popupinfo.lower()

    # Extract explicit cardinal directions from source data
    if "north side" in popupinfo_lower:
        return "NORTH"
    elif "south side" in popupinfo_lower:
        return "SOUTH"
    elif "east side" in popupinfo_lower:
        return "EAST"
    elif "west side" in popupinfo_lower:
        return "WEST"

    return "UNKNOWN"


def parse_street_info(popupinfo: str) -> Dict[str, str]:
    """
    Parse popupinfo to extract street, from, to.
    Format: "Street between From and To, side"
    """
    if not popupinfo:
        return {
            'street': 'Unknown Street',
            'from': 'Unknown',
            'to': 'Unknown'
        }

    # Try to parse "Street between From and To, side" format
    if " between " in popupinfo and " and " in popupinfo:
        parts = popupinfo.split(" between ")
        if len(parts) == 2:
            street = parts[0].strip()
            rest = parts[1]

            # Split on ", " to remove side info
            if ", " in rest:
                rest = rest.split(", ")[0]

            # Split on " and " to get from/to
            if " and " in rest:
                from_to = rest.split(" and ")
                if len(from_to) == 2:
                    return {
                        'street': street,
                        'from': from_to[0].strip(),
                        'to': from_to[1].strip()
                    }

    # Fallback: use the whole thing as street name
    return {
        'street': popupinfo.split(',')[0].strip() if ',' in popupinfo else popupinfo.strip(),
        'from': 'Unknown',
        'to': 'Unknown'
    }


def is_in_bounds(coords: List[List[float]]) -> bool:
    """Check if coordinates are within Mission District bounds"""
    if not coords or len(coords) < 1:
        return False

    lon, lat = coords[0]
    return (BOUNDS['min_lat'] <= lat <= BOUNDS['max_lat'] and
            BOUNDS['min_lon'] <= lon <= BOUNDS['max_lon'])


def parse_days_to_array(days_str: str) -> List[str]:
    """
    Convert days string to array of weekday names.
    Examples:
      "M-F" -> ["monday", "tuesday", "wednesday", "thursday", "friday"]
      "M-Sa" -> ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
      "DAILY" -> ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
      "Tu/Th" -> ["tuesday", "thursday"]
    """
    if not days_str:
        return None

    days_str = days_str.strip().upper()

    if days_str == "DAILY" or days_str == "M-SU":
        return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    elif days_str == "M-F":
        return ["monday", "tuesday", "wednesday", "thursday", "friday"]
    elif days_str == "M-SA":
        return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    # Handle day codes (M, Tu, W, Th, F, Sa, Su)
    day_map = {
        "M": "monday",
        "TU": "tuesday",
        "W": "wednesday",
        "TH": "thursday",
        "F": "friday",
        "SA": "saturday",
        "SU": "sunday"
    }

    # Try to parse patterns like "Tu/Th" or "M/W/F"
    days = []
    for code in days_str.replace("/", " ").split():
        if code in day_map:
            days.append(day_map[code])

    return days if days else None


def parse_time_to_format(time_str: str) -> Optional[str]:
    """
    Convert time string to HH:MM format.
    Examples:
      "900" -> "09:00"
      "1800" -> "18:00"
      "2400" -> "00:00"
    """
    if not time_str:
        return None

    # Handle string numbers like "900", "1800"
    time_str = str(time_str).strip()

    # Pad to 4 digits if needed
    if len(time_str) <= 2:
        time_str = time_str.zfill(2) + "00"
    elif len(time_str) == 3:
        time_str = "0" + time_str

    # Extract hours and minutes
    if len(time_str) >= 4:
        hours = int(time_str[:-2])
        minutes = int(time_str[-2:])

        # Handle 2400 as midnight
        if hours >= 24:
            hours = 0

        return f"{hours:02d}:{minutes:02d}"

    return None


def map_regulation_type(regulation: str) -> str:
    """
    Map DataSF regulation types to app's BlockfaceRegulation types.
    """
    if not regulation:
        return "other"

    regulation = regulation.strip().lower()

    mapping = {
        "time limited": "timeLimit",
        "residential permit": "residentialPermit",
        "no parking any time": "noParking",
        "no parking anytime": "noParking",
        "street cleaning": "streetCleaning",
        "metered parking": "metered",
        "pay or permit": "metered",  # Will also create residentialPermit
        "tow-away zone": "towAway",
        "tow away": "towAway",
        "loading zone": "loadingZone",
        "no oversized vehicles": "other",  # Not a standard type
    }

    return mapping.get(regulation, "other")


def extract_regulation(reg_props: Dict) -> List[Dict]:
    """
    Extract regulation data from GeoJSON properties and map to app schema.

    Returns a list because some regulation types (e.g., "Pay or Permit")
    should create multiple regulations.
    """
    regulation_type_raw = reg_props.get("regulation", "") or ""
    regulation_type = map_regulation_type(regulation_type_raw)

    # Parse time fields
    days = parse_days_to_array(reg_props.get("days"))
    enforcement_start = parse_time_to_format(reg_props.get("hrs_begin"))
    enforcement_end = parse_time_to_format(reg_props.get("hrs_end"))

    # Extract RPP zones (can have multiple)
    permit_zones = []
    for rpp_field in ["rpparea1", "rpparea2", "rpparea3"]:
        zone = reg_props.get(rpp_field)
        if zone and zone.strip():
            permit_zones.append(zone.strip())

    # Parse time limit (convert hours to minutes)
    time_limit = None
    hrlimit = reg_props.get("hrlimit")
    if hrlimit:
        try:
            hours = float(hrlimit)
            time_limit = int(hours * 60)
        except (ValueError, TypeError):
            pass

    # Get exceptions
    exceptions = reg_props.get("exceptions")

    regulations = []

    # Handle "Pay or Permit" - create both metered and residentialPermit
    if regulation_type_raw.lower() == "pay or permit":
        # Create metered regulation
        regulations.append({
            "type": "metered",
            "permitZone": None,
            "permitZones": None,
            "timeLimit": time_limit,
            "meterRate": None,  # Not in current dataset
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

        # Create residentialPermit regulation with multi-RPP support
        regulations.append({
            "type": "residentialPermit",
            "permitZone": permit_zones[0] if permit_zones else None,  # Backward compatibility
            "permitZones": permit_zones if permit_zones else None,    # Multi-RPP support
            "timeLimit": None,
            "meterRate": None,
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

    # Handle time limit with RPP zone - create both regulations
    elif regulation_type == "timeLimit" and permit_zones:
        # Create time limit regulation
        regulations.append({
            "type": "timeLimit",
            "permitZone": None,
            "permitZones": None,
            "timeLimit": time_limit,
            "meterRate": None,
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

        # Create residentialPermit regulation with multi-RPP support
        regulations.append({
            "type": "residentialPermit",
            "permitZone": permit_zones[0] if permit_zones else None,  # Backward compatibility
            "permitZones": permit_zones if permit_zones else None,    # Multi-RPP support
            "timeLimit": None,
            "meterRate": None,
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": f"Exempt from time limits. {exceptions}" if exceptions else "Exempt from time limits"
        })

    # Standard single regulation
    else:
        regulations.append({
            "type": regulation_type,
            "permitZone": permit_zones[0] if permit_zones else None,  # Backward compatibility
            "permitZones": permit_zones if permit_zones else None,    # Multi-RPP support
            "timeLimit": time_limit,
            "meterRate": None,
            "enforcementDays": days,
            "enforcementStart": enforcement_start,
            "enforcementEnd": enforcement_end,
            "specialConditions": exceptions
        })

    return regulations


def parse_week_pattern(props: Dict) -> str:
    """Convert week1-week5 bits to human-readable string"""
    weeks = [
        props.get('week1', 0),
        props.get('week2', 0),
        props.get('week3', 0),
        props.get('week4', 0),
        props.get('week5', 0)
    ]
    week_names = ["1st", "2nd", "3rd", "4th", "5th"]

    # Convert to int and check if active (handles both string "1" and int 1)
    active_weeks = [week_names[i] for i, active in enumerate(weeks) if int(active) == 1]

    if len(active_weeks) == 5:
        return "Street cleaning every week"
    elif len(active_weeks) == 0:
        return "Street cleaning (schedule TBD)"
    elif set(active_weeks) == {"1st", "3rd"} or set(active_weeks) == {"1st", "3rd", "5th"}:
        return "Street cleaning on odd weeks"
    elif set(active_weeks) == {"2nd", "4th"}:
        return "Street cleaning on even weeks"
    else:
        if len(active_weeks) > 1:
            weeks_str = ", ".join(active_weeks[:-1]) + " and " + active_weeks[-1]
        else:
            weeks_str = active_weeks[0]
        return f"Street cleaning {weeks_str} week of month"


def extract_street_sweeping(props: Dict) -> Dict:
    """Extract street sweeping fields and map to app schema"""

    # Parse weekday - handle abbreviations
    weekday = props.get('weekday', '').strip().lower()
    weekday_map = {
        'mon': 'monday',
        'tues': 'tuesday',
        'tue': 'tuesday',
        'wed': 'wednesday',
        'thurs': 'thursday',
        'thu': 'thursday',
        'fri': 'friday',
        'sat': 'saturday',
        'sun': 'sunday',
        'holiday': 'holiday'
    }

    # Map abbreviation to full name
    for abbrev, full_name in weekday_map.items():
        if weekday.startswith(abbrev):
            weekday = full_name
            break

    # Format time
    fromhour = props.get('fromhour', 0)
    tohour = props.get('tohour', 0)

    try:
        enforcement_start = f"{int(fromhour):02d}:00"
        enforcement_end = f"{int(tohour):02d}:00"
    except (ValueError, TypeError):
        enforcement_start = "00:00"
        enforcement_end = "00:00"

    # Parse week pattern
    special_conditions = parse_week_pattern(props)

    # Preserve source street name for backfilling
    corridor = props.get('corridor', '').strip()

    return {
        "type": "streetCleaning",
        "permitZone": None,
        "permitZones": None,
        "timeLimit": None,
        "meterRate": None,
        "enforcementDays": [weekday] if weekday else None,
        "enforcementStart": enforcement_start,
        "enforcementEnd": enforcement_end,
        "specialConditions": special_conditions,
        "_sourceStreet": corridor if corridor else None  # For backfilling blockface names
    }


def load_regulations(regulations_path: str) -> List[Tuple[MultiLineString, Dict]]:
    """
    Load regulations GeoJSON and extract geometries + properties.
    Returns list of (geometry, properties) tuples.
    """
    print(f"Loading regulations from: {regulations_path}")

    with open(regulations_path, 'r') as f:
        data = json.load(f)

    regulations = []
    skipped = 0

    for feature in data['features']:
        geom = feature.get('geometry')
        props = feature.get('properties', {})

        if not geom or geom.get('type') != 'MultiLineString':
            skipped += 1
            continue

        try:
            # Convert GeoJSON to Shapely geometry
            shapely_geom = shape(geom)
            regulations.append((shapely_geom, props))
        except Exception as e:
            skipped += 1
            continue

    print(f"  ✓ Loaded {len(regulations)} regulations ({skipped} skipped)")
    return regulations


def load_street_sweeping(sweeping_path: str) -> List[Tuple[LineString, Dict]]:
    """
    Load street sweeping GeoJSON and extract geometries + properties.
    Returns list of (geometry, properties) tuples.
    """
    print(f"Loading street sweeping from: {sweeping_path}")

    with open(sweeping_path, 'r') as f:
        data = json.load(f)

    sweeping_regs = []
    skipped = 0

    for feature in data['features']:
        geom = feature.get('geometry')
        props = feature.get('properties', {})

        if not geom or geom.get('type') != 'LineString':
            skipped += 1
            continue

        try:
            # Convert GeoJSON to Shapely geometry
            shapely_geom = shape(geom)
            sweeping_regs.append((shapely_geom, props))
        except Exception as e:
            skipped += 1
            continue

    print(f"  ✓ Loaded {len(sweeping_regs)} street sweeping schedules ({skipped} skipped)")
    return sweeping_regs


def load_metered_blockfaces(metered_path: str) -> List[Tuple[LineString, Dict]]:
    """
    Load metered blockfaces GeoJSON and extract geometries + properties.
    Returns list of (geometry, properties) tuples with 'metered' marker.
    """
    print(f"Loading metered blockfaces from: {metered_path}")

    with open(metered_path, 'r') as f:
        data = json.load(f)

    metered_faces = []
    skipped = 0

    for feature in data['features']:
        geom = feature.get('geometry')
        props = feature.get('properties', {})

        if not geom or geom.get('type') != 'LineString':
            skipped += 1
            continue

        try:
            # Convert GeoJSON to Shapely geometry
            shapely_geom = shape(geom)
            # Add a marker that this is a metered blockface
            props['_is_metered'] = True
            metered_faces.append((shapely_geom, props))
        except Exception as e:
            skipped += 1
            continue

    print(f"  ✓ Loaded {len(metered_faces)} metered blockfaces ({skipped} skipped)")
    return metered_faces


def determine_side_of_line(centerline: LineString, test_line: LineString) -> str:
    """
    Determine which side of a centerline a test line is on.

    Uses the cross product to determine left vs right:
    - Returns 'LEFT' if test_line is on the left side (when traveling along centerline)
    - Returns 'RIGHT' if test_line is on the right side
    - Returns 'UNKNOWN' if ambiguous (parallel, intersecting, or unclear)

    Algorithm:
    1. Get the midpoint of the test line
    2. Find the closest point on the centerline
    3. Get the direction vector of the centerline at that point
    4. Use cross product to determine if midpoint is left or right of direction
    """
    try:
        # Get midpoint of test line
        test_midpoint = test_line.interpolate(0.5, normalized=True)

        # Find closest point on centerline to test midpoint
        closest_point = centerline.interpolate(centerline.project(test_midpoint))

        # Get a small segment of centerline around the closest point for direction
        distance_along = centerline.project(closest_point)
        total_length = centerline.length

        # Get two points to establish direction (5% of line length ahead and behind)
        offset = min(total_length * 0.05, 0.00001)  # ~1-10 meters

        if distance_along < offset:
            # Near start - use forward direction
            p1 = centerline.interpolate(0)
            p2 = centerline.interpolate(offset * 2)
        elif distance_along > total_length - offset:
            # Near end - use forward direction
            p1 = centerline.interpolate(total_length - offset * 2)
            p2 = centerline.interpolate(total_length)
        else:
            # Middle - use local direction
            p1 = centerline.interpolate(distance_along - offset)
            p2 = centerline.interpolate(distance_along + offset)

        # Direction vector of centerline
        dx = p2.x - p1.x  # longitude direction
        dy = p2.y - p1.y  # latitude direction

        # Vector from closest point to test midpoint
        tx = test_midpoint.x - closest_point.x
        ty = test_midpoint.y - closest_point.y

        # Cross product: direction × to_test
        # In 2D: cross_product_z = dx * ty - dy * tx
        # Positive = left side, Negative = right side
        cross = dx * ty - dy * tx

        # Threshold for "clearly on one side" (accounts for nearly parallel lines)
        threshold = 1e-8

        if cross > threshold:
            return 'LEFT'
        elif cross < -threshold:
            return 'RIGHT'
        else:
            return 'UNKNOWN'

    except Exception as e:
        return 'UNKNOWN'


def blockface_side_to_left_right(side: str) -> str:
    """
    Convert blockface side designation to LEFT/RIGHT.

    SF convention:
    - ODD = left side of street (when traveling in typical direction)
    - EVEN = right side of street
    - Directional sides vary by street orientation
    """
    side_upper = side.upper()

    # Simple convention: ODD = LEFT, EVEN = RIGHT
    # This matches SF addressing where odd numbers are typically on one side
    if side_upper == 'ODD':
        return 'LEFT'
    elif side_upper == 'EVEN':
        return 'RIGHT'
    else:
        # For directional sides (NORTH/SOUTH/EAST/WEST), we can't reliably
        # determine left/right without knowing the street's bearing
        # So we'll match to both sides (return UNKNOWN)
        return 'UNKNOWN'


def find_matching_regulations(blockface_geom: LineString,
                             blockface_side: str,
                             regulations: List[Tuple[MultiLineString, Dict]],
                             buffer_distance: float = BUFFER_DISTANCE) -> List[Dict]:
    """
    Find all regulations that spatially intersect with the blockface.
    Uses side-aware matching to ensure regulations are assigned to the correct
    side of the street (ODD vs EVEN).
    """
    # Create buffer around blockface centerline
    buffered_blockface = blockface_geom.buffer(buffer_distance)

    # Determine which side (LEFT/RIGHT) this blockface is on
    blockface_lr_side = blockface_side_to_left_right(blockface_side)

    matching_regs = []

    for reg_geom, reg_props in regulations:
        # Check if regulation geometry intersects with buffered blockface
        if buffered_blockface.intersects(reg_geom):
            # For side-aware matching, check if regulation is on the same side
            if blockface_lr_side != 'UNKNOWN':
                # Blockface has a clear EVEN/ODD designation
                reg_side = determine_side_of_line(blockface_geom, reg_geom)

                # Skip if regulation is clearly on the wrong side
                if reg_side != 'UNKNOWN' and reg_side != blockface_lr_side:
                    continue  # Wrong side - skip this regulation

            # Extract regulation data (uses dispatcher to handle different sources)
            extracted = extract_regulation_from_props(reg_props)
            matching_regs.extend(extracted)

    return matching_regs


def extract_metered_regulation(props: Dict) -> Dict:
    """Extract metered parking regulation from metered blockface data"""
    return {
        "type": "metered",
        "permitZone": None,
        "permitZones": None,
        "timeLimit": None,
        "meterRate": None,  # Rate data not available in blockface dataset
        "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
        "enforcementStart": "09:00",  # Typical SF meter hours
        "enforcementEnd": "18:00",
        "specialConditions": "Metered parking - rates vary by location and time"
    }


def extract_regulation_from_props(props: Dict) -> List[Dict]:
    """
    Dispatch to appropriate extraction function based on source.

    Heuristics:
    - If props has '_is_metered' marker, it's a metered blockface
    - If props has 'weekday' and 'fromhour' fields, it's street sweeping
    - Otherwise, it's a parking regulation
    """
    if props.get('_is_metered'):
        # Metered blockface record
        return [extract_metered_regulation(props)]
    elif 'weekday' in props and 'fromhour' in props:
        # Street sweeping record
        return [extract_street_sweeping(props)]
    else:
        # Parking regulation record
        return extract_regulation(props)


def convert_with_regulations(blockfaces_path: str,
                             regulations_path: str,
                             output_path: str,
                             sweeping_path: Optional[str] = None,
                             metered_path: Optional[str] = None,
                             bounds_filter: bool = True):
    """
    Convert GeoJSON blockfaces to app format with regulations populated.

    Algorithm:
    1. Load all blockfaces and regulations (parking + sweeping + metered)
    2. For each regulation, find the CLOSEST blockface it intersects with
    3. Assign each regulation to only ONE blockface (prevents duplication)
    4. Build output with blockfaces containing their assigned regulations
    """

    # Load parking regulations first
    regulations = load_regulations(regulations_path)
    print(f"  Parking regulations: {len(regulations)}")

    # Load street sweeping if provided
    if sweeping_path:
        sweeping_regs = load_street_sweeping(sweeping_path)
        print(f"  Street sweeping: {len(sweeping_regs)}")
        regulations = regulations + sweeping_regs

    # Load metered blockfaces if provided
    if metered_path:
        metered_faces = load_metered_blockfaces(metered_path)
        print(f"  Metered blockfaces: {len(metered_faces)}")
        regulations = regulations + metered_faces

    all_regulations = regulations
    print(f"  Total regulations: {len(all_regulations)}")

    if not all_regulations:
        print("ERROR: No regulations loaded. Aborting.")
        return

    # Load blockfaces
    print(f"\nReading blockfaces from: {blockfaces_path}")
    with open(blockfaces_path, 'r') as f:
        blockfaces_data = json.load(f)

    print(f"Total blockface features: {len(blockfaces_data['features'])}")

    # First pass: Build blockface objects with geometries
    blockface_objects = []
    skipped_out_of_bounds = 0
    skipped_invalid = 0

    for idx, feature in enumerate(blockfaces_data['features']):
        if (idx + 1) % 1000 == 0:
            print(f"  Processing blockface {idx + 1}/{len(blockfaces_data['features'])}...")

        props = feature['properties']
        geom = feature['geometry']

        # Validate geometry
        if geom['type'] != 'LineString' or not geom.get('coordinates'):
            skipped_invalid += 1
            continue

        coords = geom['coordinates']

        # Apply bounds filter if enabled
        if bounds_filter and not is_in_bounds(coords):
            skipped_out_of_bounds += 1
            continue

        # Extract identifiers
        globalid = props.get('globalid', f'blockface_{idx}')

        # Parse street info from popupinfo
        popupinfo = props.get('popupinfo', '')
        street_info = parse_street_info(popupinfo)
        side = parse_side_from_popupinfo(popupinfo)

        # Convert to Shapely geometry for spatial matching
        try:
            blockface_geom = LineString(coords)
        except Exception as e:
            skipped_invalid += 1
            continue

        blockface_objects.append({
            'id': globalid,
            'geometry': blockface_geom,
            'coords': coords,
            'street_info': street_info,
            'side': side,
            'regulations': []  # Will be populated in second pass
        })

    print(f"\n  ✓ Loaded {len(blockface_objects)} blockfaces")
    print(f"    Skipped (out of bounds): {skipped_out_of_bounds}")
    print(f"    Skipped (invalid): {skipped_invalid}")

    # Second pass: For each regulation, find the CLOSEST blockface
    print(f"\n  Matching {len(all_regulations)} regulations to blockfaces...")

    # Build spatial index for FAST lookups (100x+ speedup)
    print(f"  Building spatial index for {len(blockface_objects)} blockfaces...")
    spatial_index = STRtree([bf['geometry'] for bf in blockface_objects])
    print(f"  ✓ Spatial index built")

    regulations_matched = 0
    regulations_unmatched = 0

    for reg_idx, (reg_geom, reg_props) in enumerate(all_regulations):
        if (reg_idx + 1) % 1000 == 0:
            print(f"    Processing regulation {reg_idx + 1}/{len(all_regulations)}...")

        # Find all blockfaces that intersect with this regulation
        buffered_reg = reg_geom.buffer(BUFFER_DISTANCE)

        # Use spatial index to find ONLY nearby blockfaces (not all 18K!)
        nearby_geom_indices = spatial_index.query(buffered_reg, predicate='intersects')

        closest_blockface = None
        min_distance = float('inf')

        # Only check the nearby blockfaces (typically 1-10 instead of 18,355!)
        for idx in nearby_geom_indices:
            bf = blockface_objects[idx]
            if buffered_reg.intersects(bf['geometry']):
                # Side-aware matching: check if regulation is on the same side as blockface
                bf_side = bf['side']
                bf_lr_side = blockface_side_to_left_right(bf_side)

                # If blockface has a clear side designation (EVEN/ODD), check regulation side
                if bf_lr_side != 'UNKNOWN':
                    reg_side = determine_side_of_line(bf['geometry'], reg_geom)

                    # Skip if regulation is clearly on the wrong side
                    if reg_side != 'UNKNOWN' and reg_side != bf_lr_side:
                        continue  # Wrong side - skip this blockface

                # Calculate distance from regulation to blockface centerline
                distance = reg_geom.distance(bf['geometry'])

                if distance < min_distance:
                    min_distance = distance
                    closest_blockface = bf

        # Assign regulation to the closest blockface only (on the correct side)
        if closest_blockface:
            extracted_regs = extract_regulation_from_props(reg_props)
            closest_blockface['regulations'].extend(extracted_regs)
            regulations_matched += 1
        else:
            regulations_unmatched += 1

    print(f"  ✓ Matched {regulations_matched} regulations ({100*regulations_matched/len(all_regulations):.1f}%)")
    print(f"    Unmatched: {regulations_unmatched} ({100*regulations_unmatched/len(all_regulations):.1f}%)")

    # Third pass: Deduplicate regulations within each blockface and build output
    blockfaces = []
    blockfaces_with_regulations = 0
    total_regulations_added = 0

    for bf_obj in blockface_objects:
        # Deduplicate regulations
        seen = set()
        unique_regulations = []
        for reg in bf_obj['regulations']:
            # Create tuple of all non-None values for comparison
            key_parts = []
            for k, v in sorted(reg.items()):
                if v is not None and k != 'meterRate':
                    if isinstance(v, list):
                        key_parts.append((k, tuple(v)))
                    else:
                        key_parts.append((k, v))
            key = tuple(key_parts)
            if key not in seen:
                seen.add(key)
                unique_regulations.append(reg)

        # NOTE: Regulation priority sorting moved to app runtime for flexibility
        # This allows the app to:
        # - Customize priority based on user preferences
        # - Filter by time/context (show only active regulations)
        # - Update priority logic without regenerating data
        # Backward compatible: Apps expecting sorted data can sort at runtime
        # unique_regulations = sort_regulations_by_priority(unique_regulations)  # REMOVED

        if unique_regulations:
            blockfaces_with_regulations += 1
            total_regulations_added += len(unique_regulations)

        # Backfill street name if missing (from regulation source data)
        street_name = bf_obj['street_info']['street']
        if street_name == "Unknown Street" and unique_regulations:
            # Try to get street name from street cleaning regulations
            for reg in unique_regulations:
                source_street = reg.get('_sourceStreet')
                if source_street and source_street.strip():
                    # Normalize street name to match existing style
                    street_name = normalize_street_name(source_street)
                    break  # Use first available street name

        # Clean up _sourceStreet from regulations before output
        for reg in unique_regulations:
            reg.pop('_sourceStreet', None)

        # Create blockface in app format
        blockface = {
            "id": bf_obj['id'],
            "street": street_name,
            "fromStreet": bf_obj['street_info']['from'],
            "toStreet": bf_obj['street_info']['to'],
            "side": bf_obj['side'],
            "geometry": {
                "type": "LineString",
                "coordinates": bf_obj['coords']
            },
            "regulations": unique_regulations
        }

        blockfaces.append(blockface)

    # Print statistics
    print(f"\n{'='*70}")
    print("CONVERSION STATISTICS")
    print(f"{'='*70}")
    print(f"Blockfaces processed:          {len(blockfaces)}")
    print(f"Blockfaces with regulations:   {blockfaces_with_regulations} ({100*blockfaces_with_regulations/max(len(blockfaces),1):.1f}%)")
    print(f"Blockfaces without regulations: {len(blockfaces) - blockfaces_with_regulations}")
    print(f"Total regulations added:       {total_regulations_added}")
    print(f"Avg regulations per blockface: {total_regulations_added/max(len(blockfaces),1):.2f}")
    print(f"\nSkipped (out of bounds):       {skipped_out_of_bounds}")
    print(f"Skipped (invalid geometry):    {skipped_invalid}")
    print(f"{'='*70}")

    # Regulation type breakdown
    reg_types = defaultdict(int)
    for bf in blockfaces:
        for reg in bf['regulations']:
            reg_types[reg['type']] += 1

    if reg_types:
        print("\nREGULATION TYPE BREAKDOWN:")
        for reg_type, count in sorted(reg_types.items(), key=lambda x: -x[1]):
            print(f"  {reg_type:20s} {count:5d} ({100*count/total_regulations_added:.1f}%)")

    # Show sample blockfaces with regulations
    print(f"\nSAMPLE BLOCKFACES WITH REGULATIONS:")
    sample_count = 0
    for bf in blockfaces:
        if bf['regulations'] and sample_count < 3:
            sample_count += 1
            print(f"\n  {bf['street']} ({bf['fromStreet']} → {bf['toStreet']}) {bf['side']}")
            for reg in bf['regulations'][:2]:  # Show first 2 regulations
                print(f"    • {reg['type']}", end="")
                if reg.get('permitZone'):
                    print(f" (Zone {reg['permitZone']})", end="")
                if reg.get('timeLimit'):
                    print(f" - {reg['timeLimit']} min limit", end="")
                if reg.get('enforcementDays'):
                    days_str = ", ".join(reg['enforcementDays'][:3])
                    if len(reg['enforcementDays']) > 3:
                        days_str += "..."
                    print(f" - {days_str}", end="")
                if reg.get('enforcementStart') and reg.get('enforcementEnd'):
                    print(f" {reg['enforcementStart']}-{reg['enforcementEnd']}", end="")
                print()

    # Save output
    output = {"blockfaces": blockfaces}
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n✓ Saved to: {output_path}")
    print(f"\nNext steps:")
    print(f"  1. Review the statistics above")
    print(f"  2. Check sample blockfaces for accuracy")
    print(f"  3. Copy to app resources:")
    print(f"     cp {output_path} SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces.json")
    print(f"  4. Test in the app")


def main():
    # Parse command-line arguments
    if len(sys.argv) > 1:
        blockfaces_file = sys.argv[1]
    else:
        blockfaces_file = "Data Sets/Blockfaces_20251128.geojson"

    if len(sys.argv) > 2:
        regulations_file = sys.argv[2]
    else:
        regulations_file = "Data Sets/Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"

    if len(sys.argv) > 3:
        output_file = sys.argv[3]
    else:
        output_file = "sample_blockfaces_with_regulations.json"

    # Check for sweeping dataset (4th argument)
    sweeping_file = None
    if len(sys.argv) > 4 and not sys.argv[4].startswith('--'):
        sweeping_file = sys.argv[4]

    # Check for metered blockfaces dataset (5th argument)
    metered_file = None
    if len(sys.argv) > 5 and not sys.argv[5].startswith('--'):
        metered_file = sys.argv[5]

    # Check for --no-bounds flag
    bounds_filter = "--no-bounds" not in sys.argv

    print("=" * 70)
    print("BLOCKFACE + REGULATIONS SPATIAL JOIN")
    print("=" * 70)
    print(f"Blockfaces:         {blockfaces_file}")
    print(f"Regulations:        {regulations_file}")
    if sweeping_file:
        print(f"Street Sweeping:    {sweeping_file}")
    if metered_file:
        print(f"Metered Blockfaces: {metered_file}")
    print(f"Output:             {output_file}")
    print(f"Bounds filter: {'ON (Mission District only)' if bounds_filter else 'OFF (all SF)'}")
    print(f"Buffer distance: {BUFFER_DISTANCE} degrees (~{BUFFER_DISTANCE * 111000:.0f}m)")
    print("=" * 70)
    print()

    convert_with_regulations(blockfaces_file, regulations_file, output_file,
                           sweeping_file, metered_file, bounds_filter)


if __name__ == "__main__":
    main()
