"""Fetcher for DataSF Parking Meters data"""
import logging
from typing import Any, Dict, List

from config import (
    DATASF_BASE_URL,
    METERS_DATASET_ID,
    DATASF_APP_TOKEN,
    DATASF_PAGE_SIZE
)
from .base_fetcher import BaseFetcher

logger = logging.getLogger(__name__)


class MetersFetcher(BaseFetcher):
    """
    Fetches parking meter data from DataSF.

    This dataset contains:
    - Meter locations (lat/lon)
    - Cap colors (indicating time limits/pricing)
    - Street addresses
    - Operating schedules

    API: https://data.sfgov.org/Transportation/Parking-Meters/8vzz-qzz9
    """

    def __init__(self):
        super().__init__()
        self.base_url = f"{DATASF_BASE_URL}/{METERS_DATASET_ID}.json"

    def get_source_name(self) -> str:
        return "DataSF Parking Meters"

    async def fetch(self) -> List[Dict[str, Any]]:
        """
        Fetch all parking meter data.
        Uses pagination to handle large dataset.
        """
        logger.info(f"Starting fetch from {self.get_source_name()}")

        all_records = []
        offset = 0

        headers = {}
        if DATASF_APP_TOKEN:
            headers["X-App-Token"] = DATASF_APP_TOKEN

        while True:
            params = {
                "$limit": DATASF_PAGE_SIZE,
                "$offset": offset,
                "$order": ":id",
            }

            logger.info(f"Fetching meters {offset} to {offset + DATASF_PAGE_SIZE}...")

            records = await self.fetch_with_retry(
                self.base_url,
                params=params,
                headers=headers
            )

            if not records:
                break

            all_records.extend(records)
            logger.info(f"Fetched {len(records)} meters (total: {len(all_records)})")

            if len(records) < DATASF_PAGE_SIZE:
                break

            offset += DATASF_PAGE_SIZE

        logger.info(f"Completed fetch: {len(all_records)} total meters")
        return all_records

    async def fetch_by_cap_color(self, cap_color: str) -> List[Dict[str, Any]]:
        """
        Fetch meters filtered by cap color.

        Common cap colors:
        - Grey: Standard metered parking
        - Green: Short-term (15-30 min)
        - Yellow: Commercial loading
        - Brown: Tour bus
        """
        logger.info(f"Fetching meters with cap color: {cap_color}")

        all_records = []
        offset = 0

        headers = {}
        if DATASF_APP_TOKEN:
            headers["X-App-Token"] = DATASF_APP_TOKEN

        while True:
            params = {
                "$limit": DATASF_PAGE_SIZE,
                "$offset": offset,
                "$order": ":id",
                "$where": f"cap_color='{cap_color}'",
            }

            records = await self.fetch_with_retry(
                self.base_url,
                params=params,
                headers=headers
            )

            if not records:
                break

            all_records.extend(records)

            if len(records) < DATASF_PAGE_SIZE:
                break

            offset += DATASF_PAGE_SIZE

        logger.info(f"Fetched {len(all_records)} {cap_color} meters")
        return all_records

    async def fetch_sample(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Fetch a sample of records for testing/inspection"""
        headers = {}
        if DATASF_APP_TOKEN:
            headers["X-App-Token"] = DATASF_APP_TOKEN

        params = {"$limit": limit}
        return await self.fetch_with_retry(self.base_url, params=params, headers=headers)
