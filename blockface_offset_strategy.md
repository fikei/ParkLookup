# Blockface Offset Strategy

## Problem
We need to plot parking lane polygons by offsetting blockface centerlines in the correct direction based on which side of the block they represent.

## Requirements
- **North side** → offset DOWN (toward south) = -6m in latitude
- **South side** → offset UP (toward north) = +6m in latitude
- **East side** → offset LEFT (toward west) = -6m in longitude (adjusted for lat)
- **West side** → offset RIGHT (toward east) = +6m in longitude (adjusted for lat)
- **Curved & Diagonal streets** → calculate perpendicular dynamically

## Current Data
From GeoJSON conversion:
- `side` field values: "EVEN" (West), "ODD" (East), "NORTH", "SOUTH", "UNKNOWN"
- Centerlines are in `[lon, lat]` format
- Coordinates are correct WGS84 - no transformation needed

## Proposed Algorithm

### 1. **Straight Streets (N-S or E-W aligned)**
For streets that are primarily aligned to cardinal directions:

```python
# Detect alignment by calculating bearing
bearing = calculate_bearing(start, end)

if is_north_south(bearing):  # 345-15° or 165-195°
    if side == "WEST" (EVEN):
        offset = (dlat: 0, dlon: +6m_in_degrees)  # offset EAST
    elif side == "EAST" (ODD):
        offset = (dlat: 0, dlon: -6m_in_degrees)  # offset WEST

elif is_east_west(bearing):  # 75-105° or 255-285°
    if side == "NORTH":
        offset = (dlat: -6m_in_degrees, dlon: 0)  # offset SOUTH
    elif side == "SOUTH":
        offset = (dlat: +6m_in_degrees, dlon: 0)  # offset NORTH
```

### 2. **Curved Streets**
For streets with varying curvature (multiple vertices with changing bearing):

```python
for each point in centerline:
    # Calculate local perpendicular at this point
    local_forward = direction_to_next_point
    perpendicular_left = rotate_90_ccw(local_forward)
    perpendicular_right = rotate_90_cw(local_forward)

    # Choose correct perpendicular based on side
    if side in ["WEST", "SOUTH"]:
        offset_vector = perpendicular_right  # into street
    else:  # EAST, NORTH
        offset_vector = perpendicular_left   # into street

    offset_point = point + normalize(offset_vector) * 6m
```

### 3. **Diagonal Streets**
For streets at angles (not aligned to cardinal directions):

```python
# Calculate average bearing
avg_bearing = calculate_average_bearing(centerline)

# Determine which cardinal direction the side faces
if side == "NORTH":
    # Blockface is on north edge, offset toward south
    preferred_direction = 180°  # south
elif side == "SOUTH":
    preferred_direction = 0°    # north
elif side == "EAST":
    preferred_direction = 270°  # west
elif side == "WEST":
    preferred_direction = 90°   # east

# Calculate both perpendiculars
perp_left = rotate_90_ccw(forward_vector)
perp_right = rotate_90_cw(forward_vector)

# Choose the perpendicular that best matches preferred_direction
if angle_diff(perp_left, preferred_direction) < angle_diff(perp_right, preferred_direction):
    offset_vector = perp_left
else:
    offset_vector = perp_right
```

## Edge Cases & Solutions

### Case 1: Unknown Side
```
If side == "UNKNOWN":
    - Log warning
    - Default to offset based on perpendicular-right (conservative choice)
    - Or skip rendering this blockface
```

### Case 2: Very Curved Streets (e.g., Twin Peaks)
```
- Use local perpendicular at each vertex
- Smooth the offset curve to avoid sharp angles
- May need to increase vertex count for smooth curves
```

### Case 3: Intersections
```
- Trim blockface polygon at intersection boundaries
- Or accept small overlaps (visual only, doesn't affect lookups)
```

### Case 4: One-way Streets
```
- Same algorithm applies
- Direction of traffic doesn't affect which side the curb is on
```

## Implementation Plan

1. **Add bearing calculation helper**
   - Calculate bearing between two points
   - Determine if street is N-S, E-W, or diagonal
   - Calculate angle difference between vectors

2. **Update offset logic in BlockfaceMapOverlays.swift**
   - Replace `offsetToRight` boolean with direction-aware logic
   - Add cardinal direction offset calculation
   - Add diagonal street perpendicular selection

3. **Add visualization debugging**
   - Color-code by side (NORTH=blue, SOUTH=red, EAST=green, WEST=yellow)
   - Draw arrows showing offset direction
   - Log calculated bearings for verification

## Testing Strategy

1. Test on Valencia St (N-S street, WEST/EAST sides)
2. Test on 16th St (E-W street, NORTH/SOUTH sides)
3. Test on diagonal street (e.g., Market St)
4. Test on curved street (if available in Mission District data)

## Conversion Factor
```
6 meters in degrees at SF latitude (37.76°):
- Latitude: 6m / 111,000m = 0.000054°
- Longitude: 6m / (111,000m * cos(37.76°)) = 6m / 87,700m = 0.000068°
```
