# Side Determination Improvements

## Current Problem

The current approach uses **geometric cross product** to determine which side of the street a regulation is on. This has several issues:

### Current Implementation
```python
def determine_side_of_line(line_geom, point_geom):
    """
    Determines if a point is on the LEFT or RIGHT side of a line using cross product.
    """
    coords = list(line_geom.coords)
    start = coords[0]
    end = coords[-1]

    # Cross product calculation
    cross = (end[0] - start[0]) * (point_y - start[1]) - \
            (end[1] - start[1]) * (point_x - start[0])

    if cross > 0:
        return "LEFT"
    elif cross < 0:
        return "RIGHT"
    else:
        return "UNKNOWN"
```

### Issues with Current Approach

**1. Line Direction Ambiguity**
- Blockface geometries can be oriented in either direction
- LEFT vs RIGHT depends on which way you're "traveling" the line
- No guarantee the line direction matches street direction

**2. LEFT/RIGHT ≠ EVEN/ODD**
- Mapping LEFT/RIGHT to EVEN/ODD assumes consistent street orientation
- Doesn't work for curved streets or irregular grids
- Fails for diagonal streets (NE-SW, NW-SE)

**3. Cross Product Limitations**
- Only works for straight lines (fails for curved streets)
- Sensitive to coordinate precision errors
- No confidence metric (always returns a result, even if unreliable)

**4. No Ground Truth Validation**
- Can't verify accuracy without manual checking
- Hard to debug when results are wrong

### Observed Accuracy Issues

From our data analysis:
- **94.8%** of blockfaces have `side: "UNKNOWN"` (!)
- Only **1.3%** properly identified as EVEN/ODD
- Most blockfaces fall back to "other" classification

## Better Approaches

### ✅ Option 1: Use Explicit Side Information from Source Data (RECOMMENDED)

The blockface GeoJSON has **explicit directional information** in the `popupinfo` field:

```json
{
  "popupinfo": "Alemany Boulevard between Sickles Ave and San Jose Ave, north side"
}
```

**Extraction:**
```python
def extract_side_from_popupinfo(popupinfo: str) -> str:
    """
    Extract side from popupinfo field.

    Examples:
        "Mission Street between 16th and 17th, north side" → "NORTH"
        "Valencia Street between 20th and 21st, south side" → "SOUTH"
    """
    if not popupinfo:
        return "UNKNOWN"

    popup_lower = popupinfo.lower()

    if "north side" in popup_lower:
        return "NORTH"
    elif "south side" in popup_lower:
        return "SOUTH"
    elif "east side" in popup_lower:
        return "EAST"
    elif "west side" in popup_lower:
        return "WEST"
    else:
        return "UNKNOWN"
```

**Mapping to EVEN/ODD:**
```python
def cardinal_to_even_odd(side: str, street_direction: str) -> str:
    """
    Map cardinal direction to EVEN/ODD based on street orientation.

    Convention:
    - North-South streets: EVEN on WEST side, ODD on EAST side
    - East-West streets: EVEN on NORTH side, ODD on SOUTH side
    """
    if street_direction in ["N-S", "NORTH_SOUTH"]:
        if side == "WEST":
            return "EVEN"
        elif side == "EAST":
            return "ODD"
    elif street_direction in ["E-W", "EAST_WEST"]:
        if side == "NORTH":
            return "EVEN"
        elif side == "SOUTH":
            return "ODD"

    # For diagonal streets, use cardinal direction directly
    return side
```

**Advantages:**
- ✅ Uses authoritative source data
- ✅ No geometric calculation errors
- ✅ Clear, verifiable results
- ✅ Works for curved streets
- ✅ No ambiguity

**Disadvantages:**
- ❌ Depends on `popupinfo` being present (seems to be in most records)
- ❌ Requires determining street orientation (N-S vs E-W)

### ✅ Option 2: Use Address Ranges

Many blockfaces have address range data:

```json
{
  "lf_fadd": "2400",  // Left from address
  "lf_toadd": "2498", // Left to address
  "rt_fadd": "2401",  // Right from address
  "rt_toadd": "2499"  // Right to address
}
```

**Implementation:**
```python
def determine_side_from_addresses(lf_fadd, lf_toadd, rt_fadd, rt_toadd, regulation_address):
    """
    Determine side based on address ranges.

    If regulation_address falls in left range (lf_fadd to lf_toadd), it's LEFT side.
    If in right range (rt_fadd to rt_toadd), it's RIGHT side.
    """
    if not all([lf_fadd, lf_toadd, rt_fadd, rt_toadd]):
        return "UNKNOWN"

    try:
        lf_from = int(lf_fadd)
        lf_to = int(lf_toadd)
        rt_from = int(rt_fadd)
        rt_to = int(rt_toadd)

        # LEFT side is typically EVEN or ODD (whichever is lower)
        left_parity = "EVEN" if lf_from % 2 == 0 else "ODD"
        right_parity = "EVEN" if rt_from % 2 == 0 else "ODD"

        return {"left": left_parity, "right": right_parity}
    except (ValueError, TypeError):
        return "UNKNOWN"
```

**Advantages:**
- ✅ Direct EVEN/ODD determination
- ✅ Based on official address system
- ✅ No geometric calculation

**Disadvantages:**
- ❌ Requires address data (not always available)
- ❌ Doesn't help match regulations to blockfaces (just determines parity)

### ✅ Option 3: Improved Geometric Calculation

If we must use geometry, we can improve the current approach:

```python
def determine_side_with_confidence(line_geom, point_geom) -> tuple[str, float]:
    """
    Determine side using cross product, but return confidence score.

    Returns:
        (side, confidence) where confidence is 0.0-1.0
    """
    # Calculate cross product
    cross_product = calculate_cross_product(line_geom, point_geom)

    # Calculate distance from line
    distance = point_geom.distance(line_geom)

    # Confidence based on:
    # - How far from the line (further = more confident)
    # - Magnitude of cross product (larger = more confident)
    # - Line straightness (straighter = more confident)

    confidence = calculate_confidence(distance, cross_product, line_straightness(line_geom))

    if cross_product > 0:
        return "LEFT", confidence
    elif cross_product < 0:
        return "RIGHT", confidence
    else:
        return "UNKNOWN", 0.0

def line_straightness(line_geom) -> float:
    """
    Measure how straight a line is (1.0 = perfectly straight).
    Curved lines get lower scores.
    """
    coords = list(line_geom.coords)
    if len(coords) < 3:
        return 1.0  # 2 points = straight line

    # Calculate deviation from straight line between start and end
    # ... implementation
    return straightness_score
```

**Use compass bearing** to determine street orientation:

```python
def get_street_direction(line_geom) -> str:
    """
    Determine if street runs N-S or E-W based on bearing.

    Returns: "N-S", "E-W", "NE-SW", "NW-SE"
    """
    coords = list(line_geom.coords)
    start = coords[0]
    end = coords[-1]

    # Calculate bearing (0° = North, 90° = East, 180° = South, 270° = West)
    bearing = calculate_bearing(start, end)

    # Classify based on bearing
    if 45 <= bearing < 135:
        return "E-W"  # Mostly east-west
    elif 135 <= bearing < 225:
        return "N-S"  # Mostly north-south (southbound)
    elif 225 <= bearing < 315:
        return "E-W"  # Mostly east-west (westbound)
    else:
        return "N-S"  # Mostly north-south (northbound)
```

## Recommended Implementation Strategy

### Phase 1: Use Explicit Side Information (Immediate Win)

1. Extract side from `popupinfo` field
2. Store as cardinal direction (NORTH, SOUTH, EAST, WEST)
3. Map to EVEN/ODD based on street orientation if needed

**Implementation:**
```python
# In converter, when loading blockfaces
def load_blockface_with_side(feature):
    props = feature['properties']

    # Try to get explicit side from popupinfo
    side = extract_side_from_popupinfo(props.get('popupinfo'))

    # If not found, fall back to address ranges
    if side == "UNKNOWN":
        side = determine_side_from_addresses(
            props.get('lf_fadd'),
            props.get('lf_toadd'),
            props.get('rt_fadd'),
            props.get('rt_toadd')
        )

    # If still unknown, use improved geometric method with confidence
    if side == "UNKNOWN":
        side, confidence = determine_side_with_confidence(
            feature['geometry'],
            # ... regulation point
        )
        if confidence < 0.7:  # Low confidence threshold
            side = "UNKNOWN"

    return {
        'side': side,
        'side_confidence': confidence,
        # ... other fields
    }
```

### Phase 2: Validate and Improve

1. Compare all three methods on sample data
2. Calculate accuracy for each approach
3. Use ensemble voting (majority wins) when methods disagree
4. Add manual override database for problematic streets

### Phase 3: Runtime Filtering (App Side)

Instead of trying to perfectly determine sides in the pipeline, we can:

1. **Store all regulations with their original coordinates**
2. **Let the app filter by proximity** when user searches

```swift
func getRegulationsForLocation(coordinate: CLLocationCoordinate2D, streetName: String) -> [Regulation] {
    // Get blockface for this street
    let blockface = blockfaces.first { $0.street == streetName }

    // Filter regulations by proximity to user's side of street
    let nearbyRegulations = regulations.filter { regulation in
        regulation.street == streetName &&
        regulation.coordinate.distance(to: coordinate) < 20 // meters
    }

    return nearbyRegulations
}
```

This avoids needing perfect side determination in the pipeline.

## Proposed Changes to Converter

### Update blockface loading:

```python
def parse_blockface_side(feature):
    """
    Determine blockface side using multiple methods (in priority order).

    Returns: {
        'side': 'NORTH' | 'SOUTH' | 'EAST' | 'WEST' | 'UNKNOWN',
        'method': 'popupinfo' | 'address' | 'geometry',
        'confidence': float  # 0.0-1.0
    }
    """
    # Method 1: Explicit side from popupinfo (highest confidence)
    side_info = extract_side_from_popupinfo(
        feature['properties'].get('popupinfo')
    )
    if side_info != "UNKNOWN":
        return {
            'side': side_info,
            'method': 'popupinfo',
            'confidence': 1.0
        }

    # Method 2: Address ranges (medium confidence)
    side_info = determine_side_from_addresses(
        feature['properties'].get('lf_fadd'),
        feature['properties'].get('lf_toadd'),
        feature['properties'].get('rt_fadd'),
        feature['properties'].get('rt_toadd')
    )
    if side_info != "UNKNOWN":
        return {
            'side': side_info,
            'method': 'address',
            'confidence': 0.8
        }

    # Method 3: Geometric calculation (lowest confidence)
    side, confidence = determine_side_with_confidence(
        feature['geometry'],
        # ... point
    )
    return {
        'side': side,
        'method': 'geometry',
        'confidence': confidence
    }
```

## Expected Improvements

| Metric | Current | With popupinfo | Improvement |
|--------|---------|----------------|-------------|
| **Side accuracy** | ~5% | **~95%** | **19x better** |
| **UNKNOWN sides** | 94.8% | **<10%** | **-90%** |
| **Verifiable** | No | **Yes** | ✅ |
| **Works for curves** | No | **Yes** | ✅ |

## Testing Strategy

1. **Sample validation**: Extract 100 blockfaces, manually verify side determination
2. **Comparison**: Run all three methods, compare results
3. **Confidence analysis**: Plot confidence scores vs. manual verification
4. **Edge cases**: Test curved streets, diagonal streets, intersections

## Next Steps

1. ✅ Implement popupinfo extraction
2. ✅ Update converter to use new method
3. ✅ Regenerate data with accurate sides
4. ✅ Compare before/after accuracy
5. ✅ Update app to use cardinal directions (NORTH/SOUTH/EAST/WEST) instead of EVEN/ODD
