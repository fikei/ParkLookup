#!/usr/bin/env python3
"""Quick script to inspect DataSF dataset schema"""
import asyncio
import aiohttp
import json

DATASET_URL = "https://data.sfgov.org/resource/qbyz-te2i.json"

async def inspect():
    async with aiohttp.ClientSession() as session:
        # Fetch just 3 records to see the schema
        params = {"$limit": 3}
        async with session.get(DATASET_URL, params=params) as response:
            if response.status != 200:
                print(f"Error: {response.status}")
                text = await response.text()
                print(text[:500])
                return

            data = await response.json()
            if data:
                print("=== FIELD NAMES ===")
                for key in sorted(data[0].keys()):
                    print(f"  - {key}")
                print()
                print("=== SAMPLE RECORD ===")
                print(json.dumps(data[0], indent=2)[:2000])
            else:
                print("No data returned")

if __name__ == "__main__":
    asyncio.run(inspect())
