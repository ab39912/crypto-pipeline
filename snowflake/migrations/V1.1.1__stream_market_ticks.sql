USE DATABASE CRYPTO_DEV;
USE SCHEMA RAW;

-- Stream tracks new inserts into market_ticks_raw
CREATE STREAM IF NOT EXISTS stream_market_ticks
  ON TABLE market_ticks_raw
  APPEND_ONLY = TRUE
  COMMENT = 'CDC stream for new rows in market_ticks_raw';
