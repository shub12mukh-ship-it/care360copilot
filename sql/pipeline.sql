-- =============================================================================
-- Care360 Evidence Copilot - Data Pipeline
-- Run after setup.sql and after uploading CSV files to @care360_stage
-- =============================================================================

USE DATABASE CARE360_DB;
USE WAREHOUSE CARE360_WH;

-- =============================================================================
-- STEP 1: Load structured data from stage
-- =============================================================================
-- Upload files first:
--   PUT file://data/patients.csv @RAW.care360_stage/patients AUTO_COMPRESS=FALSE;
--   PUT file://data/visits.csv @RAW.care360_stage/visits AUTO_COMPRESS=FALSE;
--   PUT file://data/labs.csv @RAW.care360_stage/labs AUTO_COMPRESS=FALSE;
--   PUT file://data/medications.csv @RAW.care360_stage/medications AUTO_COMPRESS=FALSE;
--   PUT file://data/claims.csv @RAW.care360_stage/claims AUTO_COMPRESS=FALSE;

COPY INTO RAW.PATIENTS (patient_id, first_name, last_name, date_of_birth, gender,
    race, ethnicity, primary_language, marital_status, address_city, address_state,
    insurance_type, primary_care_provider)
FROM @RAW.care360_stage/patients
FILE_FORMAT = RAW.csv_format
ON_ERROR = 'CONTINUE';

COPY INTO RAW.VISITS (visit_id, patient_id, visit_date, visit_type, department,
    provider_name, chief_complaint, primary_diagnosis, diagnosis_desc,
    discharge_disposition, length_of_stay_days)
FROM @RAW.care360_stage/visits
FILE_FORMAT = RAW.csv_format
ON_ERROR = 'CONTINUE';

COPY INTO RAW.LABS (lab_id, patient_id, visit_id, order_date, result_date,
    test_name, loinc_code, result_value, result_unit, reference_range,
    abnormal_flag, ordering_provider)
FROM @RAW.care360_stage/labs
FILE_FORMAT = RAW.csv_format
ON_ERROR = 'CONTINUE';

COPY INTO RAW.MEDICATIONS (medication_id, patient_id, drug_name, generic_name,
    rxnorm_code, dosage, frequency, route, start_date, end_date,
    prescribing_provider, indication, status)
FROM @RAW.care360_stage/medications
FILE_FORMAT = RAW.csv_format
ON_ERROR = 'CONTINUE';

COPY INTO RAW.CLAIMS (claim_id, patient_id, visit_id, claim_date, diagnosis_code,
    diagnosis_desc, procedure_code, procedure_desc, claim_status,
    billed_amount, allowed_amount, paid_amount, payer_name)
FROM @RAW.care360_stage/claims
FILE_FORMAT = RAW.csv_format
ON_ERROR = 'CONTINUE';

-- =============================================================================
-- STEP 2: Generate synthetic clinical notes
-- Uses Cortex LLM to create realistic clinical documents from structured data
-- =============================================================================

-- Generate discharge summaries for inpatient visits
INSERT INTO RAW.CLINICAL_NOTES (note_id, patient_id, visit_id, note_date, note_type, author_name, author_role, note_text)
SELECT
    'NOTE-' || v.visit_id AS note_id,
    v.patient_id,
    v.visit_id,
    v.visit_date AS note_date,
    CASE
        WHEN v.visit_type = 'IMP' THEN 'DISCHARGE_SUMMARY'
        WHEN v.visit_type = 'EMER' THEN 'PROGRESS_NOTE'
        ELSE 'PROGRESS_NOTE'
    END AS note_type,
    v.provider_name AS author_name,
    'Physician' AS author_role,
    SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
        'You are a clinical documentation specialist. Write a realistic but synthetic clinical '
        || CASE WHEN v.visit_type = 'IMP' THEN 'discharge summary' ELSE 'progress note' END
        || ' for a patient visit with these details. '
        || 'Patient: ' || p.first_name || ' ' || p.last_name
        || ', DOB: ' || p.date_of_birth::VARCHAR
        || ', Gender: ' || p.gender
        || '. Visit date: ' || v.visit_date::VARCHAR
        || ', Type: ' || v.visit_type
        || ', Department: ' || v.department
        || ', Chief complaint: ' || COALESCE(v.chief_complaint, 'routine follow-up')
        || ', Diagnosis: ' || COALESCE(v.diagnosis_desc, 'General examination')
        || ' (' || COALESCE(v.primary_diagnosis, 'Z00.00') || ')'
        || COALESCE(', Disposition: ' || v.discharge_disposition, '')
        || '. Include sections: History of Present Illness, Assessment, Plan, and Follow-up. '
        || 'Keep it under 500 words. Use realistic clinical language. '
        || 'This is SYNTHETIC data for demonstration purposes only.'
    ) AS note_text
FROM RAW.VISITS v
JOIN RAW.PATIENTS p ON v.patient_id = p.patient_id
WHERE v.visit_type IN ('IMP', 'EMER')
   OR MOD(ABS(HASH(v.visit_id)), 3) = 0;  -- include ~1/3 of ambulatory visits

-- =============================================================================
-- STEP 3: Chunk clinical documents for Cortex Search
-- Simple fixed-size chunking with overlap
-- =============================================================================

USE SCHEMA SEARCH;

-- Chunk documents into ~1000 character passages
INSERT INTO CLINICAL_DOCS_CHUNKED (chunk_id, note_id, patient_id, visit_id, note_date,
    note_type, author_name, chunk_index, chunk_text, patient_name)
WITH numbered_chunks AS (
    SELECT
        cn.note_id,
        cn.patient_id,
        cn.visit_id,
        cn.note_date,
        cn.note_type,
        cn.author_name,
        p.first_name || ' ' || p.last_name AS patient_name,
        cn.note_text,
        ROW_NUMBER() OVER (PARTITION BY cn.note_id ORDER BY cn.note_id) AS rn,
        -- Calculate number of chunks needed
        CEIL(LENGTH(cn.note_text) / 800.0) AS num_chunks
    FROM RAW.CLINICAL_NOTES cn
    JOIN RAW.PATIENTS p ON cn.patient_id = p.patient_id
),
chunk_indices AS (
    SELECT
        nc.*,
        idx.value::INT AS chunk_idx
    FROM numbered_chunks nc,
    LATERAL FLATTEN(ARRAY_GENERATE_RANGE(0, GREATEST(nc.num_chunks::INT, 1))) idx
)
SELECT
    note_id || '-C' || LPAD(chunk_idx::VARCHAR, 3, '0') AS chunk_id,
    note_id,
    patient_id,
    visit_id,
    note_date,
    note_type,
    author_name,
    chunk_idx AS chunk_index,
    SUBSTR(note_text, chunk_idx * 800 + 1, 1000) AS chunk_text,  -- 800 stride, 1000 window = 200 char overlap
    patient_name
FROM chunk_indices
WHERE SUBSTR(note_text, chunk_idx * 800 + 1, 1000) IS NOT NULL
  AND LENGTH(TRIM(SUBSTR(note_text, chunk_idx * 800 + 1, 1000))) > 50;

-- =============================================================================
-- STEP 4: Create Cortex Search Service
-- =============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE CARE360_DB.SEARCH.clinical_search_svc
    ON chunk_text
    ATTRIBUTES note_type, patient_id, patient_name, note_date, author_name
    WAREHOUSE = CARE360_WH
    TARGET_LAG = '1 hour'
    AS (
        SELECT
            chunk_id,
            chunk_text,
            note_id,
            patient_id,
            visit_id,
            note_date::VARCHAR AS note_date,
            note_type,
            author_name,
            chunk_index,
            patient_name
        FROM CARE360_DB.SEARCH.CLINICAL_DOCS_CHUNKED
    );
