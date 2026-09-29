-- PATIENT360 semantic-view preparation
-- Candidate business-facing views intended as stable inputs for a future semantic view.

CREATE OR REPLACE VIEW PATIENT360.ANALYTICS.SEM_PATIENT_OVERVIEW AS
SELECT
    patient_id,
    first_name,
    last_name,
    age,
    gender,
    total_visits,
    total_prescriptions,
    total_labs,
    total_claims,
    denied_claim_count,
    total_notes,
    total_diagnostic_reports,
    latest_visit_date,
    latest_lab_date,
    latest_note_date,
    latest_report_date
FROM PATIENT360.CURATED.CURATED_PATIENT_RECORD;

CREATE OR REPLACE VIEW PATIENT360.ANALYTICS.SEM_ENCOUNTER_OVERVIEW AS
SELECT
    visit_id,
    patient_id,
    doctor_id,
    visit_date,
    visit_type,
    diagnosis_code,
    diagnosis_description,
    lab_result_count,
    prescription_count,
    claim_count,
    note_count,
    diagnostic_report_count
FROM PATIENT360.CURATED.CURATED_ENCOUNTER_SUMMARY;