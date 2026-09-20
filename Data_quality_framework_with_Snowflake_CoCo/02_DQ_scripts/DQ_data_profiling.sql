/*=============================================================================
  DQ_data_profiling.sql
  Data Quality Framework - Step 1: Data Profiling & Analysis
  Database: BANKING_DQ_DB | Schema: RAW
  Tables: BRANCHES, CUSTOMERS, ACCOUNTS, TRANSACTIONS, LOAN_APPLICATIONS
=============================================================================*/

USE DATABASE BANKING_DQ_DB;
USE SCHEMA RAW;

-- ============================================================================
-- 1. ROW COUNTS
-- ============================================================================
SELECT 'BRANCHES' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM BRANCHES
UNION ALL SELECT 'CUSTOMERS', COUNT(*) FROM CUSTOMERS
UNION ALL SELECT 'ACCOUNTS', COUNT(*) FROM ACCOUNTS
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM TRANSACTIONS
UNION ALL SELECT 'LOAN_APPLICATIONS', COUNT(*) FROM LOAN_APPLICATIONS;

-- ============================================================================
-- 2. BRANCHES PROFILING (7 rows, 7 columns)
-- ============================================================================
-- Columns: BRANCH_ID (PK), BRANCH_NAME, CITY, STATE, IFSC_CODE, IS_ACTIVE, CREATED_AT

SELECT
  COUNT(*) AS total_rows,
  COUNT(BRANCH_ID) AS branch_id_nonnull, COUNT(DISTINCT BRANCH_ID) AS branch_id_distinct,
  COUNT(BRANCH_NAME) AS branch_name_nonnull, COUNT(DISTINCT BRANCH_NAME) AS branch_name_distinct,
  COUNT(CITY) AS city_nonnull, COUNT(DISTINCT CITY) AS city_distinct,
  COUNT(STATE) AS state_nonnull, COUNT(DISTINCT STATE) AS state_distinct,
  COUNT(IFSC_CODE) AS ifsc_nonnull, COUNT(DISTINCT IFSC_CODE) AS ifsc_distinct,
  COUNT(IS_ACTIVE) AS is_active_nonnull, COUNT(DISTINCT IS_ACTIVE) AS is_active_distinct,
  COUNT(CREATED_AT) AS created_at_nonnull, MIN(CREATED_AT) AS created_at_min, MAX(CREATED_AT) AS created_at_max
FROM BRANCHES;

-- Check for NULL branch names
SELECT * FROM BRANCHES WHERE BRANCH_NAME IS NULL;

-- ============================================================================
-- 3. CUSTOMERS PROFILING (10 rows, 10 columns)
-- ============================================================================
-- Columns: CUSTOMER_ID (PK), FIRST_NAME, LAST_NAME, EMAIL, PHONE,
--          DATE_OF_BIRTH, KYC_STATUS, RISK_CATEGORY, BRANCH_ID (FK->BRANCHES), CREATED_AT

SELECT
  COUNT(*) AS total_rows,
  COUNT(CUSTOMER_ID) AS cust_id_nonnull, COUNT(DISTINCT CUSTOMER_ID) AS cust_id_distinct,
  COUNT(EMAIL) AS email_nonnull, COUNT(DISTINCT EMAIL) AS email_distinct,
  COUNT(PHONE) AS phone_nonnull, COUNT(DISTINCT PHONE) AS phone_distinct,
  COUNT(DATE_OF_BIRTH) AS dob_nonnull,
  COUNT(KYC_STATUS) AS kyc_nonnull, COUNT(DISTINCT KYC_STATUS) AS kyc_distinct,
  COUNT(RISK_CATEGORY) AS risk_nonnull, COUNT(DISTINCT RISK_CATEGORY) AS risk_distinct,
  COUNT(BRANCH_ID) AS branch_id_nonnull, COUNT(DISTINCT BRANCH_ID) AS branch_id_distinct,
  MIN(CREATED_AT) AS created_at_min, MAX(CREATED_AT) AS created_at_max
FROM CUSTOMERS;

-- Distinct KYC_STATUS values (found: VERIFIED, PENDING, DONE — 'DONE' may be inconsistent)
SELECT KYC_STATUS, COUNT(*) AS cnt FROM CUSTOMERS GROUP BY KYC_STATUS;

-- Distinct RISK_CATEGORY values
SELECT RISK_CATEGORY, COUNT(*) AS cnt FROM CUSTOMERS GROUP BY RISK_CATEGORY;

-- ============================================================================
-- 4. ACCOUNTS PROFILING (10 rows, 9 columns)
-- ============================================================================
-- Columns: ACCOUNT_ID (PK), CUSTOMER_ID (FK->CUSTOMERS), BRANCH_ID (FK->BRANCHES),
--          ACCOUNT_TYPE, ACCOUNT_STATUS, OPEN_DATE, BALANCE, CURRENCY, CREATED_AT

SELECT
  COUNT(*) AS total_rows,
  COUNT(ACCOUNT_ID) AS acc_id_nonnull, COUNT(DISTINCT ACCOUNT_ID) AS acc_id_distinct,
  COUNT(CUSTOMER_ID) AS cust_id_nonnull, COUNT(DISTINCT CUSTOMER_ID) AS cust_id_distinct,
  COUNT(BRANCH_ID) AS branch_id_nonnull, COUNT(DISTINCT BRANCH_ID) AS branch_id_distinct,
  COUNT(ACCOUNT_TYPE) AS acc_type_nonnull, COUNT(DISTINCT ACCOUNT_TYPE) AS acc_type_distinct,
  COUNT(ACCOUNT_STATUS) AS acc_status_nonnull, COUNT(DISTINCT ACCOUNT_STATUS) AS acc_status_distinct,
  COUNT(OPEN_DATE) AS open_date_nonnull,
  COUNT(BALANCE) AS balance_nonnull, MIN(BALANCE) AS balance_min, MAX(BALANCE) AS balance_max, AVG(BALANCE) AS balance_avg,
  COUNT(CURRENCY) AS currency_nonnull, COUNT(DISTINCT CURRENCY) AS currency_distinct
FROM ACCOUNTS;

-- Negative balance check
SELECT * FROM ACCOUNTS WHERE BALANCE < 0;

-- Distinct ACCOUNT_TYPE and ACCOUNT_STATUS
SELECT ACCOUNT_TYPE, COUNT(*) AS cnt FROM ACCOUNTS GROUP BY ACCOUNT_TYPE;
SELECT ACCOUNT_STATUS, COUNT(*) AS cnt FROM ACCOUNTS GROUP BY ACCOUNT_STATUS;

-- ============================================================================
-- 5. TRANSACTIONS PROFILING (12 rows, 9 columns)
-- ============================================================================
-- Columns: TRANSACTION_ID (PK), ACCOUNT_ID (FK->ACCOUNTS), TRANSACTION_DATE,
--          TRANSACTION_TYPE, AMOUNT, CHANNEL, MERCHANT_CATEGORY, TRANSACTION_STATUS, CREATED_AT

SELECT
  COUNT(*) AS total_rows,
  COUNT(TRANSACTION_ID) AS txn_id_nonnull, COUNT(DISTINCT TRANSACTION_ID) AS txn_id_distinct,
  COUNT(ACCOUNT_ID) AS acc_id_nonnull, COUNT(DISTINCT ACCOUNT_ID) AS acc_id_distinct,
  COUNT(TRANSACTION_DATE) AS txn_date_nonnull,
  MIN(TRANSACTION_DATE) AS txn_date_min, MAX(TRANSACTION_DATE) AS txn_date_max,
  COUNT(TRANSACTION_TYPE) AS txn_type_nonnull, COUNT(DISTINCT TRANSACTION_TYPE) AS txn_type_distinct,
  COUNT(AMOUNT) AS amount_nonnull, MIN(AMOUNT) AS amount_min, MAX(AMOUNT) AS amount_max, AVG(AMOUNT) AS amount_avg,
  COUNT(CHANNEL) AS channel_nonnull, COUNT(DISTINCT CHANNEL) AS channel_distinct,
  COUNT(MERCHANT_CATEGORY) AS merch_nonnull, COUNT(DISTINCT MERCHANT_CATEGORY) AS merch_distinct,
  COUNT(TRANSACTION_STATUS) AS txn_status_nonnull, COUNT(DISTINCT TRANSACTION_STATUS) AS txn_status_distinct
FROM TRANSACTIONS;

-- Negative/zero amount check
SELECT * FROM TRANSACTIONS WHERE AMOUNT <= 0;

-- Inconsistent TRANSACTION_STATUS ('DONE' vs 'SUCCESS')
SELECT TRANSACTION_STATUS, COUNT(*) AS cnt FROM TRANSACTIONS GROUP BY TRANSACTION_STATUS;

-- ============================================================================
-- 6. LOAN_APPLICATIONS PROFILING (10 rows, 10 columns)
-- ============================================================================
-- Columns: APPLICATION_ID (PK), CUSTOMER_ID (FK->CUSTOMERS), BRANCH_ID (FK->BRANCHES),
--          LOAN_TYPE, APPLICATION_DATE, REQUESTED_AMOUNT, APPROVED_AMOUNT,
--          APPLICATION_STATUS, CREDIT_SCORE, CREATED_AT

SELECT
  COUNT(*) AS total_rows,
  COUNT(APPLICATION_ID) AS app_id_nonnull, COUNT(DISTINCT APPLICATION_ID) AS app_id_distinct,
  COUNT(CUSTOMER_ID) AS cust_id_nonnull, COUNT(DISTINCT CUSTOMER_ID) AS cust_id_distinct,
  COUNT(BRANCH_ID) AS branch_id_nonnull, COUNT(DISTINCT BRANCH_ID) AS branch_id_distinct,
  COUNT(LOAN_TYPE) AS loan_type_nonnull, COUNT(DISTINCT LOAN_TYPE) AS loan_type_distinct,
  COUNT(APPLICATION_DATE) AS app_date_nonnull,
  COUNT(REQUESTED_AMOUNT) AS req_amt_nonnull, MIN(REQUESTED_AMOUNT) AS req_amt_min, MAX(REQUESTED_AMOUNT) AS req_amt_max,
  COUNT(APPROVED_AMOUNT) AS appr_amt_nonnull, MIN(APPROVED_AMOUNT) AS appr_amt_min, MAX(APPROVED_AMOUNT) AS appr_amt_max,
  COUNT(APPLICATION_STATUS) AS app_status_nonnull, COUNT(DISTINCT APPLICATION_STATUS) AS app_status_distinct,
  COUNT(CREDIT_SCORE) AS credit_score_nonnull, MIN(CREDIT_SCORE) AS credit_min, MAX(CREDIT_SCORE) AS credit_max
FROM LOAN_APPLICATIONS;

-- Approved amount NULL for non-approved
SELECT APPLICATION_STATUS, COUNT(APPROVED_AMOUNT) AS approved_amt_filled, COUNT(*) AS total
FROM LOAN_APPLICATIONS GROUP BY APPLICATION_STATUS;

-- Zero requested amount check
SELECT * FROM LOAN_APPLICATIONS WHERE REQUESTED_AMOUNT <= 0;

-- Credit score range check
SELECT * FROM LOAN_APPLICATIONS WHERE CREDIT_SCORE < 300 OR CREDIT_SCORE > 900;

-- ============================================================================
-- 7. REFERENTIAL INTEGRITY CHECKS
-- ============================================================================
-- Orphan CUSTOMERS.BRANCH_ID not in BRANCHES
SELECT C.CUSTOMER_ID, C.BRANCH_ID
FROM CUSTOMERS C
LEFT JOIN BRANCHES B ON C.BRANCH_ID = B.BRANCH_ID
WHERE B.BRANCH_ID IS NULL;

-- Orphan ACCOUNTS.CUSTOMER_ID not in CUSTOMERS
SELECT A.ACCOUNT_ID, A.CUSTOMER_ID
FROM ACCOUNTS A
LEFT JOIN CUSTOMERS C ON A.CUSTOMER_ID = C.CUSTOMER_ID
WHERE C.CUSTOMER_ID IS NULL;

-- Orphan ACCOUNTS.BRANCH_ID not in BRANCHES
SELECT A.ACCOUNT_ID, A.BRANCH_ID
FROM ACCOUNTS A
LEFT JOIN BRANCHES B ON A.BRANCH_ID = B.BRANCH_ID
WHERE B.BRANCH_ID IS NULL;

-- Orphan TRANSACTIONS.ACCOUNT_ID not in ACCOUNTS
SELECT T.TRANSACTION_ID, T.ACCOUNT_ID
FROM TRANSACTIONS T
LEFT JOIN ACCOUNTS A ON T.ACCOUNT_ID = A.ACCOUNT_ID
WHERE A.ACCOUNT_ID IS NULL;

-- Orphan LOAN_APPLICATIONS.CUSTOMER_ID not in CUSTOMERS
SELECT L.APPLICATION_ID, L.CUSTOMER_ID
FROM LOAN_APPLICATIONS L
LEFT JOIN CUSTOMERS C ON L.CUSTOMER_ID = C.CUSTOMER_ID
WHERE C.CUSTOMER_ID IS NULL;

-- Orphan LOAN_APPLICATIONS.BRANCH_ID not in BRANCHES
SELECT L.APPLICATION_ID, L.BRANCH_ID
FROM LOAN_APPLICATIONS L
LEFT JOIN BRANCHES B ON L.BRANCH_ID = B.BRANCH_ID
WHERE B.BRANCH_ID IS NULL;

/*=============================================================================
  END OF PROFILING
=============================================================================*/
