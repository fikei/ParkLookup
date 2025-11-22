"""Fetcher for SFMTA RPP Area Polygons from ArcGIS"""
import logging
from typing import Any, Dict, List

from config import (
    SFMTA_ARCGIS_BASE,
    RPP_AREAS_SERVICE,
    ARCGIS_PAGE_SIZE
)
from .base_fetcher import BaseFetcher

logger = logging.getLogger(__name__)


class RPPAreasFetcher(BaseFetcher):
    """
    Fetches RPP (Residential Parking Permit) area polygon boundaries from SFMTA ArcGIS.

    This dataset contains:
    - Official RPP zone boundaries as polygons
    - Area codes (A, B, C, etc.)
    - Zone names/descriptions

    Service: SFMTA ArcGIS Feature Service
    """

    def __init__(self):
        super().__init__()
        self.base_url = f"{SFMTA_ARCGIS_BASE}/{RPP_AREAS_SERVICE}/query"

    def get_source_name(self) -> str:
        return "SFMTA RPP Area Polygons (ArcGIS)"

    async def fetch(self) -> List[Dict[str, Any]]:
        """
        Fetch all RPP area polygon boundaries.
        Uses pagination for ArcGIS Feature Service.
        """
        logger.info(f"Starting fetch from {self.get_source_name()}")

        all_features = []
        offset = 0

        while True:
            params = {
                "where": "1=1",  # Fetch all records
                "outFields": "*",  # All fields
                "returnGeometry": "true",
                "outSR": "4326",  # WGS84 for lat/lon
                "f": "json",
                "resultOffset": offset,
                "resultRecordCount": ARCGIS_PAGE_SIZE,
            }

            logger.info(f"Fetching RPP areas {offset} to {offset + ARCGIS_PAGE_SIZE}...")

            response = await self.fetch_with_retry(self.base_url, params=params)

            features = response.get("features", [])
            if not features:
                break

            all_features.extend(features)
            logger.info(f"Fetched {len(features)} areas (total: {len(all_features)})")

            # Check if there are more records
            if not response.get("exceededTransferLimit", False) and len(features) < ARCGIS_PAGE_SIZE:
                break

            offset += ARCGIS_PAGE_SIZE

        logger.info(f"Completed fetch: {len(all_features)} total RPP areas")
        return all_features

    async def fetch_by_area_code(self, area_code: str) -> List[Dict[str, Any]]:
        """Fetch a specific RPP area by its code"""
        logger.info(f"Fetching RPP area: {area_code}")

        params = {
            "where": f"AREA='{area_code}'",
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "json",
        }

        response = await self.fetch_with_retry(self.base_url, params=params)
        return response.get("features", [])

    async def fetch_metadata(self) -> Dict[str, Any]:
        """Fetch service metadata to understand available fields"""
        metadata_url = f"{SFMTA_ARCGIS_BASE}/{RPP_AREAS_SERVICE}"
        params = {"f": "json"}
        return await self.fetch_with_retry(metadata_url, params=params)

    async def fetch_sample(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Fetch a sample of records for testing/inspection"""
        params = {
            "where": "1=1",
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "json",
            "resultRecordCount": limit,
        }
        response = await self.fetch_with_retry(self.base_url, params=params)
        return response.get("features", [])
