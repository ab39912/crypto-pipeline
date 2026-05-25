USE DATABASE CRYPTO_DEV;
USE SCHEMA STAGING;
USE WAREHOUSE CRYPTO_WH;

CREATE OR REPLACE PROCEDURE sp_flatten_market_ticks()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'flatten_market_ticks'
COMMENT = 'Flatten RAW.market_ticks_raw stream into typed STAGING.prices'
AS
$$
from snowflake.snowpark import Session


def flatten_market_ticks(session: Session) -> str:
    count_df = session.sql(
        "SELECT COUNT(*) AS C FROM CRYPTO_DEV.RAW.STREAM_MARKET_TICKS"
    ).collect()
    row_count = count_df[0]["C"]

    if row_count == 0:
        return "No new rows in stream"

    merge_sql = """
    MERGE INTO CRYPTO_DEV.STAGING.PRICES AS target
    USING (
        SELECT
            PAYLOAD:symbol::VARCHAR              AS SYMBOL,
            'binance'                            AS EXCHANGE,
            FETCHED_AT                           AS EVENT_TS,
            PAYLOAD:openPrice::NUMBER(28,12)     AS OPEN_PRICE,
            PAYLOAD:highPrice::NUMBER(28,12)     AS HIGH_PRICE,
            PAYLOAD:lowPrice::NUMBER(28,12)      AS LOW_PRICE,
            PAYLOAD:lastPrice::NUMBER(28,12)     AS CLOSE_PRICE,
            PAYLOAD:volume::NUMBER(28,12)        AS VOLUME,
            FETCHED_AT,
            ID                                   AS SOURCE_ROW_ID
        FROM CRYPTO_DEV.RAW.STREAM_MARKET_TICKS
        WHERE SOURCE = 'binance'

        UNION ALL

        SELECT
            PAYLOAD:product_id::VARCHAR              AS SYMBOL,
            'coinbase'                               AS EXCHANGE,
            TO_TIMESTAMP_NTZ(PAYLOAD:time::NUMBER)   AS EVENT_TS,
            PAYLOAD:open::NUMBER(28,12)              AS OPEN_PRICE,
            PAYLOAD:high::NUMBER(28,12)              AS HIGH_PRICE,
            PAYLOAD:low::NUMBER(28,12)               AS LOW_PRICE,
            PAYLOAD:close::NUMBER(28,12)             AS CLOSE_PRICE,
            PAYLOAD:volume::NUMBER(28,12)            AS VOLUME,
            FETCHED_AT,
            ID                                       AS SOURCE_ROW_ID
        FROM CRYPTO_DEV.RAW.STREAM_MARKET_TICKS
        WHERE SOURCE = 'coinbase'
    ) AS source
      ON target.SYMBOL = source.SYMBOL
     AND target.EXCHANGE = source.EXCHANGE
     AND target.EVENT_TS = source.EVENT_TS
    WHEN NOT MATCHED THEN INSERT (
        SYMBOL, EXCHANGE, EVENT_TS,
        OPEN_PRICE, HIGH_PRICE, LOW_PRICE, CLOSE_PRICE, VOLUME,
        FETCHED_AT, SOURCE_ROW_ID
    ) VALUES (
        source.SYMBOL, source.EXCHANGE, source.EVENT_TS,
        source.OPEN_PRICE, source.HIGH_PRICE, source.LOW_PRICE, source.CLOSE_PRICE, source.VOLUME,
        source.FETCHED_AT, source.SOURCE_ROW_ID
    )
    """
    result = session.sql(merge_sql).collect()
    rows_inserted = result[0]["number of rows inserted"] if result else 0
    return f"Stream had {row_count} rows; inserted {rows_inserted} new rows"
$$;
