"""Transform raw parking data into app-ready format"""
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime

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

    def transform_rpp_parcels(self, parcel_features: List[Dict[str, Any]]) -> List[RPPZone]:
        """
        Transform DataSF RPP Eligibility Parcels GeoJSON features into RPPZone objects.
        Each parcel has its own polygon; we aggregate all parcels by RPP area into MultiPolygons.

        Dataset: i886-hxz9 (Residential Parking Permit Eligibility Parcels)
        """
        logger.info(f"Transforming {len(parcel_features)} RPP parcel features")

        # Group parcel polygons by RPP area
        areas_polygons: Dict[str, List[List[Tuple[float, float]]]] = {}

        for feature in parcel_features:
            try:
                props = feature.get("properties", {})
                geometry = feature.get("geometry", {})

                # Get RPP area code - try various field names
                # Dataset i886-hxz9 uses "rppeligib" for RPP eligibility area
                area_code = (props.get("rppeligib") or props.get("RPPELIGIB") or
                            props.get("rpp_area") or props.get("RPP_AREA") or
                            props.get("rpparea") or props.get("RPPAREA") or
                            props.get("area") or props.get("AREA"))

                if not area_code:
                    continue

                area_code = str(area_code).upper().strip()
                if not area_code:
                    continue

                # Extract polygon coordinates from GeoJSON geometry
                geom_type = geometry.get("type", "")
                coords = geometry.get("coordinates", [])

                if not coords:
                    continue

                if area_code not in areas_polygons:
                    areas_polygons[area_code] = []

                # Handle different geometry types
                if geom_type == "Polygon":
                    # Polygon has rings: [[exterior], [hole1], [hole2]...]
                    # We just want the exterior ring
                    if coords and len(coords) > 0:
                        exterior = coords[0]
                        ring = [(float(c[0]), float(c[1])) for c in exterior]
                        areas_polygons[area_code].append(ring)

                elif geom_type == "MultiPolygon":
                    # MultiPolygon: [[[ring1], [ring2]], [[ring3]]]
                    for polygon in coords:
                        if polygon and len(polygon) > 0:
                            exterior = polygon[0]
                            ring = [(float(c[0]), float(c[1])) for c in exterior]
                            areas_polygons[area_code].append(ring)

            except Exception as e:
                logger.warning(f"Error processing parcel feature: {e}")
                self.stats["errors"] += 1

        # Create zones from aggregated polygons
        zones = []
        for area_code, polygons in areas_polygons.items():
            if polygons:
                zone = RPPZone(
                    area_code=area_code,
                    name=f"Area {area_code}",
                    polygon=polygons,  # List of polygon rings (MultiPolygon)
                    total_blocks=len(polygons)
                )
                zones.append(zone)
                logger.debug(f"Zone {area_code}: {len(polygons)} parcels")

        # Sort by area code for consistent ordering
        zones.sort(key=lambda z: z.area_code)

        self.stats["rpp_zones"] = len(zones)
        total_polygons = sum(len(z.polygon) for z in zones)
        logger.info(f"Transformed {len(zones)} RPP zones from {total_polygons} parcel polygons")
        return zones

    def derive_zones_from_blockface(self, raw_blockfaces: List[Dict[str, Any]]) -> List[RPPZone]:
        """
        Derive RPP zones from blockface data when ArcGIS polygons are unavailable.
        Creates zones with bounding box polygons from the street segment endpoints.
        """
        logger.info(f"Deriving zones from {len(raw_blockfaces)} blockface records")

        # Group by RPP area
        areas: Dict[str, List[Tuple[float, float]]] = {}

        for record in raw_blockfaces:
            # hi6h-neyh dataset uses rpparea1, rpparea2, rpparea3
            rpp_area = (record.get("rpparea1") or record.get("RPPAREA1") or
                       record.get("rpp_area") or record.get("RPP_AREA"))
            if not rpp_area:
                continue

            area_code = str(rpp_area).upper().strip()
            if not area_code:
                continue

            if area_code not in areas:
                areas[area_code] = []

            # Try to extract coordinates from geometry
            geom = record.get("shape") or record.get("the_geom") or record.get("geometry")
            if geom:
                coords = self._extract_coords_from_geom(geom)
                areas[area_code].extend(coords)

        # Create zones with convex hull polygons (or bounding box as fallback)
        zones = []
        for area_code, coords in areas.items():
            if not coords:
                # Create zone without polygon
                zones.append(RPPZone(
                    area_code=area_code,
                    name=f"Area {area_code}",
                    polygon=[],
                    total_blocks=len([r for r in raw_blockfaces
                                      if (r.get("rpparea1") or r.get("RPPAREA1") or
                                          r.get("rpp_area") or r.get("RPP_AREA") or "").upper().strip() == area_code])
                ))
                continue

            # Try to create convex hull polygon
            hull_polygon = self._create_convex_hull(coords)

            if hull_polygon:
                polygon = hull_polygon
            else:
                # Fallback to bounding box
                lons = [c[0] for c in coords]
                lats = [c[1] for c in coords]
                min_lon, max_lon = min(lons), max(lons)
                min_lat, max_lat = min(lats), max(lats)
                buffer = 0.001  # ~100m
                polygon = [
                    (min_lon - buffer, min_lat - buffer),
                    (max_lon + buffer, min_lat - buffer),
                    (max_lon + buffer, max_lat + buffer),
                    (min_lon - buffer, max_lat + buffer),
                    (min_lon - buffer, min_lat - buffer),
                ]

            zones.append(RPPZone(
                area_code=area_code,
                name=f"Area {area_code}",
                polygon=[polygon],
                total_blocks=len([r for r in raw_blockfaces
                                  if (r.get("rpparea1") or r.get("RPPAREA1") or
                                      r.get("rpp_area") or r.get("RPP_AREA") or "").upper().strip() == area_code])
            ))

        logger.info(f"Derived {len(zones)} zones from blockface data")
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

    def generate_app_data(
        self,
        zones: List[RPPZone],
        regulations: List[ParkingRegulation],
        meters: List[ParkingMeter]
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

        # Build zones data
        zones_data = []
        for zone in zones:
            zones_data.append({
                "code": zone.area_code,
                "name": zone.name,
                "polygon": zone.polygon,
                "neighborhoods": zone.neighborhoods,
                "blockCount": len(regulations_by_area.get(zone.area_code, [])),
            })

        # Build output
        return {
            "version": datetime.utcnow().strftime("%Y%m%d"),
            "generated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "zones": zones_data,
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
