USE DATABASE CRYPTO_DEV;
USE SCHEMA RAW;
USE WAREHOUSE CRYPTO_WH;

-- File format for newline-delimited JSON
CREATE FILE FORMAT IF NOT EXISTS ff_json_ndjson
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE
  COMPRESSION = AUTO
  COMMENT = 'Newline-delimited JSON (one record per line)';

-- Single raw table for both sources, distinguished by metadata column
CREATE TABLE IF NOT EXISTS market_ticks_raw (
  id                NUMBER AUTOINCREMENT START 1 INCREMENT 1,
  source            VARCHAR(20)    NOT NULL,
  fetched_at        TIMESTAMP_NTZ  NOT NULL,
  payload           VARIANT        NOT NULL,
  s3_file_name      VARCHAR(500),
  ingested_at       TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (id)
)
COMMENT = 'Raw ingested ticks from all exchange APIs';
