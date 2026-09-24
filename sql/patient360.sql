-- =============================================================================
-- Care360 Evidence Copilot - Patient 360 Views & Analytical Queries
-- Run after pipeline.sql
-- =============================================================================

USE DATABASE CARE360_DB;
USE WAREHOUSE CARE360_WH;
USE SCHEMA ANALYTICS;

-- =============================================================================
-- Patient 360 Summary View
-- One row per patient with aggregated metrics from all data domains
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_360_VIEW AS
WITH active_meds AS (
    SELECT
        patient_id,
        COUNT(*) AS active_medication_count,
        LISTAGG(DISTINCT drug_name, ', ') WITHIN GROUP (ORDER BY drug_name) AS active_medications
    FROM RAW.MEDICATIONS
    WHERE status = 'ACTIVE'
    GROUP BY patient_id
),
recent_labs AS (
    SELECT
        patient_id,
        COUNT(*) AS total_lab_count,
        COUNT(CASE WHEN abnormal_flag IN ('H', 'HH', 'L', 'LL') THEN 1 END) AS abnormal_lab_count,
        MAX(result_date) AS last_lab_date
    FROM RAW.LABS
    GROUP BY patient_id
),
visit_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_visits,
        COUNT(CASE WHEN visit_type = 'EMER' THEN 1 END) AS ed_visits,
        COUNT(CASE WHEN visit_type = 'IMP' THEN 1 END) AS inpatient_stays,
        MAX(visit_date) AS last_visit_date,
        MAX(CASE WHEN visit_type = 'EMER' THEN visit_date END) AS last_ed_visit
    FROM RAW.VISITS
    GROUP BY patient_id
),
claims_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_claims,
        SUM(billed_amount) AS total_billed,
        SUM(paid_amount) AS total_paid,
        COUNT(CASE WHEN claim_status = 'DENIED' THEN 1 END) AS denied_claims
    FROM RAW.CLAIMS
    GROUP BY patient_id
),
note_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_notes,
        MAX(note_date) AS last_note_date
    FROM RAW.CLINICAL_NOTES
    GROUP BY patient_id
)
SELECT
    p.patient_id,
    p.first_name,
    p.last_name,
    p.first_name || ' ' || p.last_name AS full_name,
    p.date_of_birth,
    DATEDIFF('year', p.date_of_birth, CURRENT_DATE()) AS age,
    p.gender,
    p.race,
    p.insurance_type,
    p.primary_care_provider,

    -- Visit metrics
    COALESCE(vs.total_visits, 0) AS total_visits,
    COALESCE(vs.ed_visits, 0) AS ed_visits,
    COALESCE(vs.inpatient_stays, 0) AS inpatient_stays,
    vs.last_visit_date,

    -- Medication metrics
    COALESCE(am.active_medication_count, 0) AS active_medication_count,
    am.active_medications,

    -- Lab metrics
    COALESCE(rl.total_lab_count, 0) AS total_lab_count,
    COALESCE(rl.abnormal_lab_count, 0) AS abnormal_lab_count,
    rl.last_lab_date,

    -- Claims metrics
    COALESCE(cs.total_claims, 0) AS total_claims,
    COALESCE(cs.total_billed, 0) AS total_billed,
    COALESCE(cs.total_paid, 0) AS total_paid,
    COALESCE(cs.denied_claims, 0) AS denied_claims,

    -- Document metrics
    COALESCE(ns.total_notes, 0) AS total_clinical_notes,
    ns.last_note_date

FROM RAW.PATIENTS p
LEFT JOIN visit_summary vs ON p.patient_id = vs.patient_id
LEFT JOIN active_meds am ON p.patient_id = am.patient_id
LEFT JOIN recent_labs rl ON p.patient_id = rl.patient_id
LEFT JOIN claims_summary cs ON p.patient_id = cs.patient_id
LEFT JOIN note_summary ns ON p.patient_id = ns.patient_id;

-- =============================================================================
-- Patient Timeline View
-- All events for a patient in chronological order
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_TIMELINE AS
SELECT patient_id, event_date, event_type, event_category, description, source_id
FROM (
    -- Visits
    SELECT
        patient_id,
        visit_date AS event_date,
        'VISIT' AS event_type,
        visit_type AS event_category,
        chief_complaint || ' - ' || COALESCE(diagnosis_desc, 'N/A')
            || ' (Provider: ' || provider_name || ')' AS description,
        visit_id AS source_id
    FROM RAW.VISITS

    UNION ALL

    -- Labs
    SELECT
        patient_id,
        result_date AS event_date,
        'LAB' AS event_type,
        abnormal_flag AS event_category,
        test_name || ': ' || result_value || ' ' || COALESCE(result_unit, '')
            || ' (Ref: ' || COALESCE(reference_range, 'N/A') || ')'
            || CASE WHEN abnormal_flag IN ('H', 'HH') THEN ' [HIGH]'
                    WHEN abnormal_flag IN ('L', 'LL') THEN ' [LOW]'
                    ELSE '' END AS description,
        lab_id AS source_id
    FROM RAW.LABS

    UNION ALL

    -- Medications started
    SELECT
        patient_id,
        start_date AS event_date,
        'MED_START' AS event_type,
        status AS event_category,
        'Started: ' || drug_name || ' ' || dosage || ' ' || frequency
            || ' for ' || COALESCE(indication, 'unspecified') AS description,
        medication_id AS source_id
    FROM RAW.MEDICATIONS

    UNION ALL

    -- Medications ended
    SELECT
        patient_id,
        end_date AS event_date,
        'MED_STOP' AS event_type,
        'DISCONTINUED' AS event_category,
        'Stopped: ' || drug_name || ' ' || dosage AS description,
        medication_id AS source_id
    FROM RAW.MEDICATIONS
    WHERE end_date IS NOT NULL

    UNION ALL

    -- Clinical notes
    SELECT
        patient_id,
        note_date AS event_date,
        'NOTE' AS event_type,
        note_type AS event_category,
        note_type || ' by ' || author_name || ' (' || author_role || ')' AS description,
        note_id AS source_id
    FROM RAW.CLINICAL_NOTES
)
ORDER BY patient_id, event_date DESC;

-- =============================================================================
-- Care Gaps View
-- Identifies missing or overdue follow-up actions
-- =============================================================================

CREATE OR REPLACE VIEW CARE_GAPS AS
WITH diabetic_patients AS (
    SELECT DISTINCT patient_id
    FROM RAW.CLAIMS
    WHERE diagnosis_code LIKE 'E11%' OR diagnosis_code LIKE 'E10%'
),
last_hba1c AS (
    SELECT
        patient_id,
        MAX(result_date) AS last_hba1c_date,
        MAX_BY(result_value, result_date) AS last_hba1c_value
    FROM RAW.LABS
    WHERE LOWER(test_name) LIKE '%a1c%' OR loinc_code = '4548-4'
    GROUP BY patient_id
),
high_ed_utilizers AS (
    SELECT
        patient_id,
        COUNT(*) AS ed_visits_90d
    FROM RAW.VISITS
    WHERE visit_type = 'EMER'
      AND visit_date >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY patient_id
    HAVING COUNT(*) >= 2
)

-- Gap: Diabetic patients missing recent HbA1c
SELECT
    dp.patient_id,
    'MISSING_HBA1C' AS gap_type,
    'Diabetic patient - no HbA1c in last 6 months' AS gap_description,
    lh.last_hba1c_date AS last_relevant_date,
    'HIGH' AS priority
FROM diabetic_patients dp
LEFT JOIN last_hba1c lh ON dp.patient_id = lh.patient_id
WHERE lh.last_hba1c_date IS NULL
   OR lh.last_hba1c_date < DATEADD('month', -6, CURRENT_DATE())

UNION ALL

-- Gap: Diabetic patients with uncontrolled A1c (>9%)
SELECT
    dp.patient_id,
    'UNCONTROLLED_A1C' AS gap_type,
    'HbA1c > 9% - last value: ' || lh.last_hba1c_value AS gap_description,
    lh.last_hba1c_date AS last_relevant_date,
    'HIGH' AS priority
FROM diabetic_patients dp
JOIN last_hba1c lh ON dp.patient_id = lh.patient_id
WHERE TRY_CAST(REPLACE(lh.last_hba1c_value, '%', '') AS FLOAT) > 9.0

UNION ALL

-- Gap: High ED utilizers
SELECT
    patient_id,
    'HIGH_ED_UTILIZATION' AS gap_type,
    ed_visits_90d || ' ED visits in last 90 days' AS gap_description,
    CURRENT_DATE() AS last_relevant_date,
    'MEDIUM' AS priority
FROM high_ed_utilizers;
