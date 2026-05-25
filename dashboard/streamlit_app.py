"""Live Arbitrage Monitor — Streamlit dashboard for the crypto pipeline."""

from __future__ import annotations

from datetime import datetime

import pandas as pd
import plotly.express as px
import snowflake.connector
import streamlit as st

# -----------------------------------------------------------------------------
# Page config
# -----------------------------------------------------------------------------
st.set_page_config(
    page_title="Crypto Arbitrage Monitor",
    page_icon="📈",
    layout="wide",
)

# -----------------------------------------------------------------------------
# Snowflake connection (cached as a resource — one connection per session)
# -----------------------------------------------------------------------------
@st.cache_resource
def get_connection():
    """Return a Snowflake connection using credentials from Streamlit secrets."""
    return snowflake.connector.connect(
        account=st.secrets["snowflake"]["account"],
        user=st.secrets["snowflake"]["user"],
        password=st.secrets["snowflake"]["password"],
        role=st.secrets["snowflake"]["role"],
        warehouse=st.secrets["snowflake"]["warehouse"],
        database="CRYPTO_DEV",
    )


@st.cache_data(ttl=30)
def run_query(sql: str) -> pd.DataFrame:
    """Run a SQL query and return as DataFrame. Cached for 30 seconds."""
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(sql)
        cols = [c[0] for c in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=cols)


# -----------------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------------
st.title("📈 Crypto Arbitrage Monitor")
st.markdown(
    "Live cross-exchange price spreads from a real-time data pipeline "
    "(Binance + Coinbase → AWS S3 → Snowflake → this dashboard)."
)
st.caption(f"Auto-refreshes every 30 seconds. Last loaded: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC")

# -----------------------------------------------------------------------------
# Top-line KPIs
# -----------------------------------------------------------------------------
kpi_sql = """
SELECT
  (SELECT COUNT(*) FROM RAW.MARKET_TICKS_RAW) AS raw_total,
  (SELECT COUNT(*) FROM STAGING.PRICES) AS staging_total,
  (SELECT COUNT(*) FROM ANALYTICS.ARBITRAGE_OPPORTUNITIES) AS arb_total,
  (SELECT MAX(SPREAD_PCT) FROM ANALYTICS.ARBITRAGE_OPPORTUNITIES) AS max_spread,
  (SELECT COUNT(*) FROM ANALYTICS.ARBITRAGE_OPPORTUNITIES
   WHERE DETECTED_AT >= DATEADD('hour', -24, CURRENT_TIMESTAMP())) AS arb_24h
"""
kpis = run_query(kpi_sql).iloc[0]

col1, col2, col3, col4, col5 = st.columns(5)
col1.metric("Total Raw Records", f"{int(kpis['RAW_TOTAL']):,}")
col2.metric("Staging Rows", f"{int(kpis['STAGING_TOTAL']):,}")
col3.metric("Arb Opportunities (all-time)", f"{int(kpis['ARB_TOTAL']):,}")
col4.metric("Last 24h Opportunities", f"{int(kpis['ARB_24H']):,}")
col5.metric("Max Spread Seen", f"{float(kpis['MAX_SPREAD']):.3f}%" if kpis['MAX_SPREAD'] else "n/a")

# -----------------------------------------------------------------------------
# Tabs
# -----------------------------------------------------------------------------
tab_live, tab_opps, tab_trends, tab_health = st.tabs(
    ["🔴 Live Prices", "💰 Arbitrage Opportunities", "📊 Trends", "⚙️ Pipeline Health"]
)

# -----------------------------------------------------------------------------
# Tab 1 — Live Prices side-by-side
# -----------------------------------------------------------------------------
with tab_live:
    st.subheader("Latest Price per Symbol × Exchange")

    live_sql = """
    WITH ranked AS (
        SELECT
            CASE
                WHEN EXCHANGE = 'binance' THEN REGEXP_REPLACE(SYMBOL, 'USDT$', '')
                WHEN EXCHANGE = 'coinbase' THEN SPLIT_PART(SYMBOL, '-', 1)
            END AS BASE_SYMBOL,
            EXCHANGE,
            CLOSE_PRICE,
            EVENT_TS,
            ROW_NUMBER() OVER (
                PARTITION BY EXCHANGE,
                    CASE
                        WHEN EXCHANGE = 'binance' THEN REGEXP_REPLACE(SYMBOL, 'USDT$', '')
                        WHEN EXCHANGE = 'coinbase' THEN SPLIT_PART(SYMBOL, '-', 1)
                    END
                ORDER BY EVENT_TS DESC
            ) AS rn
        FROM STAGING.PRICES
    )
    SELECT BASE_SYMBOL, EXCHANGE, CLOSE_PRICE, EVENT_TS
    FROM ranked
    WHERE rn = 1
    ORDER BY BASE_SYMBOL, EXCHANGE
    """
    live = run_query(live_sql)

    if live.empty:
        st.info("Waiting for data...")
    else:
        # Pivot so we get one row per symbol with binance + coinbase as columns
        pivot = live.pivot(
            index="BASE_SYMBOL", columns="EXCHANGE", values="CLOSE_PRICE"
        ).reset_index()
        pivot.columns.name = None

        # Compute spread
        if "binance" in pivot.columns and "coinbase" in pivot.columns:
            pivot["SPREAD_%"] = (
                (pivot["binance"] - pivot["coinbase"]).abs()
                / pivot[["binance", "coinbase"]].min(axis=1)
            ) * 100
            pivot = pivot.rename(
                columns={"BASE_SYMBOL": "Symbol", "binance": "Binance", "coinbase": "Coinbase"}
            )
            st.dataframe(
                pivot.style.format(
                    {"Binance": "${:,.4f}", "Coinbase": "${:,.4f}", "SPREAD_%": "{:.4f}%"}
                ).background_gradient(subset=["SPREAD_%"], cmap="YlOrRd"),
                use_container_width=True,
                hide_index=True,
            )

# -----------------------------------------------------------------------------
# Tab 2 — Arbitrage Opportunities table
# -----------------------------------------------------------------------------
with tab_opps:
    st.subheader("Recent Arbitrage Opportunities")
    st.caption("Cross-exchange spreads where |price_a - price_b| / min(prices) × 100 ≥ 0.05% within a 60s observation window.")

    arb_sql = """
    SELECT
        BASE_SYMBOL AS "Symbol",
        EXCHANGE_A AS "Exchange A",
        PRICE_A AS "Price A",
        EXCHANGE_B AS "Exchange B",
        PRICE_B AS "Price B",
        SPREAD_PCT AS "Spread %",
        TS_DIFF_SECONDS AS "Δ Seconds",
        DETECTED_AT AS "Detected At"
    FROM ANALYTICS.ARBITRAGE_OPPORTUNITIES
    ORDER BY DETECTED_AT DESC
    LIMIT 100
    """
    arb = run_query(arb_sql)

    if arb.empty:
        st.info("No arbitrage opportunities detected yet — the pipeline needs both exchanges to have recent data.")
    else:
        st.dataframe(
            arb.style.format(
                {
                    "Price A": "${:,.4f}",
                    "Price B": "${:,.4f}",
                    "Spread %": "{:.4f}%",
                    "Δ Seconds": "{:.0f}",
                }
            ),
            use_container_width=True,
            hide_index=True,
        )

# -----------------------------------------------------------------------------
# Tab 3 — Trends (spread over time)
# -----------------------------------------------------------------------------
with tab_trends:
    st.subheader("Spread % Over Time per Symbol")

    trend_sql = """
    SELECT
        BASE_SYMBOL AS symbol,
        DETECTED_AT AS detected_at,
        SPREAD_PCT AS spread_pct
    FROM ANALYTICS.ARBITRAGE_OPPORTUNITIES
    WHERE DETECTED_AT >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
    ORDER BY DETECTED_AT
    """
    trends = run_query(trend_sql)

    if trends.empty:
        st.info("Not enough data yet for trend chart.")
    else:
        fig = px.line(
            trends,
            x="DETECTED_AT",
            y="SPREAD_PCT",
            color="SYMBOL",
            title="24h Spread % by Symbol",
            labels={"DETECTED_AT": "Time", "SPREAD_PCT": "Spread %"},
        )
        fig.update_layout(height=500)
        st.plotly_chart(fig, use_container_width=True)

    st.subheader("Price History (Last 6 Hours)")
    price_sql = """
    SELECT
        CASE
            WHEN EXCHANGE = 'binance' THEN REGEXP_REPLACE(SYMBOL, 'USDT$', '')
            WHEN EXCHANGE = 'coinbase' THEN SPLIT_PART(SYMBOL, '-', 1)
        END AS SYMBOL,
        EXCHANGE,
        EVENT_TS,
        CLOSE_PRICE
    FROM STAGING.PRICES
    WHERE EVENT_TS >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
    ORDER BY EVENT_TS
    """
    prices = run_query(price_sql)

    if not prices.empty:
        symbol_filter = st.selectbox(
            "Symbol", sorted(prices["SYMBOL"].unique()), key="price_filter"
        )
        filtered = prices[prices["SYMBOL"] == symbol_filter]
        fig = px.line(
            filtered,
            x="EVENT_TS",
            y="CLOSE_PRICE",
            color="EXCHANGE",
            title=f"{symbol_filter} price — both exchanges",
        )
        fig.update_layout(height=500)
        st.plotly_chart(fig, use_container_width=True)

# -----------------------------------------------------------------------------
# Tab 4 — Pipeline Health
# -----------------------------------------------------------------------------
with tab_health:
    st.subheader("Pipeline Activity (Last 24 Hours)")

    health_sql = """
    SELECT
        DATE_TRUNC('hour', INGESTED_AT) AS hour_bucket,
        SOURCE,
        COUNT(*) AS records_ingested
    FROM RAW.MARKET_TICKS_RAW
    WHERE INGESTED_AT >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
    GROUP BY hour_bucket, SOURCE
    ORDER BY hour_bucket
    """
    health = run_query(health_sql)

    if not health.empty:
        fig = px.bar(
            health,
            x="HOUR_BUCKET",
            y="RECORDS_INGESTED",
            color="SOURCE",
            barmode="group",
            title="Records ingested per hour by source",
        )
        fig.update_layout(height=400)
        st.plotly_chart(fig, use_container_width=True)

    st.subheader("Latest Activity per Layer")
    latency_sql = """
    SELECT 'RAW.market_ticks_raw' AS layer, COUNT(*) AS row_count, MAX(INGESTED_AT) AS latest
    FROM RAW.MARKET_TICKS_RAW
    UNION ALL
    SELECT 'STAGING.prices', COUNT(*), MAX(EVENT_TS)
    FROM STAGING.PRICES
    UNION ALL
    SELECT 'ANALYTICS.arbitrage_opportunities', COUNT(*), MAX(DETECTED_AT)
    FROM ANALYTICS.ARBITRAGE_OPPORTUNITIES
    """
    latency = run_query(latency_sql)
    st.dataframe(latency, use_container_width=True, hide_index=True)

# -----------------------------------------------------------------------------
# Footer
# -----------------------------------------------------------------------------
st.divider()
st.caption(
    "Source code: [github.com/ab39912/crypto-pipeline](https://github.com/ab39912/crypto-pipeline) · "
    "Pipeline: AWS Lambda → S3 → Snowpipe → Snowflake Streams → Snowpark Tasks"
)
