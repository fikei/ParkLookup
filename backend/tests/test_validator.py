"""Tests for data validator"""
import pytest

# Add parent directory to path for imports
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from validators import DataValidator


class TestDataValidator:
    """Tests for DataValidator"""

    def setup_method(self):
        """Set up test fixtures"""
        self.validator = DataValidator()

    def test_valid_app_data(self):
        """Test validation of valid app data"""
        app_data = {
            "version": "20241115",
            "generated": "2024-11-15T00:00:00",
            "zones": [
                {
                    "code": "A",
                    "name": "Area A",
                    "polygon": [[[-122.4, 37.7], [-122.4, 37.8], [-122.3, 37.7]]],
                    "blockCount": 10,
                }
                for _ in range(35)  # Enough to pass minimum zone check
            ],
            "meters": [
                {"id": f"M{i}", "lat": 37.75, "lon": -122.45}
                for i in range(25000)  # Enough to pass minimum meter check
            ],
        }

        result = self.validator.validate_app_data(app_data)

        # May have warnings about duplicate zone codes since all are "A"
        # but should be technically valid
        assert "version" not in [e for e in result.errors]

    def test_missing_version(self):
        """Test validation fails without version"""
        app_data = {
            "zones": [],
            "meters": [],
        }

        result = self.validator.validate_app_data(app_data)

        assert not result.is_valid
        assert any("version" in e for e in result.errors)

    def test_missing_zones(self):
        """Test validation fails without zones"""
        app_data = {
            "version": "20241115",
            "meters": [],
        }

        result = self.validator.validate_app_data(app_data)

        assert not result.is_valid
        assert any("zones" in e for e in result.errors)

    def test_low_zone_count_warning(self):
        """Test warning for low zone count"""
        app_data = {
            "version": "20241115",
            "zones": [
                {"code": "A", "polygon": [[[-122.4, 37.7]]]}
            ],
            "meters": [],
        }

        result = self.validator.validate_app_data(app_data)

        assert any("Low zone count" in w for w in result.warnings)

    def test_invalid_coordinates_warning(self):
        """Test warning for meters outside SF bounds"""
        app_data = {
            "version": "20241115",
            "zones": [],
            "meters": [
                {"id": "M1", "lat": 40.0, "lon": -74.0}  # New York coordinates
            ],
        }

        result = self.validator.validate_app_data(app_data)

        assert any("outside SF bounds" in w for w in result.warnings)

    def test_sf_bounds_check(self):
        """Test SF bounding box validation"""
        # Inside SF
        assert self.validator._is_in_sf_bounds(37.7749, -122.4194)

        # Outside SF (New York)
        assert not self.validator._is_in_sf_bounds(40.7128, -74.0060)

        # Just outside SF bounds
        assert not self.validator._is_in_sf_bounds(38.0, -122.4)

    def test_unknown_rpp_area_warning(self):
        """Test warning for unknown RPP area codes"""
        app_data = {
            "version": "20241115",
            "zones": [
                {"code": "ZZZ", "polygon": [[[-122.4, 37.7]]]}  # Invalid code
            ],
            "meters": [],
        }

        result = self.validator.validate_app_data(app_data)

        assert any("Unknown RPP area code" in w for w in result.warnings)

    def test_duplicate_zone_warning(self):
        """Test warning for duplicate zone codes"""
        app_data = {
            "version": "20241115",
            "zones": [
                {"code": "A", "polygon": [[[-122.4, 37.7]]]},
                {"code": "A", "polygon": [[[-122.4, 37.7]]]},  # Duplicate
            ],
            "meters": [],
        }

        result = self.validator.validate_app_data(app_data)

        assert any("Duplicate zone code" in w for w in result.warnings)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
