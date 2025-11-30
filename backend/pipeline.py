"""Main ETL pipeline orchestrator for SF Parking data"""
import asyncio
import json
import gzip
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from config import OUTPUT_DIR, DATA_DIR, COMPRESS_OUTPUT
from fetchers import BlockfaceFetcher, MetersFetcher, RPPAreasFetcher
from transformers import ParkingDataTransformer
from validators import DataValidator

# iOS Resources path (relative to backend directory)
IOS_RESOURCES_DIR = Path(__file__).parent.parent / "SFParkingZoneFinder" / "SFParkingZoneFinder" / "Resources"

# Local data path
DATA_RAW_DIR = Path(__file__).parent.parent / "data" / "raw"

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class ParkingDataPipeline:
    """
    ETL pipeline that fetches, transforms, validates, and outputs
    SF parking data for the iOS app.
    """

    def __init__(self):
        self.transformer = ParkingDataTransformer()
        self.validator = DataValidator()
        self.run_stats = {
            "start_time": None,
            "end_time": None,
            "fetch_times": {},
            "record_counts": {},
            "validation_result": None,
        }

    async def run(self, skip_meters: bool = False) -> bool:
        """
        Run the complete ETL pipeline.

        Args:
            skip_meters: If True, skip fetching meter data (for faster testing)

        Returns:
            True if pipeline completed successfully, False otherwise
        """
        self.run_stats["start_time"] = datetime.utcnow()
        logger.info("=" * 60)
        logger.info("Starting SF Parking Data Pipeline")
        logger.info("=" * 60)

        try:
            # Step 1: Fetch data from all sources
            logger.info("\n[Step 1/4] Fetching data from sources...")
            raw_data = await self._fetch_all_data(skip_meters)

            # Step 2: Transform data
            logger.info("\n[Step 2/4] Transforming data...")
            transformed_data = self._transform_data(raw_data, skip_meters)

            # Step 2b: Derive metered zones from meter data
            metered_zones = []
            if transformed_data.get("meters"):
                logger.info("\n[Step 2b] Deriving metered zones from meter locations...")
                metered_zones = self.transformer.derive_metered_zones_from_meters(
                    transformed_data["meters"]
                )

            # Step 3: Generate app data bundle
            logger.info("\n[Step 3/4] Generating app data...")
            app_data = self.transformer.generate_app_data(
                zones=transformed_data["zones"],
                regulations=transformed_data["regulations"],
                meters=transformed_data.get("meters", []),
                metered_zones=metered_zones
            )

            # Step 4: Validate
            logger.info("\n[Step 4/4] Validating data...")
            validation = self.validator.validate_app_data(app_data)
            self.run_stats["validation_result"] = validation

            if not validation.is_valid:
                logger.error("Validation failed!")
                for error in validation.errors:
                    logger.error(f"  - {error}")
                return False

            if validation.warnings:
                logger.warning("Validation warnings:")
                for warning in validation.warnings:
                    logger.warning(f"  - {warning}")

            # Step 5: Output
            logger.info("\n[Step 5/5] Writing output...")
            self._write_output(app_data)

            self.run_stats["end_time"] = datetime.utcnow()
            duration = (self.run_stats["end_time"] - self.run_stats["start_time"]).total_seconds()

            logger.info("\n" + "=" * 60)
            logger.info("Pipeline completed successfully!")
            logger.info(f"Duration: {duration:.1f} seconds")
            logger.info(f"RPP Zones: {len(app_data['zones'])}")
            logger.info(f"Metered Zones: {len(app_data.get('meteredZones', []))}")
            logger.info(f"Meters: {len(app_data['meters'])}")
            logger.info("=" * 60)

            # RPP Zone summary
            logger.info("\nRPP Zone Summary:")
            logger.info("-" * 40)
            total_polygons = 0
            for zone in sorted(app_data['zones'], key=lambda z: z.get('code', '')):
                code = zone.get('code', '?')
                polygon = zone.get('polygon', [])
                num_polygons = len(polygon)
                total_polygons += num_polygons
                logger.info(f"  {code:4s}: {num_polygons:,} polygons")
            logger.info("-" * 40)
            logger.info(f"  Total: {total_polygons:,} polygons across {len(app_data['zones'])} RPP zones")

            # Metered Zone summary
            metered_zones = app_data.get('meteredZones', [])
            if metered_zones:
                logger.info("\nMetered Zone Summary:")
                logger.info("-" * 40)
                total_metered_polygons = 0
                total_meters_in_zones = 0
                for mz in metered_zones[:10]:  # Show first 10
                    code = mz.get('code', '?')
                    name = mz.get('name', '?')[:30]
                    polygon = mz.get('polygon', [])
                    meter_count = mz.get('meterCount', 0)
                    num_polygons = len(polygon)
                    total_metered_polygons += num_polygons
                    total_meters_in_zones += meter_count
                    logger.info(f"  {code}: {name} ({meter_count} meters)")
                if len(metered_zones) > 10:
                    logger.info(f"  ... and {len(metered_zones) - 10} more zones")
                    for mz in metered_zones[10:]:
                        total_metered_polygons += len(mz.get('polygon', []))
                        total_meters_in_zones += mz.get('meterCount', 0)
                logger.info("-" * 40)
                logger.info(f"  Total: {total_metered_polygons:,} polygons, {total_meters_in_zones:,} meters across {len(metered_zones)} metered zones")

            # Step 6: Auto-export to iOS (if --export-ios flag or always)
            self._export_to_ios(app_data)

            return True

        except Exception as e:
            logger.exception(f"Pipeline failed with error: {e}")
            return False

    async def _fetch_all_data(self, skip_meters: bool, use_local: bool = True) -> dict:
        """Fetch data from all sources concurrently"""
        raw_data = {}

        # Use local geojson files if available
        if use_local:
            raw_data = await self._load_local_geojson()
            return raw_data

        # Fetch blockface (primary source) and RPP areas in parallel
        async with RPPAreasFetcher() as rpp_fetcher, \
                   BlockfaceFetcher() as blockface_fetcher:

            start = datetime.utcnow()

            # Blockface is the primary source for parking regulations
            blockface_task = asyncio.create_task(blockface_fetcher.fetch_rpp_only())
            raw_data["blockface"] = await blockface_task
            logger.info(f"Fetched {len(raw_data['blockface'])} blockface records")
            self.run_stats["fetch_times"]["blockface"] = (datetime.utcnow() - start).total_seconds()
            self.run_stats["record_counts"]["blockface"] = len(raw_data["blockface"])

            start = datetime.utcnow()

            # RPP areas fetch (fallback, may return empty if service unavailable)
            try:
                rpp_task = asyncio.create_task(rpp_fetcher.fetch())
                raw_data["rpp_areas"] = await rpp_task
            except Exception as e:
                logger.warning(f"RPP areas fetch failed (will derive from blockface): {e}")
                raw_data["rpp_areas"] = []

            self.run_stats["fetch_times"]["rpp_areas"] = (datetime.utcnow() - start).total_seconds()
            self.run_stats["record_counts"]["rpp_areas"] = len(raw_data["rpp_areas"])

        # Fetch meters separately (can be large)
        if not skip_meters:
            async with MetersFetcher() as meters_fetcher:
                start = datetime.utcnow()
                raw_data["meters"] = await meters_fetcher.fetch()
                self.run_stats["fetch_times"]["meters"] = (datetime.utcnow() - start).total_seconds()
                self.run_stats["record_counts"]["meters"] = len(raw_data["meters"])
        else:
            raw_data["meters"] = []

        # Save raw data for debugging
        self._save_raw_data(raw_data)

        return raw_data

    async def _load_local_geojson(self) -> dict:
        """Load data from local geojson files instead of fetching"""
        logger.info("Loading data from local geojson files...")

        raw_data = {
            "blockface": [],
            "rpp_areas": [],
            "meters": []
        }

        # Load blockfaces (contains multi-RPP data in rpparea1/2/3 fields)
        blockface_path = DATA_RAW_DIR / "Parking_regulations_(except_non-metered_color_curb)_20251128.geojson"
        if blockface_path.exists():
            logger.info(f"Loading blockface data from {blockface_path.name}...")
            with open(blockface_path) as f:
                geojson = json.load(f)
                for feature in geojson.get('features', []):
                    record = feature.get('properties', {})
                    if 'geometry' in feature:
                        record['shape'] = feature['geometry']
                    raw_data["blockface"].append(record)
            logger.info(f"Loaded {len(raw_data['blockface'])} blockface records with multi-RPP support")

        # Load meters
        meters_path = DATA_RAW_DIR / "Parking_Meters_20251128.geojson"
        if meters_path.exists():
            logger.info(f"Loading meter data from {meters_path.name}...")
            with open(meters_path) as f:
                geojson = json.load(f)
                for feature in geojson.get('features', []):
                    record = feature.get('properties', {})
                    if 'geometry' in feature:
                        # Extract lat/lon from geometry for meters
                        coords = feature['geometry'].get('coordinates', [])
                        if coords:
                            record['longitude'] = coords[0]
                            record['latitude'] = coords[1]
                    raw_data["meters"].append(record)
            logger.info(f"Loaded {len(raw_data['meters'])} meter records")

        # Note: RPP areas can stay empty - we derive from blockface now
        logger.info("RPP areas will be derived from blockface data")

        return raw_data

    def _transform_data(self, raw_data: dict, skip_meters: bool) -> dict:
        """Transform raw data into structured objects"""
        zones = []

        # Primary: Derive zones from blockface data (parking regulations by street segment)
        if raw_data.get("blockface"):
            logger.info(f"Deriving zones from {len(raw_data['blockface'])} blockface records...")
            zones = self.transformer.derive_zones_from_blockface(raw_data["blockface"])

        # Fallback: Try RPP areas if blockface unavailable
        if not zones and raw_data.get("rpp_areas"):
            logger.info("Falling back to RPP area polygons...")
            zones = self.transformer.transform_rpp_areas(raw_data["rpp_areas"])

        return {
            "zones": zones,
            "regulations": self.transformer.transform_blockface(raw_data["blockface"]),
            "meters": self.transformer.transform_meters(raw_data["meters"]) if not skip_meters else [],
        }

    def _save_raw_data(self, raw_data: dict):
        """Save raw fetched data for debugging/auditing"""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")

        for name, data in raw_data.items():
            output_path = DATA_DIR / f"raw_{name}_{timestamp}.json"
            with open(output_path, "w") as f:
                json.dump(data, f)
            logger.info(f"Saved raw {name} data to {output_path}")

    def _write_output(self, app_data: dict):
        """Write final output for the iOS app"""
        timestamp = datetime.utcnow().strftime("%Y%m%d")

        # Main output file
        output_filename = f"parking_data_{timestamp}.json"
        output_path = OUTPUT_DIR / output_filename

        if COMPRESS_OUTPUT:
            output_path = output_path.with_suffix(".json.gz")
            with gzip.open(output_path, "wt", encoding="utf-8") as f:
                json.dump(app_data, f, indent=2)
        else:
            with open(output_path, "w") as f:
                json.dump(app_data, f, indent=2)

        logger.info(f"Wrote output to {output_path}")

        # Also write a "latest" symlink/copy
        latest_path = OUTPUT_DIR / "parking_data_latest.json"
        if COMPRESS_OUTPUT:
            latest_path = latest_path.with_suffix(".json.gz")

        # Remove existing latest if exists
        if latest_path.exists():
            latest_path.unlink()

        # Create symlink (or copy on Windows)
        try:
            latest_path.symlink_to(output_path.name)
            logger.info(f"Created latest symlink: {latest_path}")
        except OSError:
            # Fallback to copy if symlinks not supported
            import shutil
            shutil.copy(output_path, latest_path)
            logger.info(f"Created latest copy: {latest_path}")

        # Write zones-only file for quick loading
        zones_path = OUTPUT_DIR / f"zones_only_{timestamp}.json"
        with open(zones_path, "w") as f:
            json.dump({
                "version": app_data["version"],
                "generated": app_data["generated"],
                "zones": app_data["zones"],
            }, f, indent=2)
        logger.info(f"Wrote zones-only file to {zones_path}")

    def _export_to_ios(self, app_data: dict):
        """Export data to iOS Resources folder using convert_to_ios module"""
        try:
            # Import the converter
            from convert_to_ios import convert_pipeline_to_ios, save_output

            logger.info("\n[Step 6/6] Exporting to iOS bundle...")

            # Convert to iOS format
            ios_data = convert_pipeline_to_ios(app_data)

            # Ensure iOS Resources directory exists
            ios_output = IOS_RESOURCES_DIR / "sf_parking_zones.json"
            IOS_RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

            # Save to iOS Resources
            save_output(ios_data, ios_output)

            logger.info(f"Exported to iOS: {ios_output}")
            logger.info(f"  Zones: {len(ios_data.get('zones', []))}")

        except ImportError:
            logger.warning("convert_to_ios module not found, skipping iOS export")
        except Exception as e:
            logger.warning(f"iOS export failed (non-fatal): {e}")


async def run_pipeline(skip_meters: bool = False) -> bool:
    """Entry point for running the pipeline"""
    pipeline = ParkingDataPipeline()
    return await pipeline.run(skip_meters=skip_meters)


if __name__ == "__main__":
    import sys

    skip_meters = "--skip-meters" in sys.argv
    success = asyncio.run(run_pipeline(skip_meters=skip_meters))
    sys.exit(0 if success else 1)
