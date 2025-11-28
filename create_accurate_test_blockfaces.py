#!/usr/bin/env python3
"""
Create accurate test blockface coordinates based on actual SF street grid geometry.

Mission and Valencia Streets run NW-SE (bearing ~338°) in the Mission District.
Cross streets (22nd, 23rd, 24th, etc.) run NE-SW (bearing ~68°).

Reference intersection coordinates (approximate but realistic):
- Mission & 24th: -122.4183, 37.7521
- Valencia & 24th: -122.4210, 37.7522
"""

import json
import math

# Real SF street grid parameters for Mission District
# These are derived from actual SF street geometry

# Street bearings (degrees from north)
MISSION_BEARING = 338  # NW-SE bearing
CROSS_STREET_BEARING = 68  # NE-SW bearing

# Reference point: Mission & 24th intersection
REF_LAT = 37.7521
REF_LON = -122.4183

# Spacing measurements (in degrees)
BLOCK_LENGTH_NS = 0.00135  # ~150m per block along Mission/Valencia
MISSION_TO_VALENCIA = 0.00265  # ~300m between Mission and Valencia
STREET_WIDTH = 0.00015  # ~17m street width
BLOCKFACE_LENGTH = BLOCK_LENGTH_NS  # Length of one block

def create_line_along_bearing(start_lat, start_lon, bearing_deg, distance_deg, num_points=4):
    """
    Create a LineString along a bearing from a start point.

    Args:
        start_lat, start_lon: Starting coordinates
        bearing_deg: Bearing in degrees (0=N, 90=E, 180=S, 270=W)
        distance_deg: Total distance in degrees
        num_points: Number of points in the line

    Returns:
        List of [lon, lat] coordinates (GeoJSON format)
    """
    coords = []
    bearing_rad = math.radians(bearing_deg)

    for i in range(num_points):
        fraction = i / (num_points - 1)
        dist = distance_deg * fraction

        # Simple approximation for short distances
        # For more accuracy, would use Haversine/Vincenty
        dlat = dist * math.cos(bearing_rad)
        dlon = dist * math.sin(bearing_rad)

        lat = start_lat + dlat
        lon = start_lon + dlon
        coords.append([lon, lat])  # GeoJSON format: [lon, lat]

    return coords

def offset_line_perpendicular(line_coords, offset_distance_deg, offset_right=True):
    """
    Offset a line perpendicular to its direction.

    Args:
        line_coords: List of [lon, lat] coordinates
        offset_distance_deg: Distance to offset in degrees
        offset_right: True to offset right, False for left

    Returns:
        List of offset [lon, lat] coordinates
    """
    if len(line_coords) < 2:
        return line_coords

    offset_coords = []

    for i, coord in enumerate(line_coords):
        lon, lat = coord

        # Calculate local bearing
        if i == 0:
            next_lon, next_lat = line_coords[i + 1]
            dlat = next_lat - lat
            dlon = next_lon - lon
        elif i == len(line_coords) - 1:
            prev_lon, prev_lat = line_coords[i - 1]
            dlat = lat - prev_lat
            dlon = lon - prev_lon
        else:
            prev_lon, prev_lat = line_coords[i - 1]
            next_lon, next_lat = line_coords[i + 1]
            dlat = (next_lat - prev_lat) / 2
            dlon = (next_lon - prev_lon) / 2

        # Calculate perpendicular bearing
        bearing = math.atan2(dlon, dlat)  # Note: atan2(x, y) for lon/lat
        perp_bearing = bearing + (math.pi / 2 if offset_right else -math.pi / 2)

        # Apply offset
        offset_lat = lat + offset_distance_deg * math.cos(perp_bearing)
        offset_lon = lon + offset_distance_deg * math.sin(perp_bearing)

        offset_coords.append([offset_lon, offset_lat])

    return offset_coords

def create_blockface(street, from_st, to_st, side, centerline_coords):
    """Create a blockface object"""
    return {
        "id": f"{street.lower().replace(' ', '_')}_{from_st}_{to_st}_{side.lower()}",
        "street": street,
        "fromStreet": from_st,
        "toStreet": to_st,
        "side": side,
        "geometry": {
            "type": "LineString",
            "coordinates": centerline_coords
        },
        "regulations": [
            {
                "type": "metered",
                "meterRate": 4.00,
                "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
                "enforcementStart": "09:00",
                "enforcementEnd": "18:00",
                "timeLimit": 120
            }
        ]
    }

def main():
    print("Creating accurate SF blockface test data...")
    print(f"Reference: Mission & 24th at ({REF_LAT}, {REF_LON})")
    print()

    blockfaces = []

    # === MISSION STREET ===
    # Mission runs NW-SE, so blocks go from low number to high number going SE

    # Calculate start points for each block on Mission
    # 22nd-23rd block
    mission_22nd_lat = REF_LAT + BLOCK_LENGTH_NS * 2  # 2 blocks north of 24th
    mission_22nd_lon = REF_LON

    # EVEN side (west side of Mission) - curb line is offset west from centerline
    mission_22_23_even_centerline = create_line_along_bearing(
        mission_22nd_lat, mission_22nd_lon,
        MISSION_BEARING,  # Going NW-SE
        BLOCK_LENGTH_NS,
        num_points=4
    )
    # Offset west (right when going SE)
    mission_22_23_even = offset_line_perpendicular(
        mission_22_23_even_centerline,
        STREET_WIDTH / 2,
        offset_right=True
    )

    blockfaces.append(create_blockface(
        "Mission St", "22nd St", "23rd St", "EVEN",
        mission_22_23_even
    ))

    # ODD side (east side of Mission) - offset east from centerline
    mission_22_23_odd = offset_line_perpendicular(
        mission_22_23_even_centerline,
        STREET_WIDTH / 2,
        offset_right=False
    )

    blockfaces.append(create_blockface(
        "Mission St", "22nd St", "23rd St", "ODD",
        mission_22_23_odd
    ))

    # 23rd-24th block
    mission_23rd_lat = REF_LAT + BLOCK_LENGTH_NS
    mission_23rd_lon = REF_LON

    mission_23_24_centerline = create_line_along_bearing(
        mission_23rd_lat, mission_23rd_lon,
        MISSION_BEARING,
        BLOCK_LENGTH_NS,
        num_points=4
    )

    mission_23_24_even = offset_line_perpendicular(mission_23_24_centerline, STREET_WIDTH / 2, True)
    mission_23_24_odd = offset_line_perpendicular(mission_23_24_centerline, STREET_WIDTH / 2, False)

    blockfaces.append(create_blockface("Mission St", "23rd St", "24th St", "EVEN", mission_23_24_even))
    blockfaces.append(create_blockface("Mission St", "23rd St", "24th St", "ODD", mission_23_24_odd))

    # 24th-25th block
    mission_24th_lat = REF_LAT
    mission_24th_lon = REF_LON

    mission_24_25_centerline = create_line_along_bearing(
        mission_24th_lat, mission_24th_lon,
        MISSION_BEARING,
        BLOCK_LENGTH_NS,
        num_points=4
    )

    mission_24_25_even = offset_line_perpendicular(mission_24_25_centerline, STREET_WIDTH / 2, True)
    mission_24_25_odd = offset_line_perpendicular(mission_24_25_centerline, STREET_WIDTH / 2, False)

    blockfaces.append(create_blockface("Mission St", "24th St", "25th St", "EVEN", mission_24_25_even))
    blockfaces.append(create_blockface("Mission St", "24th St", "25th St", "ODD", mission_24_25_odd))

    # === VALENCIA STREET ===
    # Valencia is parallel to Mission, offset by MISSION_TO_VALENCIA degrees west

    # Calculate Valencia positions by offsetting from Mission perpendicular to street direction
    # Valencia is SW of Mission, which is "right" when heading SE along Mission
    valencia_offset_bearing = MISSION_BEARING + 90  # Perpendicular right

    valencia_22nd_lat = mission_22nd_lat + MISSION_TO_VALENCIA * math.cos(math.radians(valencia_offset_bearing))
    valencia_22nd_lon = mission_22nd_lon + MISSION_TO_VALENCIA * math.sin(math.radians(valencia_offset_bearing))

    # 22nd-23rd
    valencia_22_23_centerline = create_line_along_bearing(
        valencia_22nd_lat, valencia_22nd_lon,
        MISSION_BEARING,
        BLOCK_LENGTH_NS,
        num_points=4
    )
    valencia_22_23_even = offset_line_perpendicular(valencia_22_23_centerline, STREET_WIDTH / 2, True)
    valencia_22_23_odd = offset_line_perpendicular(valencia_22_23_centerline, STREET_WIDTH / 2, False)

    blockfaces.append(create_blockface("Valencia St", "22nd St", "23rd St", "EVEN", valencia_22_23_even))
    blockfaces.append(create_blockface("Valencia St", "22nd St", "23rd St", "ODD", valencia_22_23_odd))

    # 23rd-24th
    valencia_23rd_lat = mission_23rd_lat + MISSION_TO_VALENCIA * math.cos(math.radians(valencia_offset_bearing))
    valencia_23rd_lon = mission_23rd_lon + MISSION_TO_VALENCIA * math.sin(math.radians(valencia_offset_bearing))

    valencia_23_24_centerline = create_line_along_bearing(
        valencia_23rd_lat, valencia_23rd_lon,
        MISSION_BEARING,
        BLOCK_LENGTH_NS,
        num_points=4
    )
    valencia_23_24_even = offset_line_perpendicular(valencia_23_24_centerline, STREET_WIDTH / 2, True)
    valencia_23_24_odd = offset_line_perpendicular(valencia_23_24_centerline, STREET_WIDTH / 2, False)

    blockfaces.append(create_blockface("Valencia St", "23rd St", "24th St", "EVEN", valencia_23_24_even))
    blockfaces.append(create_blockface("Valencia St", "23rd St", "24th St", "ODD", valencia_23_24_odd))

    # 24th-25th
    valencia_24th_lat = REF_LAT + MISSION_TO_VALENCIA * math.cos(math.radians(valencia_offset_bearing))
    valencia_24th_lon = REF_LON + MISSION_TO_VALENCIA * math.sin(math.radians(valencia_offset_bearing))

    valencia_24_25_centerline = create_line_along_bearing(
        valencia_24th_lat, valencia_24th_lon,
        MISSION_BEARING,
        BLOCK_LENGTH_NS,
        num_points=4
    )
    valencia_24_25_even = offset_line_perpendicular(valencia_24_25_centerline, STREET_WIDTH / 2, True)
    valencia_24_25_odd = offset_line_perpendicular(valencia_24_25_centerline, STREET_WIDTH / 2, False)

    blockfaces.append(create_blockface("Valencia St", "24th St", "25th St", "EVEN", valencia_24_25_even))
    blockfaces.append(create_blockface("Valencia St", "24th St", "25th St", "ODD", valencia_24_25_odd))

    # === 24TH STREET ===
    # 24th runs NE-SW (perpendicular to Mission/Valencia)
    # From Mission to Valencia

    # NORTH side (when going west from Mission to Valencia)
    street_24_north_start_lat = REF_LAT
    street_24_north_start_lon = REF_LON

    street_24_centerline = create_line_along_bearing(
        street_24_north_start_lat, street_24_north_start_lon,
        valencia_offset_bearing,  # Mission toward Valencia bearing
        MISSION_TO_VALENCIA,
        num_points=4
    )

    street_24_north = offset_line_perpendicular(street_24_centerline, STREET_WIDTH / 2, True)
    street_24_south = offset_line_perpendicular(street_24_centerline, STREET_WIDTH / 2, False)

    blockfaces.append(create_blockface("24th St", "Mission St", "Valencia St", "NORTH", street_24_north))
    blockfaces.append(create_blockface("24th St", "Mission St", "Valencia St", "SOUTH", street_24_south))

    # Save output
    output = {"blockfaces": blockfaces}
    output_file = "SFParkingZoneFinder/SFParkingZoneFinder/Resources/sample_blockfaces_corrected.json"

    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"✓ Created {len(blockfaces)} blockfaces")
    print(f"✓ Saved to: {output_file}")
    print()
    print("Sample coordinates:")
    for bf in blockfaces[:3]:
        coords = bf['geometry']['coordinates']
        print(f"  {bf['street']} {bf['side']}: {len(coords)} points")
        print(f"    Start: [{coords[0][0]:.6f}, {coords[0][1]:.6f}]")
        print(f"    End:   [{coords[-1][0]:.6f}, {coords[-1][1]:.6f}]")

if __name__ == "__main__":
    main()
