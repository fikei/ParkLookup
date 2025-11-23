"""Transform raw parking data into app-ready format"""
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime

try:
    from shapely.geometry import LineString, MultiLineString, mapping
    from shapely.ops import unary_union
    SHAPELY_AVAILABLE = True
except ImportError:
    SHAPELY_AVAILABLE = False

try:
    from scipy.spatial import ConvexHull
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

logger = logging.getLogger(__name__)


@dataclass
class RPPZone:
    """Represents a transformed RPP zone"""
    area_code: str
    name: str
    polygon: List[List[Tuple[float, float]]]  # List of rings, each ring is list of (lon, lat)
    neighborhoods: List[str] = field(default_factory=list)
    total_blocks: int = 0
    # Track which polygons are multi-permit (index -> list of all valid permit areas)
    multi_permit_polygons: Dict[int, List[str]] = field(default_factory=dict)


@dataclass
class ParkingRegulation:
    """Represents a parking regulation on a street segment"""
    street_name: str
    from_street: str
    to_street: str
    side: str  # "EVEN" or "ODD"
    rpp_area: Optional[str]
    time_limit: Optional[int]  # minutes
    hours_begin: Optional[str]
    hours_end: Optional[str]
    days: List[str] = field(default_factory=list)
    geometry: Optional[Dict[str, Any]] = None


@dataclass
class ParkingMeter:
    """Represents a parking meter"""
    post_id: str
    latitude: float
    longitude: float
    street_name: str
    street_num: Optional[str]
    cap_color: str
    time_limit: Optional[int]  # minutes
    rate_area: Optional[str]


@dataclass
class MeteredZone:
    """Represents a paid/metered parking zone derived from meter locations"""
    zone_id: str
    name: str
    polygon: List[List[Tuple[float, float]]]  # List of polygon boundaries
    meter_count: int
    cap_colors: List[str]  # Unique cap colors in zone
    avg_time_limit: Optional[int]  # Average time limit in minutes
    rate_area: Optional[str]


class ParkingDataTransformer:
    """
    Transforms raw data from multiple sources into a unified format
    suitable for the iOS app.
    """

    def __init__(self):
        self.stats = {
            "rpp_zones": 0,
            "regulations": 0,
            "meters": 0,
            "errors": 0
        }

    def transform_rpp_areas(self, raw_areas: List[Dict[str, Any]]) -> List[RPPZone]:
        """
        Transform SFMTA ArcGIS RPP area features into RPPZone objects.
        """
        logger.info(f"Transforming {len(raw_areas)} RPP areas")
        zones = []

        for feature in raw_areas:
            try:
                attrs = feature.get("attributes", {})
                geometry = feature.get("geometry", {})

                # Extract area code
                area_code = attrs.get("AREA") or attrs.get("area") or attrs.get("RPP_AREA")
                if not area_code:
                    logger.warning(f"Skipping feature without area code: {attrs}")
                    continue

                # Extract polygon rings
                rings = geometry.get("rings", [])
                if not rings:
                    logger.warning(f"Skipping area {area_code} without geometry")
                    continue

                # Convert rings to (lon, lat) tuples
                polygon = []
                for ring in rings:
                    polygon.append([(coord[0], coord[1]) for coord in ring])

                zone = RPPZone(
                    area_code=str(area_code).upper(),
                    name=attrs.get("NAME", f"Area {area_code}"),
                    polygon=polygon,
                    neighborhoods=self._extract_neighborhoods(attrs),
                )

                zones.append(zone)

            except Exception as e:
                logger.error(f"Error transforming RPP area: {e}")
                self.stats["errors"] += 1

        self.stats["rpp_zones"] = len(zones)
        logger.info(f"Transformed {len(zones)} RPP zones")
        return zones

    def derive_zones_from_blockface(self, raw_blockfaces: List[Dict[str, Any]]) -> List[RPPZone]:
        """
        Derive RPP zones from blockface data by buffering street segments into polygons.

        Key features:
        - Buffers line strings into actual block-face polygons (~10m width)
        - Handles overlapping zones via rpparea1, rpparea2, rpparea3
        - Keeps each block face as separate polygon (no convex hull)
        - Tracks multi-permit polygons for special map rendering
        """
        logger.info(f"Deriving zones from {len(raw_blockfaces)} blockface records")

        if not SHAPELY_AVAILABLE:
            logger.warning("Shapely not available - falling back to convex hull method")
            return self._derive_zones_convex_hull(raw_blockfaces)

        # Buffer distance in degrees (~10 meters at SF latitude)
        # 1 degree latitude ≈ 111km, so 10m ≈ 0.00009
        BUFFER_DISTANCE = 0.00009

        # Store polygon data with multi-permit tracking
        # areas_polygons: Dict[area_code -> List of (polygon, all_valid_areas)]
        areas_polygons: Dict[str, List[Tuple[List[Tuple[float, float]], List[str]]]] = {}

        processed = 0
        skipped_no_geom = 0
        skipped_no_area = 0
        multi_permit_count = 0

        for record in raw_blockfaces:
            # Get ALL RPP areas for this block face (supports overlapping zones)
            rpp_areas = []
            for field in ["rpparea1", "rpparea2", "rpparea3", "RPPAREA1", "RPPAREA2", "RPPAREA3"]:
                area = record.get(field)
                if area:
                    area_code = str(area).upper().strip()
                    if area_code and area_code not in rpp_areas:
                        rpp_areas.append(area_code)

            if not rpp_areas:
                skipped_no_area += 1
                continue

            # Extract geometry and buffer into polygon
            geom = record.get("shape") or record.get("the_geom") or record.get("geometry")
            if not geom:
                skipped_no_geom += 1
                continue

            # Convert geometry to Shapely LineString and buffer
            buffered_polygon = self._buffer_geometry_to_polygon(geom, BUFFER_DISTANCE)
            if not buffered_polygon:
                skipped_no_geom += 1
                continue

            # Track if this is a multi-permit blockface
            is_multi_permit = len(rpp_areas) > 1
            if is_multi_permit:
                multi_permit_count += 1

            # Add this polygon to ALL its RPP areas (handles overlapping zones)
            # Store tuple of (polygon, all_valid_areas) for multi-permit tracking
            for area_code in rpp_areas:
                if area_code not in areas_polygons:
                    areas_polygons[area_code] = []
                areas_polygons[area_code].append((buffered_polygon, sorted(rpp_areas)))

            processed += 1

        logger.info(f"Processed {processed} blockfaces, skipped {skipped_no_area} (no RPP area), {skipped_no_geom} (no geometry)")
        logger.info(f"Found {multi_permit_count} multi-permit blockfaces")

        # Create zones from collected polygons
        zones = []
        total_polygons = 0

        for area_code in sorted(areas_polygons.keys()):
            polygon_data = areas_polygons[area_code]
            polygons = [p[0] for p in polygon_data]  # Extract just the polygons
            total_polygons += len(polygons)

            # Build multi-permit polygon index (polygon_index -> all valid areas)
            multi_permit_polygons = {}
            for idx, (_, all_areas) in enumerate(polygon_data):
                if len(all_areas) > 1:
                    multi_permit_polygons[idx] = all_areas

            zone = RPPZone(
                area_code=area_code,
                name=f"Zone {area_code}",
                polygon=polygons,
                total_blocks=len(polygons),
                multi_permit_polygons=multi_permit_polygons
            )
            zones.append(zone)
            mp_count = len(multi_permit_polygons)
            logger.debug(f"Zone {area_code}: {len(polygons)} block faces ({mp_count} multi-permit)")

        logger.info(f"Derived {len(zones)} zones with {total_polygons} total block face polygons")
        return zones

    def _buffer_geometry_to_polygon(self, geom: Any, buffer_distance: float) -> Optional[List[Tuple[float, float]]]:
        """
        Convert a geometry (LineString/MultiLineString) to a buffered polygon.
        Returns list of (lon, lat) tuples forming the polygon exterior ring.
        """
        try:
            coords = []

            if isinstance(geom, dict):
                geom_type = geom.get("type", "")
                raw_coords = geom.get("coordinates", [])

                if geom_type == "LineString":
                    coords = [(c[0], c[1]) for c in raw_coords]
                elif geom_type == "MultiLineString":
                    # Flatten all line segments
                    for line in raw_coords:
                        coords.extend([(c[0], c[1]) for c in line])
                elif geom_type == "Point":
                    # Single point - create small buffer around it
                    coords = [(raw_coords[0], raw_coords[1])]
                else:
                    # Try to extract coords recursively
                    self._flatten_coords(raw_coords, coords)
            elif isinstance(geom, str):
                # WKT format - skip for now
                return None

            if len(coords) < 2:
                return None

            # Create Shapely geometry and buffer
            if len(coords) == 1:
                from shapely.geometry import Point
                line = Point(coords[0])
            else:
                line = LineString(coords)

            # Buffer the line to create a polygon
            buffered = line.buffer(buffer_distance, cap_style=2, join_style=2)  # flat cap, mitre join

            if buffered.is_empty:
                return None

            # Extract exterior coordinates
            if hasattr(buffered, 'exterior'):
                exterior_coords = list(buffered.exterior.coords)
                return [(c[0], c[1]) for c in exterior_coords]
            elif hasattr(buffered, 'geoms'):
                # MultiPolygon - take largest
                largest = max(buffered.geoms, key=lambda p: p.area)
                return [(c[0], c[1]) for c in largest.exterior.coords]

            return None

        except Exception as e:
            logger.debug(f"Failed to buffer geometry: {e}")
            return None

    def _derive_zones_convex_hull(self, raw_blockfaces: List[Dict[str, Any]]) -> List[RPPZone]:
        """
        Fallback: Derive zones using convex hull when Shapely is unavailable.
        """
        logger.info("Using convex hull fallback method")

        # Group by RPP area (check all three fields)
        areas: Dict[str, List[Tuple[float, float]]] = {}

        for record in raw_blockfaces:
            # Get ALL RPP areas for this block face
            for field in ["rpparea1", "rpparea2", "rpparea3", "RPPAREA1", "RPPAREA2", "RPPAREA3"]:
                rpp_area = record.get(field)
                if not rpp_area:
                    continue

                area_code = str(rpp_area).upper().strip()
                if not area_code:
                    continue

                if area_code not in areas:
                    areas[area_code] = []

                geom = record.get("shape") or record.get("the_geom") or record.get("geometry")
                if geom:
                    coords = self._extract_coords_from_geom(geom)
                    areas[area_code].extend(coords)

        # Create zones with convex hull
        zones = []
        for area_code in sorted(areas.keys()):
            coords = areas[area_code]
            if not coords:
                continue

            hull_polygon = self._create_convex_hull(coords)
            if hull_polygon:
                zones.append(RPPZone(
                    area_code=area_code,
                    name=f"Area {area_code}",
                    polygon=[hull_polygon],
                    total_blocks=len(coords)
                ))

        logger.info(f"Derived {len(zones)} zones using convex hull")
        return zones

    def _create_convex_hull(self, coords: List[Tuple[float, float]]) -> Optional[List[Tuple[float, float]]]:
        """
        Create a convex hull polygon from a set of coordinates.
        Returns None if scipy is not available or if hull creation fails.
        """
        if not SCIPY_AVAILABLE:
            logger.debug("scipy not available, falling back to bounding box")
            return None

        if len(coords) < 3:
            return None

        try:
            import numpy as np
            # Remove duplicates and convert to numpy array
            unique_coords = list(set(coords))
            if len(unique_coords) < 3:
                return None

            points = np.array(unique_coords)

            # Create convex hull
            hull = ConvexHull(points)

            # Extract hull vertices in order
            hull_points = points[hull.vertices]

            # Convert to list of tuples and close the ring
            polygon = [(float(p[0]), float(p[1])) for p in hull_points]
            polygon.append(polygon[0])  # Close the ring

            logger.debug(f"Created convex hull with {len(polygon)} points from {len(coords)} input points")
            return polygon

        except Exception as e:
            logger.warning(f"Failed to create convex hull: {e}")
            return None

    def _extract_coords_from_geom(self, geom: Any) -> List[Tuple[float, float]]:
        """Extract coordinate pairs from various geometry formats"""
        coords = []

        if isinstance(geom, dict):
            # GeoJSON format
            if "coordinates" in geom:
                raw_coords = geom["coordinates"]
                if isinstance(raw_coords, list):
                    # Could be Point, LineString, or MultiLineString
                    self._flatten_coords(raw_coords, coords)
        elif isinstance(geom, str):
            # WKT or other string format - skip for now
            pass

        return coords

    def _flatten_coords(self, raw: Any, coords: List[Tuple[float, float]]):
        """Recursively flatten coordinate arrays"""
        if not raw:
            return
        if isinstance(raw[0], (int, float)):
            # This is a coordinate pair [lon, lat]
            if len(raw) >= 2:
                coords.append((float(raw[0]), float(raw[1])))
        elif isinstance(raw[0], list):
            # Nested array
            for item in raw:
                self._flatten_coords(item, coords)

    def transform_blockface(self, raw_blockfaces: List[Dict[str, Any]]) -> List[ParkingRegulation]:
        """
        Transform DataSF blockface data into ParkingRegulation objects.
        hi6h-neyh dataset field mappings:
        - rpparea1/rpparea2/rpparea3 -> rpp_area
        - regulation -> regulation type
        - days -> enforcement days (e.g., "M-F")
        - hrs_begin/hrs_end or hours -> time range
        - hrlimit -> time limit in hours
        - shape -> geometry
        """
        logger.info(f"Transforming {len(raw_blockfaces)} blockface records")
        regulations = []

        for record in raw_blockfaces:
            try:
                # Get RPP area from multiple possible fields
                rpp_area = (record.get("rpparea1") or record.get("RPPAREA1") or
                           record.get("rpp_area") or record.get("RPP_AREA"))

                # Get time limit - hi6h-neyh uses 'hrlimit' in hours
                time_limit = None
                hrlimit = record.get("hrlimit") or record.get("HRLIMIT")
                if hrlimit:
                    try:
                        time_limit = int(float(hrlimit)) * 60  # Convert hours to minutes
                    except (ValueError, TypeError):
                        time_limit = self._parse_time_limit(hrlimit)
                else:
                    time_limit = self._parse_time_limit(record.get("time_limit"))

                regulation = ParkingRegulation(
                    street_name=record.get("street") or record.get("STREET") or "",
                    from_street=record.get("from_street") or record.get("FROM_STREET") or "",
                    to_street=record.get("to_street") or record.get("TO_STREET") or "",
                    side=record.get("side") or record.get("SIDE") or "",
                    rpp_area=rpp_area,
                    time_limit=time_limit,
                    hours_begin=record.get("hrs_begin") or record.get("HRS_BEGIN") or record.get("hours_begin"),
                    hours_end=record.get("hrs_end") or record.get("HRS_END") or record.get("hours_end"),
                    days=self._parse_days(record.get("days") or record.get("DAYS") or ""),
                    geometry=self._extract_geometry(record),
                )

                regulations.append(regulation)

            except Exception as e:
                logger.error(f"Error transforming blockface: {e}")
                self.stats["errors"] += 1

        self.stats["regulations"] = len(regulations)
        logger.info(f"Transformed {len(regulations)} parking regulations")
        return regulations

    def transform_meters(self, raw_meters: List[Dict[str, Any]]) -> List[ParkingMeter]:
        """
        Transform DataSF parking meter data into ParkingMeter objects.
        """
        logger.info(f"Transforming {len(raw_meters)} meter records")
        meters = []

        for record in raw_meters:
            try:
                # Extract coordinates
                lat = self._safe_float(record.get("latitude"))
                lon = self._safe_float(record.get("longitude"))

                if lat is None or lon is None:
                    # Try to get from point geometry
                    point = record.get("point")
                    if point:
                        lat = self._safe_float(point.get("latitude"))
                        lon = self._safe_float(point.get("longitude"))

                if lat is None or lon is None:
                    continue

                meter = ParkingMeter(
                    post_id=record.get("post_id", ""),
                    latitude=lat,
                    longitude=lon,
                    street_name=record.get("street_name", ""),
                    street_num=record.get("street_num"),
                    cap_color=record.get("cap_color", ""),
                    time_limit=self._parse_meter_time_limit(record.get("cap_color")),
                    rate_area=record.get("rate_area"),
                )

                meters.append(meter)

            except Exception as e:
                logger.error(f"Error transforming meter: {e}")
                self.stats["errors"] += 1

        self.stats["meters"] = len(meters)
        logger.info(f"Transformed {len(meters)} parking meters")
        return meters

    def derive_metered_zones_from_meters(self, meters: List[ParkingMeter]) -> List[MeteredZone]:
        """
        Derive paid parking zones from meter locations by clustering nearby meters.

        Uses a grid-based clustering approach:
        - Divides the city into grid cells (~100m)
        - Groups meters by grid cell
        - Creates axis-aligned rectangular polygons (right angles only)
        """
        logger.info(f"Deriving metered zones from {len(meters)} meters")

        if not meters:
            return []

        # Grid cell size in degrees (~100m at SF latitude)
        GRID_SIZE = 0.001  # ~111m
        # Padding for bounding box (~15m)
        PADDING = 0.00015

        # Group meters by grid cell
        grid_cells: Dict[Tuple[int, int], List[ParkingMeter]] = {}

        for meter in meters:
            grid_x = int(meter.longitude / GRID_SIZE)
            grid_y = int(meter.latitude / GRID_SIZE)
            cell_key = (grid_x, grid_y)

            if cell_key not in grid_cells:
                grid_cells[cell_key] = []
            grid_cells[cell_key].append(meter)

        logger.info(f"Grouped meters into {len(grid_cells)} grid cells")

        # Merge adjacent grid cells into zones
        zones = []
        processed_cells = set()
        zone_counter = 0

        for cell_key in grid_cells:
            if cell_key in processed_cells:
                continue

            # Flood fill to find connected cells
            connected_cells = []
            to_process = [cell_key]

            while to_process:
                current = to_process.pop()
                if current in processed_cells:
                    continue
                if current not in grid_cells:
                    continue

                processed_cells.add(current)
                connected_cells.append(current)

                # Check adjacent cells (4-connected)
                x, y = current
                for dx, dy in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
                    neighbor = (x + dx, y + dy)
                    if neighbor in grid_cells and neighbor not in processed_cells:
                        to_process.append(neighbor)

            # Collect all meters in connected cells
            zone_meters = []
            for cell in connected_cells:
                zone_meters.extend(grid_cells[cell])

            if len(zone_meters) < 3:  # Skip tiny clusters
                continue

            # Create axis-aligned bounding box (rectangle with right angles)
            min_lon = min(m.longitude for m in zone_meters) - PADDING
            max_lon = max(m.longitude for m in zone_meters) + PADDING
            min_lat = min(m.latitude for m in zone_meters) - PADDING
            max_lat = max(m.latitude for m in zone_meters) + PADDING

            # Create rectangular polygon (4 corners, closed ring)
            # Order: bottom-left, bottom-right, top-right, top-left, close
            rect_coords = [
                (min_lon, min_lat),  # bottom-left
                (max_lon, min_lat),  # bottom-right
                (max_lon, max_lat),  # top-right
                (min_lon, max_lat),  # top-left
                (min_lon, min_lat),  # close the ring
            ]

            polygon_coords = [rect_coords]

            # Calculate zone statistics
            cap_colors = list(set(m.cap_color for m in zone_meters if m.cap_color))
            time_limits = [m.time_limit for m in zone_meters if m.time_limit]
            avg_time = int(sum(time_limits) / len(time_limits)) if time_limits else None
            rate_areas = list(set(m.rate_area for m in zone_meters if m.rate_area))

            zone_counter += 1
            zone_id = f"METERED_{zone_counter:04d}"

            # Determine zone name from predominant street or rate area
            street_counts: Dict[str, int] = {}
            for m in zone_meters:
                if m.street_name:
                    street_counts[m.street_name] = street_counts.get(m.street_name, 0) + 1
            primary_street = max(street_counts, key=street_counts.get) if street_counts else "Unknown"
            zone_name = f"Metered - {primary_street}"

            zone = MeteredZone(
                zone_id=zone_id,
                name=zone_name,
                polygon=polygon_coords,
                meter_count=len(zone_meters),
                cap_colors=cap_colors,
                avg_time_limit=avg_time,
                rate_area=rate_areas[0] if rate_areas else None
            )
            zones.append(zone)

        logger.info(f"Derived {len(zones)} metered zones from {len(meters)} meters")
        return zones

    def generate_app_data(
        self,
        zones: List[RPPZone],
        regulations: List[ParkingRegulation],
        meters: List[ParkingMeter],
        metered_zones: Optional[List[MeteredZone]] = None
    ) -> Dict[str, Any]:
        """
        Generate the final data structure for the iOS app.
        """
        logger.info("Generating app data bundle")

        # Group regulations by RPP area
        regulations_by_area: Dict[str, List[Dict]] = {}
        for reg in regulations:
            if reg.rpp_area:
                area = reg.rpp_area.upper()
                if area not in regulations_by_area:
                    regulations_by_area[area] = []
                regulations_by_area[area].append({
                    "street": reg.street_name,
                    "from": reg.from_street,
                    "to": reg.to_street,
                    "side": reg.side,
                    "timeLimit": reg.time_limit,
                    "hoursBegin": reg.hours_begin,
                    "hoursEnd": reg.hours_end,
                    "days": reg.days,
                })

        # Build RPP zones data
        zones_data = []
        total_multi_permit = 0
        for zone in zones:
            # Convert multi_permit_polygons dict keys to strings for JSON
            mp_polygons = {str(k): v for k, v in zone.multi_permit_polygons.items()}
            total_multi_permit += len(mp_polygons)
            zones_data.append({
                "code": zone.area_code,
                "name": zone.name,
                "polygon": zone.polygon,
                "neighborhoods": zone.neighborhoods,
                "blockCount": len(regulations_by_area.get(zone.area_code, [])),
                "zoneType": "rpp",  # Residential Permit Parking
                "multiPermitPolygons": mp_polygons,  # Index -> list of valid permit areas
            })
        logger.info(f"Total multi-permit polygons across all zones: {total_multi_permit}")

        # Build metered zones data
        metered_zones_data = []
        if metered_zones:
            for mz in metered_zones:
                metered_zones_data.append({
                    "code": mz.zone_id,
                    "name": mz.name,
                    "polygon": mz.polygon,
                    "meterCount": mz.meter_count,
                    "capColors": mz.cap_colors,
                    "avgTimeLimit": mz.avg_time_limit,
                    "rateArea": mz.rate_area,
                    "zoneType": "metered",  # Paid parking
                })
            logger.info(f"Added {len(metered_zones_data)} metered zones to app data")

        # Build output
        return {
            "version": datetime.utcnow().strftime("%Y%m%d"),
            "generated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "zones": zones_data,
            "meteredZones": metered_zones_data,
            "meters": [
                {
                    "id": m.post_id,
                    "lat": m.latitude,
                    "lon": m.longitude,
                    "street": m.street_name,
                    "capColor": m.cap_color,
                    "timeLimit": m.time_limit,
                }
                for m in meters
            ],
            "stats": {
                "totalZones": len(zones),
                "totalMeteredZones": len(metered_zones_data),
                "totalMeters": len(meters),
                "totalRegulations": len(regulations),
            }
        }

    # Helper methods

    def _extract_neighborhoods(self, attrs: Dict[str, Any]) -> List[str]:
        """Extract neighborhood names from attributes"""
        neighborhoods = []
        for key in ["NEIGHBORHOOD", "neighborhood", "NHOOD", "nhood"]:
            if key in attrs and attrs[key]:
                neighborhoods.append(attrs[key])
        return neighborhoods

    def _parse_time_limit(self, value: Any) -> Optional[int]:
        """Parse time limit string to minutes"""
        if value is None:
            return None
        try:
            if isinstance(value, (int, float)):
                return int(value)
            value = str(value).upper()
            if "HR" in value or "HOUR" in value:
                hours = int("".join(filter(str.isdigit, value.split("HR")[0].split("HOUR")[0])) or "0")
                return hours * 60
            if "MIN" in value:
                return int("".join(filter(str.isdigit, value.split("MIN")[0])) or "0")
            return int("".join(filter(str.isdigit, value)) or "0")
        except (ValueError, TypeError):
            return None

    def _parse_days(self, days_str: str) -> List[str]:
        """Parse days string into list"""
        if not days_str:
            return []
        return [d.strip() for d in days_str.split(",") if d.strip()]

    def _extract_geometry(self, record: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Extract geometry from record if present"""
        # hi6h-neyh dataset uses 'shape' field
        for key in ["shape", "the_geom", "geometry"]:
            if key in record:
                return record[key]
        return None

    def _safe_float(self, value: Any) -> Optional[float]:
        """Safely convert value to float"""
        if value is None:
            return None
        try:
            return float(value)
        except (ValueError, TypeError):
            return None

    def _parse_meter_time_limit(self, cap_color: Optional[str]) -> Optional[int]:
        """Infer time limit from cap color"""
        if not cap_color:
            return None
        color_limits = {
            "GREEN": 15,     # Short-term
            "YELLOW": 30,    # Commercial loading
            "GREY": 60,      # Standard 1hr
            "GRAY": 60,
            "BROWN": 120,    # Tour bus
        }
        return color_limits.get(cap_color.upper())

    def get_stats(self) -> Dict[str, int]:
        """Return transformation statistics"""
        return self.stats.copy()
