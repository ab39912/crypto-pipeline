USE DATABASE CRYPTO_DEV;
USE SCHEMA ANALYTICS;
USE WAREHOUSE CRYPTO_WH;

CREATE TABLE IF NOT EXISTS arbitrage_opportunities (
  id              NUMBER AUTOINCREMENT START 1 INCREMENT 1,
  base_symbol     VARCHAR(10)    NOT NULL,
  exchange_a      VARCHAR(20)    NOT NULL,
  exchange_b      VARCHAR(20)    NOT NULL,
  price_a         NUMBER(28,12)  NOT NULL,
  price_b         NUMBER(28,12)  NOT NULL,
  spread_pct      NUMBER(10,6)   NOT NULL,
  spread_abs      NUMBER(28,12)  NOT NULL,
  event_ts_a      TIMESTAMP_NTZ  NOT NULL,
  event_ts_b      TIMESTAMP_NTZ  NOT NULL,
  ts_diff_seconds NUMBER(10,2),
  detected_at     TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (id)
)
COMMENT = 'Cross-exchange price spreads exceeding threshold (potential arbitrage)';
