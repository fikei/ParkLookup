# Performance Optimization Guide

## Problem: Slow Map Loading (32MB, 18,355 blockfaces)

The full SF dataset causes significant lag when loading the map because:
1. **32MB JSON parsing** takes 2-3 seconds
2. **18,355 geometry objects** created in memory (~250MB)
3. **Rendering all polygons** at once overwhelms the map view

## Solutions (In Order of Impact)

### ✅ 1. Regional Data Loading (94% File Size Reduction)

**Impact:** Load time 2-3 seconds → **0.2-0.5 seconds**

Instead of loading all 18,355 blockfaces, load only the region containing the user:

| Region | Blockfaces | File Size | Load Time |
|--------|-----------|-----------|-----------|
| Full SF | 18,355 | 32 MB | 2-3 sec |
| Downtown | 1,566 | 1.9 MB | 0.2-0.3 sec |
| Mission | 1,283 | 1.3 MB | 0.2 sec |
| Richmond | 1,720 | 1.4 MB | 0.2 sec |

**Implementation:**

```swift
// 1. Detect user's region from their location
func detectRegion(for coordinate: CLLocationCoordinate2D) -> String {
    // Check which region bounds contain the coordinate
    // Return region ID (e.g., "downtown", "mission")
}

// 2. Load only relevant region
func loadBlockfacesForRegion(_ regionId: String) {
    let filename = "blockfaces_\(regionId).json"
    // Load from app bundle
}

// 3. Optionally load adjacent regions for seamless panning
func loadAdjacentRegions(_ centerRegion: String) {
    // Load neighboring regions in background
}
```

**Files Created:**
- `data/processed/regional/blockfaces_downtown.json` (1.9MB)
- `data/processed/regional/blockfaces_mission.json` (1.3MB)
- `data/processed/regional/blockfaces_richmond.json` (1.4MB)
- etc.
- `data/processed/regional/region_index.json` (region boundaries)

### ✅ 2. Viewport-Based Rendering (App-Side)

**Impact:** Render time instant for any zoom level

Only render blockfaces visible in current map viewport:

```swift
func updateVisibleBlockfaces() {
    let visibleRegion = mapView.region

    // Filter to only visible blockfaces
    let visibleBlockfaces = allBlockfaces.filter { blockface in
        blockface.intersects(visibleRegion)
    }

    // Remove off-screen overlays
    removeInvisibleOverlays()

    // Add visible overlays
    addOverlays(for: visibleBlockfaces)
}

// Call on map region change
func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    updateVisibleBlockfaces()
}
```

### ✅ 3. Background JSON Parsing

**Impact:** UI stays responsive during load

Parse JSON on background thread:

```swift
func loadBlockfaces(region: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        // Parse JSON on background thread
        let blockfaces = parseJSON(region)

        DispatchQueue.main.async {
            // Update UI on main thread
            self.blockfaces = blockfaces
            self.renderMap()
        }
    }
}
```

### 4. Coordinate Precision Reduction (Optional)

**Impact:** 15-20% file size reduction

Reduce coordinate precision from 15 decimals to 5 (still ~1 meter accuracy):

```python
# In converter
coords = [(round(lon, 5), round(lat, 5)) for lon, lat in coords]
```

Before: `-122.419999999999999, 37.775555555555555`
After: `-122.42000, 37.77556`

Savings: ~5-7MB total

### 5. Incremental/Lazy Loading

**Impact:** Progressive improvement as user pans

Load and render in batches:

```swift
func loadIncrementally() {
    let batchSize = 500
    var offset = 0

    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
        let batch = blockfaces[offset..<min(offset + batchSize, blockfaces.count)]
        self.addToMap(batch)

        offset += batchSize
        if offset >= blockfaces.count {
            timer.invalidate()
        }
    }
}
```

### 6. Caching Strategy

**Impact:** Instant subsequent loads

Cache parsed blockfaces in memory:

```swift
class BlockfaceCache {
    static let shared = BlockfaceCache()
    private var cache: [String: [Blockface]] = [:]

    func get(region: String) -> [Blockface]? {
        return cache[region]
    }

    func set(region: String, blockfaces: [Blockface]) {
        cache[region] = blockfaces
    }
}
```

## Recommended Architecture

### Phase 1: Regional Loading (Implement Now)

```
User opens app → Detect location → Load only relevant region
  Downtown? → Load 1.9MB (1,566 blockfaces)
  Mission?  → Load 1.3MB (1,283 blockfaces)
  Richmond? → Load 1.4MB (1,720 blockfaces)
```

**Result:** 94% faster initial load (0.2-0.5 sec vs 2-3 sec)

### Phase 2: Viewport Filtering (Add Next)

```
Map loads → Filter to visible blockfaces only
  Zoomed in?  → Render ~50-200 blockfaces
  Zoomed out? → Render ~500-2,000 blockfaces
```

**Result:** Instant rendering at any zoom level

### Phase 3: Adjacent Region Preloading (Polish)

```
User near region boundary → Preload adjacent regions in background
  In Mission near Downtown? → Load Downtown in background
```

**Result:** Seamless panning across region boundaries

## Implementation Priority

**High Priority (Do First):**
1. ✅ Regional data splitting (already done)
2. ✅ Load only user's region
3. ✅ Viewport-based rendering

**Medium Priority:**
4. Background JSON parsing
5. Adjacent region preloading
6. Memory caching

**Low Priority (Only if needed):**
7. Coordinate precision reduction
8. Binary format (MessagePack)

## Performance Targets

| Metric | Before | After Regional | After Viewport |
|--------|--------|----------------|----------------|
| Initial load | 2-3 sec | **0.2-0.5 sec** | **0.2-0.5 sec** |
| Memory usage | 250 MB | **20-40 MB** | **5-15 MB** |
| File size | 32 MB | **1-2 MB** | **1-2 MB** |
| Render time | 1-2 sec | **0.5 sec** | **<0.1 sec** |

## Using Regional Data in App

**1. Copy regional files to app bundle:**
```bash
cp -r data/processed/regional/*.json \
    SFParkingZoneFinder/SFParkingZoneFinder/Resources/regions/
```

**2. Update app to use region detection:**
```swift
// On app launch or location update
let userRegion = RegionDetector.detect(coordinate: userLocation)
let blockfaces = loadBlockfaces(region: userRegion)
```

**3. Handle region boundaries:**
- Load adjacent regions when near boundaries
- Or use "other" region as fallback for outlying areas

## Monitoring

Add performance logging:

```swift
let startTime = CFAbsoluteTimeGetCurrent()
loadBlockfaces(region: region)
let loadTime = CFAbsoluteTimeGetCurrent() - startTime
print("Loaded \(blockfaces.count) blockfaces in \(loadTime) seconds")
```

Target: <0.5 seconds for regional load
