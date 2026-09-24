-- =============================================================================
-- Care360 Copilot - RAW → CURATED Transformation Pipeline
-- Run after setup.sql and data loading
-- =============================================================================

USE DATABASE CARE360_DB;
USE WAREHOUSE CARE360_WH;
USE SCHEMA CURATED;

-- =============================================================================
-- 1. PATIENT_DIAGNOSIS_SUMMARY
--    Combines all diagnoses per patient: chronic conditions, active list,
--    severity breakdown. Preserves evidence source columns.
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_DIAGNOSIS_SUMMARY AS
WITH ranked_dx AS (
    SELECT
        d.patient_id,
        d.diagnosis_id,
        d.visit_id,
        d.icd10_code,
        d.diagnosis_description,
        d.diagnosis_type,
        d.diagnosis_date,
        d.diagnosed_by,
        d.status,
        d.onset_date,
        d.severity,
        d.is_chronic,
        ROW_NUMBER() OVER (
            PARTITION BY d.patient_id, d.icd10_code
            ORDER BY d.diagnosis_date DESC
        ) AS rn_per_code
    FROM RAW.DIAGNOSIS d
)
SELECT
    patient_id,

    -- Active diagnosis count
    COUNT(DISTINCT CASE WHEN status = 'Active' THEN icd10_code END)
        AS active_diagnosis_count,

    -- Chronic condition count
    COUNT(DISTINCT CASE WHEN UPPER(is_chronic) = 'TRUE' THEN icd10_code END)
        AS chronic_condition_count,

    -- Comma-separated active diagnoses (deduplicated by ICD-10)
    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT CASE WHEN status = 'Active' THEN diagnosis_description END), '; '
    ) AS active_diagnoses_list,

    -- Comma-separated chronic conditions
    ARRAY_TO_STRING(
        ARRAY_AGG(DISTINCT CASE WHEN UPPER(is_chronic) = 'TRUE' THEN diagnosis_description END), '; '
    ) AS chronic_conditions_list,

    -- Severity breakdown
    COUNT(DISTINCT CASE WHEN severity = 'Severe' THEN icd10_code END)   AS severe_dx_count,
    COUNT(DISTINCT CASE WHEN severity = 'Moderate' THEN icd10_code END) AS moderate_dx_count,
    COUNT(DISTINCT CASE WHEN severity = 'Mild' THEN icd10_code END)     AS mild_dx_count,

    -- Most recent diagnosis
    MAX(diagnosis_date)                                  AS last_diagnosis_date,
    MAX_BY(diagnosis_description, diagnosis_date)        AS last_diagnosis_description,
    MAX_BY(icd10_code, diagnosis_date)                   AS last_diagnosis_icd10,
    MAX_BY(diagnosed_by, diagnosis_date)                 AS last_diagnosed_by,

    -- Evidence: all distinct ICD-10 codes
    ARRAY_TO_STRING(ARRAY_AGG(DISTINCT icd10_code), ', ') AS all_icd10_codes,

    -- Evidence: source diagnosis IDs
    ARRAY_TO_STRING(ARRAY_AGG(DISTINCT diagnosis_id), ', ') AS source_diagnosis_ids

FROM ranked_dx
GROUP BY patient_id;

-- =============================================================================
-- 2. PATIENT_LATEST_LABS
--    Latest result for each lab test per patient with abnormal flags
--    and reference range comparison.
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_LATEST_LABS AS
WITH latest_per_test AS (
    SELECT
        l.patient_id,
        l.test_name,
        l.test_code,
        l.lab_date,
        l.result_value,
        l.result_unit,
        l.reference_range_low,
        l.reference_range_high,
        l.abnormal_flag,
        l.ordering_provider,
        l.lab_status,
        l.category,
        l.lab_id,
        l.visit_id,
        ROW_NUMBER() OVER (
            PARTITION BY l.patient_id, l.test_name
            ORDER BY l.lab_date DESC, l.lab_id DESC
        ) AS rn
    FROM RAW.LABS l
    WHERE l.lab_status != 'Cancelled'
)
SELECT
    patient_id,
    test_name,
    test_code,
    lab_date                AS latest_result_date,
    result_value            AS latest_result_value,
    result_unit,
    reference_range_low,
    reference_range_high,
    abnormal_flag           AS latest_abnormal_flag,
    CASE
        WHEN abnormal_flag IN ('H', 'HH') THEN 'HIGH'
        WHEN abnormal_flag IN ('L', 'LL') THEN 'LOW'
        WHEN abnormal_flag = 'N' THEN 'NORMAL'
        ELSE 'UNKNOWN'
    END                     AS abnormal_category,
    ordering_provider       AS latest_ordering_provider,
    category                AS lab_category,
    DATEDIFF('day', lab_date, CURRENT_DATE()) AS days_since_result,

    -- Evidence
    lab_id                  AS source_lab_id,
    visit_id                AS source_visit_id
FROM latest_per_test
WHERE rn = 1;

-- Pivoted summary: one row per patient with key lab metrics
CREATE OR REPLACE VIEW PATIENT_LAB_SUMMARY AS
SELECT
    patient_id,

    -- Total / abnormal counts
    COUNT(*)                                                           AS distinct_test_count,
    COUNT(CASE WHEN latest_abnormal_flag IN ('H','HH','L','LL') THEN 1 END) AS abnormal_test_count,

    -- Key lab values (most recent)
    MAX(CASE WHEN UPPER(test_name) LIKE '%A1C%'       THEN latest_result_value END) AS latest_hba1c,
    MAX(CASE WHEN UPPER(test_name) LIKE '%A1C%'       THEN latest_result_date  END) AS latest_hba1c_date,
    MAX(CASE WHEN UPPER(test_name) LIKE '%A1C%'       THEN source_lab_id       END) AS hba1c_source_lab_id,

    MAX(CASE WHEN UPPER(test_name) LIKE '%LDL%'       THEN latest_result_value END) AS latest_ldl,
    MAX(CASE WHEN UPPER(test_name) LIKE '%LDL%'       THEN latest_result_date  END) AS latest_ldl_date,
    MAX(CASE WHEN UPPER(test_name) LIKE '%LDL%'       THEN source_lab_id       END) AS ldl_source_lab_id,

    MAX(CASE WHEN UPPER(test_name) LIKE '%CREATININE%' THEN latest_result_value END) AS latest_creatinine,
    MAX(CASE WHEN UPPER(test_name) LIKE '%CREATININE%' THEN latest_result_date  END) AS latest_creatinine_date,
    MAX(CASE WHEN UPPER(test_name) LIKE '%CREATININE%' THEN source_lab_id       END) AS creatinine_source_lab_id,

    MAX(CASE WHEN UPPER(test_name) LIKE '%GLUCOSE%'    THEN latest_result_value END) AS latest_glucose,
    MAX(CASE WHEN UPPER(test_name) LIKE '%GLUCOSE%'    THEN latest_result_date  END) AS latest_glucose_date,
    MAX(CASE WHEN UPPER(test_name) LIKE '%GLUCOSE%'    THEN source_lab_id       END) AS glucose_source_lab_id,

    -- Most recent lab overall
    MAX(latest_result_date) AS last_lab_date

FROM PATIENT_LATEST_LABS
GROUP BY patient_id;

-- =============================================================================
-- 3. PATIENT_MEDICATION_GAPS
--    Identifies patients with chronic/active medications that may have
--    lapsed (end_date passed, low refills, no recent activity).
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_MEDICATION_GAPS AS
WITH active_meds AS (
    SELECT
        m.patient_id,
        m.medication_id,
        m.medication_name,
        m.generic_name,
        m.drug_class,
        m.dosage,
        m.frequency,
        m.start_date,
        m.end_date,
        m.status,
        m.refills_remaining,
        m.prescribing_provider,
        m.indication,
        m.visit_id
    FROM RAW.MEDICATIONS m
),

gap_analysis AS (
    SELECT
        *,
        CASE
            -- Medication marked active but end_date has passed
            WHEN status = 'Active' AND end_date IS NOT NULL
                 AND end_date < CURRENT_DATE()
                THEN 'EXPIRED_ACTIVE'

            -- Active medication with zero refills remaining
            WHEN status = 'Active' AND refills_remaining = 0
                THEN 'NO_REFILLS'

            -- Discontinued medication for a chronic indication — potential gap
            WHEN status IN ('Discontinued', 'Inactive')
                 AND indication IS NOT NULL
                 AND DATEDIFF('day', COALESCE(end_date, start_date), CURRENT_DATE()) < 180
                THEN 'RECENTLY_STOPPED'

            ELSE NULL
        END AS gap_type,

        CASE
            WHEN status = 'Active' AND end_date IS NOT NULL
                 AND end_date < CURRENT_DATE()
                THEN 'Medication ' || medication_name || ' expired on ' || end_date::VARCHAR
                     || ' but still marked Active'

            WHEN status = 'Active' AND refills_remaining = 0
                THEN 'Medication ' || medication_name || ' has 0 refills remaining'

            WHEN status IN ('Discontinued', 'Inactive')
                 AND indication IS NOT NULL
                 AND DATEDIFF('day', COALESCE(end_date, start_date), CURRENT_DATE()) < 180
                THEN 'Medication ' || medication_name || ' for ' || indication
                     || ' was stopped on ' || COALESCE(end_date, start_date)::VARCHAR

            ELSE NULL
        END AS gap_description,

        CASE
            WHEN status = 'Active' AND end_date IS NOT NULL
                 AND end_date < CURRENT_DATE()
                THEN 'HIGH'
            WHEN status = 'Active' AND refills_remaining = 0
                THEN 'MEDIUM'
            ELSE 'LOW'
        END AS gap_priority
    FROM active_meds
)
SELECT
    patient_id,
    medication_id       AS source_medication_id,
    visit_id            AS source_visit_id,
    medication_name,
    generic_name,
    drug_class,
    dosage,
    frequency,
    start_date,
    end_date,
    status              AS medication_status,
    refills_remaining,
    prescribing_provider,
    indication,
    gap_type,
    gap_description,
    gap_priority
FROM gap_analysis
WHERE gap_type IS NOT NULL;

-- =============================================================================
-- 4. PATIENT_FOLLOWUP_GAPS
--    Identifies patients overdue for follow-up based on visit history,
--    chronic diagnoses, and lab timing.
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_FOLLOWUP_GAPS AS

-- Gap: Chronic condition with no visit in 6+ months
WITH chronic_no_visit AS (
    SELECT
        d.patient_id,
        'CHRONIC_NO_VISIT' AS gap_type,
        'Chronic condition (' || d.diagnosis_description || ') with no visit in 6+ months'
            AS gap_description,
        'HIGH' AS gap_priority,
        MAX(v.visit_date) AS last_relevant_date,
        d.diagnosis_id AS source_id,
        'DIAGNOSIS' AS source_table
    FROM RAW.DIAGNOSIS d
    LEFT JOIN RAW.VISITS v
        ON d.patient_id = v.patient_id
        AND v.visit_date >= DATEADD('month', -6, CURRENT_DATE())
    WHERE UPPER(d.is_chronic) = 'TRUE'
      AND d.status = 'Active'
      AND v.visit_id IS NULL
    GROUP BY d.patient_id, d.diagnosis_description, d.diagnosis_id
),

-- Gap: Diabetic patients without recent HbA1c (>6 months)
diabetic_no_a1c AS (
    SELECT
        d.patient_id,
        'MISSING_HBA1C' AS gap_type,
        'Diabetic patient - no HbA1c in last 6 months' AS gap_description,
        'HIGH' AS gap_priority,
        MAX(l.lab_date) AS last_relevant_date,
        d.diagnosis_id AS source_id,
        'DIAGNOSIS' AS source_table
    FROM RAW.DIAGNOSIS d
    LEFT JOIN RAW.LABS l
        ON d.patient_id = l.patient_id
        AND UPPER(l.test_name) LIKE '%A1C%'
        AND l.lab_date >= DATEADD('month', -6, CURRENT_DATE())
    WHERE d.icd10_code LIKE 'E11%' OR d.icd10_code LIKE 'E10%'
    GROUP BY d.patient_id, d.diagnosis_id
    HAVING MAX(l.lab_id) IS NULL
),

-- Gap: High ED utilization (2+ ED visits in 90 days)
high_ed AS (
    SELECT
        v.patient_id,
        'HIGH_ED_UTILIZATION' AS gap_type,
        COUNT(*) || ' ED visits in last 90 days - consider care management referral'
            AS gap_description,
        'MEDIUM' AS gap_priority,
        MAX(v.visit_date) AS last_relevant_date,
        MAX_BY(v.visit_id, v.visit_date) AS source_id,
        'VISITS' AS source_table
    FROM RAW.VISITS v
    WHERE v.visit_type = 'EMER'
      AND v.visit_date >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY v.patient_id
    HAVING COUNT(*) >= 2
),

-- Gap: No visit in 12+ months for any patient
no_recent_visit AS (
    SELECT
        p.patient_id,
        'NO_RECENT_VISIT' AS gap_type,
        'No visit recorded in the last 12 months' AS gap_description,
        'LOW' AS gap_priority,
        MAX(v.visit_date) AS last_relevant_date,
        MAX_BY(v.visit_id, v.visit_date) AS source_id,
        'VISITS' AS source_table
    FROM RAW.PATIENTS p
    LEFT JOIN RAW.VISITS v ON p.patient_id = v.patient_id
    GROUP BY p.patient_id
    HAVING MAX(v.visit_date) IS NULL
        OR MAX(v.visit_date) < DATEADD('month', -12, CURRENT_DATE())
)

SELECT * FROM chronic_no_visit
UNION ALL
SELECT * FROM diabetic_no_a1c
UNION ALL
SELECT * FROM high_ed
UNION ALL
SELECT * FROM no_recent_visit;

-- =============================================================================
-- 5. PATIENT_VISIT_SUMMARY
--    Summarizes recent visits per patient with counts by type,
--    last visit details, and cost rollup from claims.
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_VISIT_SUMMARY AS
WITH visit_metrics AS (
    SELECT
        v.patient_id,
        COUNT(*)                                                       AS total_visits,
        COUNT(CASE WHEN v.visit_type = 'EMER'  THEN 1 END)            AS ed_visit_count,
        COUNT(CASE WHEN v.visit_type = 'IMP'   THEN 1 END)            AS inpatient_count,
        COUNT(CASE WHEN v.visit_type = 'AMB'   THEN 1 END)            AS ambulatory_count,

        MAX(v.visit_date)                                              AS last_visit_date,
        MAX_BY(v.visit_type, v.visit_date)                             AS last_visit_type,
        MAX_BY(v.department, v.visit_date)                             AS last_visit_department,
        MAX_BY(v.provider_name, v.visit_date)                          AS last_visit_provider,
        MAX_BY(v.chief_complaint, v.visit_date)                        AS last_visit_complaint,
        MAX_BY(v.diagnosis_desc, v.visit_date)                         AS last_visit_diagnosis,
        MAX_BY(v.discharge_disposition, v.visit_date)                  AS last_visit_disposition,
        MAX_BY(v.visit_id, v.visit_date)                               AS last_visit_id,

        DATEDIFF('day', MAX(v.visit_date), CURRENT_DATE())             AS days_since_last_visit,

        -- Recent 3 visits summary
        LISTAGG(
            CASE WHEN rn <= 3 THEN
                v.visit_date::VARCHAR || ' | ' || v.visit_type || ' | '
                || COALESCE(v.chief_complaint, 'N/A')
            END, ' /// '
        ) WITHIN GROUP (ORDER BY v.visit_date DESC)                    AS recent_visits_summary
    FROM (
        SELECT v2.*,
            ROW_NUMBER() OVER (PARTITION BY v2.patient_id ORDER BY v2.visit_date DESC) AS rn
        FROM RAW.VISITS v2
    ) v
    GROUP BY v.patient_id
),
claims_rollup AS (
    SELECT
        c.patient_id,
        SUM(c.billed_amount)                                           AS total_billed,
        SUM(c.paid_amount)                                             AS total_paid,
        SUM(c.patient_responsibility)                                  AS total_patient_responsibility,
        COUNT(*)                                                       AS total_claims,
        COUNT(CASE WHEN c.claim_status = 'Denied' THEN 1 END)         AS denied_claim_count
    FROM RAW.CLAIMS c
    GROUP BY c.patient_id
)
SELECT
    vm.*,
    COALESCE(cr.total_billed, 0)                    AS total_billed,
    COALESCE(cr.total_paid, 0)                      AS total_paid,
    COALESCE(cr.total_patient_responsibility, 0)    AS total_patient_responsibility,
    COALESCE(cr.total_claims, 0)                    AS total_claims,
    COALESCE(cr.denied_claim_count, 0)              AS denied_claim_count
FROM visit_metrics vm
LEFT JOIN claims_rollup cr ON vm.patient_id = cr.patient_id;

-- =============================================================================
-- 6. PATIENT_360
--    Master view: one row per patient combining demographics, diagnoses,
--    labs, medications, visit history, and care gaps. Every derived metric
--    carries its evidence source column(s).
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT_360 AS
WITH med_summary AS (
    SELECT
        m.patient_id,
        COUNT(CASE WHEN m.status = 'Active' THEN 1 END)            AS active_medication_count,
        ARRAY_TO_STRING(
            ARRAY_AGG(DISTINCT CASE WHEN m.status = 'Active' THEN m.medication_name END), '; '
        ) AS active_medications_list,
        ARRAY_TO_STRING(
            ARRAY_AGG(DISTINCT CASE WHEN m.status = 'Active' THEN m.drug_class END), '; '
        ) AS active_drug_classes,
        COUNT(DISTINCT CASE WHEN m.status = 'Active' THEN m.drug_class END) AS active_drug_class_count,
        ARRAY_TO_STRING(
            ARRAY_AGG(DISTINCT CASE WHEN m.status = 'Active' THEN m.medication_id END), ', '
        ) AS source_active_medication_ids
    FROM RAW.MEDICATIONS m
    GROUP BY m.patient_id
),
med_gap_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS medication_gap_count,
        COUNT(CASE WHEN gap_priority = 'HIGH' THEN 1 END) AS high_priority_med_gaps
    FROM PATIENT_MEDICATION_GAPS
    GROUP BY patient_id
),
followup_gap_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS followup_gap_count,
        COUNT(CASE WHEN gap_priority = 'HIGH' THEN 1 END) AS high_priority_followup_gaps,
        ARRAY_TO_STRING(ARRAY_AGG(DISTINCT gap_type), ', ') AS followup_gap_types
    FROM PATIENT_FOLLOWUP_GAPS
    GROUP BY patient_id
)
SELECT
    -- Demographics
    p.patient_id,
    p.first_name,
    p.last_name,
    p.first_name || ' ' || p.last_name                     AS full_name,
    p.date_of_birth,
    DATEDIFF('year', p.date_of_birth, CURRENT_DATE())       AS age,
    p.gender,
    p.race,
    p.ethnicity,
    p.insurance_type,
    p.insurance_plan,
    p.pcp_name,
    p.smoking_status,
    p.bmi,
    p.risk_score,
    p.blood_type,

    -- Diagnosis summary
    COALESCE(dx.active_diagnosis_count, 0)                  AS active_diagnosis_count,
    COALESCE(dx.chronic_condition_count, 0)                 AS chronic_condition_count,
    dx.active_diagnoses_list,
    dx.chronic_conditions_list,
    COALESCE(dx.severe_dx_count, 0)                         AS severe_diagnosis_count,
    dx.last_diagnosis_date,
    dx.last_diagnosis_description,
    dx.last_diagnosis_icd10,
    dx.all_icd10_codes                                      AS evidence_icd10_codes,
    dx.source_diagnosis_ids                                 AS evidence_diagnosis_ids,

    -- Lab summary
    COALESCE(lab.distinct_test_count, 0)                    AS distinct_lab_test_count,
    COALESCE(lab.abnormal_test_count, 0)                    AS abnormal_lab_count,
    lab.latest_hba1c,
    lab.latest_hba1c_date,
    lab.hba1c_source_lab_id                                 AS evidence_hba1c_lab_id,
    lab.latest_ldl,
    lab.latest_ldl_date,
    lab.ldl_source_lab_id                                   AS evidence_ldl_lab_id,
    lab.latest_creatinine,
    lab.latest_creatinine_date,
    lab.creatinine_source_lab_id                            AS evidence_creatinine_lab_id,
    lab.latest_glucose,
    lab.latest_glucose_date,
    lab.glucose_source_lab_id                               AS evidence_glucose_lab_id,
    lab.last_lab_date,

    -- Medication summary
    COALESCE(ms.active_medication_count, 0)                 AS active_medication_count,
    ms.active_medications_list,
    ms.active_drug_classes,
    COALESCE(ms.active_drug_class_count, 0)                 AS active_drug_class_count,
    ms.source_active_medication_ids                         AS evidence_active_medication_ids,

    -- Medication gaps
    COALESCE(mg.medication_gap_count, 0)                    AS medication_gap_count,
    COALESCE(mg.high_priority_med_gaps, 0)                  AS high_priority_medication_gaps,

    -- Visit summary
    COALESCE(vs.total_visits, 0)                            AS total_visits,
    COALESCE(vs.ed_visit_count, 0)                          AS ed_visit_count,
    COALESCE(vs.inpatient_count, 0)                         AS inpatient_count,
    COALESCE(vs.ambulatory_count, 0)                        AS ambulatory_count,
    vs.last_visit_date,
    vs.last_visit_type,
    vs.last_visit_provider,
    vs.last_visit_complaint,
    vs.last_visit_diagnosis,
    vs.days_since_last_visit,
    vs.recent_visits_summary,
    vs.last_visit_id                                        AS evidence_last_visit_id,

    -- Claims summary
    COALESCE(vs.total_billed, 0)                            AS total_billed,
    COALESCE(vs.total_paid, 0)                              AS total_paid,
    COALESCE(vs.total_claims, 0)                            AS total_claims,
    COALESCE(vs.denied_claim_count, 0)                      AS denied_claim_count,

    -- Follow-up gaps
    COALESCE(fg.followup_gap_count, 0)                      AS followup_gap_count,
    COALESCE(fg.high_priority_followup_gaps, 0)             AS high_priority_followup_gaps,
    fg.followup_gap_types,

    -- Composite risk signal
    CASE
        WHEN COALESCE(mg.high_priority_med_gaps, 0)
           + COALESCE(fg.high_priority_followup_gaps, 0) >= 2
            THEN 'HIGH'
        WHEN COALESCE(mg.medication_gap_count, 0)
           + COALESCE(fg.followup_gap_count, 0) >= 2
            THEN 'MEDIUM'
        WHEN COALESCE(mg.medication_gap_count, 0)
           + COALESCE(fg.followup_gap_count, 0) >= 1
            THEN 'LOW'
        ELSE 'NONE'
    END                                                     AS care_gap_risk_level

FROM RAW.PATIENTS p
LEFT JOIN PATIENT_DIAGNOSIS_SUMMARY dx  ON p.patient_id = dx.patient_id
LEFT JOIN PATIENT_LAB_SUMMARY       lab ON p.patient_id = lab.patient_id
LEFT JOIN med_summary               ms  ON p.patient_id = ms.patient_id
LEFT JOIN med_gap_summary           mg  ON p.patient_id = mg.patient_id
LEFT JOIN PATIENT_VISIT_SUMMARY     vs  ON p.patient_id = vs.patient_id
LEFT JOIN followup_gap_summary      fg  ON p.patient_id = fg.patient_id;
