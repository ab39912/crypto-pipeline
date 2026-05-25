USE DATABASE CRYPTO_DEV;
USE SCHEMA STAGING;
USE WAREHOUSE CRYPTO_WH;

-- Task that runs the flatten proc whenever the stream has new rows
CREATE OR REPLACE TASK task_flatten_market_ticks
  WAREHOUSE = CRYPTO_WH
  SCHEDULE = '1 MINUTE'
  COMMENT = 'Process new rows from market_ticks_raw stream into STAGING.prices'
  WHEN SYSTEM$STREAM_HAS_DATA('CRYPTO_DEV.RAW.STREAM_MARKET_TICKS')
AS
  CALL CRYPTO_DEV.STAGING.SP_FLATTEN_MARKET_TICKS();

-- Tasks start suspended by default — must resume to run
ALTER TASK task_flatten_market_ticks RESUME;
