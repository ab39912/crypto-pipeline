USE DATABASE CRYPTO_DEV;
USE SCHEMA RAW;
USE WAREHOUSE CRYPTO_WH;

-- Snowpipe: auto-load new files from S3 into market_ticks_raw
CREATE OR REPLACE PIPE pipe_market_ticks_raw
  AUTO_INGEST = TRUE
  COMMENT = 'Auto-ingest new files from S3 raw stage'
AS
COPY INTO market_ticks_raw (source, fetched_at, payload, s3_file_name)
FROM (
  SELECT
    $1:source::VARCHAR,
    $1:fetched_at::TIMESTAMP_NTZ,
    $1:payload::VARIANT,
    METADATA$FILENAME
  FROM @s3_crypto_stage
)
FILE_FORMAT = (FORMAT_NAME = ff_json_ndjson)
ON_ERROR = 'CONTINUE';
