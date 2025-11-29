# Blockface Migration Plan

**Status:** Planning Phase
**Last Updated:** 2025-11-26
**Owner:** Engineering Team

---

## Executive Summary

This document outlines the complete migration from zone-based polygon rendering to blockface-based linestring rendering. The goal is to display parking regulations at the street segment level, enabling granular street cleaning data and more accurate parking information.

### Key Benefits
- **Granular Data**: Show regulations per street block instead of aggregated zones
- **Street Cleaning**: Display which specific blocks have street cleaning on which days
- **Better UX**: Users see exactly which side of which street has which regulations
- **Accurate**: No data loss from blockface → zone aggregation

### Timeline Estimate
- **Phase 1 (Backend):** 1 week
- **Phase 2 (iOS Models):** 3 days
- **Phase 3 (Rendering):** 1 week
- **Phase 4 (Testing & Migration):** 1 week
- **Total:** ~4 weeks

---

## Current Architecture

### Data Flow (Current)
```
DataSF Blockface API
    ↓
BlockfaceFetcher (fetches street segments)
    ↓
ParkingTransformer (aggregates into zones)
    ↓
Polygon Generator (creates zone polygons from blockfaces)
    ↓
sf_parking_zones.json (polygon-based zones)
    ↓
iOS App (renders zone polygons)
```

### Current Data Structure
```json
{
  "zones": [
    {
      "id": "zone_q_001",
      "zoneType": "residentialPermit",
      "permitArea": "Q",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[lat, lon], [lat, lon], ...]]
      },
      "rules": [
        {
          "ruleType": "timeLimit",
          "timeLimit": 120,
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
          "enforcementStartTime": {"hour": 8, "minute": 0},
          "enforcementEndTime": {"hour": 18, "minute": 0}
        }
      ]
    }
  ]
}
```

### Problems with Current Approach
1. **Data Loss**: Multiple blockfaces with different regulations get merged into single zone
2. **No Street-Level Detail**: Can't show that north side of Mission has different rules than south side
3. **Street Cleaning Impossible**: Street cleaning happens on specific blocks, not entire zones
4. **Aggregation Errors**: Rules get generalized when combining blockfaces

---

## Target Architecture

### Data Flow (New)
```
DataSF Blockface API
    ↓
BlockfaceFetcher (fetches street segments)
    ↓
ParkingTransformer (classifies regulations per blockface)
    ↓
Blockface Formatter (preserves individual segments)
    ↓
sf_parking_blockfaces.json (linestring-based segments)
    ↓
iOS App (renders blockface linestrings)
```

### Target Data Structure
```json
{
  "blockfaces": [
    {
      "id": "mission_24th_25th_even",
      "street": "Mission St",
      "fromStreet": "24th St",
      "toStreet": "25th St",
      "side": "EVEN",
      "cnn": "12345678",
      "geometry": {
        "type": "LineString",
        "coordinates": [[lon, lat], [lon, lat], ...]
      },
      "regulations": [
        {
          "type": "residentialPermit",
          "permitZone": "Q",
          "timeLimit": 120,
          "enforcementDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
          "enforcementStart": "08:00",
          "enforcementEnd": "18:00"
        },
        {
          "type": "streetCleaning",
          "enforcementDays": ["monday", "thursday"],
          "enforcementStart": "08:00",
          "enforcementEnd": "10:00"
        }
      ],
      "metadata": {
        "length": 300.5,
        "lastUpdated": "2025-11-26"
      }
    }
  ],
  "spatialIndex": {
    "type": "QuadTree",
    "bounds": [[lat, lon], [lat, lon]]
  }
}
```

---

## Phase 1: Backend Data Pipeline

### 1.1 Update BlockfaceFetcher

**File:** `backend/fetchers/blockface_fetcher.py`

**Changes:**
- Add method to fetch street sweeping data from `yhqp-riqs` dataset
- Join street sweeping schedule with blockface geometry

```python
class BlockfaceFetcher(BaseFetcher):
    """Fetches blockface and street sweeping data"""

    def __init__(self):
        super().__init__()
        self.blockface_url = f"{DATASF_BASE_URL}/{BLOCKFACE_DATASET_ID}.json"
        self.sweeping_url = f"{DATASF_BASE_URL}/yhqp-riqs.json"

    async def fetch(self) -> List[Dict[str, Any]]:
        """Fetch blockface regulations and street sweeping data"""
        blockfaces = await self.fetch_blockfaces()
        sweeping_schedule = await self.fetch_street_sweeping()

        # Join sweeping data with blockfaces
        return self.join_sweeping_data(blockfaces, sweeping_schedule)

    async def fetch_street_sweeping(self) -> List[Dict[str, Any]]:
        """Fetch street sweeping schedule from yhqp-riqs dataset"""
        logger.info("Fetching street sweeping schedule")

        all_records = []
        offset = 0

        while True:
            params = {
                "$limit": DATASF_PAGE_SIZE,
                "$offset": offset,
                "$order": ":id"
            }

            records = await self.fetch_with_retry(
                self.sweeping_url,
                params=params
            )

            if not records:
                break

            all_records.extend(records)

            if len(records) < DATASF_PAGE_SIZE:
                break

            offset += DATASF_PAGE_SIZE

        logger.info(f"Fetched {len(all_records)} street sweeping records")
        return all_records

    def join_sweeping_data(
        self,
        blockfaces: List[Dict],
        sweeping: List[Dict]
    ) -> List[Dict]:
        """Join street sweeping schedule with blockface geometry"""

        # Index sweeping data by CNN (street segment ID)
        sweeping_by_cnn = {}
        for record in sweeping:
            cnn = record.get('cnn')
            if cnn:
                if cnn not in sweeping_by_cnn:
                    sweeping_by_cnn[cnn] = []
                sweeping_by_cnn[cnn].append(record)

        # Add sweeping data to matching blockfaces
        for blockface in blockfaces:
            cnn = blockface.get('cnn')
            if cnn and cnn in sweeping_by_cnn:
                blockface['street_sweeping'] = sweeping_by_cnn[cnn]

        return blockfaces
```

### 1.2 Create Regulation Classifier

**File:** `backend/transformers/regulation_classifier.py` (NEW)

```python
"""Classifies parking regulations into distinct types"""
import logging
from typing import Dict, Any, Optional
from dataclasses import dataclass
from datetime import time

logger = logging.getLogger(__name__)


@dataclass
class RegulationClassification:
    """Result of regulation classification"""
    type: str  # "streetCleaning", "timeLimit", "residentialPermit", "metered"
    confidence: float  # 0.0 to 1.0
    reason: str  # Why this classification was chosen


class RegulationClassifier:
    """
    Classifies parking regulations based on patterns in blockface data.

    Uses multiple heuristics to determine if a time restriction is:
    - Street cleaning (no parking during specific short windows)
    - Time limit (parking allowed for X hours)
    - Residential permit (permit required)
    - Metered parking
    """

    def classify_time_restriction(
        self,
        record: Dict[str, Any]
    ) -> RegulationClassification:
        """
        Classify a time-based restriction.

        Args:
            record: Blockface record with hrs_begin, hrs_end, days, hrlimit

        Returns:
            RegulationClassification with type and confidence score
        """
        hrs_begin = record.get('hrs_begin') or record.get('HRS_BEGIN')
        hrs_end = record.get('hrs_end') or record.get('HRS_END')
        days = record.get('days') or record.get('DAYS', '')
        hrlimit = record.get('hrlimit') or record.get('HRLIMIT')

        score = 0.0
        reasons = []

        # Calculate duration
        duration_hours = self._calculate_duration(hrs_begin, hrs_end)

        # Heuristic 1: Short duration (1-3 hours) suggests street cleaning
        if duration_hours and 1 <= duration_hours <= 3:
            score += 0.3
            reasons.append(f"Short {duration_hours}h window")

        # Heuristic 2: Non-contiguous days (Mon, Thu) suggests cleaning
        day_list = self._parse_days(days)
        if day_list and len(day_list) <= 3 and not self._is_contiguous(day_list):
            score += 0.4
            reasons.append(f"Non-contiguous days: {days}")

        # Heuristic 3: No time limit (or 0) suggests street cleaning
        if hrlimit is None or (isinstance(hrlimit, (int, float)) and hrlimit == 0):
            score += 0.3
            reasons.append("No time limit (no parking)")

        # Classify based on score
        if score >= 0.6:
            return RegulationClassification(
                type="streetCleaning",
                confidence=min(score, 1.0),
                reason="; ".join(reasons)
            )
        else:
            return RegulationClassification(
                type="timeLimit",
                confidence=1.0 - score,
                reason="General time restriction"
            )

    def _calculate_duration(
        self,
        start_str: Optional[str],
        end_str: Optional[str]
    ) -> Optional[float]:
        """Calculate duration in hours between start and end times"""
        if not start_str or not end_str:
            return None

        try:
            # Parse times (format: "0800" or "08:00")
            start = self._parse_time(start_str)
            end = self._parse_time(end_str)

            if not start or not end:
                return None

            # Calculate duration
            start_mins = start.hour * 60 + start.minute
            end_mins = end.hour * 60 + end.minute

            duration_mins = end_mins - start_mins
            if duration_mins < 0:
                duration_mins += 24 * 60  # Handle overnight

            return duration_mins / 60.0
        except Exception as e:
            logger.warning(f"Failed to calculate duration: {e}")
            return None

    def _parse_time(self, time_str: str) -> Optional[time]:
        """Parse time string to time object"""
        try:
            # Remove colons and spaces
            clean = time_str.replace(':', '').replace(' ', '').strip()

            # Format: "0800" or "800"
            if len(clean) == 4:
                hour = int(clean[:2])
                minute = int(clean[2:])
            elif len(clean) == 3:
                hour = int(clean[0])
                minute = int(clean[1:])
            else:
                return None

            return time(hour=hour, minute=minute)
        except Exception:
            return None

    def _parse_days(self, days_str: str) -> list:
        """Parse day string to list of days"""
        if not days_str:
            return []

        days_str = days_str.upper()

        # Handle ranges (M-F)
        if '-' in days_str:
            # Simple range expansion
            if days_str == 'M-F':
                return ['MON', 'TUE', 'WED', 'THU', 'FRI']
            elif days_str == 'M-SAT':
                return ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']

        # Handle comma-separated (Mon,Thu)
        if ',' in days_str:
            return [d.strip()[:3] for d in days_str.split(',')]

        return [days_str[:3]]

    def _is_contiguous(self, days: list) -> bool:
        """Check if days are contiguous (Mon, Tue, Wed vs Mon, Thu)"""
        if len(days) <= 1:
            return True

        day_order = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
        indices = [day_order.index(d) for d in days if d in day_order]

        if not indices:
            return False

        indices.sort()

        # Check if consecutive
        for i in range(len(indices) - 1):
            if indices[i+1] - indices[i] != 1:
                return False

        return True
```

### 1.3 Update ParkingTransformer

**File:** `backend/transformers/parking_transformer.py`

**Changes:**
- Stop aggregating blockfaces into zones
- Keep blockfaces as individual segments
- Add regulation classification
- Include street sweeping data

```python
from .regulation_classifier import RegulationClassifier

class ParkingDataTransformer:
    """Transforms raw DataSF data into blockface format"""

    def __init__(self):
        self.classifier = RegulationClassifier()

    def transform_to_blockfaces(
        self,
        raw_blockfaces: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """
        Transform raw blockface data into structured format.

        Unlike the old approach, this preserves individual blockfaces
        instead of aggregating into zones.
        """
        logger.info(f"Transforming {len(raw_blockfaces)} blockfaces")

        blockfaces = []

        for record in raw_blockfaces:
            try:
                blockface = self._transform_single_blockface(record)
                if blockface:
                    blockfaces.append(blockface)
            except Exception as e:
                logger.error(f"Failed to transform blockface: {e}")
                continue

        logger.info(f"Successfully transformed {len(blockfaces)} blockfaces")
        return blockfaces

    def _transform_single_blockface(
        self,
        record: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Transform a single blockface record"""

        # Extract base information
        street = record.get('street') or record.get('STREET')
        from_street = record.get('from_street') or record.get('FROM_STREET')
        to_street = record.get('to_street') or record.get('TO_STREET')
        side = record.get('side') or record.get('SIDE', 'UNKNOWN')
        cnn = record.get('cnn') or record.get('CNN')

        if not street:
            return None

        # Generate unique ID
        blockface_id = self._generate_blockface_id(
            street, from_street, to_street, side
        )

        # Extract geometry
        geometry = self._extract_geometry(record)
        if not geometry:
            return None

        # Extract regulations
        regulations = []

        # 1. Residential Permit
        if permit_reg := self._extract_permit_regulation(record):
            regulations.append(permit_reg)

        # 2. Time restrictions (classify as street cleaning or time limit)
        if time_reg := self._extract_time_regulation(record):
            regulations.append(time_reg)

        # 3. Street sweeping (from joined data)
        if sweeping_regs := self._extract_sweeping_regulations(record):
            regulations.extend(sweeping_regs)

        # 4. Metered parking
        if meter_reg := self._extract_meter_regulation(record):
            regulations.append(meter_reg)

        return {
            'id': blockface_id,
            'street': street,
            'fromStreet': from_street,
            'toStreet': to_street,
            'side': side,
            'cnn': cnn,
            'geometry': geometry,
            'regulations': regulations,
            'metadata': {
                'length': self._calculate_length(geometry),
                'lastUpdated': datetime.now().isoformat()
            }
        }

    def _extract_time_regulation(
        self,
        record: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Extract and classify time-based regulation"""

        hrs_begin = record.get('hrs_begin') or record.get('HRS_BEGIN')
        hrs_end = record.get('hrs_end') or record.get('HRS_END')

        if not hrs_begin or not hrs_end:
            return None

        # Classify the regulation
        classification = self.classifier.classify_time_restriction(record)

        # Parse enforcement details
        days = self._parse_days_to_array(record.get('days', ''))

        regulation = {
            'type': classification.type,
            'enforcementDays': days,
            'enforcementStart': hrs_begin,
            'enforcementEnd': hrs_end,
        }

        # Add type-specific fields
        if classification.type == 'timeLimit':
            hrlimit = record.get('hrlimit') or record.get('HRLIMIT')
            if hrlimit:
                regulation['timeLimit'] = int(float(hrlimit) * 60)  # Convert to minutes

        return regulation

    def _extract_sweeping_regulations(
        self,
        record: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """Extract street sweeping from joined data"""

        sweeping_data = record.get('street_sweeping', [])
        regulations = []

        for sweep in sweeping_data:
            regulation = {
                'type': 'streetCleaning',
                'enforcementDays': [sweep.get('weekday', '').lower()],
                'enforcementStart': sweep.get('from_hour', ''),
                'enforcementEnd': sweep.get('to_hour', ''),
            }

            # Add frequency if available (weekly, biweekly, monthly)
            if freq := sweep.get('week'):
                regulation['frequency'] = freq

            regulations.append(regulation)

        return regulations

    def _generate_blockface_id(
        self,
        street: str,
        from_street: Optional[str],
        to_street: Optional[str],
        side: str
    ) -> str:
        """Generate unique blockface ID"""

        # Sanitize street names
        street_clean = street.lower().replace(' ', '_').replace('.', '')
        from_clean = (from_street or 'start').lower().replace(' ', '_').replace('.', '')
        to_clean = (to_street or 'end').lower().replace(' ', '_').replace('.', '')
        side_clean = side.lower()

        return f"{street_clean}_{from_clean}_{to_clean}_{side_clean}"

    def _extract_geometry(self, record: Dict[str, Any]) -> Optional[Dict]:
        """Extract LineString geometry from blockface"""

        # Try different geometry fields
        geom = (
            record.get('shape') or
            record.get('the_geom') or
            record.get('geometry')
        )

        if not geom:
            return None

        # Handle GeoJSON
        if isinstance(geom, dict):
            if geom.get('type') == 'LineString':
                return geom
            elif geom.get('type') == 'MultiLineString':
                # Take first linestring
                coords = geom.get('coordinates', [[]])[0]
                return {
                    'type': 'LineString',
                    'coordinates': coords
                }

        return None

    def _calculate_length(self, geometry: Dict) -> float:
        """Calculate approximate length of linestring in meters"""

        if geometry.get('type') != 'LineString':
            return 0.0

        coords = geometry.get('coordinates', [])
        if len(coords) < 2:
            return 0.0

        # Simple Haversine distance sum
        total = 0.0
        for i in range(len(coords) - 1):
            lon1, lat1 = coords[i]
            lon2, lat2 = coords[i + 1]
            total += self._haversine_distance(lat1, lon1, lat2, lon2)

        return total
```

### 1.4 Output Format

**File:** `backend/output/blockface_writer.py` (NEW)

```python
"""Writes blockface data to JSON format for iOS"""
import json
import logging
from typing import List, Dict, Any
from pathlib import Path

logger = logging.getLogger(__name__)


class BlockfaceWriter:
    """Writes blockface data in iOS-compatible format"""

    def write(
        self,
        blockfaces: List[Dict[str, Any]],
        output_path: Path
    ):
        """Write blockfaces to JSON file"""

        logger.info(f"Writing {len(blockfaces)} blockfaces to {output_path}")

        # Group blockfaces by permit zone for efficient lookup
        zones_index = self._build_zones_index(blockfaces)

        # Build spatial index for efficient queries
        spatial_index = self._build_spatial_index(blockfaces)

        output = {
            'version': '2.0',
            'dataType': 'blockfaces',
            'generatedAt': datetime.now().isoformat(),
            'blockfaces': blockfaces,
            'zonesIndex': zones_index,
            'spatialIndex': spatial_index,
            'statistics': {
                'totalBlockfaces': len(blockfaces),
                'withStreetCleaning': sum(
                    1 for b in blockfaces
                    if any(r['type'] == 'streetCleaning' for r in b['regulations'])
                ),
                'withPermits': sum(
                    1 for b in blockfaces
                    if any(r['type'] == 'residentialPermit' for r in b['regulations'])
                )
            }
        }

        with open(output_path, 'w') as f:
            json.dump(output, f, indent=2)

        logger.info(f"Successfully wrote blockface data")

    def _build_zones_index(
        self,
        blockfaces: List[Dict]
    ) -> Dict[str, List[str]]:
        """Build index of blockface IDs by permit zone"""

        index = {}

        for blockface in blockfaces:
            for reg in blockface.get('regulations', []):
                if reg['type'] == 'residentialPermit':
                    zone = reg.get('permitZone')
                    if zone:
                        if zone not in index:
                            index[zone] = []
                        index[zone].append(blockface['id'])

        return index

    def _build_spatial_index(self, blockfaces: List[Dict]) -> Dict:
        """Build simple grid-based spatial index"""

        # Simple grid: divide SF into 0.01 degree cells
        # (about 1km x 1km at SF latitude)

        grid = {}

        for blockface in blockfaces:
            geom = blockface.get('geometry')
            if not geom:
                continue

            # Get bounding box
            coords = geom.get('coordinates', [])
            if not coords:
                continue

            lons = [c[0] for c in coords]
            lats = [c[1] for c in coords]

            min_lon, max_lon = min(lons), max(lons)
            min_lat, max_lat = min(lats), max(lats)

            # Add to grid cells
            cell_x = int(min_lon * 100)
            cell_y = int(min_lat * 100)

            cell_key = f"{cell_x},{cell_y}"

            if cell_key not in grid:
                grid[cell_key] = []

            grid[cell_key].append(blockface['id'])

        return grid
```

---

## Phase 2: iOS Data Models

### 2.1 Create Blockface Model

**File:** `SFParkingZoneFinder/Core/Models/Blockface.swift` (NEW)

```swift
import Foundation
import CoreLocation

/// Represents a single street segment (blockface) with parking regulations
struct Blockface: Codable, Identifiable, Hashable {
    let id: String
    let street: String
    let fromStreet: String?
    let toStreet: String?
    let side: BlockfaceSide
    let cnn: String?
    let geometry: LineStringGeometry
    let regulations: [BlockfaceRegulation]
    let metadata: BlockfaceMetadata

    enum CodingKeys: String, CodingKey {
        case id, street, fromStreet, toStreet, side, cnn, geometry, regulations, metadata
    }
}

enum BlockfaceSide: String, Codable {
    case even = "EVEN"
    case odd = "ODD"
    case unknown = "UNKNOWN"
}

struct LineStringGeometry: Codable, Hashable {
    let type: String
    let coordinates: [[Double]]  // [[lon, lat], [lon, lat], ...]

    /// Convert to array of CLLocationCoordinate2D for MapKit
    var locationCoordinates: [CLLocationCoordinate2D] {
        coordinates.compactMap { coord in
            guard coord.count >= 2 else { return nil }
            return CLLocationCoordinate2D(
                latitude: coord[1],
                longitude: coord[0]
            )
        }
    }

    /// Bounding box for this linestring
    var boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let lats = coordinates.map { $0[1] }
        let lons = coordinates.map { $0[0] }

        return (
            minLat: lats.min() ?? 0,
            maxLat: lats.max() ?? 0,
            minLon: lons.min() ?? 0,
            maxLon: lons.max() ?? 0
        )
    }
}

struct BlockfaceRegulation: Codable, Hashable, Identifiable {
    let id = UUID()
    let type: RegulationType
    let permitZone: String?
    let timeLimit: Int?  // Minutes
    let enforcementDays: [DayOfWeek]?
    let enforcementStart: String?  // "08:00"
    let enforcementEnd: String?    // "18:00"
    let frequency: String?         // "weekly", "biweekly", etc.

    enum RegulationType: String, Codable {
        case streetCleaning
        case timeLimit
        case residentialPermit
        case metered
    }

    enum CodingKeys: String, CodingKey {
        case type, permitZone, timeLimit
        case enforcementDays, enforcementStart, enforcementEnd, frequency
    }

    /// Human-readable description
    var description: String {
        switch type {
        case .streetCleaning:
            return streetCleaningDescription
        case .timeLimit:
            return timeLimitDescription
        case .residentialPermit:
            return permitDescription
        case .metered:
            return "Metered parking"
        }
    }

    private var streetCleaningDescription: String {
        guard let days = enforcementDays, !days.isEmpty else {
            return "Street cleaning"
        }

        let dayNames = days.map(\.shortName).joined(separator: ", ")

        if let start = enforcementStart, let end = enforcementEnd {
            return "Street cleaning \(dayNames) \(start)-\(end)"
        } else {
            return "Street cleaning \(dayNames)"
        }
    }

    private var timeLimitDescription: String {
        guard let limit = timeLimit else {
            return "Time limit"
        }

        let hours = limit / 60
        let mins = limit % 60

        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m limit"
        } else if hours > 0 {
            return "\(hours) hour limit"
        } else {
            return "\(mins) minute limit"
        }
    }

    private var permitDescription: String {
        if let zone = permitZone {
            return "Zone \(zone) permit required"
        } else {
            return "Permit required"
        }
    }

    /// Check if this regulation is in effect at a given date
    func isInEffect(at date: Date) -> Bool {
        guard let days = enforcementDays else { return true }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday)

        guard days.contains(dayOfWeek) else { return false }

        // Check time if specified
        if let startStr = enforcementStart, let endStr = enforcementEnd {
            let components = calendar.dateComponents([.hour, .minute], from: date)
            guard let hour = components.hour, let minute = components.minute else {
                return false
            }

            // Parse enforcement times
            guard let start = TimeOfDay.parse(startStr),
                  let end = TimeOfDay.parse(endStr) else {
                return true  // Can't verify time, assume in effect
            }

            let currentMins = hour * 60 + minute
            let startMins = start.hour * 60 + start.minute
            let endMins = end.hour * 60 + end.minute

            return currentMins >= startMins && currentMins < endMins
        }

        return true
    }
}

struct BlockfaceMetadata: Codable, Hashable {
    let length: Double  // Meters
    let lastUpdated: String
}

// MARK: - Extensions

extension Blockface {
    /// All street cleaning regulations for this blockface
    var streetCleaningRegulations: [BlockfaceRegulation] {
        regulations.filter { $0.type == .streetCleaning }
    }

    /// Check if this blockface has active street cleaning
    func hasActiveStreetCleaning(at date: Date = Date()) -> Bool {
        streetCleaningRegulations.contains { $0.isInEffect(at: date) }
    }

    /// Primary permit zone (if any)
    var permitZone: String? {
        regulations.first(where: { $0.type == .residentialPermit })?.permitZone
    }

    /// Time limit for non-permit holders (if any)
    var timeLimitMinutes: Int? {
        regulations.first(where: { $0.type == .timeLimit })?.timeLimit
    }

    /// Display name for this blockface
    var displayName: String {
        if let from = fromStreet, let to = toStreet {
            return "\(street) (\(from) to \(to))"
        } else if let from = fromStreet {
            return "\(street) from \(from)"
        } else if let to = toStreet {
            return "\(street) to \(to)"
        } else {
            return street
        }
    }
}

extension DayOfWeek {
    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

extension TimeOfDay {
    /// Parse time string like "08:00" or "0800"
    static func parse(_ string: String) -> TimeOfDay? {
        let clean = string.replacingOccurrences(of: ":", with: "")

        guard clean.count == 4 || clean.count == 3 else {
            return nil
        }

        let hourStr: String
        let minStr: String

        if clean.count == 4 {
            hourStr = String(clean.prefix(2))
            minStr = String(clean.suffix(2))
        } else {
            hourStr = String(clean.prefix(1))
            minStr = String(clean.suffix(2))
        }

        guard let hour = Int(hourStr), let minute = Int(minStr) else {
            return nil
        }

        return TimeOfDay(hour: hour, minute: minute)
    }
}
```

### 2.2 Create Blockface Data Loader

**File:** `SFParkingZoneFinder/Core/Services/BlockfaceDataLoader.swift` (NEW)

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "BlockfaceDataLoader")

/// Loads blockface data from embedded JSON file
class BlockfaceDataLoader {

    static let shared = BlockfaceDataLoader()

    private var cachedBlockfaces: [Blockface]?
    private var spatialIndex: SpatialIndex?

    private init() {}

    /// Load all blockfaces from embedded JSON
    func loadBlockfaces() throws -> [Blockface] {
        if let cached = cachedBlockfaces {
            logger.info("Returning cached blockfaces")
            return cached
        }

        logger.info("Loading blockfaces from embedded JSON")

        guard let url = Bundle.main.url(forResource: "sf_parking_blockfaces", withExtension: "json") else {
            throw DataLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(BlockfaceDataResponse.self, from: data)

        cachedBlockfaces = response.blockfaces

        logger.info("Loaded \(response.blockfaces.count) blockfaces")
        logger.info("Statistics: \(response.statistics)")

        return response.blockfaces
    }

    /// Find blockfaces near a coordinate
    func findBlockfaces(
        near coordinate: CLLocationCoordinate2D,
        radius: Double = 100  // meters
    ) throws -> [Blockface] {
        let blockfaces = try loadBlockfaces()

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return blockfaces.filter { blockface in
            // Check if any point in linestring is within radius
            blockface.geometry.locationCoordinates.contains { coord in
                let pointLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                return location.distance(from: pointLocation) <= radius
            }
        }
    }

    /// Find blockfaces with active street cleaning
    func findActiveStreetCleaning(at date: Date = Date()) throws -> [Blockface] {
        let blockfaces = try loadBlockfaces()

        return blockfaces.filter { $0.hasActiveStreetCleaning(at: date) }
    }

    /// Find blockfaces in a permit zone
    func findBlockfaces(inPermitZone zone: String) throws -> [Blockface] {
        let blockfaces = try loadBlockfaces()

        return blockfaces.filter { $0.permitZone == zone }
    }
}

struct BlockfaceDataResponse: Codable {
    let version: String
    let dataType: String
    let generatedAt: String
    let blockfaces: [Blockface]
    let statistics: BlockfaceStatistics
}

struct BlockfaceStatistics: Codable {
    let totalBlockfaces: Int
    let withStreetCleaning: Int
    let withPermits: Int
}

enum DataLoaderError: Error {
    case fileNotFound
    case invalidData
}
```

---

## Phase 3: Map Rendering

### 3.1 Create BlockfaceMapView

**File:** `SFParkingZoneFinder/Features/Map/Views/BlockfaceMapView.swift` (NEW)

```swift
import SwiftUI
import MapKit
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "BlockfaceMapView")

/// Map view that renders individual blockface linestrings
struct BlockfaceMapView: UIViewRepresentable {
    let blockfaces: [Blockface]
    let userCoordinate: CLLocationCoordinate2D?
    let highlightStreetCleaning: Bool
    let onBlockfaceTapped: ((Blockface, CLLocationCoordinate2D) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        logger.info("🚀 Creating BlockfaceMapView with \(blockfaces.count) blockfaces")

        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update coordinator
        context.coordinator.blockfaces = blockfaces
        context.coordinator.onBlockfaceTapped = onBlockfaceTapped
        context.coordinator.highlightStreetCleaning = highlightStreetCleaning

        // Remove old overlays
        mapView.removeOverlays(mapView.overlays)

        // Add blockface polylines
        for blockface in blockfaces {
            let coordinates = blockface.geometry.locationCoordinates
            guard coordinates.count >= 2 else { continue }

            let polyline = BlockfacePolyline(
                coordinates: coordinates,
                count: coordinates.count
            )
            polyline.blockface = blockface

            mapView.addOverlay(polyline)
        }

        // Center on user location if available
        if let coord = userCoordinate {
            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            mapView.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            blockfaces: blockfaces,
            highlightStreetCleaning: highlightStreetCleaning,
            onBlockfaceTapped: onBlockfaceTapped
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var blockfaces: [Blockface]
        var highlightStreetCleaning: Bool
        var onBlockfaceTapped: ((Blockface, CLLocationCoordinate2D) -> Void)?
        weak var mapView: MKMapView?

        init(
            blockfaces: [Blockface],
            highlightStreetCleaning: Bool,
            onBlockfaceTapped: ((Blockface, CLLocationCoordinate2D) -> Void)?
        ) {
            self.blockfaces = blockfaces
            self.highlightStreetCleaning = highlightStreetCleaning
            self.onBlockfaceTapped = onBlockfaceTapped
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? BlockfacePolyline,
                  let blockface = polyline.blockface else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)

            // Determine color based on regulations
            if highlightStreetCleaning && blockface.hasActiveStreetCleaning() {
                // Red for active street cleaning
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
                renderer.lineWidth = 5
                renderer.lineDashPattern = [8, 4]  // Dashed line
            } else if let zone = blockface.permitZone {
                // Color by permit zone
                renderer.strokeColor = permitZoneColor(zone).withAlphaComponent(0.7)
                renderer.lineWidth = 4
            } else {
                // Default for non-permit areas
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.5)
                renderer.lineWidth = 3
            }

            return renderer
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            // Find nearest blockface
            if let nearest = findNearestBlockface(to: coordinate, within: 50) {
                onBlockfaceTapped?(nearest, coordinate)
            }
        }

        private func findNearestBlockface(
            to coordinate: CLLocationCoordinate2D,
            within meters: Double
        ) -> Blockface? {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            var nearest: Blockface?
            var minDistance = meters

            for blockface in blockfaces {
                for coord in blockface.geometry.locationCoordinates {
                    let pointLocation = CLLocation(
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                    let distance = location.distance(from: pointLocation)

                    if distance < minDistance {
                        minDistance = distance
                        nearest = blockface
                    }
                }
            }

            return nearest
        }

        private func permitZoneColor(_ zone: String) -> UIColor {
            // Simple hash-based color generation
            let hash = zone.hashValue
            let hue = CGFloat(abs(hash) % 360) / 360.0
            return UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
        }
    }
}

/// Custom polyline that holds reference to blockface
class BlockfacePolyline: MKPolyline {
    weak var blockface: Blockface?
}
```

### 3.2 Create Blockface Info Card

**File:** `SFParkingZoneFinder/Features/Map/Views/BlockfaceInfoCard.swift` (NEW)

```swift
import SwiftUI

/// Info card showing regulations for a tapped blockface
struct BlockfaceInfoCard: View {
    let blockface: Blockface
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(blockface.street)
                        .font(.headline)

                    if let from = blockface.fromStreet, let to = blockface.toStreet {
                        Text("\(from) to \(to) (\(blockface.side.rawValue) side)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Regulations
            if blockface.regulations.isEmpty {
                Text("No specific regulations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(blockface.regulations) { regulation in
                    RegulationRow(regulation: regulation)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .padding()
    }
}

struct RegulationRow: View {
    let regulation: BlockfaceRegulation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(regulation.description)
                    .font(.subheadline)

                if let days = regulation.enforcementDays, !days.isEmpty {
                    Text(days.map(\.shortName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var iconName: String {
        switch regulation.type {
        case .streetCleaning:
            return "leaf.fill"
        case .timeLimit:
            return "clock.fill"
        case .residentialPermit:
            return "parkingsign.circle.fill"
        case .metered:
            return "dollarsign.circle.fill"
        }
    }

    private var iconColor: Color {
        switch regulation.type {
        case .streetCleaning:
            return .red
        case .timeLimit:
            return .orange
        case .residentialPermit:
            return .blue
        case .metered:
            return .green
        }
    }
}
```

---

## Phase 4: Migration & Testing

### 4.1 Dual-Mode Support

Add developer setting to toggle between zone and blockface rendering:

**File:** `SFParkingZoneFinder/Core/Services/DeveloperSettings.swift`

```swift
@Published var useBlockfaceRendering: Bool = false {
    didSet {
        UserDefaults.standard.set(useBlockfaceRendering, forKey: "useBlockfaceRendering")
    }
}
```

**File:** `SFParkingZoneFinder/Features/Main/Views/MainResultView.swift`

```swift
// In map rendering section
if devSettings.useBlockfaceRendering {
    BlockfaceMapView(
        blockfaces: viewModel.nearbyBlockfaces,
        userCoordinate: activeCoordinate,
        highlightStreetCleaning: true,
        onBlockfaceTapped: { blockface, coordinate in
            selectedBlockface = blockface
        }
    )
} else {
    ZoneMapView(
        zones: viewModel.allLoadedZones,
        // ... existing parameters
    )
}
```

### 4.2 Testing Plan

#### Unit Tests
- Regulation classifier accuracy (>90% for known patterns)
- Blockface geometry parsing
- Spatial queries (find nearby blockfaces)
- Active street cleaning detection

#### Integration Tests
- Backend pipeline end-to-end
- iOS data loading
- Map rendering performance

#### Manual Testing
1. **Street Cleaning Display**
   - Navigate to known street cleaning areas
   - Verify correct days/times shown
   - Check active cleaning highlighting

2. **Performance**
   - Load 10,000+ blockfaces
   - Measure rendering time
   - Test zoom/pan smoothness

3. **Data Accuracy**
   - Compare with SFMTA official data
   - Verify permit zones match
   - Check time limits

### 4.3 Migration Rollout

**Week 1: Backend**
- Implement regulation classifier
- Update transformer
- Generate blockface JSON

**Week 2: iOS Models**
- Add Blockface.swift
- Create data loader
- Test with sample data

**Week 3: Rendering**
- Implement BlockfaceMapView
- Add info cards
- Integrate with main view

**Week 4: Testing & Rollout**
- Developer beta with dual-mode
- Gather feedback
- Fix bugs
- Enable for all users

---

## Performance Optimization

### Backend
- **Compression**: Gzip blockface JSON (~70% size reduction)
- **Incremental Updates**: Only send changed blockfaces
- **Spatial Indexing**: QuadTree for fast spatial queries

### iOS
- **Lazy Loading**: Only load visible blockfaces
- **Simplification**: Reduce coordinate precision when zoomed out
- **Caching**: Cache rendered polylines
- **Culling**: Don't render blockfaces outside viewport

### Example Optimizations

```swift
// Viewport culling
func visibleBlockfaces(in region: MKCoordinateRegion) -> [Blockface] {
    let bounds = region.boundingBox

    return allBlockfaces.filter { blockface in
        let geomBounds = blockface.geometry.boundingBox
        return bounds.intersects(geomBounds)
    }
}

// LOD (Level of Detail)
func simplifiedGeometry(for blockface: Blockface, zoomLevel: Double) -> [CLLocationCoordinate2D] {
    let coords = blockface.geometry.locationCoordinates

    if zoomLevel < 15 {
        // Very zoomed out - keep only endpoints
        return [coords.first!, coords.last!]
    } else if zoomLevel < 17 {
        // Medium zoom - keep every 3rd point
        return coords.enumerated().compactMap { i, coord in
            i % 3 == 0 ? coord : nil
        }
    } else {
        // Fully zoomed in - keep all points
        return coords
    }
}
```

---

## Rollback Plan

If issues arise, maintain backward compatibility:

1. **Keep Zone Data**: Generate both formats during transition
2. **Feature Flag**: `useBlockfaceRendering` defaults to `false`
3. **Quick Rollback**: Flip flag to revert to zones
4. **Data Validation**: Compare zone vs blockface results

---

## Success Metrics

### Data Quality
- [ ] >95% of SF streets have blockface data
- [ ] >90% street cleaning classification accuracy
- [ ] <1% user-reported data errors

### Performance
- [ ] Initial load <2 seconds
- [ ] Smooth 60fps panning/zooming
- [ ] Memory usage <100MB for full SF dataset

### User Experience
- [ ] Street cleaning visible on map
- [ ] Blockface info cards load instantly
- [ ] No regression in existing features

---

## Next Steps

1. **Immediate**: Review and approve this plan
2. **Week 1**: Start backend implementation
3. **Week 2**: Parallel iOS model development
4. **Week 3**: Integration and rendering
5. **Week 4**: Testing and refinement

---

**Questions? Concerns? Ready to proceed?**
