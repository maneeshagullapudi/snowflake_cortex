/*=============================================================================
  DQ_Proposed_Rules.sql
  Data Quality Framework - Step 2: Recommended Data Quality Rules
  Database: BANKING_DQ_DB | Schema: RAW
  
  Rule Types:
    - SYSTEM DMF  : Built-in Snowflake Data Metric Functions
    - CUSTOM DMF  : User-defined Data Metric Functions
    - BUSINESS    : Business logic validation rules
  
  DQ Dimensions:
    - COMPLETENESS : Missing/NULL values
    - UNIQUENESS   : Duplicate detection
    - VALIDITY     : Format & range checks
    - CONSISTENCY  : Cross-column & cross-table consistency
    - ACCURACY     : Business logic accuracy
    - TIMELINESS   : Freshness & recency
    - INTEGRITY    : Referential integrity (FK checks)
=============================================================================*/

/*-----------------------------------------------------------------------------
  TABLE 1: BRANCHES
  Purpose: Reference/dimension table for bank branch locations
  Rows: 7 | Columns: 7
  Issues Found: 1 NULL BRANCH_NAME, IS_ACTIVE has only 1 distinct value
-----------------------------------------------------------------------------*/

-- ==========================================================================
-- BRANCHES — TECHNICAL RULES
-- ==========================================================================
-- RULE_ID | RULE_NAME                         | TYPE        | DIMENSION      | PRIORITY | DESCRIPTION
-- BR-T01  | BRANCHES_NULL_COUNT_BRANCH_ID      | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on BRANCH_ID (PK must never be NULL)
-- BR-T02  | BRANCHES_DUPLICATE_COUNT_BRANCH_ID  | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on BRANCH_ID (PK must be unique)
-- BR-T03  | BRANCHES_NULL_COUNT_BRANCH_NAME     | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on BRANCH_NAME (1 NULL detected)
-- BR-T04  | BRANCHES_NULL_COUNT_IFSC_CODE       | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | NULL_COUNT on IFSC_CODE
-- BR-T05  | BRANCHES_ROW_COUNT                  | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | ROW_COUNT — volume monitoring
-- BR-T06  | BRANCHES_FRESHNESS                  | SYSTEM DMF  | TIMELINESS     | LOW      | FRESHNESS — track staleness

-- ==========================================================================
-- BRANCHES — BUSINESS RULES
-- ==========================================================================
-- BR-B01  | BRANCHES_IFSC_FORMAT               | CUSTOM DMF  | VALIDITY       | HIGH     | IFSC_CODE must match pattern: 4 alpha + 0 + 6 alphanum (e.g., SBIN0001234)
-- BR-B02  | BRANCHES_VALID_IS_ACTIVE            | CUSTOM DMF  | VALIDITY       | MEDIUM   | IS_ACTIVE must be TRUE or FALSE (not NULL)
-- BR-B03  | BRANCHES_UNIQUE_IFSC                | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on IFSC_CODE — each branch must have unique IFSC
-- BR-B04  | BRANCHES_STATE_NOT_EMPTY            | CUSTOM DMF  | COMPLETENESS   | MEDIUM   | STATE must not be NULL or empty string


/*-----------------------------------------------------------------------------
  TABLE 2: CUSTOMERS
  Purpose: Customer master with KYC and risk classification
  Rows: 10 | Columns: 10
  Issues Found: Inconsistent KYC_STATUS ('DONE' should be 'VERIFIED')
-----------------------------------------------------------------------------*/

-- ==========================================================================
-- CUSTOMERS — TECHNICAL RULES
-- ==========================================================================
-- CU-T01  | CUSTOMERS_NULL_COUNT_CUSTOMER_ID    | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on CUSTOMER_ID (PK)
-- CU-T02  | CUSTOMERS_DUPLICATE_COUNT_CUST_ID   | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on CUSTOMER_ID (PK)
-- CU-T03  | CUSTOMERS_NULL_COUNT_EMAIL           | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on EMAIL
-- CU-T04  | CUSTOMERS_DUPLICATE_COUNT_EMAIL      | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on EMAIL (must be unique)
-- CU-T05  | CUSTOMERS_NULL_COUNT_PHONE           | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | NULL_COUNT on PHONE
-- CU-T06  | CUSTOMERS_NULL_COUNT_DOB             | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | NULL_COUNT on DATE_OF_BIRTH
-- CU-T07  | CUSTOMERS_ROW_COUNT                  | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | ROW_COUNT — volume monitoring
-- CU-T08  | CUSTOMERS_FRESHNESS                  | SYSTEM DMF  | TIMELINESS     | MEDIUM   | FRESHNESS — track staleness

-- ==========================================================================
-- CUSTOMERS — BUSINESS RULES
-- ==========================================================================
-- CU-B01  | CUSTOMERS_EMAIL_FORMAT               | CUSTOM DMF  | VALIDITY       | HIGH     | EMAIL must contain '@' and '.' (basic format)
-- CU-B02  | CUSTOMERS_KYC_ACCEPTED_VALUES        | CUSTOM DMF  | CONSISTENCY    | HIGH     | KYC_STATUS must be in ('VERIFIED','PENDING','REJECTED') — 'DONE' is invalid
-- CU-B03  | CUSTOMERS_RISK_ACCEPTED_VALUES        | CUSTOM DMF  | VALIDITY       | HIGH     | RISK_CATEGORY must be in ('LOW','MEDIUM','HIGH')
-- CU-B04  | CUSTOMERS_DOB_RANGE                   | CUSTOM DMF  | ACCURACY       | MEDIUM   | DATE_OF_BIRTH must be between 18 and 120 years ago
-- CU-B05  | CUSTOMERS_BRANCH_FK                   | SYSTEM DMF  | INTEGRITY      | HIGH     | REFERENTIAL_INTEGRITY_COUNT: BRANCH_ID must exist in BRANCHES
-- CU-B06  | CUSTOMERS_PHONE_FORMAT                | CUSTOM DMF  | VALIDITY       | MEDIUM   | PHONE must be 10+ digits


/*-----------------------------------------------------------------------------
  TABLE 3: ACCOUNTS
  Purpose: Customer bank accounts with balance tracking
  Rows: 10 | Columns: 9
  Issues Found: Negative balance (-1500), mixed currencies
-----------------------------------------------------------------------------*/

-- ==========================================================================
-- ACCOUNTS — TECHNICAL RULES
-- ==========================================================================
-- AC-T01  | ACCOUNTS_NULL_COUNT_ACCOUNT_ID       | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on ACCOUNT_ID (PK)
-- AC-T02  | ACCOUNTS_DUPLICATE_COUNT_ACCOUNT_ID   | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on ACCOUNT_ID (PK)
-- AC-T03  | ACCOUNTS_NULL_COUNT_CUSTOMER_ID       | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on CUSTOMER_ID (FK)
-- AC-T04  | ACCOUNTS_NULL_COUNT_BALANCE           | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on BALANCE
-- AC-T05  | ACCOUNTS_ROW_COUNT                    | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | ROW_COUNT — volume monitoring
-- AC-T06  | ACCOUNTS_FRESHNESS                    | SYSTEM DMF  | TIMELINESS     | MEDIUM   | FRESHNESS — track staleness

-- ==========================================================================
-- ACCOUNTS — BUSINESS RULES
-- ==========================================================================
-- AC-B01  | ACCOUNTS_TYPE_ACCEPTED_VALUES         | CUSTOM DMF  | VALIDITY       | HIGH     | ACCOUNT_TYPE must be in ('SAVINGS','CURRENT','LOAN','FD','RD')
-- AC-B02  | ACCOUNTS_STATUS_ACCEPTED_VALUES       | CUSTOM DMF  | VALIDITY       | HIGH     | ACCOUNT_STATUS must be in ('ACTIVE','CLOSED','DORMANT','FROZEN')
-- AC-B03  | ACCOUNTS_SAVINGS_BALANCE_NON_NEG      | CUSTOM DMF  | ACCURACY       | HIGH     | SAVINGS accounts must have BALANCE >= 0
-- AC-B04  | ACCOUNTS_CURRENCY_ACCEPTED_VALUES     | CUSTOM DMF  | VALIDITY       | MEDIUM   | CURRENCY must be in ('INR','USD','EUR','GBP')
-- AC-B05  | ACCOUNTS_CUSTOMER_FK                  | SYSTEM DMF  | INTEGRITY      | HIGH     | REFERENTIAL_INTEGRITY_COUNT: CUSTOMER_ID must exist in CUSTOMERS
-- AC-B06  | ACCOUNTS_BRANCH_FK                    | SYSTEM DMF  | INTEGRITY      | HIGH     | REFERENTIAL_INTEGRITY_COUNT: BRANCH_ID must exist in BRANCHES
-- AC-B07  | ACCOUNTS_CLOSED_ZERO_BALANCE          | CUSTOM DMF  | CONSISTENCY    | MEDIUM   | CLOSED accounts should have BALANCE = 0


/*-----------------------------------------------------------------------------
  TABLE 4: TRANSACTIONS
  Purpose: Financial transaction records
  Rows: 12 | Columns: 9
  Issues Found: Negative amount (-50), inconsistent status 'DONE'
-----------------------------------------------------------------------------*/

-- ==========================================================================
-- TRANSACTIONS — TECHNICAL RULES
-- ==========================================================================
-- TX-T01  | TXNS_NULL_COUNT_TRANSACTION_ID        | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on TRANSACTION_ID (PK)
-- TX-T02  | TXNS_DUPLICATE_COUNT_TRANSACTION_ID    | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on TRANSACTION_ID (PK)
-- TX-T03  | TXNS_NULL_COUNT_ACCOUNT_ID             | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on ACCOUNT_ID (FK)
-- TX-T04  | TXNS_NULL_COUNT_AMOUNT                 | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on AMOUNT
-- TX-T05  | TXNS_NULL_COUNT_TRANSACTION_DATE       | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on TRANSACTION_DATE
-- TX-T06  | TXNS_ROW_COUNT                         | SYSTEM DMF  | COMPLETENESS   | HIGH     | ROW_COUNT — high-volume table, volume shifts matter
-- TX-T07  | TXNS_FRESHNESS                         | SYSTEM DMF  | TIMELINESS     | HIGH     | FRESHNESS — transactions must be current

-- ==========================================================================
-- TRANSACTIONS — BUSINESS RULES
-- ==========================================================================
-- TX-B01  | TXNS_AMOUNT_POSITIVE                   | CUSTOM DMF  | ACCURACY       | HIGH     | AMOUNT must be > 0 (negative amounts invalid)
-- TX-B02  | TXNS_TYPE_ACCEPTED_VALUES              | CUSTOM DMF  | VALIDITY       | HIGH     | TRANSACTION_TYPE must be in ('CREDIT','DEBIT','TRANSFER','PAYMENT')
-- TX-B03  | TXNS_STATUS_ACCEPTED_VALUES            | CUSTOM DMF  | CONSISTENCY    | HIGH     | TRANSACTION_STATUS must be in ('SUCCESS','FAILED','PENDING','REVERSED') — 'DONE' is invalid
-- TX-B04  | TXNS_CHANNEL_ACCEPTED_VALUES           | CUSTOM DMF  | VALIDITY       | MEDIUM   | CHANNEL must be in ('UPI','NEFT','IMPS','RTGS','CARD','ATM','CHEQUE','BRANCH')
-- TX-B05  | TXNS_ACCOUNT_FK                        | SYSTEM DMF  | INTEGRITY      | HIGH     | REFERENTIAL_INTEGRITY_COUNT: ACCOUNT_ID must exist in ACCOUNTS
-- TX-B06  | TXNS_DATE_NOT_FUTURE                   | CUSTOM DMF  | ACCURACY       | HIGH     | TRANSACTION_DATE must not be in the future
-- TX-B07  | TXNS_AMOUNT_RANGE                      | CUSTOM DMF  | ACCURACY       | MEDIUM   | AMOUNT should be <= 10,000,000 (outlier detection)


/*-----------------------------------------------------------------------------
  TABLE 5: LOAN_APPLICATIONS
  Purpose: Loan application processing and decisioning
  Rows: 10 | Columns: 10
  Issues Found: REQUESTED_AMOUNT = 0, 6 NULL APPROVED_AMOUNT
-----------------------------------------------------------------------------*/

-- ==========================================================================
-- LOAN_APPLICATIONS — TECHNICAL RULES
-- ==========================================================================
-- LA-T01  | LOANS_NULL_COUNT_APPLICATION_ID       | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on APPLICATION_ID (PK)
-- LA-T02  | LOANS_DUPLICATE_COUNT_APPLICATION_ID   | SYSTEM DMF  | UNIQUENESS     | HIGH     | DUPLICATE_COUNT on APPLICATION_ID (PK)
-- LA-T03  | LOANS_NULL_COUNT_CUSTOMER_ID           | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on CUSTOMER_ID (FK)
-- LA-T04  | LOANS_NULL_COUNT_REQUESTED_AMT         | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on REQUESTED_AMOUNT
-- LA-T05  | LOANS_NULL_COUNT_CREDIT_SCORE          | SYSTEM DMF  | COMPLETENESS   | HIGH     | NULL_COUNT on CREDIT_SCORE
-- LA-T06  | LOANS_ROW_COUNT                        | SYSTEM DMF  | COMPLETENESS   | MEDIUM   | ROW_COUNT — volume monitoring
-- LA-T07  | LOANS_FRESHNESS                        | SYSTEM DMF  | TIMELINESS     | MEDIUM   | FRESHNESS — track staleness

-- ==========================================================================
-- LOAN_APPLICATIONS — BUSINESS RULES
-- ==========================================================================
-- LA-B01  | LOANS_REQUESTED_AMT_POSITIVE           | CUSTOM DMF  | ACCURACY       | HIGH     | REQUESTED_AMOUNT must be > 0
-- LA-B02  | LOANS_APPROVED_LTE_REQUESTED           | CUSTOM DMF  | ACCURACY       | HIGH     | APPROVED_AMOUNT must be <= REQUESTED_AMOUNT (when not NULL)
-- LA-B03  | LOANS_CREDIT_SCORE_RANGE               | CUSTOM DMF  | VALIDITY       | HIGH     | CREDIT_SCORE must be between 300 and 900
-- LA-B04  | LOANS_STATUS_ACCEPTED_VALUES            | CUSTOM DMF  | VALIDITY       | HIGH     | APPLICATION_STATUS must be in ('APPROVED','PENDING','REJECTED','CANCELLED')
-- LA-B05  | LOANS_TYPE_ACCEPTED_VALUES              | CUSTOM DMF  | VALIDITY       | MEDIUM   | LOAN_TYPE must be in ('HOME','PERSONAL','CAR','EDUCATION','BUSINESS','GOLD')
-- LA-B06  | LOANS_APPROVED_HAS_AMOUNT              | CUSTOM DMF  | CONSISTENCY    | HIGH     | If APPLICATION_STATUS = 'APPROVED', APPROVED_AMOUNT must not be NULL
-- LA-B07  | LOANS_CUSTOMER_FK                       | SYSTEM DMF  | INTEGRITY      | HIGH     | REFERENTIAL_INTEGRITY_COUNT: CUSTOMER_ID must exist in CUSTOMERS
-- LA-B08  | LOANS_BRANCH_FK                         | SYSTEM DMF  | INTEGRITY      | HIGH     | REFERENTIAL_INTEGRITY_COUNT: BRANCH_ID must exist in BRANCHES
-- LA-B09  | LOANS_DATE_NOT_FUTURE                   | CUSTOM DMF  | ACCURACY       | MEDIUM   | APPLICATION_DATE must not be in the future


/*=============================================================================
  SUMMARY: RULE COUNTS BY TABLE, TYPE, AND PRIORITY
=============================================================================

  TABLE               | SYSTEM DMF | CUSTOM DMF | TOTAL | HIGH | MEDIUM | LOW
  --------------------|------------|------------|-------|------|--------|----
  BRANCHES            |     6      |     4      |   10  |   4  |   5    |  1
  CUSTOMERS           |     8      |     6      |   14  |   8  |   5    |  1  (incl. 1 REFERENTIAL_INTEGRITY)
  ACCOUNTS            |     6      |     7      |   13  |   8  |   5    |  0  (incl. 2 REFERENTIAL_INTEGRITY)
  TRANSACTIONS        |     7      |     7      |   14  |  10  |   4    |  0  (incl. 1 REFERENTIAL_INTEGRITY)
  LOAN_APPLICATIONS   |     7      |     9      |   16  |  12  |   4    |  0  (incl. 2 REFERENTIAL_INTEGRITY)
  --------------------|------------|------------|-------|------|--------|----
  TOTAL               |    34      |    33      |   67  |  42  |  23    |  2

  DQ DIMENSION COVERAGE:
  - COMPLETENESS  : 22 rules (NULL_COUNT + ROW_COUNT)
  - UNIQUENESS    :  7 rules (DUPLICATE_COUNT)
  - VALIDITY      : 13 rules (format, range, accepted values)
  - ACCURACY      :  9 rules (business logic, amount positivity, date checks)
  - CONSISTENCY   :  5 rules (cross-column, status consistency)
  - INTEGRITY     :  6 rules (REFERENTIAL_INTEGRITY_COUNT)
  - TIMELINESS    :  5 rules (FRESHNESS)

=============================================================================*/

/*=============================================================================
  END OF PROPOSED RULES
=============================================================================*/
