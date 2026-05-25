USE DATABASE CRYPTO_DEV;
USE SCHEMA ANALYTICS;
USE WAREHOUSE CRYPTO_WH;

CREATE OR REPLACE PROCEDURE sp_detect_arbitrage(spread_threshold_pct FLOAT DEFAULT 0.05)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'detect_arbitrage'
COMMENT = 'Detect cross-exchange price spreads exceeding threshold'
AS
$$
from snowflake.snowpark import Session


def detect_arbitrage(session: Session, spread_threshold_pct: float = 0.05) -> str:
    """Find pairs of (binance, coinbase) observations of the same coin
    within 60 seconds of each other where the price spread exceeds threshold.

    Only looks at the past hour to keep the join cheap and focused on real-time arb.
    Idempotent via NOT EXISTS dedup on (symbol, exchange_a, exchange_b, ts_a, ts_b).
    """
    insert_sql = f"""
    INSERT INTO CRYPTO_DEV.ANALYTICS.ARBITRAGE_OPPORTUNITIES (
        BASE_SYMBOL, EXCHANGE_A, EXCHANGE_B,
        PRICE_A, PRICE_B, SPREAD_PCT, SPREAD_ABS,
        EVENT_TS_A, EVENT_TS_B, TS_DIFF_SECONDS
    )
    WITH normalized AS (
        SELECT
            CASE
                WHEN EXCHANGE = 'binance' THEN REGEXP_REPLACE(SYMBOL, 'USDT$', '')
                WHEN EXCHANGE = 'coinbase' THEN SPLIT_PART(SYMBOL, '-', 1)
            END AS BASE_SYMBOL,
            EXCHANGE,
            EVENT_TS,
            CLOSE_PRICE
        FROM CRYPTO_DEV.STAGING.PRICES
        WHERE EVENT_TS >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
    ),
    binance AS (SELECT * FROM normalized WHERE EXCHANGE = 'binance'),
    coinbase AS (SELECT * FROM normalized WHERE EXCHANGE = 'coinbase'),
    candidates AS (
        SELECT
            b.BASE_SYMBOL,
            'binance' AS EXCHANGE_A,
            'coinbase' AS EXCHANGE_B,
            b.CLOSE_PRICE AS PRICE_A,
            c.CLOSE_PRICE AS PRICE_B,
            (ABS(b.CLOSE_PRICE - c.CLOSE_PRICE) / LEAST(b.CLOSE_PRICE, c.CLOSE_PRICE)) * 100 AS SPREAD_PCT,
            ABS(b.CLOSE_PRICE - c.CLOSE_PRICE) AS SPREAD_ABS,
            b.EVENT_TS AS EVENT_TS_A,
            c.EVENT_TS AS EVENT_TS_B,
            ABS(DATEDIFF('second', b.EVENT_TS, c.EVENT_TS)) AS TS_DIFF_SECONDS
        FROM binance b
        JOIN coinbase c
          ON b.BASE_SYMBOL = c.BASE_SYMBOL
         AND ABS(DATEDIFF('second', b.EVENT_TS, c.EVENT_TS)) <= 60
    )
    SELECT
        candidates.BASE_SYMBOL,
        candidates.EXCHANGE_A,
        candidates.EXCHANGE_B,
        candidates.PRICE_A,
        candidates.PRICE_B,
        candidates.SPREAD_PCT,
        candidates.SPREAD_ABS,
        candidates.EVENT_TS_A,
        candidates.EVENT_TS_B,
        candidates.TS_DIFF_SECONDS
    FROM candidates
    WHERE candidates.SPREAD_PCT >= {spread_threshold_pct}
      AND NOT EXISTS (
        SELECT 1
        FROM CRYPTO_DEV.ANALYTICS.ARBITRAGE_OPPORTUNITIES existing
        WHERE existing.BASE_SYMBOL = candidates.BASE_SYMBOL
          AND existing.EXCHANGE_A = candidates.EXCHANGE_A
          AND existing.EXCHANGE_B = candidates.EXCHANGE_B
          AND existing.EVENT_TS_A = candidates.EVENT_TS_A
          AND existing.EVENT_TS_B = candidates.EVENT_TS_B
      )
    """
    result = session.sql(insert_sql).collect()
    rows_inserted = result[0]["number of rows inserted"] if result else 0
    return f"Detected and inserted {rows_inserted} new arbitrage opportunities (threshold={spread_threshold_pct}%)"
$$;
