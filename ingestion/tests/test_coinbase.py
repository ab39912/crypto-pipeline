"""Unit tests for Coinbase ingestion."""

from __future__ import annotations

import pytest
import requests
import responses

from ingestion.coinbase import COINBASE_BASE_URL, fetch_candles


@responses.activate
def test_fetch_candles_normalizes_records():
    # Coinbase returns: [time, low, high, open, close, volume]
    mock_response = [
        [1700000000, 35000.0, 36000.0, 35500.0, 35800.0, 12.5],
        [1700000060, 35800.0, 36100.0, 35900.0, 36000.0, 8.3],
    ]
    responses.add(
        responses.GET,
        f"{COINBASE_BASE_URL}/products/BTC-USD/candles",
        json=mock_response,
        status=200,
    )

    records = fetch_candles("BTC-USD", granularity=60)

    assert len(records) == 2
    assert all(r["source"] == "coinbase" for r in records)
    assert records[0]["payload"]["product_id"] == "BTC-USD"
    assert records[0]["payload"]["open"] == 35500.0
    assert records[0]["payload"]["close"] == 35800.0


@responses.activate
def test_fetch_candles_raises_on_http_error():
    responses.add(
        responses.GET,
        f"{COINBASE_BASE_URL}/products/BTC-USD/candles",
        status=500,
    )

    with pytest.raises(requests.HTTPError):
        fetch_candles("BTC-USD")
