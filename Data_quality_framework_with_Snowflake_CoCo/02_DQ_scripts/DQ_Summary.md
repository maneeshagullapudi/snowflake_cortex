# Data Quality Framework POC — Summary

## Objective

Enterprise-grade, end-to-end Data Quality Framework in Snowflake for the **BANKING_DQ_DB.RAW** schema — 5 banking tables monitored with 61 rules across 7 DQ dimensions, automated orchestration, anomaly detection, and a Streamlit dashboard.

---

## Source Tables

| Table | Rows | Purpose |
|---|---|---|
| `BRANCHES` | 11 | Bank branch reference data |
| `CUSTOMERS` | 17 | Customer master with KYC and risk |
| `ACCOUNTS` | 18 | Bank accounts with balances |
| `TRANSACTIONS` | 25 | Financial transaction records |
| `LOAN_APPLICATIONS` | 18 | Loan application processing |

---

## Architecture — Two-Layer Monitoring

| Layer | Mechanism | Purpose |
|---|---|---|
| **Native DMFs** (Step 3) | Snowflake-managed, `TRIGGER_ON_CHANGES` | Always-on continuous monitoring — runs automatically when data changes |
| **Framework Procedure** (Step 5) | `SP_RUN_DQ_FRAMEWORK` | On-demand orchestrated runs with full logging, anomaly detection, error capture |

---

## Step-by-Step Breakdown

### Step 1: Data Profiling
- Inspected all 5 tables — column types, row counts, distinct values, nulls, categorical distributions
- Identified quality issues: NULL branch names, inconsistent KYC_STATUS ("DONE"), negative balances/amounts, invalid IFSC codes, orphan foreign keys
- **Output:** `DQ_data_profiling.sql`

### Step 2: Rule Recommendations
- Designed **61 rules** across 7 DQ dimensions:
  - **Completeness** (22): NULL_COUNT + ROW_COUNT
  - **Uniqueness** (7): DUPLICATE_COUNT on PKs and unique columns
  - **Validity** (13): Format, range, accepted values
  - **Accuracy** (9): Business logic, positive amounts, date checks
  - **Consistency** (5): Cross-column, status consistency
  - **Integrity** (6): FK checks across tables
  - **Timeliness** (5): FRESHNESS (not available in account; deferred)
- Each rule classified as HIGH / MEDIUM / LOW priority
- **Output:** `DQ_Proposed_Rules.sql`

### Step 3: DMF Creation & Attachment
- Set `DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'` on all 5 tables
- Attached **59 DMF associations** using Snowflake native system DMFs:
  - `NULL_COUNT`, `DUPLICATE_COUNT`, `ROW_COUNT`, `ACCEPTED_VALUES`, `REFERENTIAL_INTEGRITY_COUNT`
- Created **8 custom DMFs** for cross-column validation:
  - `DMF_IFSC_FORMAT` — IFSC code regex validation
  - `DMF_EMAIL_FORMAT` — Email format check
  - `DMF_PHONE_FORMAT` — Phone digit count check
  - `DMF_SAVINGS_BALANCE_NON_NEG` — Savings accounts must have balance >= 0
  - `DMF_CLOSED_ZERO_BALANCE` — Closed accounts must have balance = 0
  - `DMF_AMOUNT_RANGE` — Transaction amount outlier detection (> 10M)
  - `DMF_APPROVED_HAS_AMOUNT` — Approved loans must have approved amount
  - `DMF_APPROVED_LTE_REQUESTED` — Approved amount must not exceed requested
- **Output:** `DQ_Rules.sql`

### Step 4: Framework Schema & Config
- Created `BANKING_DQ_DB.DQ_MONITORING` schema with 5 tables:

| Table | Purpose |
|---|---|
| `DQ_RULE_CONFIG` | 61 rule definitions with full executable SQL |
| `DQ_RUN_CONTROL` | Execution tracking per rule per run |
| `DQ_RULE_RESULTS` | Detailed results (actual vs expected, pass %, severity) |
| `DQ_ERROR_RECORDS` | Violation details for failed rules |
| `DQ_ANOMALY_RESULTS` | Statistical deviations from historical baseline |

- Loaded all 61 rules with **plain SQL** in RULE_SQL (no DMF function calls)
- **Output:** `DQ_Framework_Config.sql`

### Step 5: Orchestration Stored Procedure
- Created `SP_RUN_DQ_FRAMEWORK(P_TRIGGERED_BY)` — **fully dynamic**
- **Key design principle:** Every rule's `RULE_SQL` is a complete executable SELECT returning a violation count. The procedure just does `EXECUTE IMMEDIATE` — zero branching by rule type
- Uses **temp table pattern** for reliable dynamic SQL value capture in Snowflake SQL scripting
- Logs to all 4 framework tables per rule execution
- **Anomaly detection:**
  - 2+ prior runs → **2-sigma** (flags values outside mean ± 2 standard deviations)
  - 1 prior run → **50% change** threshold
  - 0 prior runs → skipped (no baseline)
- **Adding new rules = INSERT into DQ_RULE_CONFIG. Zero procedure changes needed.**
- **Output:** `DQ_Orchestration.sql`

### Step 6: Test Run
- **Run 1:** 61 processed | 44 passed | 17 failed | 0 errors | 0 anomalies
  - Correctly detected: NULL branch names, invalid KYC/transaction statuses, negative balances, orphan FKs, IFSC format violations, etc.
- **Run 2 (after adding data):** 61 processed | 32 passed | 29 failed | 0 errors | **10 anomalies**
  - Anomaly detection activated — flagged row count spikes and worsening violations

### Step 7: Streamlit Dashboard
- Created `dq-monitoring-dashboard/` with 4 tabs:

| Tab | Content |
|---|---|
| **Overview** | 7 KPI cards with deltas from previous run, table health scores, pass/fail distribution, failures by severity/type, top failing tables/columns, health trend across all runs |
| **Rule Results** | Failed rules detail, all results table, error records, failure count trend |
| **Anomalies** | All anomaly details, anomalies per run, row count trends, violation trends per table |
| **Coverage** | Rules per table, by type/criticality, all rule configs, table drill-down with recommended fixes |

- Auto-defaults to latest run — no manual RUN_ID selection needed
- Trends computed across all historical runs automatically
- **Output:** `dq-monitoring-dashboard/streamlit_app.py`

### Step 8: Cleanup Script
- Drops all objects in reverse dependency order: DMF associations → schedules → custom DMFs → procedure → tables → schema
- Preserves source database, RAW schema, and source tables
- **Not executed** — stored for reference
- **Output:** `DQ_cleanup.sql`

---

## Key Design Decisions

| Decision | Why |
|---|---|
| **Plain SQL in RULE_SQL** (not DMF calls) | Self-contained, debuggable, no dependency on DMF availability, faster execution |
| **Fully dynamic procedure** | No rule-type branching; adding new rules = just an INSERT into DQ_RULE_CONFIG |
| **Temp table pattern** for dynamic SQL | Works around Snowflake SQL scripting FETCH INTO / RESULTSET scoping limitations |
| **Errors vs Anomalies separation** | Errors catch current violations; anomalies catch statistical deviations from historical baselines |
| **INSERT...SELECT** for PARSE_JSON | Avoids Snowflake VALUES clause restriction on function expressions |
| **Two-layer monitoring** | Native DMFs for always-on monitoring; procedure for orchestrated runs with logging |

---

## Errors vs Anomalies

| Aspect | Errors (DQ_ERROR_RECORDS) | Anomalies (DQ_ANOMALY_RESULTS) |
|---|---|---|
| **Trigger** | Violation count > threshold | Statistical deviation from baseline |
| **Question** | What is wrong with my data **today**? | Is something **unusual** happening? |
| **Needs history?** | No — works on first run | Yes — requires 1+ prior runs |
| **Example** | KYC_STATUS = "DONE" is invalid | NULL_COUNT suddenly jumped from 0 to 5 |

---

## File Inventory

```
Data_quality_framework_with_Snowflake_CoCo/
├── 00_setup/                    (source data setup)
├── 01_DQ_instructions/          (framework requirements)
├── DQ_data_profiling.sql        (Step 1 — profiling queries)
├── DQ_Proposed_Rules.sql        (Step 2 — rule recommendations)
├── DQ_Rules.sql                 (Step 3 — DMF creation & attachment)
├── DQ_Framework_Config.sql      (Step 4 — schema, tables, config load)
├── DQ_Orchestration.sql         (Step 5 — stored procedure)
├── DQ_cleanup.sql               (Step 8 — teardown script)
└── DQ_Summary.md                (this file)

dq-monitoring-dashboard/
├── .streamlit/config.toml
├── pyproject.toml
├── snowflake.yml
└── streamlit_app.py             (Step 7 — Streamlit dashboard)
```

---

## How to Use

```sql
-- Run the DQ framework
CALL BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK('MANUAL');

-- Add a new rule (no procedure changes needed)
INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_CONFIG
(RULE_ID, RULE_NAME, RULE_TYPE, FREQUENCY, CRITICALITY, DB_NAME, TABLE_NM,
 COLUMN_NM, RULE_DESCRIPTION, RULE_SQL, THRESHOLD_VALUE, RULE_DIMENSION, IS_ACTIVE)
SELECT 'NEW-01', 'MY_NEW_RULE', 'CUSTOM', 'ON_DEMAND', 'HIGH',
       'BANKING_DQ_DB.RAW', 'MY_TABLE', 'MY_COLUMN',
       'Description of what this rule checks',
       'SELECT COUNT(*) FROM BANKING_DQ_DB.RAW.MY_TABLE WHERE <condition>',
       0, PARSE_JSON('["validity"]'), TRUE;

-- Schedule daily runs (optional)
CREATE OR REPLACE TASK BANKING_DQ_DB.DQ_MONITORING.TASK_DQ_DAILY
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
  CALL BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK('SCHEDULED_TASK');
```
