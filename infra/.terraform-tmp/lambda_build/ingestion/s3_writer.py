"""Shared helper for writing ingestion records to S3."""

from __future__ import annotations

import json
import logging
import os
from datetime import UTC, datetime

import boto3

logger = logging.getLogger(__name__)


def write_s3(records: list[dict], source: str, bucket: str | None = None) -> str:
    """Write records to S3 as newline-delimited JSON, partitioned by source/date/hour.

    Returns the s3:// URI of the written object.
    """
    bucket = bucket or os.environ.get("RAW_BUCKET")
    if not bucket:
        raise ValueError("RAW_BUCKET env var not set and no bucket arg provided")

    now = datetime.now(UTC)
    key = (
        f"raw/{source}/"
        f"year={now.year:04d}/"
        f"month={now.month:02d}/"
        f"day={now.day:02d}/"
        f"hour={now.hour:02d}/"
        f"{source}_{now.strftime('%Y%m%d_%H%M%S')}.jsonl"
    )

    body = "\n".join(json.dumps(r) for r in records).encode("utf-8")

    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/x-ndjson",
    )

    uri = f"s3://{bucket}/{key}"
    logger.info("Wrote %d records to %s", len(records), uri)
    return uri
