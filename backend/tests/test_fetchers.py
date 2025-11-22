"""Tests for data fetchers"""
import pytest
import asyncio

# Add parent directory to path for imports
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from fetchers import BlockfaceFetcher, MetersFetcher, RPPAreasFetcher


class TestBlockfaceFetcher:
    """Tests for BlockfaceFetcher"""

    @pytest.mark.asyncio
    async def test_fetch_sample(self):
        """Test fetching a sample of blockface data"""
        async with BlockfaceFetcher() as fetcher:
            records = await fetcher.fetch_sample(limit=10)

            assert isinstance(records, list)
            assert len(records) <= 10

            if records:
                # Check expected fields exist
                record = records[0]
                assert "street" in record or "cnn" in record  # At least one identifier

    @pytest.mark.asyncio
    async def test_source_name(self):
        """Test source name is set correctly"""
        fetcher = BlockfaceFetcher()
        assert "Blockface" in fetcher.get_source_name()


class TestMetersFetcher:
    """Tests for MetersFetcher"""

    @pytest.mark.asyncio
    async def test_fetch_sample(self):
        """Test fetching a sample of meter data"""
        async with MetersFetcher() as fetcher:
            records = await fetcher.fetch_sample(limit=10)

            assert isinstance(records, list)
            assert len(records) <= 10

            if records:
                record = records[0]
                # Meters should have location data
                has_location = (
                    "latitude" in record or
                    "longitude" in record or
                    "point" in record
                )
                assert has_location

    @pytest.mark.asyncio
    async def test_source_name(self):
        """Test source name is set correctly"""
        fetcher = MetersFetcher()
        assert "Meters" in fetcher.get_source_name()


class TestRPPAreasFetcher:
    """Tests for RPPAreasFetcher"""

    @pytest.mark.asyncio
    async def test_fetch_sample(self):
        """Test fetching a sample of RPP area data"""
        async with RPPAreasFetcher() as fetcher:
            features = await fetcher.fetch_sample(limit=5)

            assert isinstance(features, list)
            assert len(features) <= 5

            if features:
                feature = features[0]
                # ArcGIS features should have attributes and geometry
                assert "attributes" in feature or "geometry" in feature

    @pytest.mark.asyncio
    async def test_source_name(self):
        """Test source name is set correctly"""
        fetcher = RPPAreasFetcher()
        assert "RPP" in fetcher.get_source_name()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
