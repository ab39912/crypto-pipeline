"""Snowpark stored procedure: flatten RAW.market_ticks_raw into STAGING.prices."""

from snowflake.snowpark import Session


def flatten_market_ticks(session: Session) -> str:
    """Read from stream, flatten VARIANT to typed columns, merge into STAGING.prices.

    Handles both Binance (24hr ticker) and Coinbase (OHLCV candle) payloads.
    Idempotent: MERGE skips rows that already exist on (symbol, exchange, event_ts).
    """
    # Count what's in the stream — if zero, exit fast
    count_df = session.sql(
        "SELECT COUNT(*) AS C FROM CRYPTO_DEV.RAW.STREAM_MARKET_TICKS"
    ).collect()
    row_count = count_df[0]["C"]

    if row_count == 0:
        return "No new rows in stream"

    # MERGE directly in SQL — flatten VARIANT inline, handle both sources via UNION ALL
    merge_sql = """
    MERGE INTO CRYPTO_DEV.STAGING.PRICES AS target
    USING (
        -- Binance shape
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

        -- Coinbase shape (epoch seconds → timestamp)
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

    return f"Stream had {row_count} rows; inserted {rows_inserted} new rows into STAGING.PRICES"
