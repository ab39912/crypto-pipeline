"""Pull OHLCV candle data from Coinbase Exchange public API."""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

from ingestion.s3_writer import write_s3

logger = logging.getLogger(__name__)

COINBASE_BASE_URL = "https://api.exchange.coinbase.com"
DEFAULT_PRODUCTS = ["BTC-USD", "ETH-USD", "SOL-USD", "ADA-USD", "DOGE-USD"]
DEFAULT_GRANULARITY = 60


def fetch_candles(
    product_id: str,
    granularity: int = DEFAULT_GRANULARITY,
    timeout: int = 10,
) -> list[dict]:
    """Fetch recent candles for one product from Coinbase Exchange."""
    url = f"{COINBASE_BASE_URL}/products/{product_id}/candles"
    params = {"granularity": granularity}

    response = requests.get(url, params=params, timeout=timeout)
    response.raise_for_status()

    raw_candles = response.json()
    fetched_at = datetime.now(timezone.utc).isoformat()

    records = []
    for candle in raw_candles:
        records.append(
            {
                "source": "coinbase",
                "fetched_at": fetched_at,
                "payload": {
                    "product_id": product_id,
                    "time": candle[0],
                    "low": candle[1],
                    "high": candle[2],
                    "open": candle[3],
                    "close": candle[4],
                    "volume": candle[5],
                },
            }
        )
    return records


def fetch_all_products(
    products: list[str] | None = None,
    granularity: int = DEFAULT_GRANULARITY,
) -> list[dict]:
    """Fetch candles for all products, with polite rate limiting."""
    products = products or DEFAULT_PRODUCTS
    all_records = []

    for product_id in products:
        try:
            logger.info("Fetching candles for %s", product_id)
            records = fetch_candles(product_id, granularity=granularity)
            all_records.extend(records)
            time.sleep(0.5)
        except requests.HTTPError:
            logger.exception("Failed to fetch %s", product_id)

    return all_records


def write_local(records: list[dict], output_dir: str = "./data/raw") -> Path:
    """Write records to a timestamped JSON file locally."""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filepath = output_path / f"coinbase_{ts}.jsonl"

    with filepath.open("w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")

    logger.info("Wrote %d records to %s", len(records), filepath)
    return filepath


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    records = fetch_all_products()

    if os.environ.get("RAW_BUCKET"):
        uri = write_s3(records, source="coinbase")
        print(f"✅ Wrote {len(records)} records to {uri}")
    else:
        filepath = write_local(records)
        print(f"✅ Wrote {len(records)} records to {filepath}")


if __name__ == "__main__":
    main()
