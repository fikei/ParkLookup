"""Validate transformed parking data for quality and completeness"""
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Set
from datetime import datetime

logger = logging.getLogger(__name__)


@dataclass
class ValidationResult:
    """Result of data validation"""
    is_valid: bool
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    stats: Dict[str, Any] = field(default_factory=dict)

    def add_error(self, message: str):
        self.errors.append(message)
        self.is_valid = False

    def add_warning(self, message: str):
        self.warnings.append(message)


class DataValidator:
    """
    Validates parking data for quality, completeness, and consistency.
    """

    # Known RPP areas in San Francisco
    KNOWN_RPP_AREAS: Set[str] = {
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "AA", "BB", "CC", "DD", "EE", "FF", "GG", "HH", "II", "JJ", "KK", "LL"
    }

    # SF bounding box
    SF_BOUNDS = {
        "min_lat": 37.6398,
        "max_lat": 37.9298,
        "min_lon": -123.1738,
        "max_lon": -122.2818,
    }

    # Minimum expected counts
    MIN_ZONES = 30
    MIN_METERS = 20000
    MIN_REGULATIONS = 10000

    def validate_app_data(self, data: Dict[str, Any]) -> ValidationResult:
        """
        Validate the complete app data bundle.
        """
        result = ValidationResult(is_valid=True)

        # Check required fields
        if "version" not in data:
            result.add_error("Missing 'version' field")
        if "zones" not in data:
            result.add_error("Missing 'zones' field")
        if "meters" not in data:
            result.add_error("Missing 'meters' field")

        if not result.is_valid:
            return result

        # Validate zones
        zones_result = self._validate_zones(data.get("zones", []))
        result.errors.extend(zones_result.errors)
        result.warnings.extend(zones_result.warnings)
        if not zones_result.is_valid:
            result.is_valid = False

        # Validate meters
        meters_result = self._validate_meters(data.get("meters", []))
        result.errors.extend(meters_result.errors)
        result.warnings.extend(meters_result.warnings)
        if not meters_result.is_valid:
            result.is_valid = False

        # Cross-validation
        cross_result = self._cross_validate(data)
        result.warnings.extend(cross_result.warnings)

        # Build stats
        result.stats = {
            "zones_count": len(data.get("zones", [])),
            "meters_count": len(data.get("meters", [])),
            "validation_time": datetime.utcnow().isoformat(),
        }

        logger.info(
            f"Validation complete: valid={result.is_valid}, "
            f"errors={len(result.errors)}, warnings={len(result.warnings)}"
        )

        return result

    def _validate_zones(self, zones: List[Dict[str, Any]]) -> ValidationResult:
        """Validate RPP zones data"""
        result = ValidationResult(is_valid=True)

        if len(zones) < self.MIN_ZONES:
            result.add_warning(
                f"Low zone count: {len(zones)} (expected >= {self.MIN_ZONES})"
            )

        seen_codes: Set[str] = set()

        for i, zone in enumerate(zones):
            # Check required fields
            code = zone.get("code")
            if not code:
                result.add_error(f"Zone {i}: missing 'code' field")
                continue

            # Check for duplicates
            if code in seen_codes:
                result.add_warning(f"Duplicate zone code: {code}")
            seen_codes.add(code)

            # Validate code format
            if code not in self.KNOWN_RPP_AREAS:
                result.add_warning(f"Unknown RPP area code: {code}")

            # Check polygon
            polygon = zone.get("polygon", [])
            if not polygon:
                result.add_error(f"Zone {code}: missing polygon geometry")
            else:
                # Validate polygon coordinates
                for ring in polygon:
                    for coord in ring:
                        if len(coord) != 2:
                            result.add_error(f"Zone {code}: invalid coordinate format")
                            break
                        lon, lat = coord
                        if not self._is_in_sf_bounds(lat, lon):
                            result.add_warning(
                                f"Zone {code}: coordinate outside SF bounds ({lat}, {lon})"
                            )

        return result

    def _validate_meters(self, meters: List[Dict[str, Any]]) -> ValidationResult:
        """Validate parking meters data"""
        result = ValidationResult(is_valid=True)

        if len(meters) < self.MIN_METERS:
            result.add_warning(
                f"Low meter count: {len(meters)} (expected >= {self.MIN_METERS})"
            )

        seen_ids: Set[str] = set()
        invalid_coords = 0
        outside_bounds = 0

        for meter in meters:
            meter_id = meter.get("id")

            # Check for duplicates
            if meter_id and meter_id in seen_ids:
                result.add_warning(f"Duplicate meter ID: {meter_id}")
            if meter_id:
                seen_ids.add(meter_id)

            # Validate coordinates
            lat = meter.get("lat")
            lon = meter.get("lon")

            if lat is None or lon is None:
                invalid_coords += 1
                continue

            if not self._is_in_sf_bounds(lat, lon):
                outside_bounds += 1

        if invalid_coords > 0:
            result.add_warning(f"{invalid_coords} meters with invalid coordinates")

        if outside_bounds > 0:
            result.add_warning(f"{outside_bounds} meters outside SF bounds")

        # Error if too many issues
        if invalid_coords > len(meters) * 0.1:  # More than 10%
            result.add_error(f"Too many meters with invalid coordinates ({invalid_coords})")

        return result

    def _cross_validate(self, data: Dict[str, Any]) -> ValidationResult:
        """Cross-validate data between different sources"""
        result = ValidationResult(is_valid=True)

        zones = data.get("zones", [])
        zone_codes = {z.get("code") for z in zones if z.get("code")}

        # Check for zones with no blocks
        for zone in zones:
            block_count = zone.get("blockCount", 0)
            if block_count == 0:
                result.add_warning(f"Zone {zone.get('code')} has no associated blocks")

        return result

    def _is_in_sf_bounds(self, lat: float, lon: float) -> bool:
        """Check if coordinate is within San Francisco bounds"""
        return (
            self.SF_BOUNDS["min_lat"] <= lat <= self.SF_BOUNDS["max_lat"] and
            self.SF_BOUNDS["min_lon"] <= lon <= self.SF_BOUNDS["max_lon"]
        )

    def validate_incremental(
        self,
        new_data: Dict[str, Any],
        existing_data: Dict[str, Any]
    ) -> ValidationResult:
        """
        Validate new data against existing data to detect significant changes.
        Useful for detecting data quality issues in updates.
        """
        result = ValidationResult(is_valid=True)

        new_zones = len(new_data.get("zones", []))
        existing_zones = len(existing_data.get("zones", []))

        # Check for significant zone count changes
        if existing_zones > 0:
            zone_change = abs(new_zones - existing_zones) / existing_zones
            if zone_change > 0.2:  # More than 20% change
                result.add_warning(
                    f"Significant zone count change: {existing_zones} -> {new_zones}"
                )

        new_meters = len(new_data.get("meters", []))
        existing_meters = len(existing_data.get("meters", []))

        # Check for significant meter count changes
        if existing_meters > 0:
            meter_change = abs(new_meters - existing_meters) / existing_meters
            if meter_change > 0.1:  # More than 10% change
                result.add_warning(
                    f"Significant meter count change: {existing_meters} -> {new_meters}"
                )

        return result
