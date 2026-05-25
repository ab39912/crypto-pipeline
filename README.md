# Crypto Market Intelligence Pipeline

End-to-end data engineering pipeline that ingests real-time crypto market data from multiple exchanges, detects cross-exchange price arbitrage opportunities, and runs autonomously 24/7 with full CI/CD.

**Stack:** Python · AWS Lambda · S3 · EventBridge · Snowflake · Snowpark · Snowpipe · Streams · Tasks · Terraform · GitHub Actions · schemachange

---

## What it does

Every 5 minutes, two AWS Lambda functions pull live ticker and OHLCV candle data from the **Binance** and **Coinbase** public APIs. Files land in S3 partitioned by date/hour. Snowflake's Snowpipe auto-ingests via S3 event notifications, and a chain of Snowflake Tasks running Snowpark Python procs incrementally processes new rows through a medallion architecture (RAW → STAGING → ANALYTICS), surfacing cross-exchange price spreads that represent real arbitrage opportunities.

See [docs/architecture.md](docs/architecture.md) for the architecture diagram.

---

## Key engineering decisions

**Snowflake-native incremental processing.** Streams provide change data capture; Tasks orchestrate as a DAG; `WHEN SYSTEM$STREAM_HAS_DATA(...)` clauses ensure tasks only consume warehouse credits when there's actual work to do.

**Snowpark Python stored procedures.** Transformation logic runs *inside* Snowflake's compute — no data movement, no separate compute layer. Two procs: one to flatten VARIANT JSON into typed columns, one to detect cross-exchange spreads.

**Cross-cloud auth via IAM trust + external ID.** Snowflake assumes an IAM role in our AWS account to read S3; the trust policy verifies an external ID to prevent confused-deputy attacks. All provisioned via Terraform.

**Versioned migrations with schemachange.** Snowflake DDL lives in `snowflake/migrations/` as numbered SQL files. schemachange tracks applied versions in a `CHANGE_HISTORY` table.

**RSA key-pair JWT auth for CI/CD.** No passwords in GitHub Actions. The CI runner authenticates to Snowflake using a private key stored as a GitHub secret.

**Terraform with S3 remote state.** Multi-provider config (AWS + random + null) provisions everything: S3 bucket, IAM roles, Snowflake storage integration trust, Snowpipe SQS notification, Lambda functions, EventBridge schedules. State lives in S3 so CI/CD can read it.

---

## Tech stack

| Layer | Tools |
|---|---|
| Ingestion | Python 3.11, requests, boto3 |
| Compute | AWS Lambda, EventBridge cron schedules |
| Storage | AWS S3 (partitioned), Snowflake (medallion) |
| Transformation | Snowpark Python, SQL MERGE |
| Orchestration | Snowflake Tasks (chained DAG) |
| Auto-ingest | Snowpipe + S3 SQS notifications |
| Infrastructure | Terraform (AWS + null providers) |
| CI/CD | GitHub Actions, schemachange, RSA key-pair auth |
| Testing | pytest with responses HTTP mocking |
| Linting | ruff (lint + format) |

---

## Repo structure

```text
crypto-pipeline/
├── ingestion/                 # Python ingestion + Lambda handlers
│   ├── binance.py
│   ├── coinbase.py
│   ├── s3_writer.py
│   ├── lambda_handler.py
│   └── tests/                 # pytest with mocked HTTP
├── snowflake/migrations/      # schemachange versioned DDL + procs
│   └── V1.x.x__*.sql          # 12+ migrations covering DDL, streams, tasks, procs
├── infra/                     # Terraform: AWS + Snowflake handshake
│   ├── main.tf
│   ├── snowflake_iam.tf
│   ├── snowpipe_notification.tf
│   ├── lambda.tf
│   └── backend.tf
├── .github/workflows/
│   ├── ci.yml                 # lint + tests + validate on every push
│   └── deploy.yml             # terraform apply + schemachange on main
└── docs/architecture.md       # Mermaid architecture diagram
```

## Sample queries

**Recent prices across exchanges:**

```sql
SELECT exchange, symbol, close_price, event_ts
FROM CRYPTO_DEV.STAGING.PRICES
WHERE event_ts >= DATEADD('minute', -30, CURRENT_TIMESTAMP())
ORDER BY event_ts DESC;
```

**Top arbitrage opportunities by spread:**

```sql
SELECT base_symbol, price_a, price_b, spread_pct, ts_diff_seconds, detected_at
FROM CRYPTO_DEV.ANALYTICS.ARBITRAGE_OPPORTUNITIES
ORDER BY spread_pct DESC
LIMIT 20;
```

**Task DAG run history:**

```sql
SELECT NAME, STATE, SCHEDULED_TIME, RETURN_VALUE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())
))
WHERE NAME IN ('TASK_FLATTEN_MARKET_TICKS', 'TASK_DETECT_ARBITRAGE')
ORDER BY SCHEDULED_TIME DESC;
```

---

## CI/CD

Two GitHub Actions workflows:

**`ci.yml`** runs on every push and PR:
- ruff lint + format check
- pytest unit tests
- `terraform fmt -check -recursive` + `terraform validate`
- Migration filename validation

**`deploy.yml`** runs on push to main:
- Terraform apply (S3-backed state)
- schemachange applies new Snowflake migrations using RSA key-pair JWT auth
- Idempotent: already-applied migrations are skipped via `CHANGE_HISTORY`

---

## Running it locally

Prerequisites: AWS account, Snowflake account, GitHub Codespaces (or local Python 3.11 + Terraform + Snowflake CLI).

1. Clone the repo
2. Configure secrets (AWS keys, Snowflake account/user/private-key) as Codespaces secrets
3. `terraform init && terraform apply` in `infra/`
4. Apply Snowflake migrations via the deploy workflow or manually with `snow sql -f`
5. Lambdas + EventBridge schedules start firing every 5 minutes

---

## What I learned building this

- **Cross-cloud auth is the hardest part.** The Snowflake↔AWS handshake took more debugging than the data transformations themselves.
- **Streams + Tasks beat external orchestrators for Snowflake-native pipelines.** No Airflow, no Prefect. The `WHEN SYSTEM$STREAM_HAS_DATA(...)` clause means zero credits burned when there's nothing to do.
- **GitHub Codespaces makes multi-cloud dev frictionless.** No local AWS CLI / Snowflake CLI / Terraform install dance.
- **Idempotent migrations matter.** `CREATE OR REPLACE`, `IF NOT EXISTS`, and MERGE everywhere — so the same migration can be safely re-run by CI/CD.