USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION IF NOT EXISTS s3_crypto_raw
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::768132174945:role/snowflake-s3-access-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://crypto-pipeline-raw-dev-db5482f2/raw/')
  COMMENT = 'Read access to crypto-pipeline raw bucket';

-- Grant usage to a role we'll use for pipes (start with SYSADMIN for simplicity)
GRANT USAGE ON INTEGRATION s3_crypto_raw TO ROLE SYSADMIN;
