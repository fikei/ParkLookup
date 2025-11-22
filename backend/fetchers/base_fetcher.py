"""Base fetcher class with common functionality"""
import asyncio
import logging
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional
import aiohttp

from config import MAX_RETRIES, RETRY_DELAY, REQUEST_TIMEOUT

logger = logging.getLogger(__name__)


class BaseFetcher(ABC):
    """Abstract base class for all data fetchers"""

    def __init__(self):
        self.session: Optional[aiohttp.ClientSession] = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=REQUEST_TIMEOUT)
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def fetch_with_retry(
        self,
        url: str,
        params: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        """Fetch URL with retry logic and exponential backoff"""
        last_error = None

        for attempt in range(MAX_RETRIES):
            try:
                async with self.session.get(url, params=params, headers=headers) as response:
                    response.raise_for_status()
                    return await response.json()
            except aiohttp.ClientError as e:
                last_error = e
                wait_time = RETRY_DELAY * (2 ** attempt)
                logger.warning(
                    f"Request failed (attempt {attempt + 1}/{MAX_RETRIES}): {e}. "
                    f"Retrying in {wait_time}s..."
                )
                await asyncio.sleep(wait_time)
            except Exception as e:
                logger.error(f"Unexpected error fetching {url}: {e}")
                raise

        raise last_error or Exception(f"Failed to fetch {url} after {MAX_RETRIES} attempts")

    @abstractmethod
    async def fetch(self) -> List[Dict[str, Any]]:
        """Fetch all data from the source. Must be implemented by subclasses."""
        pass

    @abstractmethod
    def get_source_name(self) -> str:
        """Return the name of this data source"""
        pass
