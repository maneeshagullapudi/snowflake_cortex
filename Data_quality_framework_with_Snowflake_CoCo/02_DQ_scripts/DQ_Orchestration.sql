/*=============================================================================
  DQ_Orchestration.sql
  Data Quality Framework - Step 5: Orchestration Stored Procedure
  Database: BANKING_DQ_DB | Schema: DQ_MONITORING
  
  Procedure: SP_RUN_DQ_FRAMEWORK
  - FULLY DYNAMIC: Reads RULE_SQL from DQ_RULE_CONFIG and executes directly
  - Uses temp table pattern for reliable dynamic SQL value capture
  - Logs to: DQ_RUN_CONTROL, DQ_RULE_RESULTS, DQ_ERROR_RECORDS, DQ_ANOMALY_RESULTS
  - Uses RESULTSET and $$ approach per Snowflake SQL scripting

  KEY PATTERN: Temp table for dynamic SQL
    - EXECUTE IMMEDIATE 'INSERT INTO _DQ_TEMP(VAL) <dynamic_query>'
    - v_variable := (SELECT VAL FROM _DQ_TEMP)
    - This avoids FETCH INTO scoping issues in Snowflake SQL scripting
=============================================================================*/

CREATE OR REPLACE PROCEDURE BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK(
    P_TRIGGERED_BY VARCHAR DEFAULT 'MANUAL'
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_run_id VARCHAR; v_rule_id VARCHAR; v_rule_name VARCHAR; v_rule_type VARCHAR;
    v_criticality VARCHAR; v_db_name VARCHAR; v_table_nm VARCHAR; v_column_nm VARCHAR;
    v_rule_sql VARCHAR; v_threshold NUMBER; v_rule_desc VARCHAR;
    v_actual_value NUMBER DEFAULT 0; v_total_rows NUMBER DEFAULT 0;
    v_failed_count NUMBER DEFAULT 0; v_pass_pct NUMBER DEFAULT 0;
    v_result_status VARCHAR; v_result_id VARCHAR; v_error_id VARCHAR;
    v_run_start TIMESTAMP_NTZ; v_run_end TIMESTAMP_NTZ;
    v_error_msg VARCHAR DEFAULT '';
    v_rules_processed NUMBER DEFAULT 0; v_rules_passed NUMBER DEFAULT 0;
    v_rules_failed NUMBER DEFAULT 0; v_rules_errored NUMBER DEFAULT 0;
    v_anomalies_detected NUMBER DEFAULT 0;
    v_prev_value NUMBER; v_baseline_avg NUMBER; v_baseline_std NUMBER;
    v_anomaly_id VARCHAR; v_anomaly_reason VARCHAR; v_prev_count NUMBER DEFAULT 0;
    cur CURSOR FOR
        SELECT RULE_ID, RULE_NAME, RULE_TYPE, CRITICALITY, DB_NAME, TABLE_NM,
               COLUMN_NM, RULE_SQL, THRESHOLD_VALUE, RULE_DESCRIPTION
        FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_CONFIG
        WHERE IS_ACTIVE = TRUE ORDER BY TABLE_NM, RULE_ID;
BEGIN
    v_run_id := 'RUN_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS') || '_' || ABS(MOD(RANDOM(), 9000) + 1000)::VARCHAR;
    CREATE OR REPLACE TEMPORARY TABLE BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP (VAL NUMBER(38,4));

    FOR rec IN cur DO
        v_rule_id := rec.RULE_ID; v_rule_name := rec.RULE_NAME; v_rule_type := rec.RULE_TYPE;
        v_criticality := rec.CRITICALITY; v_db_name := rec.DB_NAME; v_table_nm := rec.TABLE_NM;
        v_column_nm := rec.COLUMN_NM; v_rule_sql := rec.RULE_SQL;
        v_threshold := rec.THRESHOLD_VALUE; v_rule_desc := rec.RULE_DESCRIPTION;
        v_run_start := CURRENT_TIMESTAMP(); v_error_msg := '';
        v_actual_value := 0; v_total_rows := 0; v_failed_count := 0;

        BEGIN
            -- Step 1: Get total row count via temp table
            TRUNCATE TABLE BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP;
            EXECUTE IMMEDIATE 'INSERT INTO BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP(VAL) SELECT COUNT(*) FROM ' || :v_db_name || '.' || :v_table_nm;
            v_total_rows := (SELECT VAL FROM BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP);

            -- Step 2: Execute RULE_SQL via temp table
            TRUNCATE TABLE BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP;
            EXECUTE IMMEDIATE 'INSERT INTO BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP(VAL) ' || :v_rule_sql;
            v_actual_value := (SELECT VAL FROM BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP);

            -- Step 3: Determine pass/fail
            IF (v_rule_name LIKE '%ROW_COUNT%') THEN
                v_failed_count := 0; v_total_rows := v_actual_value;
                v_pass_pct := 100; v_result_status := 'PASS';
            ELSE
                v_failed_count := v_actual_value;
                IF (v_total_rows > 0) THEN
                    v_pass_pct := ROUND(((v_total_rows - v_failed_count) / v_total_rows) * 100, 2);
                ELSE v_pass_pct := 100; END IF;
                IF (v_failed_count > v_threshold) THEN v_result_status := 'FAIL';
                ELSE v_result_status := 'PASS'; END IF;
            END IF;
            IF (v_result_status = 'PASS') THEN v_rules_passed := v_rules_passed + 1;
            ELSE v_rules_failed := v_rules_failed + 1; END IF;
            v_run_end := CURRENT_TIMESTAMP();

            -- Step 4: Log to DQ_RUN_CONTROL
            INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL
                (RUN_ID, RULE_ID, RUN_START_TIME, RUN_END_TIME, RULE_EXEC_RESULT, RULE_OUTPUT_VALUE, RUN_STATUS, TRIGGERED_BY)
            VALUES (:v_run_id, :v_rule_id, :v_run_start, :v_run_end, :v_result_status, :v_actual_value, 'COMPLETED', :P_TRIGGERED_BY);

            -- Step 5: Log to DQ_RULE_RESULTS
            v_result_id := :v_rule_id || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');
            INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS
                (RESULT_ID, RUN_ID, RULE_ID, DB_NAME, TABLE_NAME, COLUMN_NAME, RULE_NAME, RULE_TYPE,
                 EXPECTED_VALUE, ACTUAL_VALUE, FAILED_RECORD_COUNT, TOTAL_RECORD_COUNT,
                 PASS_PERCENTAGE, RESULT_STATUS, SEVERITY, ERROR_SAMPLE_QUERY)
            VALUES (:v_result_id, :v_run_id, :v_rule_id, :v_db_name, :v_table_nm, :v_column_nm,
                    :v_rule_name, :v_rule_type, :v_threshold, :v_actual_value, :v_failed_count,
                    :v_total_rows, :v_pass_pct, :v_result_status, :v_criticality, :v_rule_sql);

            -- Step 6: Log error records for failed rules (INSERT ... SELECT to avoid PARSE_JSON in VALUES)
            IF (v_result_status = 'FAIL') THEN
                v_error_id := 'ERR_' || :v_rule_id || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');
                INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_ERROR_RECORDS
                    (ERROR_ID, RUN_ID, RULE_ID, DB_NAME, TABLE_NAME, ERROR_RECORD_VARIANT, ERROR_REASON)
                SELECT :v_error_id, :v_run_id, :v_rule_id, :v_db_name, :v_table_nm,
                       PARSE_JSON('{"failed_count":' || :v_failed_count || ',"total_rows":' || :v_total_rows || '}'),
                       :v_rule_desc || ' - Found ' || :v_failed_count || ' violations';
            END IF;

            -- Step 7: ANOMALY DETECTION
            BEGIN
                TRUNCATE TABLE BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP;
                EXECUTE IMMEDIATE 'INSERT INTO BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP(VAL) SELECT COUNT(*) FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS WHERE RULE_ID = ''' || :v_rule_id || ''' AND RUN_ID != ''' || :v_run_id || '''';
                v_prev_count := (SELECT VAL FROM BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP);

                IF (v_prev_count >= 2) THEN
                    -- 2-SIGMA: enough history for statistical baseline
                    v_prev_value := (SELECT ACTUAL_VALUE FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS WHERE RULE_ID = :v_rule_id AND RUN_ID != :v_run_id ORDER BY EXECUTED_AT DESC LIMIT 1);
                    v_baseline_avg := (SELECT AVG(ACTUAL_VALUE) FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS WHERE RULE_ID = :v_rule_id AND RUN_ID != :v_run_id);
                    v_baseline_std := (SELECT STDDEV(ACTUAL_VALUE) FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS WHERE RULE_ID = :v_rule_id AND RUN_ID != :v_run_id);
                    IF (v_baseline_std IS NOT NULL AND v_baseline_std > 0 AND ABS(v_actual_value - v_baseline_avg) > 2 * v_baseline_std) THEN
                        v_anomaly_reason := :v_rule_name || ': value=' || :v_actual_value || ' (avg=' || ROUND(:v_baseline_avg,2) || ', std=' || ROUND(:v_baseline_std,2) || '). Exceeds 2-sigma.';
                        v_anomaly_id := 'ANM_' || :v_rule_id || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');
                        INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_ANOMALY_RESULTS
                            (ANOMALY_ID, RUN_ID, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, METRIC_NAME,
                             CURRENT_VALUE, PREVIOUS_VALUE, BASELINE_AVG, BASELINE_STDDEV, ANOMALY_STATUS, ANOMALY_REASON)
                        SELECT :v_anomaly_id, :v_run_id, 'BANKING_DQ_DB', 'RAW', :v_table_nm, :v_rule_name,
                               :v_actual_value, :v_prev_value, :v_baseline_avg, :v_baseline_std, 'ANOMALY_DETECTED', :v_anomaly_reason;
                        v_anomalies_detected := v_anomalies_detected + 1;
                    END IF;
                ELSEIF (v_prev_count = 1) THEN
                    -- PERCENTAGE: only 1 previous run, flag >50% change
                    v_prev_value := (SELECT ACTUAL_VALUE FROM BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_RESULTS WHERE RULE_ID = :v_rule_id AND RUN_ID != :v_run_id ORDER BY EXECUTED_AT DESC LIMIT 1);
                    IF (v_prev_value IS NOT NULL AND v_prev_value > 0 AND ABS(v_actual_value - v_prev_value) / v_prev_value > 0.5) THEN
                        v_anomaly_reason := :v_rule_name || ': changed from ' || :v_prev_value || ' to ' || :v_actual_value || ' (>50% change)';
                        v_anomaly_id := 'ANM_' || :v_rule_id || '_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');
                        INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_ANOMALY_RESULTS
                            (ANOMALY_ID, RUN_ID, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, METRIC_NAME,
                             CURRENT_VALUE, PREVIOUS_VALUE, BASELINE_AVG, BASELINE_STDDEV, ANOMALY_STATUS, ANOMALY_REASON)
                        SELECT :v_anomaly_id, :v_run_id, 'BANKING_DQ_DB', 'RAW', :v_table_nm, :v_rule_name,
                               :v_actual_value, :v_prev_value, :v_prev_value, NULL, 'ANOMALY_DETECTED', :v_anomaly_reason;
                        v_anomalies_detected := v_anomalies_detected + 1;
                    END IF;
                END IF;
            EXCEPTION WHEN OTHER THEN NULL;
            END;
            v_rules_processed := v_rules_processed + 1;
        EXCEPTION
            WHEN OTHER THEN
                v_error_msg := SQLERRM; v_run_end := CURRENT_TIMESTAMP();
                v_rules_errored := v_rules_errored + 1; v_rules_processed := v_rules_processed + 1;
                INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RUN_CONTROL
                    (RUN_ID, RULE_ID, RUN_START_TIME, RUN_END_TIME, RULE_EXEC_RESULT, RULE_OUTPUT_VALUE, RUN_STATUS, TRIGGERED_BY, ERROR_MESSAGE)
                VALUES (:v_run_id, :v_rule_id, :v_run_start, :v_run_end, 'ERROR', 0, 'FAILED', :P_TRIGGERED_BY, :v_error_msg);
        END;
    END FOR;
    DROP TABLE IF EXISTS BANKING_DQ_DB.DQ_MONITORING._DQ_TEMP;
    RETURN 'DQ Framework Run Complete | Run ID: ' || v_run_id || ' | Rules Processed: ' || v_rules_processed ||
           ' | Passed: ' || v_rules_passed || ' | Failed: ' || v_rules_failed ||
           ' | Errors: ' || v_rules_errored || ' | Anomalies: ' || v_anomalies_detected;
END;
$$;

-- ============================================================================
-- HOW TO ADD NEW RULES (no procedure changes needed)
-- ============================================================================
-- INSERT INTO BANKING_DQ_DB.DQ_MONITORING.DQ_RULE_CONFIG
-- (RULE_ID, RULE_NAME, RULE_TYPE, FREQUENCY, CRITICALITY, DB_NAME, TABLE_NM,
--  COLUMN_NM, RULE_DESCRIPTION, RULE_SQL, THRESHOLD_VALUE, RULE_DIMENSION, IS_ACTIVE)
-- SELECT 'NEW-01', 'MY_NEW_RULE', 'CUSTOM', 'ON_DEMAND', 'HIGH',
--        'BANKING_DQ_DB.RAW', 'MY_TABLE', 'MY_COLUMN',
--        'Description of what this rule checks',
--        'SELECT COUNT(*) FROM BANKING_DQ_DB.RAW.MY_TABLE WHERE <condition>',
--        0, PARSE_JSON('["validity"]'), TRUE;

-- ============================================================================
-- USAGE
-- ============================================================================
-- CALL BANKING_DQ_DB.DQ_MONITORING.SP_RUN_DQ_FRAMEWORK('MANUAL');

/*=============================================================================
  END OF DQ ORCHESTRATION
=============================================================================*/
