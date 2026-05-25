USE DATABASE CRYPTO_DEV;
USE SCHEMA RAW;
USE WAREHOUSE CRYPTO_WH;

-- External stage pointing at the raw S3 bucket
CREATE OR REPLACE STAGE s3_crypto_stage
  STORAGE_INTEGRATION = S3_CRYPTO_RAW
  URL = 's3://crypto-pipeline-raw-dev-db5482f2/raw/'
  FILE_FORMAT = ff_json_ndjson
  COMMENT = 'Read-only stage over S3 raw landing zone';
