-- PATIENT360 Curation Logic
-- Canonical database target: PATIENT360
-- This file defines the CURATED and ANALYTICS curation strategy for the
-- synthetic healthcare dataset under synthetic-healthcare-data/.

-- -----------------------------------------------------------------------------
-- Naming and layer strategy
-- -----------------------------------------------------------------------------
-- CURATED holds canonical patient-centered business entities.
-- ANALYTICS holds broader cohort metrics and downstream derived summaries.
-- No new CARE360_DB references may be introduced in forward-looking artifacts.

-- -----------------------------------------------------------------------------
-- Source-to-curated mapping
-- -----------------------------------------------------------------------------
-- PATIENTS                -> CURATED_PATIENT_RECORD
-- VISITS                  -> CURATED_ENCOUNTER_SUMMARY
-- PRESCRIPTIONS           -> CURATED_MEDICATION_EVIDENCE_SUMMARY
-- LAB_RESULTS             -> CURATED_LAB_MONITORING_SUMMARY
-- INSURANCE_CLAIMS        -> CURATED_CARE_GAP_SIGNAL (via utilization / missing evidence)
-- CLINICAL_NOTES          -> CURATED_EVIDENCE_ASSET
-- DIAGNOSTIC_REPORTS      -> CURATED_EVIDENCE_ASSET
-- Timeline across all     -> CURATED_PATIENT_TIMELINE_EVENT

-- -----------------------------------------------------------------------------
-- Provenance and traceability rules
-- -----------------------------------------------------------------------------
-- Every curated entity should preserve:
--   * patient_id
--   * source record identifiers
--   * source event or document date
--   * source asset file name where relevant
--   * enough context to drill back into raw sources

-- -----------------------------------------------------------------------------
-- CURATED_PATIENT_RECORD
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_PATIENT_RECORD AS
WITH visit_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_visits,
        MIN(visit_date) AS first_visit_date,
        MAX(visit_date) AS latest_visit_date,
        MAX(diagnosis_code) AS latest_diagnosis_code,
        MAX(diagnosis_description) AS latest_diagnosis_description
    FROM PATIENT360.RAW.VISITS
    GROUP BY patient_id
),
med_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_prescriptions,
        MAX(prescription_date) AS latest_prescription_date
    FROM PATIENT360.RAW.PRESCRIPTIONS
    GROUP BY patient_id
),
lab_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_labs,
        MAX(test_date) AS latest_lab_date,
        COUNT_IF(critical_flag) AS critical_lab_count
    FROM PATIENT360.RAW.LAB_RESULTS
    GROUP BY patient_id
),
claim_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_claims,
        SUM(COALESCE(billed_amount, 0)) AS total_billed_amount,
        SUM(COALESCE(insurance_paid, 0)) AS total_paid_amount,
        SUM(IFF(claim_status = 'Denied', 1, 0)) AS denied_claim_count
    FROM PATIENT360.RAW.INSURANCE_CLAIMS
    GROUP BY patient_id
),
evidence_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_notes,
        MAX(note_date) AS latest_note_date
    FROM PATIENT360.RAW.CLINICAL_NOTES
    GROUP BY patient_id
),
report_summary AS (
    SELECT
        patient_id,
        COUNT(*) AS total_diagnostic_reports,
        MAX(exam_date) AS latest_report_date
    FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
    GROUP BY patient_id
)
SELECT
    p.patient_id,
    p.first_name,
    p.last_name,
    p.date_of_birth,
    p.age,
    p.gender,
    p.ethnicity,
    p.blood_type,
    p.insurance_provider,
    p.insurance_policy_number,
    COALESCE(v.total_visits, 0) AS total_visits,
    v.first_visit_date,
    v.latest_visit_date,
    v.latest_diagnosis_code,
    v.latest_diagnosis_description,
    COALESCE(m.total_prescriptions, 0) AS total_prescriptions,
    m.latest_prescription_date,
    COALESCE(l.total_labs, 0) AS total_labs,
    l.latest_lab_date,
    COALESCE(l.critical_lab_count, 0) AS critical_lab_count,
    COALESCE(c.total_claims, 0) AS total_claims,
    COALESCE(c.total_billed_amount, 0) AS total_billed_amount,
    COALESCE(c.total_paid_amount, 0) AS total_paid_amount,
    COALESCE(c.denied_claim_count, 0) AS denied_claim_count,
    COALESCE(e.total_notes, 0) AS total_notes,
    e.latest_note_date,
    COALESCE(r.total_diagnostic_reports, 0) AS total_diagnostic_reports,
    r.latest_report_date,
    'PATIENTS' AS source_root_table,
    p.patient_id AS source_patient_record_id
FROM PATIENT360.RAW.PATIENTS p
LEFT JOIN visit_summary v ON p.patient_id = v.patient_id
LEFT JOIN med_summary m ON p.patient_id = m.patient_id
LEFT JOIN lab_summary l ON p.patient_id = l.patient_id
LEFT JOIN claim_summary c ON p.patient_id = c.patient_id
LEFT JOIN evidence_summary e ON p.patient_id = e.patient_id
LEFT JOIN report_summary r ON p.patient_id = r.patient_id;

-- -----------------------------------------------------------------------------
-- CURATED_ENCOUNTER_SUMMARY
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_ENCOUNTER_SUMMARY AS
SELECT
    v.visit_id,
    v.patient_id,
    v.doctor_id,
    v.visit_date,
    v.visit_time,
    v.visit_type,
    v.chief_complaint,
    v.diagnosis_code,
    v.diagnosis_description,
    v.treatment_plan,
    v.follow_up_required,
    v.follow_up_date,
    COUNT(DISTINCT l.lab_result_id) AS lab_result_count,
    COUNT(DISTINCT p.prescription_id) AS prescription_count,
    COUNT(DISTINCT c.claim_id) AS claim_count,
    COUNT(DISTINCT n.note_id) AS note_count,
    COUNT(DISTINCT d.report_id) AS diagnostic_report_count,
    MIN(l.test_date) AS first_lab_date,
    MAX(l.test_date) AS latest_lab_date,
    MAX(n.note_date) AS latest_note_date,
    MAX(d.exam_date) AS latest_report_date,
    v.visit_id AS source_visit_id
FROM PATIENT360.RAW.VISITS v
LEFT JOIN PATIENT360.RAW.LAB_RESULTS l ON v.visit_id = l.visit_id
LEFT JOIN PATIENT360.RAW.PRESCRIPTIONS p ON v.visit_id = p.visit_id
LEFT JOIN PATIENT360.RAW.INSURANCE_CLAIMS c ON v.visit_id = c.visit_id
LEFT JOIN PATIENT360.RAW.CLINICAL_NOTES n ON v.visit_id = n.visit_id
LEFT JOIN PATIENT360.RAW.DIAGNOSTIC_REPORTS d ON v.visit_id = d.visit_id
GROUP BY
    v.visit_id,
    v.patient_id,
    v.doctor_id,
    v.visit_date,
    v.visit_time,
    v.visit_type,
    v.chief_complaint,
    v.diagnosis_code,
    v.diagnosis_description,
    v.treatment_plan,
    v.follow_up_required,
    v.follow_up_date;

-- -----------------------------------------------------------------------------
-- CURATED_MEDICATION_EVIDENCE_SUMMARY
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_MEDICATION_EVIDENCE_SUMMARY AS
WITH prior_labs AS (
    SELECT
        p.prescription_id,
        l.lab_result_id,
        l.test_type,
        l.test_date,
        ROW_NUMBER() OVER (
            PARTITION BY p.prescription_id
            ORDER BY l.test_date DESC, l.lab_result_id DESC
        ) AS lab_rank
    FROM PATIENT360.RAW.PRESCRIPTIONS p
    LEFT JOIN PATIENT360.RAW.LAB_RESULTS l
        ON p.patient_id = l.patient_id
       AND l.test_date <= p.prescription_date
),
note_context AS (
    SELECT
        visit_id,
        MAX(note_id) AS note_id,
        MAX(note_type) AS note_type,
        MAX(summary) AS note_summary
    FROM PATIENT360.RAW.CLINICAL_NOTES
    GROUP BY visit_id
)
SELECT
    p.prescription_id,
    p.patient_id,
    p.visit_id,
    p.doctor_id,
    p.prescription_date,
    p.medication_name,
    p.ndc_code,
    p.dosage,
    p.frequency,
    p.duration,
    p.refills,
    p.pdf_filename,
    IFF(COALESCE(p.refills, 0) > 0, 'ACTIVE_OR_REFILLABLE', 'LIMITED_SUPPLY') AS medication_status,
    l.lab_result_id AS latest_prior_lab_result_id,
    l.test_type AS latest_prior_lab_test_type,
    l.test_date AS latest_prior_lab_test_date,
    n.note_id AS supporting_note_id,
    n.note_type AS supporting_note_type,
    n.note_summary AS supporting_note_summary,
    p.prescription_id AS source_prescription_id
FROM PATIENT360.RAW.PRESCRIPTIONS p
LEFT JOIN prior_labs l
    ON p.prescription_id = l.prescription_id
   AND l.lab_rank = 1
LEFT JOIN note_context n
    ON p.visit_id = n.visit_id;

-- -----------------------------------------------------------------------------
-- CURATED_LAB_MONITORING_SUMMARY
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_LAB_MONITORING_SUMMARY AS
SELECT
    lab_result_id,
    patient_id,
    visit_id,
    center_id,
    test_date,
    test_type,
    test_code,
    pdf_filename,
    ordered_by_doctor_id,
    status,
    critical_flag,
    ROW_NUMBER() OVER (PARTITION BY patient_id, test_type ORDER BY test_date DESC, lab_result_id DESC) AS recency_rank,
    COUNT(*) OVER (PARTITION BY patient_id, test_type) AS total_results_for_test_type,
    MAX(test_date) OVER (PARTITION BY patient_id, test_type) AS latest_test_date_for_type,
    lab_result_id AS source_lab_result_id
FROM PATIENT360.RAW.LAB_RESULTS;

-- -----------------------------------------------------------------------------
-- CURATED_CARE_GAP_SIGNAL
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_CARE_GAP_SIGNAL AS
WITH visit_frequency AS (
    SELECT patient_id, COUNT(*) AS visit_count, MAX(visit_date) AS latest_visit_date
    FROM PATIENT360.RAW.VISITS
    GROUP BY patient_id
),
lab_frequency AS (
    SELECT patient_id, COUNT(*) AS lab_count, MAX(test_date) AS latest_lab_date
    FROM PATIENT360.RAW.LAB_RESULTS
    GROUP BY patient_id
),
claim_denials AS (
    SELECT patient_id, SUM(IFF(claim_status = 'Denied', 1, 0)) AS denied_claim_count
    FROM PATIENT360.RAW.INSURANCE_CLAIMS
    GROUP BY patient_id
),
note_frequency AS (
    SELECT patient_id, COUNT(*) AS note_count
    FROM PATIENT360.RAW.CLINICAL_NOTES
    GROUP BY patient_id
)
SELECT
    p.patient_id,
    CASE
        WHEN COALESCE(l.lab_count, 0) = 0 THEN 'MISSING_LAB_EVIDENCE'
        WHEN COALESCE(v.visit_count, 0) >= 6 THEN 'HIGH_UTILIZATION'
        WHEN COALESCE(c.denied_claim_count, 0) > 0 THEN 'CLAIM_FRICTION'
        WHEN COALESCE(n.note_count, 0) = 0 THEN 'MISSING_CLINICAL_NOTES'
        ELSE 'MONITORING_PRESENT'
    END AS gap_category,
    CASE
        WHEN COALESCE(l.lab_count, 0) = 0 THEN 'No lab evidence available'
        WHEN COALESCE(v.visit_count, 0) >= 6 THEN 'High encounter volume requires review'
        WHEN COALESCE(c.denied_claim_count, 0) > 0 THEN 'One or more claims were denied'
        WHEN COALESCE(n.note_count, 0) = 0 THEN 'No clinical notes available for review'
        ELSE 'Evidence and monitoring records are present'
    END AS gap_description,
    CASE
        WHEN COALESCE(l.lab_count, 0) = 0 THEN 'HIGH'
        WHEN COALESCE(v.visit_count, 0) >= 6 THEN 'HIGH'
        WHEN COALESCE(c.denied_claim_count, 0) > 0 THEN 'MEDIUM'
        WHEN COALESCE(n.note_count, 0) = 0 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS gap_priority,
    v.latest_visit_date,
    l.latest_lab_date,
    COALESCE(c.denied_claim_count, 0) AS denied_claim_count,
    COALESCE(v.visit_count, 0) AS total_visit_count,
    COALESCE(n.note_count, 0) AS total_note_count,
    p.patient_id AS source_patient_record_id
FROM PATIENT360.RAW.PATIENTS p
LEFT JOIN visit_frequency v ON p.patient_id = v.patient_id
LEFT JOIN lab_frequency l ON p.patient_id = l.patient_id
LEFT JOIN claim_denials c ON p.patient_id = c.patient_id;

-- -----------------------------------------------------------------------------
-- CURATED_EVIDENCE_ASSET
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_EVIDENCE_ASSET AS
SELECT
    note_id AS evidence_asset_id,
    patient_id,
    visit_id,
    'CLINICAL_NOTE' AS asset_type,
    pdf_filename AS source_asset_name,
    note_date AS source_event_date,
    note_type AS asset_subtype,
    summary AS asset_summary,
    NULL AS modality,
    NULL AS body_part,
    note_id AS source_record_id
FROM PATIENT360.RAW.CLINICAL_NOTES

UNION ALL

SELECT
    report_id AS evidence_asset_id,
    patient_id,
    visit_id,
    'DIAGNOSTIC_REPORT' AS asset_type,
    image_filename AS source_asset_name,
    exam_date AS source_event_date,
    exam_type AS asset_subtype,
    impression AS asset_summary,
    modality,
    body_part,
    report_id AS source_record_id
FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS

UNION ALL

SELECT
    lab_result_id AS evidence_asset_id,
    patient_id,
    visit_id,
    'LAB_DOCUMENT' AS asset_type,
    pdf_filename AS source_asset_name,
    test_date AS source_event_date,
    test_type AS asset_subtype,
    status AS asset_summary,
    NULL AS modality,
    NULL AS body_part,
    lab_result_id AS source_record_id
FROM PATIENT360.RAW.LAB_RESULTS

UNION ALL

SELECT
    prescription_id AS evidence_asset_id,
    patient_id,
    visit_id,
    'PRESCRIPTION' AS asset_type,
    pdf_filename AS source_asset_name,
    prescription_date AS source_event_date,
    medication_name AS asset_subtype,
    dosage || ' / ' || frequency AS asset_summary,
    NULL AS modality,
    NULL AS body_part,
    prescription_id AS source_record_id
FROM PATIENT360.RAW.PRESCRIPTIONS;

-- -----------------------------------------------------------------------------
-- CURATED_PATIENT_TIMELINE_EVENT
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_PATIENT_TIMELINE_EVENT AS
SELECT patient_id, visit_id AS event_id, 'VISIT' AS event_type, visit_date AS event_date,
       chief_complaint AS event_summary, visit_id AS linked_record_id
FROM PATIENT360.RAW.VISITS

UNION ALL

SELECT patient_id, lab_result_id AS event_id, 'LAB_RESULT' AS event_type, test_date AS event_date,
       test_type AS event_summary, visit_id AS linked_record_id
FROM PATIENT360.RAW.LAB_RESULTS

UNION ALL

SELECT patient_id, prescription_id AS event_id, 'PRESCRIPTION' AS event_type, prescription_date AS event_date,
       medication_name AS event_summary, visit_id AS linked_record_id
FROM PATIENT360.RAW.PRESCRIPTIONS

UNION ALL

SELECT patient_id, claim_id AS event_id, 'CLAIM' AS event_type, claim_date AS event_date,
       procedure_description AS event_summary, visit_id AS linked_record_id
FROM PATIENT360.RAW.INSURANCE_CLAIMS

UNION ALL

SELECT patient_id, note_id AS event_id, 'CLINICAL_NOTE' AS event_type, note_date AS event_date,
       note_type AS event_summary, visit_id AS linked_record_id
FROM PATIENT360.RAW.CLINICAL_NOTES

UNION ALL

SELECT patient_id, report_id AS event_id, 'DIAGNOSTIC_REPORT' AS event_type, exam_date AS event_date,
       exam_type || ' ' || body_part AS event_summary, visit_id AS linked_record_id
FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS;

-- -----------------------------------------------------------------------------
-- Validation queries
-- -----------------------------------------------------------------------------
-- 1. Confirm no forward-looking CARE360_DB references remain in this file.
-- 2. Validate one row per patient in CURATED_PATIENT_RECORD.
-- 3. Validate encounter-level child counts in CURATED_ENCOUNTER_SUMMARY.
-- 4. Validate timeline ordering by patient_id, event_date, event_type.
-- 5. Validate evidence assets for report/image linkage by patient and visit.