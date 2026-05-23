"""Pull 24hr ticker data from Binance public API."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import requests

logger = logging.getLogger(__name__)

BINANCE_TICKER_URL = "https://data-api.binance.vision/api/v3/ticker/24hr"
DEFAULT_SYMBOLS = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "ADAUSDT", "DOGEUSDT"]


def fetch_tickers(symbols: list[str] | None = None, timeout: int = 10) -> list[dict]:
    """Fetch 24hr ticker stats for given symbols from Binance."""
    symbols = symbols or DEFAULT_SYMBOLS
    params = {"symbols": json.dumps(symbols, separators=(",", ":"))}

    logger.info("Fetching %d symbols from Binance", len(symbols))
    response = requests.get(BINANCE_TICKER_URL, params=params, timeout=timeout)
    response.raise_for_status()

    data = response.json()
    fetched_at = datetime.now(timezone.utc).isoformat()

    # Enrich each record with ingestion metadata
    return [{"source": "binance", "fetched_at": fetched_at, "payload": item} for item in data]


def write_local(records: list[dict], output_dir: str = "./data/raw") -> Path:
    """Write records to a timestamped JSON file locally (dev/testing)."""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filepath = output_path / f"binance_{ts}.json"

    with filepath.open("w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")

    logger.info("Wrote %d records to %s", len(records), filepath)
    return filepath


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    records = fetch_tickers()
    filepath = write_local(records)
    print(f"✅ Wrote {len(records)} records to {filepath}")


if __name__ == "__main__":
    main()
