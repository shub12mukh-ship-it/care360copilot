-- =============================================================================
-- Care360 Evidence Copilot - CSV Data Loading
-- Run after setup.sql to load CSV files from local data/ folder into RAW schema
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE CARE360_DB;
USE WAREHOUSE CARE360_WH;
USE SCHEMA RAW;

-- =============================================================================
-- STEP 1: File Format
-- =============================================================================

CREATE FILE FORMAT IF NOT EXISTS csv_format
    TYPE = 'CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL = TRUE
    DATE_FORMAT = 'YYYY-MM-DD'
    TRIM_SPACE = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;

-- =============================================================================
-- STEP 2: Internal Stage
-- =============================================================================

CREATE STAGE IF NOT EXISTS care360_stage
    FILE_FORMAT = csv_format;

-- =============================================================================
-- STEP 3: Upload CSV files to stage (run from SnowSQL or Snowflake CLI)
-- =============================================================================
-- PUT file://data/patients.csv    @care360_stage/patients    AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://data/visits.csv      @care360_stage/visits      AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://data/labs.csv        @care360_stage/labs         AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://data/medications.csv @care360_stage/medications  AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://data/diagnosis.csv   @care360_stage/diagnosis    AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file://data/claims.csv      @care360_stage/claims       AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Verify uploads
-- LIST @care360_stage;

-- =============================================================================
-- STEP 4: Truncate tables (idempotent reload)
-- =============================================================================

TRUNCATE TABLE IF EXISTS CLAIMS;
TRUNCATE TABLE IF EXISTS DIAGNOSIS;
TRUNCATE TABLE IF EXISTS MEDICATIONS;
TRUNCATE TABLE IF EXISTS LABS;
TRUNCATE TABLE IF EXISTS VISITS;
TRUNCATE TABLE IF EXISTS PATIENTS;

-- =============================================================================
-- STEP 5: COPY INTO - Load each CSV into its RAW table
-- Column lists match CSV headers exactly (created_at auto-populated)
-- =============================================================================

-- 5a. Patients (26 CSV columns → 26 table columns)
COPY INTO PATIENTS (
    patient_id, first_name, last_name, date_of_birth, gender,
    race, ethnicity, language, marital_status,
    address, city, state, zip_code,
    phone, email,
    insurance_type, insurance_plan,
    pcp_name, pcp_phone,
    emergency_contact_name, emergency_contact_phone,
    blood_type, smoking_status, alcohol_use, bmi, risk_score
)
FROM @care360_stage/patients
FILE_FORMAT = csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 5b. Visits (11 CSV columns → 11 table columns)
COPY INTO VISITS (
    visit_id, patient_id, visit_date, visit_type, department,
    provider_name, chief_complaint, primary_diagnosis, diagnosis_desc,
    discharge_disposition, length_of_stay_days
)
FROM @care360_stage/visits
FILE_FORMAT = csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 5c. Labs (14 CSV columns → 14 table columns)
COPY INTO LABS (
    lab_id, patient_id, visit_id, lab_date, test_name, test_code,
    result_value, result_unit,
    reference_range_low, reference_range_high,
    abnormal_flag, ordering_provider, lab_status, category
)
FROM @care360_stage/labs
FILE_FORMAT = csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 5d. Medications (17 CSV columns → 17 table columns)
COPY INTO MEDICATIONS (
    medication_id, patient_id, visit_id,
    medication_name, generic_name, ndc_code,
    dosage, route, frequency,
    prescribing_provider, start_date, end_date,
    status, refills_remaining, pharmacy, indication, drug_class
)
FROM @care360_stage/medications
FILE_FORMAT = csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 5e. Diagnosis (12 CSV columns → 12 table columns)
COPY INTO DIAGNOSIS (
    diagnosis_id, patient_id, visit_id,
    icd10_code, diagnosis_description, diagnosis_type,
    diagnosis_date, diagnosed_by, status,
    onset_date, severity, is_chronic
)
FROM @care360_stage/diagnosis
FILE_FORMAT = csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 5f. Claims (19 CSV columns → 19 table columns)
COPY INTO CLAIMS (
    claim_id, patient_id, visit_id,
    claim_date, service_date, claim_type,
    icd10_primary, cpt_code, cpt_description,
    billed_amount, allowed_amount, paid_amount, patient_responsibility,
    claim_status, payer_name, denial_reason,
    provider_name, facility_name, place_of_service
)
FROM @care360_stage/claims
FILE_FORMAT = csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- =============================================================================
-- STEP 6: Validation Queries
-- =============================================================================

-- 6a. Row counts per table
SELECT 'PATIENTS' AS table_name, COUNT(*) AS row_count FROM PATIENTS
UNION ALL
SELECT 'VISITS', COUNT(*) FROM VISITS
UNION ALL
SELECT 'LABS', COUNT(*) FROM LABS
UNION ALL
SELECT 'MEDICATIONS', COUNT(*) FROM MEDICATIONS
UNION ALL
SELECT 'DIAGNOSIS', COUNT(*) FROM DIAGNOSIS
UNION ALL
SELECT 'CLAIMS', COUNT(*) FROM CLAIMS
ORDER BY table_name;

-- 6b. Check for NULL primary keys (should return 0 rows)
SELECT 'PATIENTS' AS tbl, COUNT(*) AS null_pks FROM PATIENTS WHERE patient_id IS NULL
UNION ALL
SELECT 'VISITS', COUNT(*) FROM VISITS WHERE visit_id IS NULL
UNION ALL
SELECT 'LABS', COUNT(*) FROM LABS WHERE lab_id IS NULL
UNION ALL
SELECT 'MEDICATIONS', COUNT(*) FROM MEDICATIONS WHERE medication_id IS NULL
UNION ALL
SELECT 'DIAGNOSIS', COUNT(*) FROM DIAGNOSIS WHERE diagnosis_id IS NULL
UNION ALL
SELECT 'CLAIMS', COUNT(*) FROM CLAIMS WHERE claim_id IS NULL;

-- 6c. Referential integrity - orphaned patient_id references
SELECT 'VISITS' AS tbl, COUNT(*) AS orphaned_rows
FROM VISITS v LEFT JOIN PATIENTS p ON v.patient_id = p.patient_id
WHERE p.patient_id IS NULL
UNION ALL
SELECT 'LABS', COUNT(*)
FROM LABS l LEFT JOIN PATIENTS p ON l.patient_id = p.patient_id
WHERE p.patient_id IS NULL
UNION ALL
SELECT 'MEDICATIONS', COUNT(*)
FROM MEDICATIONS m LEFT JOIN PATIENTS p ON m.patient_id = p.patient_id
WHERE p.patient_id IS NULL
UNION ALL
SELECT 'DIAGNOSIS', COUNT(*)
FROM DIAGNOSIS d LEFT JOIN PATIENTS p ON d.patient_id = p.patient_id
WHERE p.patient_id IS NULL
UNION ALL
SELECT 'CLAIMS', COUNT(*)
FROM CLAIMS c LEFT JOIN PATIENTS p ON c.patient_id = p.patient_id
WHERE p.patient_id IS NULL;

-- 6d. Sample data preview (5 rows per table)
SELECT * FROM PATIENTS LIMIT 5;
SELECT * FROM VISITS LIMIT 5;
SELECT * FROM LABS LIMIT 5;
SELECT * FROM MEDICATIONS LIMIT 5;
SELECT * FROM DIAGNOSIS LIMIT 5;
SELECT * FROM CLAIMS LIMIT 5;

-- 6e. Check for any load errors in COPY history (last 24 hours)
SELECT
    table_name,
    file_name,
    status,
    rows_parsed,
    rows_loaded,
    error_count,
    first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'PATIENTS',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
UNION ALL
SELECT table_name, file_name, status, rows_parsed, rows_loaded, error_count, first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'VISITS',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
UNION ALL
SELECT table_name, file_name, status, rows_parsed, rows_loaded, error_count, first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'LABS',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
UNION ALL
SELECT table_name, file_name, status, rows_parsed, rows_loaded, error_count, first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'MEDICATIONS',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
UNION ALL
SELECT table_name, file_name, status, rows_parsed, rows_loaded, error_count, first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'DIAGNOSIS',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
))
UNION ALL
SELECT table_name, file_name, status, rows_parsed, rows_loaded, error_count, first_error_message
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'CLAIMS',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
));
