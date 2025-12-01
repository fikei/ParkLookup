# Street Name Data Sources - Recommendations

**Current Status**: 46% of blockfaces have "Unknown Street" (8,450 of 18,355)

---

## Available Data Sources (Ranked by Priority)

### 1. ✅ **Existing Blockface `street_nam` Field** (10.4% coverage)
**Source**: Already in `Blockfaces_20251128.geojson`
**Coverage**: 1,910 blockfaces (10.4%)
**Format**: `"17th Street between Valencia St and Mission St, south side"`

**Pros**:
- Already in our data
- Very detailed (includes cross streets and side)
- Official SFMTA data

**Cons**:
- Only 10.4% coverage
- Needs parsing to extract just the street name

**Implementation**:
```python
# Extract from pipeline during blockface processing
street_nam = blockface_props.get('street_nam')
if street_nam:
    # Parse "17th Street between..." → "17th Street"
    street_name = street_nam.split(' between')[0].strip()
```

**Estimated coverage improvement**: +1,910 blockfaces (8,450 → 6,540 unknown)

---

### 2. ⭐ **Street Sweeping `corridor` Field** (Spatial Join)
**Source**: `Street_Sweeping_Schedule_20251128.geojson`
**Coverage**: 37,878 street sweeping regulations
**Format**: `"Market St"`, `"Lower Great Hwy"`, `"08th Ave"`

**Pros**:
- High coverage (1,351 streets have sweeping)
- Already being spatially joined in pipeline
- Free, no API calls needed
- Official city data

**Cons**:
- Already being used (why still have unknowns?)
- Need to verify spatial join is extracting street names

**Implementation**:
```python
# In pipeline during street sweeping regulation join
if sweeping_feature and 'corridor' in sweeping_props:
    if not blockface['street'] or blockface['street'] == 'Unknown Street':
        blockface['street'] = sweeping_props['corridor']
```

**Estimated coverage improvement**: Could fill most of the 1,351 streets with sweeping

---

### 3. 🔥 **San Francisco CNN (Centerline Network) Dataset**
**Source**: [DataSF Basemap Street Centerlines](https://data.sfgov.org/Geographic-Locations-and-Boundaries/San-Francisco-Basemap-Street-Centerlines/7hfy-8h8k)
**Coverage**: ~28,000 street segments with full names
**Format**: Official street centerline data with CNN IDs

**Pros**:
- Official city dataset
- Has CNN_ID matching our blockface data (1,910 blockfaces have CNN IDs)
- Authoritative source for San Francisco street names
- Free, no API costs
- High quality, maintained by city

**Cons**:
- Requires downloading separate dataset (~10MB)
- Need to implement spatial join or CNN ID lookup

**Implementation**:
```python
# Download once and cache
cnn_data = load_cnn_centerlines()  # GeoJSON from DataSF

# During pipeline:
# Option 1: Use CNN ID if available
if blockface_props.get('cnn_id'):
    cnn_id = blockface_props['cnn_id']
    street_name = cnn_lookup[cnn_id]['street_name']

# Option 2: Spatial join with centerlines
closest_centerline = find_nearest_centerline(blockface_geometry, cnn_data)
street_name = closest_centerline['street_name']
```

**Estimated coverage improvement**: Could fill 70-80% of unknowns (~6,000 blockfaces)

**Download**:
```bash
curl "https://data.sfgov.org/api/geospatial/7hfy-8h8k?method=export&format=GeoJSON" \
  -o data/raw/SF_Street_Centerlines.geojson
```

---

### 4. 🌍 **OpenStreetMap Reverse Geocoding** (Free)
**Source**: [Nominatim API](https://nominatim.openstreetmap.org/)
**Coverage**: Nearly 100% of San Francisco streets
**Format**: Free reverse geocoding API

**Pros**:
- Free (with rate limits)
- Very high coverage
- No API key required
- Community-maintained, good quality

**Cons**:
- Rate limited (1 request/second)
- Would take ~2-3 hours for 8,450 blockfaces
- Network dependent
- Results may vary in format

**Implementation**:
```python
from geopy.geocoders import Nominatim

geolocator = Nominatim(user_agent="sf-parking-pipeline")

# Get center point of blockface
lat, lon = blockface_center
location = geolocator.reverse(f"{lat}, {lon}")
street_name = location.raw['address'].get('road')

# Add rate limiting: time.sleep(1) between requests
```

**Estimated coverage improvement**: ~95% of unknowns (~8,000 blockfaces)
**Time required**: 2-3 hours with rate limiting

---

### 5. 💰 **Google Maps / Mapbox Reverse Geocoding** (Paid)
**Source**: Google Maps Geocoding API or Mapbox Geocoding API
**Coverage**: Nearly 100%
**Format**: Commercial APIs with high accuracy

**Pros**:
- Very high accuracy
- Fast (no strict rate limits)
- Well-maintained
- Consistent format

**Cons**:
- **Costs money** ($5-7 per 1,000 requests)
- ~$40-60 to fill 8,450 blockfaces
- Requires API key
- Ongoing costs if run regularly

**Implementation**:
```python
# Google Maps
import googlemaps
gmaps = googlemaps.Client(key='YOUR_API_KEY')
result = gmaps.reverse_geocode((lat, lon))
street_name = result[0]['address_components'][1]['long_name']

# Mapbox
import requests
response = requests.get(
    f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lon},{lat}.json",
    params={'access_token': 'YOUR_TOKEN'}
)
street_name = response.json()['features'][0]['text']
```

**Estimated coverage improvement**: ~99% of unknowns (~8,300 blockfaces)
**Cost**: $40-60 for one-time fill

---

### 6. 📊 **Parking Regulations `corridor` Field**
**Source**: `Parking_regulations_(except_non-metered_color_curb)_20251128.geojson`
**Coverage**: 7,783 regulations

**Pros**:
- Already in our data
- Already being spatially joined

**Cons**:
- Properties don't seem to have a direct street name field (need to verify)
- Lower coverage than street sweeping

**Implementation**: Check if regulations have any street name fields

---

## Recommended Implementation Strategy

### Phase 1: Quick Wins (No external dependencies)
1. ✅ **Extract from existing `street_nam`** (+1,910 blockfaces)
2. ✅ **Use street sweeping `corridor`** (verify/fix spatial join)
3. ✅ **Parse parking regulation fields** (if available)

**Estimated improvement**: 54% → 70-75% named streets

---

### Phase 2: High-Quality Free Data (Recommended)
4. 🔥 **Download and join CNN Centerlines** (+5,000-6,000 blockfaces)
   - One-time download
   - Official city data
   - No ongoing costs
   - Best quality

**Estimated improvement**: 70-75% → 90-95% named streets

---

### Phase 3: Complete Coverage (Optional)
5. 🌍 **OpenStreetMap reverse geocoding for remaining unknowns**
   - Fill last 5-10%
   - Free but slow (2-3 hours)
   - Run once, cache results

**Estimated final coverage**: 95-99% named streets

---

## Implementation Priority

```
┌─────────────────────────────────────────────────┐
│ PRIORITY 1: Use existing data sources          │
│ - street_nam field (10.4%)                     │
│ - street sweeping corridor (verify)            │
│ - parking regulation fields                     │
│                                                 │
│ Result: 54% → 70-75% coverage (FREE)           │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ PRIORITY 2: Add CNN Centerlines (RECOMMENDED)  │
│ - Download once from DataSF                    │
│ - Spatial join or CNN ID lookup                │
│                                                 │
│ Result: 70-75% → 90-95% coverage (FREE)        │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ PRIORITY 3: Fill remaining gaps (OPTIONAL)     │
│ - OpenStreetMap for last 5-10%                 │
│ - OR Google Maps ($40-60 one-time)             │
│                                                 │
│ Result: 90-95% → 99% coverage                  │
└─────────────────────────────────────────────────┘
```

---

## Code Example: Complete Implementation

```python
def improve_street_names(blockface, blockface_props, matched_regulations):
    """
    Fill in street name using multiple data sources in priority order.
    """
    street_name = None

    # Priority 1: Use existing street_nam field
    if blockface_props.get('street_nam'):
        # Parse "17th Street between Valencia St and Mission St, south side"
        street_name = blockface_props['street_nam'].split(' between')[0].strip()

    # Priority 2: Use CNN lookup if we have CNN ID
    elif blockface_props.get('cnn_id'):
        cnn_id = blockface_props['cnn_id']
        street_name = cnn_centerlines_lookup.get(cnn_id, {}).get('street_name')

    # Priority 3: Use street sweeping corridor
    elif not street_name:
        for reg in matched_regulations:
            if reg.get('source') == 'sweeping' and reg.get('corridor'):
                street_name = reg['corridor']
                break

    # Priority 4: Spatial join with CNN centerlines
    if not street_name:
        closest_centerline = find_nearest_centerline(
            blockface['geometry'],
            cnn_centerlines_spatial_index
        )
        if closest_centerline:
            street_name = closest_centerline['street_name']

    # Priority 5: Cache reverse geocode results (run offline, load from cache)
    if not street_name and reverse_geocode_cache:
        blockface_id = blockface['id']
        street_name = reverse_geocode_cache.get(blockface_id)

    return street_name or "Unknown Street"
```

---

## Recommendation: **Use CNN Centerlines First**

The San Francisco CNN (Centerline Network) dataset is the **best option** because:

1. ✅ **Official city data** - Same source as blockfaces
2. ✅ **Free** - No API costs
3. ✅ **High coverage** - 28,000+ street segments
4. ✅ **High quality** - Maintained by SFMTA
5. ✅ **Easy to use** - Can join by CNN ID or spatial proximity
6. ✅ **One-time download** - No ongoing dependencies

Would improve coverage from **54% → 90-95%** with no recurring costs.
