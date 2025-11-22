"""Transform raw parking data into app-ready format"""
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime

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

    def transform_blockface(self, raw_blockfaces: List[Dict[str, Any]]) -> List[ParkingRegulation]:
        """
        Transform DataSF blockface data into ParkingRegulation objects.
        """
        logger.info(f"Transforming {len(raw_blockfaces)} blockface records")
        regulations = []

        for record in raw_blockfaces:
            try:
                regulation = ParkingRegulation(
                    street_name=record.get("street", ""),
                    from_street=record.get("from_street", ""),
                    to_street=record.get("to_street", ""),
                    side=record.get("side", ""),
                    rpp_area=record.get("rpp_area"),
                    time_limit=self._parse_time_limit(record.get("time_limit")),
                    hours_begin=record.get("hours_begin"),
                    hours_end=record.get("hours_end"),
                    days=self._parse_days(record.get("days", "")),
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
            "generated": datetime.utcnow().isoformat(),
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
        for key in ["the_geom", "geometry", "shape"]:
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
