"""Lambda handlers for scheduled ingestion."""

from __future__ import annotations

import logging
import os

from ingestion import binance, coinbase
from ingestion.s3_writer import write_s3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def binance_handler(event, context):
    """Lambda entry: fetch Binance tickers and write to S3."""
    bucket = os.environ["RAW_BUCKET"]
    records = binance.fetch_tickers()
    uri = write_s3(records, source="binance", bucket=bucket)
    return {"statusCode": 200, "records_written": len(records), "s3_uri": uri}


def coinbase_handler(event, context):
    """Lambda entry: fetch Coinbase candles and write to S3."""
    bucket = os.environ["RAW_BUCKET"]
    records = coinbase.fetch_all_products()
    uri = write_s3(records, source="coinbase", bucket=bucket)
    return {"statusCode": 200, "records_written": len(records), "s3_uri": uri}
