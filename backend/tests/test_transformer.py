"""Tests for data transformer"""
import pytest

# Add parent directory to path for imports
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from transformers import ParkingDataTransformer


class TestParkingDataTransformer:
    """Tests for ParkingDataTransformer"""

    def setup_method(self):
        """Set up test fixtures"""
        self.transformer = ParkingDataTransformer()

    def test_transform_rpp_areas(self):
        """Test RPP area transformation"""
        raw_areas = [
            {
                "attributes": {
                    "AREA": "A",
                    "NAME": "Test Area A",
                },
                "geometry": {
                    "rings": [
                        [[-122.4, 37.7], [-122.4, 37.8], [-122.3, 37.8], [-122.3, 37.7], [-122.4, 37.7]]
                    ]
                }
            }
        ]

        zones = self.transformer.transform_rpp_areas(raw_areas)

        assert len(zones) == 1
        assert zones[0].area_code == "A"
        assert zones[0].name == "Test Area A"
        assert len(zones[0].polygon) == 1
        assert len(zones[0].polygon[0]) == 5  # 5 coordinates (closed ring)

    def test_transform_rpp_areas_missing_geometry(self):
        """Test handling of areas without geometry"""
        raw_areas = [
            {
                "attributes": {"AREA": "B"},
                "geometry": {}  # No rings
            }
        ]

        zones = self.transformer.transform_rpp_areas(raw_areas)
        assert len(zones) == 0  # Should skip areas without geometry

    def test_transform_blockface(self):
        """Test blockface transformation"""
        raw_blockfaces = [
            {
                "street": "MAIN ST",
                "from_street": "1ST AVE",
                "to_street": "2ND AVE",
                "side": "EVEN",
                "rpp_area": "A",
                "time_limit": "2HR",
            }
        ]

        regulations = self.transformer.transform_blockface(raw_blockfaces)

        assert len(regulations) == 1
        assert regulations[0].street_name == "MAIN ST"
        assert regulations[0].rpp_area == "A"
        assert regulations[0].time_limit == 120  # 2 hours = 120 minutes

    def test_transform_meters(self):
        """Test meter transformation"""
        raw_meters = [
            {
                "post_id": "TEST001",
                "latitude": "37.7749",
                "longitude": "-122.4194",
                "street_name": "Market St",
                "cap_color": "Grey",
            }
        ]

        meters = self.transformer.transform_meters(raw_meters)

        assert len(meters) == 1
        assert meters[0].post_id == "TEST001"
        assert meters[0].latitude == pytest.approx(37.7749)
        assert meters[0].longitude == pytest.approx(-122.4194)
        assert meters[0].cap_color == "Grey"
        assert meters[0].time_limit == 60  # Grey = 60 minutes

    def test_parse_time_limit_hours(self):
        """Test time limit parsing for hours"""
        assert self.transformer._parse_time_limit("2HR") == 120
        assert self.transformer._parse_time_limit("1 HOUR") == 60
        assert self.transformer._parse_time_limit("4HR") == 240

    def test_parse_time_limit_minutes(self):
        """Test time limit parsing for minutes"""
        assert self.transformer._parse_time_limit("30MIN") == 30
        assert self.transformer._parse_time_limit("15 MIN") == 15

    def test_generate_app_data(self):
        """Test app data generation"""
        from transformers.parking_transformer import RPPZone, ParkingRegulation, ParkingMeter

        zones = [RPPZone(area_code="A", name="Area A", polygon=[[]])]
        regulations = [ParkingRegulation(
            street_name="Test St", from_street="1st", to_street="2nd",
            side="EVEN", rpp_area="A", time_limit=60, hours_begin="8AM", hours_end="6PM"
        )]
        meters = [ParkingMeter(
            post_id="M1", latitude=37.77, longitude=-122.41,
            street_name="Test St", street_num="100", cap_color="Grey", time_limit=60, rate_area="1"
        )]

        app_data = self.transformer.generate_app_data(zones, regulations, meters)

        assert "version" in app_data
        assert "zones" in app_data
        assert "meters" in app_data
        assert len(app_data["zones"]) == 1
        assert len(app_data["meters"]) == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
