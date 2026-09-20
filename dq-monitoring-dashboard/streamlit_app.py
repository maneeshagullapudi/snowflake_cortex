import os
import pandas as pd
import streamlit as st

st.set_page_config(page_title="DQ Monitoring Dashboard", page_icon=":bar_chart:", layout="wide")

conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))


@st.cache_data(ttl=120)
def load_rule_config():
    return conn.query("SELECT * FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_CONFIG WHERE IS_ACTIVE = TRUE ORDER BY TABLE_NM, RULE_ID")

@st.cache_data(ttl=60)
def load_rule_results():
    return conn.query("SELECT * FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS ORDER BY EXECUTED_AT DESC")

@st.cache_data(ttl=60)
def load_error_records():
    return conn.query("SELECT * FROM BANKING_DQ_DB.DQ_MONITORING.DQ_ERROR_RECORDS ORDER BY CREATED_AT DESC")

@st.cache_data(ttl=60)
def load_anomaly_results():
    return conn.query("SELECT * FROM BANKING_DQ_DB.DQ_MONITORING.DQ_ANOMALY_RESULTS ORDER BY DETECTED_AT DESC")


def clear_all_caches():
    load_rule_config.clear()
    load_rule_results.clear()
    load_error_records.clear()
    load_anomaly_results.clear()


with st.spinner("Loading DQ data..."):
    df_config = load_rule_config()
    df_results = load_rule_results()
    df_errors = load_error_records()
    df_anomalies = load_anomaly_results()

# --- Header ---
st.title("Data Quality Monitoring Dashboard")
st.caption("BANKING_DQ_DB.RAW | Enterprise DQ Framework")
st.button("Refresh Data", on_click=clear_all_caches)

if df_results.empty:
    st.warning("No DQ results found. Run the framework first: `CALL BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK('MANUAL')`")
    st.stop()

# --- Derive latest run automatically ---
all_runs = sorted(df_results["RUN_ID"].dropna().unique().tolist(), reverse=True)
latest_run = all_runs[0]
df_latest = df_results[df_results["RUN_ID"] == latest_run]

# --- Sidebar filters (no RUN_ID selector — always latest) ---
with st.sidebar:
    st.header("Filters")
    all_tables = sorted(df_latest["TABLE_NAME"].dropna().unique().tolist())
    sel_tables = st.multiselect("Table", all_tables, default=all_tables)

    all_rule_types = sorted(df_latest["RULE_TYPE"].dropna().unique().tolist())
    sel_rule_types = st.multiselect("Rule Type", all_rule_types, default=all_rule_types)

    all_severities = sorted(df_latest["SEVERITY"].dropna().unique().tolist())
    sel_severities = st.multiselect("Severity", all_severities, default=all_severities)

    st.divider()
    st.caption(f"Latest Run: `{latest_run}`")
    st.caption(f"Total Runs: {len(all_runs)}")

# --- Apply filters to latest run ---
df_filtered = df_latest[
    (df_latest["TABLE_NAME"].isin(sel_tables)) &
    (df_latest["RULE_TYPE"].isin(sel_rule_types)) &
    (df_latest["SEVERITY"].isin(sel_severities))
]

# --- Compute KPIs from latest run ---
total_rules = len(df_filtered)
passed_rules = len(df_filtered[df_filtered["RESULT_STATUS"] == "PASS"])
failed_rules = len(df_filtered[df_filtered["RESULT_STATUS"] == "FAIL"])
critical_failures = len(df_filtered[(df_filtered["RESULT_STATUS"] == "FAIL") & (df_filtered["SEVERITY"] == "HIGH")])
monitored_tables = df_filtered["TABLE_NAME"].nunique()
health_score = round((passed_rules / total_rules) * 100, 1) if total_rules > 0 else 0

latest_anomalies = df_anomalies[df_anomalies["RUN_ID"] == latest_run] if not df_anomalies.empty else pd.DataFrame()
active_anomalies = len(latest_anomalies)

fail_df = df_filtered[df_filtered["RESULT_STATUS"] == "FAIL"]

# --- Compute previous run delta for KPI sparklines ---
prev_health = None
if len(all_runs) >= 2:
    prev_run = all_runs[1]
    df_prev = df_results[df_results["RUN_ID"] == prev_run]
    prev_total = len(df_prev)
    prev_pass = len(df_prev[df_prev["RESULT_STATUS"] == "PASS"])
    prev_health = round((prev_pass / prev_total) * 100, 1) if prev_total > 0 else 0

health_delta = f"{health_score - prev_health:+.1f}%" if prev_health is not None else None

# --- Tabs ---
tab_overview, tab_results, tab_anomalies, tab_coverage = st.tabs(["Overview", "Rule Results", "Anomalies", "Coverage"])

# =====================================================================
# TAB 1: OVERVIEW
# =====================================================================
with tab_overview:
    with st.container(horizontal=True):
        st.metric("Health Score", f"{health_score}%", delta=health_delta, border=True)
        st.metric("Monitored Tables", monitored_tables, border=True)
        st.metric("Total Active Rules", total_rules, border=True)
        st.metric("Passed", passed_rules, border=True)
    with st.container(horizontal=True):
        st.metric("Failed", failed_rules, border=True)
        st.metric("Critical Failures", critical_failures, border=True)
        st.metric("Active Anomalies", active_anomalies, border=True)

    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.subheader("Table-wise Health Score")
            health_by_table = df_filtered.groupby("TABLE_NAME").apply(
                lambda g: round(len(g[g["RESULT_STATUS"] == "PASS"]) / len(g) * 100, 1) if len(g) > 0 else 0
            ).reset_index()
            health_by_table.columns = ["TABLE_NAME", "HEALTH_PCT"]
            st.bar_chart(health_by_table, x="TABLE_NAME", y="HEALTH_PCT", horizontal=True)

    with col2:
        with st.container(border=True):
            st.subheader("Rule Pass/Fail Distribution")
            status_dist = df_filtered["RESULT_STATUS"].value_counts().reset_index()
            status_dist.columns = ["STATUS", "COUNT"]
            st.bar_chart(status_dist, x="STATUS", y="COUNT", color="STATUS")

    col3, col4 = st.columns(2)
    with col3:
        with st.container(border=True):
            st.subheader("Failures by Severity")
            if not fail_df.empty:
                sev_dist = fail_df["SEVERITY"].value_counts().reset_index()
                sev_dist.columns = ["SEVERITY", "COUNT"]
                st.bar_chart(sev_dist, x="SEVERITY", y="COUNT", color="SEVERITY")
            else:
                st.success("No failures detected.")

    with col4:
        with st.container(border=True):
            st.subheader("Failures by Rule Type")
            if not fail_df.empty:
                type_dist = fail_df["RULE_TYPE"].value_counts().reset_index()
                type_dist.columns = ["RULE_TYPE", "COUNT"]
                st.bar_chart(type_dist, x="RULE_TYPE", y="COUNT", color="RULE_TYPE")
            else:
                st.success("No failures detected.")

    col5, col6 = st.columns(2)
    with col5:
        with st.container(border=True):
            st.subheader("Top Failing Tables")
            if not fail_df.empty:
                top_tables = fail_df["TABLE_NAME"].value_counts().head(10).reset_index()
                top_tables.columns = ["TABLE_NAME", "FAILURES"]
                st.bar_chart(top_tables, x="TABLE_NAME", y="FAILURES", horizontal=True)
            else:
                st.success("No failures.")

    with col6:
        with st.container(border=True):
            st.subheader("Top Failing Columns")
            if not fail_df.empty:
                top_cols = fail_df[fail_df["COLUMN_NAME"].notna()]["COLUMN_NAME"].value_counts().head(10).reset_index()
                top_cols.columns = ["COLUMN_NAME", "FAILURES"]
                st.bar_chart(top_cols, x="COLUMN_NAME", y="FAILURES", horizontal=True)
            else:
                st.success("No failures.")

    # Health trend over ALL runs
    with st.container(border=True):
        st.subheader("Health Score Trend Over Runs")
        if len(all_runs) > 1:
            trend_data = []
            for run in all_runs:
                run_df = df_results[df_results["RUN_ID"] == run]
                run_total = len(run_df)
                run_pass = len(run_df[run_df["RESULT_STATUS"] == "PASS"])
                run_health = round((run_pass / run_total) * 100, 1) if run_total > 0 else 0
                run_time = run_df["EXECUTED_AT"].max() if not run_df.empty else None
                trend_data.append({"HEALTH_PCT": run_health, "EXECUTED_AT": run_time})
            trend_df = pd.DataFrame(trend_data).sort_values("EXECUTED_AT")
            st.line_chart(trend_df, x="EXECUTED_AT", y="HEALTH_PCT")
        else:
            st.info("Only 1 run available. Run the framework again to see trends.")

# =====================================================================
# TAB 2: RULE RESULTS
# =====================================================================
with tab_results:
    st.subheader("Rule Execution Results (Latest Run)")

    with st.container(horizontal=True):
        st.metric("Total Rules", total_rules, border=True)
        st.metric("Passed", passed_rules, border=True)
        st.metric("Failed", failed_rules, border=True)
        st.metric("Pass Rate", f"{health_score}%", border=True)

    with st.container(border=True):
        st.subheader("Failed Rules")
        if not fail_df.empty:
            st.dataframe(
                fail_df[["TABLE_NAME", "RULE_NAME", "SEVERITY", "ACTUAL_VALUE",
                         "FAILED_RECORD_COUNT", "TOTAL_RECORD_COUNT", "PASS_PERCENTAGE", "RULE_TYPE"]].sort_values(
                    ["SEVERITY", "TABLE_NAME"]),
                use_container_width=True, hide_index=True
            )
        else:
            st.success("All rules passed.")

    with st.container(border=True):
        st.subheader("All Rule Results")
        st.dataframe(
            df_filtered[["TABLE_NAME", "RULE_NAME", "RULE_TYPE", "SEVERITY", "RESULT_STATUS",
                         "ACTUAL_VALUE", "FAILED_RECORD_COUNT", "TOTAL_RECORD_COUNT", "PASS_PERCENTAGE"]].sort_values(
                ["RESULT_STATUS", "TABLE_NAME", "RULE_NAME"]),
            use_container_width=True, hide_index=True
        )

    with st.container(border=True):
        st.subheader("Error Records (Latest Run)")
        latest_errors = df_errors[df_errors["RUN_ID"] == latest_run] if not df_errors.empty else pd.DataFrame()
        if not latest_errors.empty:
            st.dataframe(
                latest_errors[["TABLE_NAME", "RULE_ID", "ERROR_REASON", "CREATED_AT"]],
                use_container_width=True, hide_index=True
            )
        else:
            st.info("No error records for the latest run.")

    # Failure trend per rule across ALL runs
    with st.container(border=True):
        st.subheader("Failure Count Trend Across Runs")
        if len(all_runs) > 1:
            fail_trend = df_results[df_results["RESULT_STATUS"] == "FAIL"].groupby(
                [pd.Grouper(key="EXECUTED_AT")]
            ).size().reset_index(name="FAILURES")
            if not fail_trend.empty:
                st.line_chart(fail_trend, x="EXECUTED_AT", y="FAILURES")
            else:
                st.success("No failures across any run.")
        else:
            st.info("Run the framework multiple times to see failure trends.")

# =====================================================================
# TAB 3: ANOMALIES
# =====================================================================
with tab_anomalies:
    st.subheader("Anomaly Detection Results")

    total_anomalies = len(df_anomalies) if not df_anomalies.empty else 0

    if total_anomalies > 0:
        with st.container(horizontal=True):
            st.metric("Total Anomalies (All Runs)", total_anomalies, border=True)
            st.metric("Latest Run Anomalies", active_anomalies, border=True)

        with st.container(border=True):
            st.subheader("All Anomaly Details")
            st.dataframe(
                df_anomalies[["TABLE_NAME", "METRIC_NAME", "CURRENT_VALUE", "PREVIOUS_VALUE",
                              "BASELINE_AVG", "BASELINE_STDDEV", "ANOMALY_STATUS", "ANOMALY_REASON", "DETECTED_AT"]],
                use_container_width=True, hide_index=True
            )

        with st.container(border=True):
            st.subheader("Anomalies per Run")
            anom_per_run = df_anomalies.groupby("RUN_ID").size().reset_index(name="ANOMALIES")
            st.bar_chart(anom_per_run, x="RUN_ID", y="ANOMALIES")
    else:
        st.info("No anomalies detected yet. Anomalies appear after multiple runs when metric values deviate from the historical baseline (2-sigma or >50% change).")

    # Row count trend across ALL runs
    with st.container(border=True):
        st.subheader("Row Count Trend Across Runs")
        row_count_results = df_results[df_results["RULE_NAME"].str.contains("ROW_COUNT", na=False)]
        if not row_count_results.empty and len(all_runs) > 1:
            rc_pivot = row_count_results.pivot_table(
                index="EXECUTED_AT", columns="TABLE_NAME", values="ACTUAL_VALUE", aggfunc="first"
            ).reset_index()
            y_cols = [c for c in rc_pivot.columns if c != "EXECUTED_AT"]
            st.line_chart(rc_pivot, x="EXECUTED_AT", y=y_cols)
        else:
            st.info("Run the framework multiple times to see row count trends.")

    # Freshness trend (NULL_COUNT trend as proxy for data quality over time)
    with st.container(border=True):
        st.subheader("Violation Trend per Table Across Runs")
        if len(all_runs) > 1:
            non_rc = df_results[~df_results["RULE_NAME"].str.contains("ROW_COUNT", na=False)]
            viol_trend = non_rc.groupby(["EXECUTED_AT", "TABLE_NAME"])["ACTUAL_VALUE"].sum().reset_index()
            if not viol_trend.empty:
                viol_pivot = viol_trend.pivot_table(
                    index="EXECUTED_AT", columns="TABLE_NAME", values="ACTUAL_VALUE", aggfunc="sum"
                ).reset_index()
                y_cols = [c for c in viol_pivot.columns if c != "EXECUTED_AT"]
                st.line_chart(viol_pivot, x="EXECUTED_AT", y=y_cols)
        else:
            st.info("Run the framework multiple times to see violation trends.")

# =====================================================================
# TAB 4: COVERAGE
# =====================================================================
with tab_coverage:
    st.subheader("DQ Rule Coverage")

    with st.container(border=True):
        st.subheader("Rules per Table")
        coverage = df_config.groupby("TABLE_NM").agg(
            TOTAL_RULES=("RULE_ID", "count"),
            HIGH=("CRITICALITY", lambda x: (x == "HIGH").sum()),
            MEDIUM=("CRITICALITY", lambda x: (x == "MEDIUM").sum()),
            LOW=("CRITICALITY", lambda x: (x == "LOW").sum()),
        ).reset_index()
        st.dataframe(coverage, use_container_width=True, hide_index=True)

    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.subheader("Rules by Type")
            type_cov = df_config["RULE_TYPE"].value_counts().reset_index()
            type_cov.columns = ["RULE_TYPE", "COUNT"]
            st.bar_chart(type_cov, x="RULE_TYPE", y="COUNT", color="RULE_TYPE")

    with col2:
        with st.container(border=True):
            st.subheader("Rules by Criticality")
            crit_cov = df_config["CRITICALITY"].value_counts().reset_index()
            crit_cov.columns = ["CRITICALITY", "COUNT"]
            st.bar_chart(crit_cov, x="CRITICALITY", y="COUNT", color="CRITICALITY")

    with st.container(border=True):
        st.subheader("All Rule Configurations")
        st.dataframe(
            df_config[["RULE_ID", "RULE_NAME", "RULE_TYPE", "CRITICALITY", "TABLE_NM",
                        "COLUMN_NM", "RULE_DESCRIPTION", "IS_ACTIVE"]],
            use_container_width=True, hide_index=True
        )

    # Drill-down by table
    with st.container(border=True):
        st.subheader("Table Drill-Down")
        drill_table = st.selectbox("Select a table to drill down", all_tables)
        if drill_table:
            table_results = df_filtered[df_filtered["TABLE_NAME"] == drill_table]
            table_errors = latest_errors[latest_errors["TABLE_NAME"] == drill_table] if not latest_errors.empty else pd.DataFrame()

            t_total = len(table_results)
            t_pass = len(table_results[table_results["RESULT_STATUS"] == "PASS"])
            t_health = round((t_pass / t_total) * 100, 1) if t_total > 0 else 0

            with st.container(horizontal=True):
                st.metric("Table Health", f"{t_health}%", border=True)
                st.metric("Rules", t_total, border=True)
                st.metric("Passed", t_pass, border=True)
                st.metric("Failed", t_total - t_pass, border=True)

            st.markdown("**Failed Rules**")
            table_fails = table_results[table_results["RESULT_STATUS"] == "FAIL"]
            if not table_fails.empty:
                st.dataframe(
                    table_fails[["RULE_NAME", "SEVERITY", "ACTUAL_VALUE", "TOTAL_RECORD_COUNT", "PASS_PERCENTAGE"]],
                    use_container_width=True, hide_index=True
                )
            else:
                st.success("All rules pass for this table.")

            if not table_errors.empty:
                st.markdown("**Error Records**")
                st.dataframe(table_errors[["RULE_ID", "ERROR_REASON"]], use_container_width=True, hide_index=True)

            # Table-level anomalies
            table_anomalies = df_anomalies[df_anomalies["TABLE_NAME"] == drill_table] if not df_anomalies.empty else pd.DataFrame()
            if not table_anomalies.empty:
                st.markdown("**Recent Anomalies**")
                st.dataframe(
                    table_anomalies[["METRIC_NAME", "CURRENT_VALUE", "PREVIOUS_VALUE", "ANOMALY_REASON", "DETECTED_AT"]].head(5),
                    use_container_width=True, hide_index=True
                )

            # Recommended fixes
            if not table_fails.empty:
                st.markdown("**Recommended Fixes**")
                for _, row in table_fails.iterrows():
                    rule = row["RULE_NAME"]
                    col_name = row.get("COLUMN_NAME", "N/A")
                    violations = int(row["ACTUAL_VALUE"]) if pd.notna(row["ACTUAL_VALUE"]) else 0
                    if "NULL_COUNT" in rule:
                        st.markdown(f"- **{rule}**: {violations} NULL(s) in `{col_name}`. Check upstream ETL for missing data.")
                    elif "DUPLICATE" in rule:
                        st.markdown(f"- **{rule}**: {violations} duplicate(s) on `{col_name}`. Check for duplicate inserts.")
                    elif "ACCEPTED_VALUES" in rule or "STATUS" in rule or "TYPE" in rule:
                        st.markdown(f"- **{rule}**: {violations} invalid value(s) in `{col_name}`. Standardize values upstream.")
                    elif "FK" in rule or "INTEGRITY" in rule:
                        st.markdown(f"- **{rule}**: {violations} orphaned row(s) on `{col_name}`. Ensure parent records exist.")
                    elif "FORMAT" in rule:
                        st.markdown(f"- **{rule}**: {violations} format violation(s) in `{col_name}`. Add input validation.")
                    elif "BALANCE" in rule or "AMOUNT" in rule or "POSITIVE" in rule:
                        st.markdown(f"- **{rule}**: {violations} invalid amount(s). Review business logic for negative/zero values.")
                    else:
                        st.markdown(f"- **{rule}**: {violations} violation(s) found. Check `ERROR_SAMPLE_QUERY` for details.")
