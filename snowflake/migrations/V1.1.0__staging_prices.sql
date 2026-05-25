USE DATABASE CRYPTO_DEV;
USE SCHEMA STAGING;
USE WAREHOUSE CRYPTO_WH;

-- Typed, normalized table that unifies Binance + Coinbase records
CREATE TABLE IF NOT EXISTS prices (
  symbol       VARCHAR(20)    NOT NULL,    -- e.g. BTC-USD, ETH-USD
  exchange     VARCHAR(20)    NOT NULL,    -- binance / coinbase
  event_ts     TIMESTAMP_NTZ  NOT NULL,    -- when the price was observed
  open_price   NUMBER(28,12),
  high_price   NUMBER(28,12),
  low_price    NUMBER(28,12),
  close_price  NUMBER(28,12)  NOT NULL,    -- the canonical price
  volume       NUMBER(28,12),
  fetched_at   TIMESTAMP_NTZ  NOT NULL,    -- when we ingested it
  source_row_id NUMBER,                    -- pointer back to RAW
  inserted_at  TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (symbol, exchange, event_ts)
)
COMMENT = 'Typed, normalized prices unified across exchanges';
