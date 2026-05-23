"""Unit tests for Binance ingestion."""

from __future__ import annotations

import pytest
import requests
import responses

from ingestion.binance import BINANCE_TICKER_URL, fetch_tickers


@responses.activate
def test_fetch_tickers_returns_enriched_records():
    mock_response = [
        {"symbol": "BTCUSDT", "lastPrice": "65000.00", "volume": "1234.56"},
        {"symbol": "ETHUSDT", "lastPrice": "3500.00", "volume": "7890.12"},
    ]
    responses.add(
        responses.GET,
        BINANCE_TICKER_URL,
        json=mock_response,
        status=200,
    )

    records = fetch_tickers(symbols=["BTCUSDT", "ETHUSDT"])

    assert len(records) == 2
    assert all(r["source"] == "binance" for r in records)
    assert all("fetched_at" in r for r in records)
    assert records[0]["payload"]["symbol"] == "BTCUSDT"


@responses.activate
def test_fetch_tickers_raises_on_http_error():
    responses.add(responses.GET, BINANCE_TICKER_URL, status=500)

    with pytest.raises(requests.HTTPError):
        fetch_tickers(symbols=["BTCUSDT"])
