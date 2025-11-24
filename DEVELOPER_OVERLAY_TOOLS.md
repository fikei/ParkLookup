# SF Parking Zone Finder - Developer Overlay Tools

## Quick Start Tutorial

### 1. Unlocking Developer Mode

The developer overlay tools are hidden by default. To unlock them:

1. Open the app and tap **Settings** (⚙️ icon at top-right)
2. Scroll to the bottom and tap **"Version X.X.X"** five times rapidly
3. You'll feel haptic feedback and see developer mode unlock
4. A **code icon (`</>`)** will appear in the top-right of the main map view

**Note**: Developer mode stays unlocked until you manually disable it in settings.

---

### 2. Opening the Overlay Tools Panel

Once developer mode is unlocked:

1. Tap the **`</>`** icon in the top-right corner
2. The developer overlay tools panel slides up from the bottom
3. Works on both **minimized** and **expanded** map views
4. When opened on minimized view, other UI animates out to give full screen to map + tools

**Panel Controls:**
- **Drag handle** at top to expand/collapse sections
- **Save Candidate** button (bottom) to export current configuration
- **Tap outside** or the `</>` icon again to close

---

### 3. Understanding the Interface

The panel is organized into collapsible sections:

#### **📐 Simplification** (Pipeline Features)
Controls that reduce polygon complexity - will be moved to data preprocessing in production.
- **Douglas-Peucker**: Reduces vertex count
- **Grid Snapping**: Straightens edges to street grid
- **Convex Hull**: Extreme simplification (creates smooth envelope)
- **Curve Preservation**: Protects winding roads from over-simplification
- **Corner Rounding**: Smooths sharp corners with arcs

#### **✂️ Overlap Handling** (Runtime Features)
Visual processing applied when zones are loaded.
- **Overlap Clipping**: Cuts overlapping zones so colors don't stack
- **Polygon Merging**: Combines separate pieces of the same zone
- **Deduplication**: Removes duplicate polygons

#### **🎨 Visual Style** (Rendering Only)
Pure cosmetic controls - only affect colors/opacity/stroke, not geometry.
- **Zone Colors**: Custom colors for Paid, My Permit, Free Timed zones
- **Opacity**: Fill and stroke transparency for each category
- **Current Zone**: Override styling when user is inside a zone
- **Stroke**: Width and dash pattern

#### **🔍 Debug Visualization**
Development-only overlays for comparison.
- **Show Lookup Boundaries**: Red outline of original accurate boundaries
- **Show Original Overlay**: Dashed overlay comparing simplified vs original
- **Show Vertex Counts**: Display vertex count on zone labels

---

### 4. Basic Workflow: Testing Simplification

**Goal**: Find the best balance between visual quality and file size.

#### Step 1: Start with Defaults
All settings start at recommended defaults. The map shows zones with moderate simplification.

#### Step 2: Enable Douglas-Peucker
1. Expand **Simplification** section
2. Toggle **"Douglas-Peucker"** ON
3. Adjust **tolerance slider**:
   - Slide **left** (smaller values) = more detail, more vertices
   - Slide **right** (larger values) = more simplification, fewer vertices
4. Watch zones redraw in real-time

**What to Look For:**
- Are block edges still recognizable?
- Do diagonal streets look smooth or jagged?
- Check vertex count reduction in console logs

#### Step 3: Add Grid Snapping
1. Toggle **"Grid Snapping"** ON
2. Adjust **grid size slider**
3. Notice how edges straighten and align with SF's street grid

**Best Practice**: Use grid snapping AFTER Douglas-Peucker for cleanest results.

#### Step 4: Protect Curves (Optional)
1. If winding roads look too simplified, toggle **"Preserve Curves"** ON
2. Adjust **angle threshold**:
   - **Lower** (10-20°) = preserves gentle curves
   - **Higher** (40-60°) = only preserves sharp turns

**Use Cases:**
- Twin Peaks winding roads
- Lombard Street curves
- Hillside neighborhoods (Castro, Noe Valley)

#### Step 5: Save Your Configuration
1. Scroll to bottom of panel
2. Tap **"Save Candidate"**
3. Configuration is:
   - Copied to clipboard as JSON
   - Logged to Xcode console with human-readable description
   - Ready to integrate into data pipeline

**Example Output:**
```
=== SIMPLIFICATION CANDIDATE SAVED ===
Name: dp11m_grid5m_curves30deg

=== CONFIGURATION: dp11m_grid5m_curves30deg ===

--- PIPELINE (Preprocessing) ---
Douglas-Peucker: ON
  Tolerance: 0.00010° (~11m)
  Curve preservation: ON (>30°)
Grid Snapping: ON
  Grid size: 0.00005° (~5m)
Corner Rounding: OFF

--- APP RUNTIME (Visual Processing) ---
Overlap Clipping: OFF
Merge Same Zone: OFF
Proximity Merging: OFF
Deduplication Threshold: 95%
```

---

### 5. Advanced Workflow: Fixing Visual Issues

#### Issue: Overlapping Zones Look Too Dark

**Problem**: Multiple zones stack on top of each other, opacity compounds (20% + 20% = ~36% darker area).

**Solution A - Clipping:**
1. Expand **Overlap Handling** section
2. Toggle **"Overlap Clipping"** ON
3. Higher-priority zones (metered) clip lower-priority zones (RPP)
4. No more visual stacking

**Solution B - Reduce Opacity:**
1. Expand **Visual Style** → **Paid Zones**
2. Lower **Fill Opacity** to 10-15%
3. Overlaps will be lighter

#### Issue: Too Many Small Zone Pieces

**Problem**: A single zone (like "Zone HV") has 11 separate polygons scattered around.

**Solution - Merge:**
1. Toggle **"Merge Overlapping Same Zone"** ON (combines touching pieces)
2. OR toggle **"Proximity Merging"** ON (combines nearby pieces)
3. Adjust **proximity distance** if needed (default: 50m)

**Note**: Merging creates connecting corridors between pieces - may look strange if too aggressive.

#### Issue: Zones Rendering Multiple Times

**Problem**: Logs show the same polygon rendering over and over (duplicates from data processing).

**Solution - Deduplication:**
- Already enabled by default at 95% threshold
- Lower threshold (e.g., 80%) for more aggressive duplicate removal
- Check logs for "🔍 Removed X near-duplicate polygon(s)"

#### Issue: Need to See Original vs Simplified

**Problem**: Want to compare simplified zones against original data.

**Solution - Debug Overlays:**
1. Expand **Debug Visualization**
2. Toggle **"Show Original Overlay"** ON
3. Original boundaries appear as dashed outlines
4. Toggle **"Show Vertex Counts"** ON to see reduction numbers

---

### 6. Understanding Real-Time Performance

Every time you change a setting, the app:

1. **Clears** all existing overlays from the map
2. **Reprocesses** all 421 zones with new settings
3. **Rerenders** ~2,000-2,500 polygons (depends on settings)

**Typical Processing Time:** 150-400ms

**What Triggers Reload:**
- ✅ Changing any slider or toggle in Simplification, Overlap Handling, or Visual Style
- ✅ Tapping "Manual Refresh" button (if visible)
- ❌ Opening/closing the panel (fixed in latest version)
- ❌ Expanding/collapsing the map (fixed in latest version)

**Monitoring Reloads:**
Check Xcode console for:
```
🔄 Developer settings changed - reloading overlays
🔍 Removed 46 near-duplicate polygon(s) (≥95% overlap)
Deferred overlays loaded: 615 polygons
```

---

### 7. Exporting Configurations for Production

When you've found settings you like:

#### Step 1: Save Candidate
1. Tap **"Save Candidate"** button
2. See confirmation: "Saved as 'dp11m_grid5m_curves30deg'"
3. JSON is copied to clipboard

#### Step 2: Paste Configuration
Paste from clipboard into your notes/issue tracker. You'll see:

```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "useDouglasPeucker": true,
  "douglasPeuckerTolerance": 0.0001,
  "useGridSnapping": true,
  "gridSnapSize": 0.00005,
  "useConvexHull": false,
  "preserveCurves": true,
  "curveAngleThreshold": 30,
  "useCornerRounding": false,
  "cornerRoundingRadius": 0.00003,
  "useOverlapClipping": false,
  "overlapTolerance": 0.00001,
  "mergeOverlappingSameZone": false,
  "useProximityMerging": false,
  "proximityMergeDistance": 50,
  "deduplicationThreshold": 0.95
}
```

#### Step 3: Check Xcode Console
The console also prints:
- Human-readable configuration summary
- Swift code snippet for easy integration
- Vertex reduction statistics (if enabled)

#### Step 4: Integrate into Pipeline
**Pipeline features** (Douglas-Peucker, Grid Snapping, etc.) should be applied during GeoJSON preprocessing to reduce app bundle size and improve load times.

**Runtime features** (Overlap Clipping, Merging) can stay in the app for now, but may move to pipeline later if they prove stable.

---

## Technical Reference

### Processing Pipeline Order

All manipulations are applied in this exact order:

```
1. Proximity Filtering (hardcoded ~3.3km radius)
   ↓
2. SIMPLIFICATION PIPELINE (per polygon)
   ├─ Douglas-Peucker (optional)
   ├─ Grid Snapping (optional)
   ├─ Convex Hull (optional - aggressive)
   └─ Corner Rounding (optional)
   ↓
3. Overlap Clipping (optional - cross-polygon)
   ↓
4. Polygon Merging (optional - same-zone groups)
   ↓
5. Deduplication (removes near-duplicates)
   ↓
6. Zone Type Sorting (fixed priority: Metered → Non-Permitted RPP → Permitted RPP)
   ↓
7. Rendering (colors, opacity, stroke - MapKit GPU)
```

---

### Step 0: Proximity Filtering

**Purpose**: Performance optimization - only process zones near the viewport.

**Algorithm**: Bounding box intersection check
```swift
let filterRadius = 0.03  // ~3.3km
let hasNearbyPoint = boundary.contains { coord in
    coord.latitude >= minLat && coord.latitude <= maxLat &&
    coord.longitude >= minLon && coord.longitude <= maxLon
}
```

**Parameters**: None (hardcoded)

**Production Strategy**: Keep in app - always needed for performance.

**Typical Result**: Filters from 421 zones → ~200-300 zones (depends on map position)

---

### Step 1: Douglas-Peucker Simplification

**Purpose**: Reduce vertex count while preserving polygon shape.

**Algorithm**: Recursive divide-and-conquer
1. Draw line from start→end point
2. Find point with maximum perpendicular distance from line
3. If distance > tolerance, keep point and recursively simplify [start→max] and [max→end]
4. If distance ≤ tolerance, discard all intermediate points

**Mathematical Formula**:
```
distance = |cross_product(p - p1, p2 - p1)| / length(p2 - p1)
```

**Parameters**:
- **Enable**: `useDouglasPeucker: Bool`
- **Tolerance**: `douglasPeuckerTolerance: Double` (degrees)
  - **Units**: Degrees latitude/longitude
  - **Conversion**: 1° ≈ 111km, so 0.00001° ≈ 1.11m
  - **Range**: 0.00001 (1m) to 0.001 (110m)
  - **Default**: 0.00005 (5.5m)
  - **Sweet Spot**: 0.00008 - 0.00012 (9-13m) for SF

**Trade-offs**:
- ✅ **Smaller tolerance** (0.00001):
  - Preserves fine detail
  - Keeps more vertices (~10-20% reduction)
  - Larger file size
  - Good for: zoomed-in views, curved areas

- ✅ **Larger tolerance** (0.0001):
  - Aggressive simplification
  - Removes most vertices (~50-70% reduction)
  - Smaller file size
  - May lose detail on diagonal streets
  - Good for: zoomed-out views, simple blocks

**Performance**: O(n log n) average, ~10-30ms for SF dataset

**Production Strategy**:
✅ **Move to Pipeline** - Apply during GeoJSON preprocessing
- Pre-simplify with tolerance 0.0001° (~11m)
- Reduces app bundle by ~30-50%
- Users can't adjust, so test carefully first

**Visual Examples**:
- **Original**: 47 vertices for 1-block zone
- **Tolerance 0.00005**: 28 vertices (40% reduction)
- **Tolerance 0.0001**: 15 vertices (68% reduction)

---

### Step 1b: Curve Preservation

**Purpose**: Protect winding roads from over-simplification when Douglas-Peucker is enabled.

**Algorithm**: Two-pass approach
1. **Identify curves**: Scan all vertices, calculate angle deviation
   ```
   angle = angleBetweenSegments(prev, current, next)
   isCurve = abs(180° - angle) > curveThreshold
   ```
2. **Preserve curves**: Run Douglas-Peucker but force-keep all curve points

**Parameters**:
- **Enable**: `preserveCurves: Bool` (only applies if D-P enabled)
- **Threshold**: `curveAngleThreshold: Double` (degrees)
  - **Units**: Degrees of angle deviation from straight
  - **Range**: 10° to 90°
  - **Default**: 30°
  - **Lower** (10-20°): Preserves gentle curves, saves fewer vertices
  - **Higher** (40-60°): Only preserves sharp turns, more aggressive

**Trade-offs**:
- ✅ Preserves character of winding roads (Twin Peaks, Lombard Street)
- ❌ Reduces vertex savings (may only get 30% reduction instead of 50%)

**Use Cases**:
- **Enable for**: Hilly neighborhoods, diagonal streets, waterfront curves
- **Disable for**: Downtown grid streets, rectangular zones

**Performance**: +5-10ms over standard D-P

**Production Strategy**:
✅ **Move to Pipeline** with D-P
- Use threshold 25-35° for good balance
- Essential for maintaining neighborhood character

**Example**:
```
Zone: Twin Peaks (winding roads)
Original: 127 vertices

D-P only (tolerance 0.0001): 34 vertices (73% reduction)
  → Problem: Curves become straight, looks wrong

D-P + Curve Preservation (threshold 30°): 58 vertices (54% reduction)
  → Curves preserved, still good reduction
```

---

### Step 2: Grid Snapping

**Purpose**: Align vertices to a regular grid for cleaner, straighter edges aligned with SF's street grid.

**Algorithm**: Simple rounding
```swift
func gridSnap(_ coord: CLLocationCoordinate2D, gridSize: Double) -> CLLocationCoordinate2D {
    return CLLocationCoordinate2D(
        latitude: round(coord.latitude / gridSize) * gridSize,
        longitude: round(coord.longitude / gridSize) * gridSize
    )
}
```

**Parameters**:
- **Enable**: `useGridSnapping: Bool`
- **Grid Size**: `gridSnapSize: Double` (degrees)
  - **Units**: Degrees latitude/longitude
  - **Range**: 0.00001 (1m) to 0.0002 (22m)
  - **Default**: 0.00005 (5.5m)
  - **Common values**:
    - 0.00002 (2.2m): Fine grid, subtle straightening
    - 0.00005 (5.5m): Block-corner snapping (recommended)
    - 0.0001 (11m): Half-block snapping (aggressive)

**Best Practices**:
1. **Always use AFTER Douglas-Peucker** (D-P first reduces points, then grid cleans them up)
2. **Best for downtown** SF grid streets (Market, Mission, numbered streets)
3. **Less effective** in diagonal areas (Mission Bay, Embarcadero)

**Visual Effect**:
- Creates right angles at intersections
- Removes GPS jitter/noise
- Makes zones look "crisp" and aligned

**Side Effects**:
- Creates consecutive duplicate points (automatically removed)
- May shift boundaries by up to gridSize/2 in any direction
- Can reduce vertex count by additional 5-15% (duplicates removed)

**Performance**: O(n), ~5-10ms for SF dataset

**Production Strategy**:
✅ **Move to Pipeline** - Apply after Douglas-Peucker
- Use 0.00005° (5.5m) for good balance
- Creates cleaner GeoJSON that's easier to manually edit

**Example**:
```
Original coordinates (GPS noise):
  (37.77491, -122.41894)
  (37.77493, -122.41896)  ← jittery
  (37.77489, -122.41892)

Grid snapped (0.00005° grid):
  (37.77490, -122.41895)
  (37.77490, -122.41895)  ← duplicate (removed)
  (37.77490, -122.41890)
```

---

### Step 3: Convex Hull

**Purpose**: Replace polygon with its convex envelope (smallest convex shape containing all points).

**Algorithm**: Graham's scan
1. Find lowest point (lexicographically)
2. Sort remaining points by polar angle
3. Scan points, maintaining convex property (turn direction test)
4. Return outer perimeter only

**Parameters**:
- **Enable**: `useConvexHull: Bool` (no tolerance - all or nothing)

**Visual Effect**:
- Creates smooth, bulging outline
- **Eliminates**: Interior cutouts, courtyard gaps, indentations
- **Most aggressive** simplification (50-90% vertex reduction)

**Trade-offs**:
- ✅ Extreme file size reduction
- ✅ Very smooth appearance
- ❌ **LOSES ACCURACY** - zone boundaries become incorrect
- ❌ May include areas not actually in the zone
- ❌ May exclude areas that ARE in the zone

**Use Cases**:
- ⚠️ Testing extreme simplification
- ⚠️ Abstract/artistic visualization only
- ⚠️ Maybe for zoomed-out city-wide view
- ❌ **NOT for navigation/lookup** (too inaccurate)

**Performance**: O(n log n), ~5-10ms

**Production Strategy**:
❌ **DO NOT use in pipeline** - Too lossy, creates incorrect zones

**Example**:
```
Zone: "L"-shaped zone with courtyard
Original: 24 vertices forming L-shape with gap

Convex Hull: 8 vertices forming filled rectangle
  → Gap is now filled (WRONG - parking not allowed there!)
```

---

### Step 4: Corner Rounding

**Purpose**: Smooth sharp corners by replacing angular vertices with circular arc segments.

**Algorithm**: Trigonometric arc interpolation
1. For each corner with angle < 180° (convex corner):
2. Calculate tangent points at radius distance from vertex
3. Generate arc points following circular path
4. Insert arc points, remove original vertex

**Parameters**:
- **Enable**: `useCornerRounding: Bool`
- **Radius**: `cornerRoundingRadius: Double` (degrees)
  - **Units**: Degrees (radius of circular arc)
  - **Range**: 0.00001 (1m) to 0.0001 (11m)
  - **Default**: 0.00003 (3.3m)
  - **Small** (0.00001-0.00002): Subtle rounding, barely noticeable
  - **Medium** (0.00003-0.00005): Noticeable smooth corners (recommended for visuals)
  - **Large** (0.0001): Very rounded, bubble-like appearance

**Side Effects**:
- **Increases vertex count** by ~3-5 points per corner (opposite of simplification!)
- Works against Douglas-Peucker savings
- Best used AFTER all simplification steps (as final polish)

**Visual Effect**:
- Makes zones look friendlier, less geometric
- Good for marketing materials, presentation slides
- Creates organic, hand-drawn appearance

**Performance**: O(n), ~10-20ms

**Production Strategy**:
⚠️ **Maybe Pipeline** - Depends on aesthetic preference
- Only use if you want rounded look permanently
- Otherwise keep in app for user customization

**Example**:
```
Sharp corner:
  Points: A, B (corner), C
  Vertices: 3

Rounded corner (radius 3m, 5 arc points):
  Points: A, arc1, arc2, arc3, arc4, arc5, C
  Vertices: 7  (added 4 points)
```

---

### Step 5: Overlap Clipping

**Purpose**: When two zones overlap, clip the lower-priority zone to remove the overlapping area. Prevents visual "double darkening" from stacked opacity.

**Algorithm**: Sutherland-Hodgman polygon clipping
1. Sort all polygons by priority:
   - **Metered zones** > RPP zones (paid beats free)
   - **Vertical zones** (N-S) > Horizontal zones (E-W)
2. For each polygon pair that overlaps (bounding box check):
3. Clip lower-priority polygon against each edge of higher-priority polygon
4. Replace original with clipped result (may be multiple pieces)

**Priority Determination**:
```swift
func priority(_ polygon: Polygon) -> Int {
    // Higher number = higher priority (renders on top, clips others)
    var priority = 0

    // Metered zones have highest priority
    if polygon.zoneType == .metered {
        priority += 1000
    }

    // Vertical orientation gets bonus
    let boundingBox = polygon.boundingBox
    let isVertical = (boundingBox.height > boundingBox.width)
    if isVertical {
        priority += 100
    }

    return priority
}
```

**Parameters**:
- **Enable**: `useOverlapClipping: Bool`
- **Tolerance**: `overlapTolerance: Double` (degrees)
  - **Units**: Degrees (floating-point comparison tolerance)
  - **Range**: 0.000001 to 0.0001
  - **Default**: 0.00001
  - Used for coordinate equality checks
  - **Too small**: May miss clips due to floating-point errors
  - **Too large**: May clip non-overlapping edges

**Visual Effect**:
- Clean zone boundaries - no color stacking
- Complex clipped shapes (may create slivers)
- Helps distinguish where one zone ends and another begins

**Trade-offs**:
- ✅ Cleaner visual appearance
- ✅ Easier to see zone boundaries
- ❌ May create many small polygon fragments
- ❌ Complex geometry (more vertices in some cases)
- ❌ Slower (O(n*m) for overlapping pairs)

**Performance**: ~50-150ms for SF dataset (depends on overlap count)

**Production Strategy**:
⚠️ **Could Move to Pipeline** - But has challenges:
- **Challenge**: Clipping priority depends on which zones user has permits for
- **Solution A**: Apply generic priority rules (metered > RPP, vertical > horizontal)
- **Solution B**: Keep in app for runtime personalization

**Example**:
```
Before Clipping:
  Zone A (Metered, grey): Rectangle at (0,0) to (10,10)
  Zone B (RPP, orange): Rectangle at (5,0) to (15,10)
  → Overlap: (5,0) to (10,10)
  → User sees dark area where grey+orange stack

After Clipping:
  Zone A (Metered): Rectangle at (0,0) to (10,10) [unchanged - higher priority]
  Zone B (RPP): Clipped to (10,0) to (15,10) [left edge clipped away]
  → No overlap, clean boundary at x=10
```

---

### Step 6: Polygon Merging

**Purpose**: Combine multiple separate polygons from the same zone into fewer, larger polygons.

**Two Modes**:

#### Mode A: Overlap Merging
Merges polygons that overlap or share edges.

**Algorithm**: Boolean union operation
```
for each zone:
    group = all polygons with same zone ID
    for each pair in group:
        if overlap or touching:
            union = booleanUnion(poly1, poly2)
            replace both with union
```

**When to Use**: Zone has multiple pieces that touch/overlap due to data artifacts.

#### Mode B: Proximity Merging
Merges polygons within X meters of each other by creating connecting corridors.

**Algorithm**: Distance-based bridging
```
for each zone:
    group = all polygons with same zone ID
    for each pair in group:
        distance = centroidDistance(poly1, poly2)
        if distance < threshold:
            connector = createConnectingRectangle(poly1, poly2)
            union = booleanUnion(poly1, connector, poly2)
            replace all with union
```

**When to Use**: Zone has scattered pieces you want to visually connect.

**Parameters**:
- **Overlap Enable**: `mergeOverlappingSameZone: Bool`
- **Proximity Enable**: `useProximityMerging: Bool`
- **Proximity Distance**: `proximityMergeDistance: Double` (meters)
  - **Units**: Meters (not degrees!)
  - **Range**: 10m to 200m
  - **Default**: 50m
  - **Small** (10-25m): Only very close pieces merge (conservative)
  - **Medium** (50-75m): Merge nearby pieces (recommended)
  - **Large** (100-200m): Aggressive merging, may create weird corridors

**Visual Effect**:
- Fewer, larger polygons instead of many scattered pieces
- Cleaner appearance
- May create strange connector shapes if too aggressive

**Trade-offs**:
- ✅ Reduces polygon count (10-30% typical)
- ✅ Cleaner map appearance
- ❌ **May create incorrect zones** (merging across streets)
- ❌ Connecting corridors may not match real parking boundaries
- ❌ Computationally expensive (complex geometry operations)

**Performance**: ~30-100ms

**Production Strategy**:
✅ **Overlap Merging → Pipeline** - Safe, cleans up data artifacts
⚠️ **Proximity Merging → Keep in App** - Needs manual tuning per area

**Example**:
```
Zone HV (Hayes Valley) - 11 separate polygons:
  Polygon 1: Hayes St (blocks 1-2)
  Polygon 2: Hayes St (blocks 3-4)
  ...
  Polygon 11: Fell St (block 8)

After Overlap Merging:
  → No change (none touching)

After Proximity Merging (50m threshold):
  → Polygons 1-4 merged (within 50m)
  → Polygons 5-9 merged
  → Polygon 10-11 merged
  → Result: 3 large polygons instead of 11
```

---

### Step 7: Deduplication

**Purpose**: Remove near-duplicate polygons that are essentially the same (≥95% bounding box overlap).

**Algorithm**: Pairwise bounding box comparison
```swift
for i in 0..<polygons.count:
    for j in (i+1)..<polygons.count:
        if sameZone(polygons[i], polygons[j]):
            overlap = boundingBoxOverlap(polygons[i], polygons[j])
            smaller = min(area[i], area[j])
            if (overlap / smaller) >= threshold:
                // Keep polygon with fewer vertices (more simplified)
                // or smaller area (more specific)
                remove(polygon with more vertices)
```

**Why Needed**: Data processing artifacts create near-identical polygons:
- Floating-point rounding differences
- Multiple data sources with slight variations
- Simplification creating convergent shapes

**Parameters**:
- **Threshold**: `deduplicationThreshold: Double` (0.0 - 1.0)
  - **Units**: Fraction of overlap (0.95 = 95% overlap)
  - **Range**: 0.80 to 1.0
  - **Default**: 0.95 (95% overlap)
  - **Lower** (0.80): More aggressive, may remove distinct polygons
  - **Higher** (0.98): Very conservative, only removes near-exact duplicates
  - **1.0**: Only removes 100% identical polygons

**Selection Rules** (when duplicate found):
Keep the polygon with:
1. **Fewer vertices** (more simplified) OR
2. **Smaller area** (more specific/detailed)

Discard the other.

**Performance**: O(n²), but fast (~10-20ms) due to bounding box optimization

**Typical Results**: Removes ~46 polygons from SF dataset (2%)

**Production Strategy**:
✅ **Move to Pipeline** - Always safe, no downside
- Run as final cleanup before bundling GeoJSON
- Use 0.95 threshold
- Reduces polygon count without any visual impact

**Example**:
```
Polygon A: Zone "P" at Market St
  Vertices: 18
  Bounding box: (37.7749, -122.4194) to (37.7755, -122.4186)
  Area: 0.000048

Polygon B: Zone "P" at Market St (slight variation)
  Vertices: 22
  Bounding box: (37.7749, -122.4194) to (37.7755, -122.4185)
  Area: 0.000050

Overlap check:
  Overlap area: 0.000046
  Smaller area: 0.000048
  Ratio: 0.000046 / 0.000048 = 0.96 (96%)

Result: 96% > 95% threshold → Duplicate detected
  → Keep Polygon A (fewer vertices: 18 < 22)
  → Remove Polygon B
```

---

### Step 8: Zone Type Sorting

**Purpose**: Control rendering order (z-index) so zones appear in correct visual priority.

**Algorithm**: Array concatenation in fixed order
```swift
let orderedPolygons = meteredPolygons + nonPermittedPolygons + permittedPolygons
mapView.addOverlays(orderedPolygons, level: .aboveRoads)
```

**Layer Order** (bottom → top):
1. **Metered zones** (grey, paid parking) - bottom layer
2. **Non-permitted RPP** (orange, free timed parking) - middle layer
3. **Permitted RPP** (green, user has permit) - top layer

**Why This Order**:
- User's permit zones are most important → render on top
- Paid parking is least favorable → render on bottom
- Free timed parking (RPP without permit) is middle ground

**Parameters**: None - fixed priority

**Performance**: O(n), instant (just array operations)

**Production Strategy**:
🔒 **Always App Runtime** - Cannot preprocess because it's personalized per-user
- Depends on which permits the user has entered
- Different users see different layer orders

**Example**:
```
User has Permit: "I" (Ingleside)

All polygons:
  [Metered #1, RPP-P, RPP-I, Metered #2, RPP-Q]

After sorting:
  [Metered #1, Metered #2]  ← Bottom (grey)
  [RPP-P, RPP-Q]            ← Middle (orange - user doesn't have permit)
  [RPP-I]                   ← Top (green - user has this permit)

User sees RPP-I zones prominently on top of everything else.
```

---

### Step 9: Rendering

**Purpose**: Apply visual styling (colors, opacity, stroke) to polygons. Does NOT modify geometry.

**Algorithm**: MapKit delegate callback
```swift
func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    let polygon = overlay as! ZonePolygon
    let renderer = MKPolygonRenderer(polygon: polygon)

    // 1. Determine category
    let category = determineCategory(polygon)

    // 2. Look up colors/opacity for category
    renderer.fillColor = categoryColor.withAlpha(categoryFillOpacity)
    renderer.strokeColor = categoryColor.withAlpha(categoryStrokeOpacity)
    renderer.lineWidth = globalStrokeWidth

    // 3. Check for overrides
    if isCurrentZone {
        renderer.fillColor = color.withAlpha(currentZoneFillOpacity)
        renderer.strokeColor = color.withAlpha(currentZoneStrokeOpacity)
    }

    // 4. Apply dash pattern if multi-permit
    if isMultiPermit && dashLength > 0 {
        renderer.lineDashPattern = [dashLength, dashLength * 0.5]
    }

    return renderer
}
```

**Categories**:
1. **Paid Zones** (metered parking)
2. **My Permit Zones** (user has permit for this RPP zone)
3. **Free Timed Zones** (RPP zones without user's permit)
4. **Current Zone** (user is physically inside this zone - overrides above)

**Parameters** (18 total):

#### Per-Category Colors (hex strings):
- `paidZonesColorHex` - Default: "808080" (grey)
- `myPermitZonesColorHex` - Default: "33B366" (green)
- `freeTimedZonesColorHex` - Default: "F29933" (orange)

#### Per-Category Fill Opacity (0.0 - 1.0):
- `paidZonesFillOpacity` - Default: 0.20 (20%)
- `myPermitZonesFillOpacity` - Default: 0.20
- `freeTimedZonesFillOpacity` - Default: 0.20

#### Per-Category Stroke Opacity (0.0 - 1.0):
- `paidZonesStrokeOpacity` - Default: 0.60 (60%)
- `myPermitZonesStrokeOpacity` - Default: 0.60
- `freeTimedZonesStrokeOpacity` - Default: 0.60

#### Current Zone Override (0.0 - 1.0):
- `currentZoneFillOpacity` - Default: 0.30 (30%)
- `currentZoneStrokeOpacity` - Default: 0.80 (80%)

#### Global Stroke:
- `strokeWidth` - Range: 0.0 to 5.0 points, Default: 1.0
- `dashLength` - Range: 0.0 to 10.0, Default: 0.0 (solid)
  - 0 = solid line
  - >0 = dashed line (pattern: [dashLength, dashLength*0.5])

**Special Cases**:

**Multi-Permit Zones**: Some polygons allow parking with multiple different permits.
- If user has ANY of the valid permits → render as "My Permit Zone" (green)
- If user has NONE of the valid permits → render as "Free Timed Zone" (orange)
- Apply dashed border if `dashLength > 0`

**Current Zone**: If user's GPS location is inside a zone:
- Override fill/stroke opacity with `currentZone*Opacity` values
- Keep the category color (grey/green/orange)
- Makes current zone more prominent

**Performance**: GPU-accelerated, instant rendering per polygon

**Production Strategy**:
🔒 **Always App Runtime** - Pure visual preferences
- Users should be able to customize colors/opacity
- Consider adding theme support (light/dark mode)
- Possibly add accessibility presets (high contrast)

---

## Performance Characteristics

### Processing Time Breakdown

**SF Dataset** (421 zones, ~2,500 raw polygons):

| Operation | Time (ms) | Notes |
|-----------|-----------|-------|
| Proximity Filter | <1 | Hardcoded, very fast |
| Douglas-Peucker | 10-30 | Depends on tolerance |
| Grid Snapping | 5-10 | Simple rounding |
| Convex Hull | 5-10 | O(n log n) |
| Corner Rounding | 10-20 | Adds vertices |
| Overlap Clipping | 50-150 | Most expensive |
| Polygon Merging | 30-100 | Complex geometry |
| Deduplication | 10-20 | Fast bounding box check |
| **Total** | **150-400ms** | Varies by settings |
| Rendering | GPU | Instant per polygon |

### Vertex Count Impact

**Original Dataset**: ~85,000 total vertices across all zones

| Configuration | Total Vertices | Reduction | File Size Impact |
|---------------|----------------|-----------|------------------|
| Original (no simplification) | ~85,000 | 0% | 100% (baseline) |
| D-P (0.00005, 5.5m) | ~55,000 | 35% | ~65% |
| D-P + Grid Snapping | ~48,000 | 44% | ~57% |
| D-P + Grid + Curves | ~58,000 | 32% | ~68% |
| D-P + Grid + Corner Rounding | ~62,000 | 27% | ~73% |
| Convex Hull only | ~12,000 | 86% | ~14% |

### Polygon Count Impact

**Original Dataset**: ~2,500 polygons (after multipolygon expansion)

| Operation | Polygon Count | Change |
|-----------|---------------|--------|
| Original | 2,500 | - |
| After Deduplication | 2,454 | -46 (-2%) |
| After Overlap Merging | 2,200-2,350 | -150-300 (-6-12%) |
| After Proximity Merging (50m) | 1,800-2,100 | -400-700 (-16-28%) |

### Memory Usage

- **Raw GeoJSON**: ~3.2 MB
- **Simplified (D-P + Grid)**: ~1.8 MB (44% reduction)
- **In-Memory Polygons**: ~8-12 MB (depends on settings)
- **Rendered Map Tiles**: GPU memory, varies by zoom

---

## Recommended Production Configurations

### Configuration 1: Balanced (Recommended)
**Goal**: Good balance between file size and visual quality.

```json
{
  "useDouglasPeucker": true,
  "douglasPeuckerTolerance": 0.0001,
  "useGridSnapping": true,
  "gridSnapSize": 0.00005,
  "preserveCurves": true,
  "curveAngleThreshold": 30,
  "useCornerRounding": false,
  "useOverlapClipping": false,
  "mergeOverlappingSameZone": true,
  "useProximityMerging": false,
  "deduplicationThreshold": 0.95
}
```

**Expected Results**:
- 40-45% vertex reduction
- Clean, straight edges on grid streets
- Curves preserved in hilly areas
- ~150-200ms processing time

---

### Configuration 2: Maximum Quality
**Goal**: Preserve as much detail as possible while still cleaning up data.

```json
{
  "useDouglasPeucker": true,
  "douglasPeuckerTolerance": 0.00005,
  "useGridSnapping": false,
  "preserveCurves": true,
  "curveAngleThreshold": 20,
  "useCornerRounding": false,
  "useOverlapClipping": false,
  "mergeOverlappingSameZone": true,
  "deduplicationThreshold": 0.98
}
```

**Expected Results**:
- 25-30% vertex reduction
- High detail preservation
- Longer processing time (~250-350ms)

---

### Configuration 3: Maximum Compression
**Goal**: Smallest possible file size for low-end devices.

```json
{
  "useDouglasPeucker": true,
  "douglasPeuckerTolerance": 0.00015,
  "useGridSnapping": true,
  "gridSnapSize": 0.0001,
  "preserveCurves": false,
  "useCornerRounding": false,
  "useOverlapClipping": false,
  "mergeOverlappingSameZone": true,
  "useProximityMerging": true,
  "proximityMergeDistance": 75,
  "deduplicationThreshold": 0.90
}
```

**Expected Results**:
- 60-70% vertex reduction
- Noticeable quality loss on curves
- Very small file size
- Fastest processing (~100-150ms)

---

## Troubleshooting

### Issue: Zones look too jagged/pixelated
**Cause**: Douglas-Peucker tolerance too high
**Solution**: Lower `douglasPeuckerTolerance` to 0.00005-0.00008

### Issue: Zones don't align with streets
**Cause**: Grid snapping disabled or too fine
**Solution**: Enable grid snapping with `gridSnapSize` = 0.00005

### Issue: Winding roads look unrealistic
**Cause**: Curve preservation disabled
**Solution**: Enable `preserveCurves` with threshold 25-35°

### Issue: Processing takes too long (>500ms)
**Cause**: Complex operations (clipping, merging)
**Solution**: Disable overlap clipping and proximity merging

### Issue: Overlapping zones create dark areas
**Cause**: Opacity stacking
**Solution A**: Enable overlap clipping
**Solution B**: Reduce fill opacity to 0.10-0.15

### Issue: Too many small polygon fragments
**Cause**: Overlap clipping creating slivers
**Solution**: Disable clipping OR enable merging to recombine fragments

### Issue: Zones disappearing after reload
**Cause**: `.id()` modifier preventing view updates
**Solution**: Already fixed - ensure running latest code with `.id("zoneMapView-\(zoneCount)")`

### Issue: Excessive reloads on panel open/close
**Cause**: UI state changes triggering overlay reload
**Solution**: Already fixed - ensure running latest code with zone-count-based view identity

---

## Glossary

**Bounding Box**: Smallest rectangle (aligned to lat/lon axes) that contains all points of a polygon.

**Centroid**: Geographic center point of a polygon (average of all vertices).

**Convex**: A shape where any line drawn between two points inside the shape stays inside the shape (no indentations).

**Coordinate**: A (latitude, longitude) pair representing a point on Earth.

**Degrees**: Unit of angular measurement. 1° latitude ≈ 111km. At SF's latitude, 1° longitude ≈ 85km.

**GeoJSON**: Standard file format for geographic data (polygons, points, etc.).

**MapKit**: Apple's framework for displaying maps and rendering geographic shapes.

**Multipolygon**: A zone represented by multiple separate polygons (e.g., zone split by a park).

**Overlay**: A visual layer drawn on top of the map (zone boundaries are rendered as overlays).

**Pipeline**: Data processing that happens before the app runs (preprocessing).

**Renderer**: Code that converts polygon geometry into pixels on screen (GPU-accelerated).

**RPP**: Residential Permit Parking (zones requiring permits for long-term parking).

**Simplification**: Process of reducing polygon complexity while preserving overall shape.

**Tolerance**: Maximum allowed distance/error in a simplification algorithm.

**Vertex**: A corner point in a polygon (plural: vertices).

**Z-index**: Drawing order - higher z-index renders on top of lower z-index.

---

## Version History

- **v1.0** (2025-01-15): Initial developer overlay tools with all manipulations
- **v1.1** (2025-01-15): Fixed excessive reloading on UI state changes
- **v1.2** (2025-01-15): Fixed zone disappearance with dynamic view ID
- **v1.3** (2025-01-15): Updated SimplificationCandidate to save all settings

---

## Future Enhancements

**Planned Features**:
- [ ] Side-by-side comparison view (original vs simplified)
- [ ] Vertex count heat map (show which zones are most complex)
- [ ] Export to multiple formats (GeoJSON, KML, Shapefile)
- [ ] Batch processing (apply settings to multiple cities)
- [ ] Undo/redo for settings changes
- [ ] Preset library (save/load named configurations)
- [ ] A/B testing mode (compare two configurations)

**Pipeline Integration**:
- [ ] Python script to apply SimplificationCandidate to GeoJSON files
- [ ] Batch processing tool for all SF zones
- [ ] Quality metrics (visual similarity score, vertex reduction %)
- [ ] Automated testing suite for regression checks

---

## Contact & Support

For questions, issues, or feature requests related to developer overlay tools:
- **GitHub Issues**: https://github.com/fikei/ParkLookup/issues
- Tag issues with `developer-tools` label

---

*Last updated: January 15, 2025*
