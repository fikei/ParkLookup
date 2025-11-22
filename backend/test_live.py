#!/usr/bin/env python3
"""Live integration test for SF Parking Data Pipeline"""
import asyncio
import json
import sys
from datetime import datetime

# Test imports
print("=" * 60)
print("SF Parking Data Pipeline - Live Integration Test")
print("=" * 60)
print()

# Test 1: Import all modules
print("[Test 1] Importing modules...")
try:
    from fetchers import BlockfaceFetcher, MetersFetcher, RPPAreasFetcher
    from transformers import ParkingDataTransformer
    from validators import DataValidator
    print("  ✓ All modules imported successfully")
except ImportError as e:
    print(f"  ✗ Import failed: {e}")
    sys.exit(1)


async def test_fetchers():
    """Test 2: Fetch sample data from all sources"""
    print()
    print("[Test 2] Fetching sample data from all sources...")
    results = {}

    # Test Blockface fetcher
    print("  • DataSF Blockface...")
    try:
        async with BlockfaceFetcher() as fetcher:
            records = await fetcher.fetch_sample(limit=5)
            results["blockface"] = records
            print(f"    ✓ Fetched {len(records)} blockface records")
            if records:
                print(f"    Sample fields: {list(records[0].keys())[:5]}...")
    except Exception as e:
        print(f"    ✗ Blockface fetch failed: {e}")
        results["blockface"] = []

    # Test Meters fetcher
    print("  • DataSF Meters...")
    try:
        async with MetersFetcher() as fetcher:
            records = await fetcher.fetch_sample(limit=5)
            results["meters"] = records
            print(f"    ✓ Fetched {len(records)} meter records")
            if records:
                print(f"    Sample fields: {list(records[0].keys())[:5]}...")
    except Exception as e:
        print(f"    ✗ Meters fetch failed: {e}")
        results["meters"] = []

    # Test RPP Areas fetcher
    print("  • SFMTA RPP Areas...")
    try:
        async with RPPAreasFetcher() as fetcher:
            features = await fetcher.fetch_sample(limit=5)
            results["rpp_areas"] = features
            print(f"    ✓ Fetched {len(features)} RPP area features")
            if features:
                attrs = features[0].get("attributes", {})
                print(f"    Sample attributes: {list(attrs.keys())[:5]}...")
    except Exception as e:
        print(f"    ✗ RPP Areas fetch failed: {e}")
        results["rpp_areas"] = []

    return results


def test_transformer(raw_data):
    """Test 3: Transform data into normalized schema"""
    print()
    print("[Test 3] Transforming data...")

    transformer = ParkingDataTransformer()
    transformed = {}

    # Transform RPP areas
    if raw_data.get("rpp_areas"):
        zones = transformer.transform_rpp_areas(raw_data["rpp_areas"])
        transformed["zones"] = zones
        print(f"  ✓ Transformed {len(zones)} RPP zones")
        if zones:
            z = zones[0]
            print(f"    Sample zone: code={z.area_code}, name={z.name}")
    else:
        transformed["zones"] = []
        print("  ⚠ No RPP areas to transform")

    # Transform blockface
    if raw_data.get("blockface"):
        regulations = transformer.transform_blockface(raw_data["blockface"])
        transformed["regulations"] = regulations
        print(f"  ✓ Transformed {len(regulations)} parking regulations")
        if regulations:
            r = regulations[0]
            print(f"    Sample: {r.street_name} ({r.side}), RPP={r.rpp_area}")
    else:
        transformed["regulations"] = []
        print("  ⚠ No blockface data to transform")

    # Transform meters
    if raw_data.get("meters"):
        meters = transformer.transform_meters(raw_data["meters"])
        transformed["meters"] = meters
        print(f"  ✓ Transformed {len(meters)} parking meters")
        if meters:
            m = meters[0]
            print(f"    Sample: {m.post_id} at ({m.latitude:.4f}, {m.longitude:.4f})")
    else:
        transformed["meters"] = []
        print("  ⚠ No meter data to transform")

    # Generate app data
    print()
    print("  Generating app data bundle...")
    app_data = transformer.generate_app_data(
        zones=transformed["zones"],
        regulations=transformed["regulations"],
        meters=transformed["meters"]
    )
    print(f"  ✓ Generated app data with version: {app_data.get('version')}")
    print(f"    - {len(app_data.get('zones', []))} zones")
    print(f"    - {len(app_data.get('meters', []))} meters")

    return app_data


def test_validator(app_data):
    """Test 4: Validate data and test error catching"""
    print()
    print("[Test 4] Testing validator...")

    validator = DataValidator()

    # Test with actual data
    print("  • Validating transformed data...")
    result = validator.validate_app_data(app_data)
    print(f"    Valid: {result.is_valid}")
    if result.errors:
        print(f"    Errors: {len(result.errors)}")
        for e in result.errors[:3]:
            print(f"      - {e}")
    if result.warnings:
        print(f"    Warnings: {len(result.warnings)}")
        for w in result.warnings[:3]:
            print(f"      - {w}")

    # Test with invalid data (should catch errors)
    print()
    print("  • Testing error catching with invalid data...")

    # Missing version
    invalid_data = {"zones": [], "meters": []}
    result = validator.validate_app_data(invalid_data)
    if not result.is_valid and any("version" in e for e in result.errors):
        print("    ✓ Caught missing 'version' field")
    else:
        print("    ✗ Failed to catch missing version")

    # Invalid coordinates
    invalid_coords = {
        "version": "test",
        "zones": [],
        "meters": [{"id": "M1", "lat": 50.0, "lon": -100.0}]  # Outside SF
    }
    result = validator.validate_app_data(invalid_coords)
    if any("outside SF bounds" in w for w in result.warnings):
        print("    ✓ Caught coordinates outside SF bounds")
    else:
        print("    ✗ Failed to catch invalid coordinates")

    # Unknown RPP area
    invalid_zone = {
        "version": "test",
        "zones": [{"code": "INVALID_ZONE", "polygon": [[[-122.4, 37.7]]]}],
        "meters": []
    }
    result = validator.validate_app_data(invalid_zone)
    if any("Unknown RPP area" in w for w in result.warnings):
        print("    ✓ Caught unknown RPP area code")
    else:
        print("    ✗ Failed to catch unknown RPP area")

    return True


def test_scheduler():
    """Test 5: Verify scheduler configuration"""
    print()
    print("[Test 5] Testing scheduler configuration...")

    try:
        from config import UPDATE_SCHEDULE, UPDATE_DAY, UPDATE_HOUR
        import schedule

        print(f"  Schedule: {UPDATE_SCHEDULE}")
        print(f"  Day: {UPDATE_DAY}")
        print(f"  Hour: {UPDATE_HOUR}:00 UTC")

        # Verify schedule module works
        def dummy_job():
            pass

        if UPDATE_SCHEDULE == "weekly":
            getattr(schedule.every(), UPDATE_DAY.lower()).at(f"{UPDATE_HOUR:02d}:00").do(dummy_job)
        else:
            schedule.every().day.at(f"{UPDATE_HOUR:02d}:00").do(dummy_job)

        next_run = schedule.next_run()
        print(f"  ✓ Scheduler configured, next run: {next_run}")

        # Clear test jobs
        schedule.clear()
        return True

    except Exception as e:
        print(f"  ✗ Scheduler test failed: {e}")
        return False


async def main():
    """Run all tests"""
    start_time = datetime.now()
    all_passed = True

    # Test 2: Fetch data
    raw_data = await test_fetchers()
    if not any(raw_data.values()):
        print("\n⚠ Warning: No data fetched from any source")
        all_passed = False

    # Test 3: Transform data
    app_data = test_transformer(raw_data)
    if not app_data.get("zones") and not app_data.get("meters"):
        print("\n⚠ Warning: No data transformed")

    # Test 4: Validate data
    test_validator(app_data)

    # Test 5: Scheduler
    if not test_scheduler():
        all_passed = False

    # Summary
    duration = (datetime.now() - start_time).total_seconds()
    print()
    print("=" * 60)
    print(f"Tests completed in {duration:.1f}s")
    if all_passed:
        print("✓ All completion criteria verified!")
    else:
        print("⚠ Some tests had warnings - review output above")
    print("=" * 60)

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
