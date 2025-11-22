"""Fetcher for DataSF RPP Eligibility Parcels data (actual polygons)"""
import logging
from typing import Any, Dict, List

from config import (
    DATASF_BASE_URL,
    RPP_PARCELS_DATASET_ID,
    DATASF_APP_TOKEN,
    DATASF_PAGE_SIZE
)
from .base_fetcher import BaseFetcher

logger = logging.getLogger(__name__)


class RPPParcelsFetcher(BaseFetcher):
    """
    Fetches RPP eligibility parcel polygons from DataSF.

    Dataset: Residential Parking Permit Eligibility Parcels
    ID: i886-hxz9

    This dataset contains actual parcel polygons with RPP area codes,
    providing precise zone boundaries instead of approximations.

    API: https://data.sfgov.org/Transportation/Residential-Parking-Permit-Eligibility-Parcels/i886-hxz9
    """

    def __init__(self):
        super().__init__()
        self.base_url = f"{DATASF_BASE_URL}/{RPP_PARCELS_DATASET_ID}.geojson"

    def get_source_name(self) -> str:
        return "DataSF RPP Eligibility Parcels"

    async def fetch(self) -> List[Dict[str, Any]]:
        """
        Fetch all RPP parcel polygons.
        Returns GeoJSON features with polygon geometry.
        """
        logger.info(f"Starting fetch from {self.get_source_name()}")

        headers = {}
        if DATASF_APP_TOKEN:
            headers["X-App-Token"] = DATASF_APP_TOKEN

        # Fetch as GeoJSON to get polygon geometries
        # The .geojson endpoint returns all features with geometry
        try:
            result = await self.fetch_with_retry(
                self.base_url,
                headers=headers
            )

            # Result should be a GeoJSON FeatureCollection
            if isinstance(result, dict) and "features" in result:
                features = result["features"]
                logger.info(f"Fetched {len(features)} RPP parcel features")
                return features
            else:
                logger.warning(f"Unexpected response format: {type(result)}")
                return []

        except Exception as e:
            logger.error(f"Failed to fetch RPP parcels: {e}")
            return []

    async def fetch_by_area(self, area_code: str) -> List[Dict[str, Any]]:
        """Fetch parcels for a specific RPP area"""
        headers = {}
        if DATASF_APP_TOKEN:
            headers["X-App-Token"] = DATASF_APP_TOKEN

        # Use JSON endpoint with filter
        json_url = f"{DATASF_BASE_URL}/{RPP_PARCELS_DATASET_ID}.json"
        params = {
            "$where": f"rpp_area = '{area_code}'",
            "$limit": DATASF_PAGE_SIZE
        }

        return await self.fetch_with_retry(json_url, params=params, headers=headers)
