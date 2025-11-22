"""Fetcher for DataSF Map of Parking Regulations (Blockface) data"""
import logging
from typing import Any, Dict, List

from config import (
    DATASF_BASE_URL,
    BLOCKFACE_DATASET_ID,
    DATASF_APP_TOKEN,
    DATASF_PAGE_SIZE
)
from .base_fetcher import BaseFetcher

logger = logging.getLogger(__name__)


class BlockfaceFetcher(BaseFetcher):
    """
    Fetches parking regulation data from DataSF Blockface dataset.

    Dataset: Parking regulations (except non-metered color curb)
    ID: hi6h-neyh

    This dataset contains:
    - Street segments with parking regulations
    - RPP (Residential Parking Permit) areas (rpparea1, rpparea2, rpparea3)
    - Time limits (hrlimit), hours of operation (hrs_begin, hrs_end)
    - Geometry (multilinestring for each block face)

    API: https://data.sfgov.org/Transportation/Parking-regulations-except-non-metered-color-curb-/hi6h-neyh
    """

    def __init__(self):
        super().__init__()
        self.base_url = f"{DATASF_BASE_URL}/{BLOCKFACE_DATASET_ID}.json"

    def get_source_name(self) -> str:
        return "DataSF Blockface (Parking Regulations)"

    async def fetch(self) -> List[Dict[str, Any]]:
        """
        Fetch all blockface parking regulation data.
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
                "$order": ":id",  # Consistent ordering for pagination
            }

            logger.info(f"Fetching records {offset} to {offset + DATASF_PAGE_SIZE}...")

            records = await self.fetch_with_retry(
                self.base_url,
                params=params,
                headers=headers
            )

            if not records:
                break

            all_records.extend(records)
            logger.info(f"Fetched {len(records)} records (total: {len(all_records)})")

            if len(records) < DATASF_PAGE_SIZE:
                break

            offset += DATASF_PAGE_SIZE

        logger.info(f"Completed fetch: {len(all_records)} total records")
        return all_records

    async def fetch_rpp_only(self) -> List[Dict[str, Any]]:
        """
        Fetch only records with RPP (Residential Parking Permit) restrictions.
        More efficient if we only need RPP data.
        """
        logger.info("Fetching RPP-only records from Blockface dataset")

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
                "$where": "rpparea1 IS NOT NULL",  # Only RPP records
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

        logger.info(f"Fetched {len(all_records)} RPP records")
        return all_records

    async def fetch_sample(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Fetch a sample of records for testing/inspection"""
        headers = {}
        if DATASF_APP_TOKEN:
            headers["X-App-Token"] = DATASF_APP_TOKEN

        params = {"$limit": limit}
        return await self.fetch_with_retry(self.base_url, params=params, headers=headers)
