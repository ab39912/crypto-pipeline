-- Create databases for dev environment
CREATE DATABASE IF NOT EXISTS CRYPTO_DEV
  COMMENT = 'Crypto pipeline - development environment';

USE DATABASE CRYPTO_DEV;

-- RAW: immutable landing zone, VARIANT columns
CREATE SCHEMA IF NOT EXISTS RAW
  COMMENT = 'Raw API ingestion - append-only, VARIANT payloads';

-- STAGING: typed, deduped, normalized
CREATE SCHEMA IF NOT EXISTS STAGING
  COMMENT = 'Typed and cleaned data';

-- ANALYTICS: business-facing marts
CREATE SCHEMA IF NOT EXISTS ANALYTICS
  COMMENT = 'Final consumption layer';

-- Dedicated warehouse for the pipeline
CREATE WAREHOUSE IF NOT EXISTS CRYPTO_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for crypto pipeline (auto-suspends in 60s)';
