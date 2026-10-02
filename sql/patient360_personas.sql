-- PATIENT360 Persona Access Layer
-- Canonical database target: PATIENT360
--
-- Purpose
--   Gives each of the four constitutional personas (see .specify/memory/constitution.md,
--   "Target Users & Required Outcomes") a data surface that contains ONLY the columns
--   that persona is permitted to see, and a persona-scoped semantic view so that
--   Cortex Analyst physically cannot return a restricted field.
--
-- Layer boundary (Principle V)
--   This file creates objects in ANALYTICS only. Every persona view reads from
--   CURATED or ANALYTICS. No persona view reads PATIENT360.RAW directly.
--
-- Enforcement model
--   Restriction is achieved by COLUMN ABSENCE, not by app-side hiding: a column a
--   persona may not see is not projected by that persona's secure view, so it cannot
--   appear in a Cortex Analyst result, a Streamlit dataframe, or an export.
--   Views are SECURE so the view text and underlying data are not exposed to
--   non-owner roles via SHOW/GET_DDL or query-plan side channels.
--
-- Known limitation (carried forward from docs/architecture.md section 5.5)
--   This account has one working role (CARE360_RW_ROLE), so a role that holds SELECT
--   on PATIENT360.RAW can still read excluded columns directly. The persona layer is
--   the minimum-necessary boundary the application honours; ROW ACCESS POLICY is not
--   available on this account edition. PERSONA_ROLE_MAP below is the activation point
--   for real RBAC: populate it with dedicated roles and the resolver enforces them
--   with no application change.
--
-- Safety posture: findings for clinician review only. No diagnosis, no prognosis,
-- no treatment recommendation. Synthetic data only (Principle IV).

USE DATABASE PATIENT360;

-- =============================================================================
-- 1. Persona registry
-- =============================================================================
-- Declarative description of each persona and the access tier it operates under.
-- Seeded with MERGE so this script is safely re-runnable (no duplicate personas).

CREATE TABLE IF NOT EXISTS PATIENT360.ANALYTICS.PERSONA_REGISTRY (
    persona_code            STRING      NOT NULL,
    display_name            STRING      NOT NULL,
    role_description        STRING,
    identity_tier           STRING      NOT NULL,
    document_text_access    BOOLEAN     NOT NULL,
    allowed_doc_categories  STRING      NOT NULL,
    semantic_view_name      STRING      NOT NULL,
    minimum_necessary_note  STRING,
    CONSTRAINT pk_persona_registry PRIMARY KEY (persona_code)
)
COMMENT = 'Registry of the four constitutional personas. identity_tier values are IDENTIFIED (may see patient name), DEIDENTIFIED (patient_id only), and COHORT (patient_id plus age band only). document_text_access FALSE means the persona sees document metadata and citations but never document body text.';

MERGE INTO PATIENT360.ANALYTICS.PERSONA_REGISTRY AS t
USING (
    SELECT * FROM VALUES
        ('CARE_COORDINATOR',
         'Clinical Care Coordinator',
         'Manages care plans across providers',
         'IDENTIFIED',
         TRUE,
         'CLINICAL_NOTE,LAB_DOCUMENT,PRESCRIPTION,DIAGNOSTIC_IMAGE',
         'PATIENT360.ANALYTICS.PATIENT360_SEM_CARE_COORDINATOR',
         'Treating care team. Needs full identified longitudinal record including clinical narrative to coordinate care across providers.'),
        ('QUALITY_ANALYST',
         'Quality & Compliance Analyst',
         'Audits clinical documentation for regulatory adherence',
         'DEIDENTIFIED',
         FALSE,
         'CLINICAL_NOTE,LAB_DOCUMENT,PRESCRIPTION,DIAGNOSTIC_IMAGE',
         'PATIENT360.ANALYTICS.PATIENT360_SEM_QUALITY_ANALYST',
         'Audits whether documentation exists and is traceable, not what it says clinically. Receives document metadata and citation pointers but no document body text, no patient name, and no clinical free text.'),
        ('POPULATION_HEALTH',
         'Population Health Manager',
         'Identifies at-risk cohorts and care gaps',
         'COHORT',
         FALSE,
         '',
         'PATIENT360.ANALYTICS.PATIENT360_SEM_POPULATION_HEALTH',
         'Works at cohort level. Receives no patient name, no exact age (age band only), no clinical narrative, no claims, and no document evidence. Patient identifier is retained solely so an identified persona can act on a flagged cohort member.'),
        ('PHARMACIST',
         'Clinical Pharmacist',
         'Reviews medication safety and interactions',
         'IDENTIFIED',
         TRUE,
         'PRESCRIPTION,LAB_DOCUMENT,CLINICAL_NOTE',
         'PATIENT360.ANALYTICS.PATIENT360_SEM_PHARMACIST',
         'Verifies medication safety against labs on an identified patient. Receives full medication and lab detail and the claim denial signal that predicts medication abandonment, but not imaging evidence and not claim financial data.')
    AS s (persona_code, display_name, role_description, identity_tier, document_text_access,
          allowed_doc_categories, semantic_view_name, minimum_necessary_note)
) AS s
ON t.persona_code = s.persona_code
WHEN MATCHED THEN UPDATE SET
    t.display_name = s.display_name,
    t.role_description = s.role_description,
    t.identity_tier = s.identity_tier,
    t.document_text_access = s.document_text_access,
    t.allowed_doc_categories = s.allowed_doc_categories,
    t.semantic_view_name = s.semantic_view_name,
    t.minimum_necessary_note = s.minimum_necessary_note
WHEN NOT MATCHED THEN INSERT
    (persona_code, display_name, role_description, identity_tier, document_text_access,
     allowed_doc_categories, semantic_view_name, minimum_necessary_note)
VALUES
    (s.persona_code, s.display_name, s.role_description, s.identity_tier, s.document_text_access,
     s.allowed_doc_categories, s.semantic_view_name, s.minimum_necessary_note);

-- =============================================================================
-- 2. Role -> persona mapping (RBAC activation point)
-- =============================================================================
-- Left intentionally EMPTY in the synthetic phase. The application resolver checks
-- this table first; when a deployment creates dedicated roles (for example
-- CARE360_COORDINATOR_ROLE), inserting one row per role switches the application
-- from selector-driven personas to role-enforced personas with no code change.

CREATE TABLE IF NOT EXISTS PATIENT360.ANALYTICS.PERSONA_ROLE_MAP (
    snowflake_role  STRING NOT NULL,
    persona_code    STRING NOT NULL,
    assigned_on     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_persona_role_map PRIMARY KEY (snowflake_role)
)
COMMENT = 'Maps a Snowflake role to a persona. Empty during the synthetic-data phase because the account has a single working role. Populating this table activates role-enforced persona resolution (constitution: Structural Compliance Requirements / Access Control).';

-- =============================================================================
-- 3. Immutable access audit log
-- =============================================================================
-- Constitution, Audit Logging: every access to patient data is logged with
-- timestamp, user identity, action, patient identifier, and session identifier.
-- The application only ever INSERTs here. No UPDATE or DELETE path is provided,
-- and no view or procedure in this project exposes one.
-- NOTE: log content is metadata only. Per "No PHI in logs", we record the
-- synthetic patient_id and the question text but never patient names or clinical values.

CREATE TABLE IF NOT EXISTS PATIENT360.ANALYTICS.APP_ACCESS_AUDIT (
    audit_id            NUMBER IDENTITY(1,1),
    event_at            TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    session_id          STRING,
    user_identity       STRING        NOT NULL,
    active_role         STRING,
    persona_code        STRING        NOT NULL,
    persona_resolution  STRING,
    action              STRING        NOT NULL,
    target_object       STRING,
    patient_id          STRING,
    question_text       STRING,
    row_count           NUMBER,
    outcome             STRING,
    CONSTRAINT pk_app_access_audit PRIMARY KEY (audit_id)
)
COMMENT = 'Append-only audit trail of persona-scoped access to PATIENT360 patient data. Insert-only by design: no UPDATE or DELETE path is provided by the application (constitution: Audit Logging, immutability + 6-year retention).';

-- =============================================================================
-- 4. Persona-scoped secure views
-- =============================================================================
-- Naming: PERSONA_<persona abbreviation>_<entity>
--   CC = Clinical Care Coordinator, QA = Quality & Compliance Analyst,
--   PH = Population Health Manager, RX = Clinical Pharmacist

-- -----------------------------------------------------------------------------
-- 4.1 Clinical Care Coordinator (IDENTIFIED, full clinical narrative)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_PATIENT
COMMENT = 'Care Coordinator patient surface. Identified: name is exposed because the coordinator is on the treating care team and must contact providers about a named patient.'
AS
SELECT
    patient_id,
    first_name,
    last_name,
    age,
    gender,
    total_visits,
    total_labs,
    total_prescriptions,
    total_claims,
    critical_lab_count,
    total_evidence_assets,
    searchable_evidence_assets,
    broken_evidence_assets,
    total_chunks,
    latest_evidence_date,
    evidence_readiness_status
FROM PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_ENCOUNTER
COMMENT = 'Care Coordinator encounter surface. Includes chief complaint, treatment plan, and follow-up status because care-plan coordination is this persona primary job.'
AS
SELECT
    visit_id,
    patient_id,
    doctor_id,
    visit_date,
    visit_type,
    chief_complaint,
    diagnosis_code,
    diagnosis_description,
    treatment_plan,
    follow_up_required,
    follow_up_date,
    lab_result_count,
    prescription_count,
    claim_count,
    note_count,
    diagnostic_report_count,
    latest_note_date,
    latest_report_date
FROM PATIENT360.CURATED.CURATED_ENCOUNTER_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_MEDICATION
COMMENT = 'Care Coordinator medication surface. Answers "what is this patient on and when was it last adjusted".'
AS
SELECT
    prescription_id,
    patient_id,
    visit_id,
    doctor_id,
    prescription_date,
    medication_name,
    dosage,
    frequency,
    duration,
    refills,
    medication_status,
    latest_prior_lab_test_type,
    latest_prior_lab_test_date,
    supporting_note_type
FROM PATIENT360.CURATED.CURATED_MEDICATION_EVIDENCE_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_LAB
COMMENT = 'Care Coordinator lab monitoring surface. Numeric result values are not present in structured data. They exist only in the lab report document text.'
AS
SELECT
    lab_result_id,
    patient_id,
    visit_id,
    test_date,
    test_type,
    test_code,
    status,
    critical_flag,
    ordered_by_doctor_id,
    recency_rank,
    total_results_for_test_type,
    latest_test_date_for_type
FROM PATIENT360.CURATED.CURATED_LAB_MONITORING_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_CLAIM
COMMENT = 'Care Coordinator claim surface. Clinical claim context only. Financial amounts and policy identifiers are excluded upstream in CURATED_CLAIM_CLINICAL_CONTEXT under HIPAA minimum-necessary.'
AS
SELECT
    claim_id,
    patient_id,
    visit_id,
    claim_date,
    diagnosis_code,
    procedure_code,
    procedure_description,
    claim_status,
    denial_reason,
    is_denied,
    coverage_friction_flag,
    days_to_claim_decision
FROM PATIENT360.CURATED.CURATED_CLAIM_CLINICAL_CONTEXT;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_CARE_GAP
COMMENT = 'Care Coordinator care-gap surface with citation capability.'
AS
SELECT
    patient_id,
    gap_category,
    gap_description,
    gap_priority,
    latest_visit_date,
    latest_lab_date,
    denied_claim_count,
    total_visit_count,
    total_note_count,
    evidence_readiness_status,
    citation_capability
FROM PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_CC_EVIDENCE
COMMENT = 'Care Coordinator document evidence surface. Includes document body text because this persona reads the clinical narrative.'
AS
SELECT
    ingestion_asset_id,
    patient_id,
    visit_id,
    document_category,
    source_asset_name,
    source_event_date,
    canonical_stage_path,
    extraction_outcome_status,
    is_searchable_evidence,
    extracted_text_length,
    parsed_page_count,
    chunk_count,
    stage_file_present,
    evidence_text
FROM PATIENT360.CURATED.CURATED_DOCUMENT_EVIDENCE;

-- -----------------------------------------------------------------------------
-- 4.2 Quality & Compliance Analyst (DEIDENTIFIED, metadata only)
-- -----------------------------------------------------------------------------
-- Rationale: this persona audits whether documentation exists, is traceable, and
-- was extracted successfully. That is answerable from metadata. Therefore
-- first_name / last_name, chief_complaint, treatment_plan, dosage-level medication
-- detail, and evidence_text are NOT projected.

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_PATIENT
COMMENT = 'Quality Analyst patient surface. De-identified: patient name is NOT projected. Documentation audit does not require patient identity, only a traceable identifier.'
AS
SELECT
    patient_id,
    age,
    gender,
    total_visits,
    total_labs,
    total_prescriptions,
    total_claims,
    critical_lab_count,
    total_evidence_assets,
    searchable_evidence_assets,
    searchable_notes,
    searchable_lab_docs,
    searchable_prescriptions,
    searchable_imaging,
    broken_evidence_assets,
    total_chunks,
    latest_evidence_date,
    evidence_readiness_status
FROM PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_ENCOUNTER
COMMENT = 'Quality Analyst encounter surface. Coded diagnosis and documentation counts only. Clinical free text (chief_complaint, treatment_plan) is NOT projected because a documentation audit is satisfied by coded fields and record counts.'
AS
SELECT
    visit_id,
    patient_id,
    visit_date,
    visit_type,
    diagnosis_code,
    diagnosis_description,
    follow_up_required,
    follow_up_date,
    lab_result_count,
    prescription_count,
    claim_count,
    note_count,
    diagnostic_report_count
FROM PATIENT360.CURATED.CURATED_ENCOUNTER_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_LAB
COMMENT = 'Quality Analyst lab monitoring surface. Supports "show evidence of HbA1c monitoring" and "which patients are missing follow-up labs".'
AS
SELECT
    lab_result_id,
    patient_id,
    visit_id,
    test_date,
    test_type,
    test_code,
    status,
    critical_flag,
    recency_rank,
    total_results_for_test_type,
    latest_test_date_for_type
FROM PATIENT360.CURATED.CURATED_LAB_MONITORING_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_CLAIM
COMMENT = 'Quality Analyst claim surface. Coded and status fields for regulatory adherence review. Financial and policy columns are excluded upstream.'
AS
SELECT
    claim_id,
    patient_id,
    visit_id,
    claim_date,
    diagnosis_code,
    procedure_code,
    claim_status,
    denial_reason,
    is_denied,
    coverage_friction_flag,
    days_to_claim_decision
FROM PATIENT360.CURATED.CURATED_CLAIM_CLINICAL_CONTEXT;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_CARE_GAP
COMMENT = 'Quality Analyst care-gap surface, including whether a gap can be substantiated with a citable document.'
AS
SELECT
    patient_id,
    gap_category,
    gap_description,
    gap_priority,
    latest_visit_date,
    latest_lab_date,
    denied_claim_count,
    total_visit_count,
    total_note_count,
    searchable_notes,
    searchable_lab_docs,
    broken_evidence_assets,
    evidence_readiness_status,
    citation_capability
FROM PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_EVIDENCE
COMMENT = 'Quality Analyst document evidence surface. METADATA ONLY: evidence_text is deliberately NOT projected. The auditor verifies that a document exists, is linked, and produced searchable text. Reading the clinical narrative is beyond minimum necessary for that task.'
AS
SELECT
    ingestion_asset_id,
    patient_id,
    visit_id,
    document_category,
    source_asset_name,
    source_event_date,
    canonical_stage_path,
    match_status,
    processing_status,
    stage_file_present,
    extraction_mode,
    extraction_outcome_status,
    is_searchable_evidence,
    extracted_text_length,
    parsed_page_count,
    chunk_count
FROM PATIENT360.CURATED.CURATED_DOCUMENT_EVIDENCE;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_QA_INGESTION_QUALITY
COMMENT = 'Quality Analyst pipeline-quality surface. Aggregate only, no patient identifiers.'
AS
SELECT
    asset_family,
    total_assets,
    present_assets,
    missing_assets,
    searchable_assets,
    metadata_only_assets,
    failed_assets,
    searchable_pct,
    avg_extracted_text_length,
    chunk_count
FROM PATIENT360.ANALYTICS.ANALYTICS_INGESTION_QUALITY_SUMMARY;

-- -----------------------------------------------------------------------------
-- 4.3 Population Health Manager (COHORT, age-banded, no documents)
-- -----------------------------------------------------------------------------
-- Rationale: this persona sizes and ranks cohorts. Exact age is a re-identification
-- vector in a small population, so only a band is projected. Name, clinical
-- narrative, claims, and document evidence are not projected at all.
-- Age bands follow conventional population-health reporting brackets.

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_PH_PATIENT_COHORT
COMMENT = 'Population Health cohort surface. No patient name and no exact age: age is generalised to a band because exact age is a re-identification vector in a small cohort. patient_id is retained only so an identified persona can follow up on a flagged member.'
AS
SELECT
    patient_id,
    CASE
        WHEN age IS NULL      THEN 'UNKNOWN'
        WHEN age < 18         THEN '0-17'
        WHEN age BETWEEN 18 AND 34 THEN '18-34'
        WHEN age BETWEEN 35 AND 49 THEN '35-49'
        WHEN age BETWEEN 50 AND 64 THEN '50-64'
        WHEN age BETWEEN 65 AND 79 THEN '65-79'
        ELSE '80+'
    END AS age_band,
    gender,
    total_visits,
    total_labs,
    total_prescriptions,
    critical_lab_count,
    searchable_evidence_assets,
    evidence_readiness_status
FROM PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_PH_ENCOUNTER_COHORT
COMMENT = 'Population Health encounter surface. Supports utilisation questions such as "patients with more than two ED visits in 90 days". Clinical free text is not projected.'
AS
SELECT
    visit_id,
    patient_id,
    visit_date,
    visit_type,
    diagnosis_code,
    diagnosis_description,
    follow_up_required,
    lab_result_count,
    prescription_count
FROM PATIENT360.CURATED.CURATED_ENCOUNTER_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_PH_LAB_COHORT
COMMENT = 'Population Health lab surface. Test type, date, and critical flag support cohort monitoring. Threshold questions such as "A1c above 9 percent" are NOT answerable here: no numeric result value exists in structured data.'
AS
SELECT
    lab_result_id,
    patient_id,
    test_date,
    test_type,
    test_code,
    status,
    critical_flag,
    recency_rank,
    total_results_for_test_type,
    latest_test_date_for_type
FROM PATIENT360.CURATED.CURATED_LAB_MONITORING_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_PH_MEDICATION_COHORT
COMMENT = 'Population Health medication surface. Drug name and status support therapy-class cohorts. Dosage, frequency, NDC, and prescriber are NOT projected: they are dispensing detail, not cohort attributes.'
AS
SELECT
    prescription_id,
    patient_id,
    prescription_date,
    medication_name,
    medication_status
FROM PATIENT360.CURATED.CURATED_MEDICATION_EVIDENCE_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_PH_CARE_GAP
COMMENT = 'Population Health care-gap surface. The primary at-risk cohort signal for this persona.'
AS
SELECT
    patient_id,
    gap_category,
    gap_description,
    gap_priority,
    latest_visit_date,
    latest_lab_date,
    total_visit_count,
    total_note_count,
    evidence_readiness_status,
    citation_capability
FROM PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE;

-- -----------------------------------------------------------------------------
-- 4.4 Clinical Pharmacist (IDENTIFIED, medication and lab depth, no imaging)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_RX_PATIENT
COMMENT = 'Pharmacist patient surface. Identified: medication safety review and dispensing are performed against a named patient.'
AS
SELECT
    patient_id,
    first_name,
    last_name,
    age,
    gender,
    total_prescriptions,
    total_labs,
    critical_lab_count,
    total_visits,
    searchable_prescriptions,
    searchable_lab_docs,
    evidence_readiness_status
FROM PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_RX_MEDICATION
COMMENT = 'Pharmacist medication surface. Full dispensing detail plus the lab test most recently performed BEFORE each prescription, which answers "what labs were ordered before starting this medication" without a join.'
AS
SELECT
    prescription_id,
    patient_id,
    visit_id,
    doctor_id,
    prescription_date,
    medication_name,
    ndc_code,
    dosage,
    frequency,
    duration,
    refills,
    medication_status,
    latest_prior_lab_result_id,
    latest_prior_lab_test_type,
    latest_prior_lab_test_date,
    supporting_note_type,
    supporting_note_summary
FROM PATIENT360.CURATED.CURATED_MEDICATION_EVIDENCE_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_RX_LAB
COMMENT = 'Pharmacist lab surface. Full monitoring detail for interaction and organ-function checks. Numeric values live only in the lab report document text.'
AS
SELECT
    lab_result_id,
    patient_id,
    visit_id,
    test_date,
    test_type,
    test_code,
    status,
    critical_flag,
    ordered_by_doctor_id,
    recency_rank,
    total_results_for_test_type,
    latest_test_date_for_type
FROM PATIENT360.CURATED.CURATED_LAB_MONITORING_SUMMARY;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_RX_CLAIM
COMMENT = 'Pharmacist claim surface. Restricted to the coverage-friction signal: a denied or pending claim predicts medication abandonment, which is a pharmacy concern. Procedure narrative and decision latency are not projected.'
AS
SELECT
    claim_id,
    patient_id,
    visit_id,
    claim_date,
    procedure_code,
    claim_status,
    denial_reason,
    is_denied,
    coverage_friction_flag
FROM PATIENT360.CURATED.CURATED_CLAIM_CLINICAL_CONTEXT;

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_RX_EVIDENCE
COMMENT = 'Pharmacist document evidence surface. Filtered to prescription, lab, and clinical note documents. Diagnostic imaging is excluded because image interpretation is outside the pharmacy scope of practice.'
AS
SELECT
    ingestion_asset_id,
    patient_id,
    visit_id,
    document_category,
    source_asset_name,
    source_event_date,
    canonical_stage_path,
    extraction_outcome_status,
    is_searchable_evidence,
    extracted_text_length,
    chunk_count,
    stage_file_present,
    evidence_text
FROM PATIENT360.CURATED.CURATED_DOCUMENT_EVIDENCE
WHERE document_category IN ('PRESCRIPTION', 'LAB_DOCUMENT', 'CLINICAL_NOTE');

CREATE OR REPLACE SECURE VIEW PATIENT360.ANALYTICS.PERSONA_RX_CARE_GAP
COMMENT = 'Pharmacist care-gap surface, scoped to monitoring and claim-friction signals relevant to medication safety.'
AS
SELECT
    patient_id,
    gap_category,
    gap_description,
    gap_priority,
    latest_lab_date,
    denied_claim_count,
    evidence_readiness_status,
    citation_capability
FROM PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE;

-- =============================================================================
-- 5. Persona-scoped semantic views
-- =============================================================================
-- Each semantic view is built ONLY over that persona secure views. Cortex Analyst
-- therefore cannot generate SQL that reaches a restricted column: the column is not
-- in the model and not in the underlying view.
-- The shared PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC is left intact for
-- the existing agent and administrative path.

-- -----------------------------------------------------------------------------
-- 5.1 Clinical Care Coordinator
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW PATIENT360.ANALYTICS.PATIENT360_SEM_CARE_COORDINATOR
  TABLES (
    patients AS PATIENT360.ANALYTICS.PERSONA_CC_PATIENT
      PRIMARY KEY (patient_id)
      WITH SYNONYMS ('patient', 'people')
      COMMENT = 'One row per synthetic patient with utilisation counts and evidence readiness',
    encounters AS PATIENT360.ANALYTICS.PERSONA_CC_ENCOUNTER
      PRIMARY KEY (visit_id)
      WITH SYNONYMS ('visits', 'encounters', 'appointments')
      COMMENT = 'One row per clinical encounter including chief complaint and treatment plan',
    medications AS PATIENT360.ANALYTICS.PERSONA_CC_MEDICATION
      PRIMARY KEY (prescription_id)
      WITH SYNONYMS ('medications', 'drugs', 'prescriptions', 'meds')
      COMMENT = 'One row per prescription with dosage, frequency, and status',
    labs AS PATIENT360.ANALYTICS.PERSONA_CC_LAB
      PRIMARY KEY (lab_result_id)
      WITH SYNONYMS ('labs', 'lab results', 'tests')
      COMMENT = 'One row per lab result. Numeric result values are NOT present. They exist only in the lab report document text',
    claims AS PATIENT360.ANALYTICS.PERSONA_CC_CLAIM
      PRIMARY KEY (claim_id)
      WITH SYNONYMS ('claims', 'coverage')
      COMMENT = 'Clinical claim context only. Financial amounts and policy identifiers are deliberately excluded',
    care_gaps AS PATIENT360.ANALYTICS.PERSONA_CC_CARE_GAP
      PRIMARY KEY (patient_id, gap_category)
      WITH SYNONYMS ('gaps', 'care gaps')
      COMMENT = 'Care gap signals with citation capability',
    evidence AS PATIENT360.ANALYTICS.PERSONA_CC_EVIDENCE
      PRIMARY KEY (ingestion_asset_id)
      WITH SYNONYMS ('documents', 'evidence', 'files')
      COMMENT = 'One row per ingested clinical document with extraction status'
  )
  RELATIONSHIPS (
    encounters_to_patients AS encounters (patient_id) REFERENCES patients (patient_id),
    medications_to_patients AS medications (patient_id) REFERENCES patients (patient_id),
    labs_to_patients AS labs (patient_id) REFERENCES patients (patient_id),
    claims_to_patients AS claims (patient_id) REFERENCES patients (patient_id),
    care_gaps_to_patients AS care_gaps (patient_id) REFERENCES patients (patient_id),
    evidence_to_patients AS evidence (patient_id) REFERENCES patients (patient_id)
  )
  FACTS (
    patients.visit_count AS total_visits,
    patients.lab_count AS total_labs,
    patients.prescription_count AS total_prescriptions,
    patients.claim_count AS total_claims,
    patients.critical_labs AS critical_lab_count,
    patients.searchable_assets AS searchable_evidence_assets,
    encounters.lab_results AS lab_result_count,
    encounters.prescriptions AS prescription_count,
    medications.refill_count AS refills,
    labs.recency AS recency_rank,
    claims.decision_days AS days_to_claim_decision,
    evidence.chunks AS chunk_count
  )
  DIMENSIONS (
    patients.patient AS patient_id WITH SYNONYMS ('patient id') COMMENT = 'Synthetic patient identifier',
    patients.first_name AS first_name,
    patients.last_name AS last_name,
    patients.age AS age,
    patients.gender AS gender,
    patients.readiness AS evidence_readiness_status WITH SYNONYMS ('evidence coverage'),
    encounters.visit AS visit_id,
    encounters.visit_date AS visit_date WITH SYNONYMS ('date of visit'),
    encounters.visit_type AS visit_type WITH SYNONYMS ('encounter type'),
    encounters.diagnosis AS diagnosis_description,
    encounters.chief_complaint AS chief_complaint WITH SYNONYMS ('presenting problem'),
    encounters.treatment_plan AS treatment_plan WITH SYNONYMS ('plan of care'),
    encounters.follow_up_required AS follow_up_required,
    encounters.follow_up_date AS follow_up_date,
    medications.medication AS medication_name WITH SYNONYMS ('drug', 'drug name'),
    medications.dosage AS dosage,
    medications.frequency AS frequency,
    medications.duration AS duration,
    medications.medication_status AS medication_status WITH SYNONYMS ('active medication'),
    medications.prescribed_on AS prescription_date WITH SYNONYMS ('when prescribed', 'last adjusted'),
    medications.prior_lab_test AS latest_prior_lab_test_type,
    medications.prior_lab_date AS latest_prior_lab_test_date,
    labs.test AS test_type WITH SYNONYMS ('lab test', 'panel'),
    labs.test_date AS test_date,
    labs.lab_status AS status,
    labs.is_critical AS critical_flag WITH SYNONYMS ('critical result'),
    claims.claim AS claim_id,
    claims.claim_date AS claim_date,
    claims.procedure AS procedure_description,
    claims.claim_status AS claim_status,
    claims.denial_reason AS denial_reason WITH SYNONYMS ('why denied'),
    claims.is_denied AS is_denied,
    care_gaps.gap AS gap_category,
    care_gaps.gap_priority AS gap_priority,
    care_gaps.citation_capability AS citation_capability,
    evidence.asset AS ingestion_asset_id,
    evidence.category AS document_category WITH SYNONYMS ('document type'),
    evidence.file_name AS source_asset_name,
    evidence.event_date AS source_event_date,
    evidence.searchable AS is_searchable_evidence
  )
  METRICS (
    patients.patient_total AS COUNT(patients.patient_id) COMMENT = 'Number of patients',
    patients.avg_visits AS AVG(patients.total_visits) COMMENT = 'Average visits per patient',
    encounters.encounter_total AS COUNT(encounters.visit_id) COMMENT = 'Number of encounters',
    medications.medication_total AS COUNT(medications.prescription_id) COMMENT = 'Number of prescriptions',
    medications.distinct_medication_total AS COUNT(DISTINCT medications.medication_name)
      COMMENT = 'Number of distinct drugs prescribed',
    labs.lab_total AS COUNT(labs.lab_result_id) COMMENT = 'Number of lab results',
    labs.critical_lab_total AS SUM(IFF(labs.critical_flag, 1, 0)) COMMENT = 'Number of critical lab results',
    claims.claim_total AS COUNT(claims.claim_id) COMMENT = 'Number of claims',
    claims.denied_claim_total AS SUM(IFF(claims.is_denied, 1, 0)) COMMENT = 'Number of denied claims',
    care_gaps.gap_total AS COUNT(care_gaps.gap_category) COMMENT = 'Number of care gap signals',
    evidence.document_total AS COUNT(evidence.ingestion_asset_id) COMMENT = 'Number of ingested documents'
  )
  COMMENT = 'Persona-scoped semantic model for the Clinical Care Coordinator. Identified patient access with full clinical narrative and care-plan context. Claim financial amounts and policy identifiers are excluded. Synthetic data only. Findings for clinician review.';

-- -----------------------------------------------------------------------------
-- 5.2 Quality & Compliance Analyst
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW PATIENT360.ANALYTICS.PATIENT360_SEM_QUALITY_ANALYST
  TABLES (
    patients AS PATIENT360.ANALYTICS.PERSONA_QA_PATIENT
      PRIMARY KEY (patient_id)
      WITH SYNONYMS ('patient', 'members')
      COMMENT = 'De-identified patient row with documentation counts. Patient name is not available to this persona',
    encounters AS PATIENT360.ANALYTICS.PERSONA_QA_ENCOUNTER
      PRIMARY KEY (visit_id)
      WITH SYNONYMS ('visits', 'encounters')
      COMMENT = 'Encounter with coded diagnosis and documentation counts. Clinical free text is not available',
    labs AS PATIENT360.ANALYTICS.PERSONA_QA_LAB
      PRIMARY KEY (lab_result_id)
      WITH SYNONYMS ('labs', 'lab tests', 'monitoring')
      COMMENT = 'Lab monitoring evidence: test type, date, critical flag, recency',
    claims AS PATIENT360.ANALYTICS.PERSONA_QA_CLAIM
      PRIMARY KEY (claim_id)
      WITH SYNONYMS ('claims')
      COMMENT = 'Coded claim status for adherence review. Financial columns excluded',
    care_gaps AS PATIENT360.ANALYTICS.PERSONA_QA_CARE_GAP
      PRIMARY KEY (patient_id, gap_category)
      WITH SYNONYMS ('gaps', 'care gaps', 'missing follow up')
      COMMENT = 'Care gap signals with citation capability',
    evidence AS PATIENT360.ANALYTICS.PERSONA_QA_EVIDENCE
      PRIMARY KEY (ingestion_asset_id)
      WITH SYNONYMS ('documents', 'evidence', 'files', 'records')
      COMMENT = 'Document metadata and extraction outcome. Document body text is NOT available to this persona',
    pipeline_quality AS PATIENT360.ANALYTICS.PERSONA_QA_INGESTION_QUALITY
      PRIMARY KEY (asset_family)
      WITH SYNONYMS ('ingestion quality', 'pipeline health')
      COMMENT = 'Aggregate ingestion quality by asset family'
  )
  RELATIONSHIPS (
    encounters_to_patients AS encounters (patient_id) REFERENCES patients (patient_id),
    labs_to_patients AS labs (patient_id) REFERENCES patients (patient_id),
    claims_to_patients AS claims (patient_id) REFERENCES patients (patient_id),
    care_gaps_to_patients AS care_gaps (patient_id) REFERENCES patients (patient_id),
    evidence_to_patients AS evidence (patient_id) REFERENCES patients (patient_id)
  )
  FACTS (
    patients.visit_count AS total_visits,
    patients.lab_count AS total_labs,
    patients.claim_count AS total_claims,
    patients.critical_labs AS critical_lab_count,
    patients.evidence_assets AS total_evidence_assets,
    patients.searchable_assets AS searchable_evidence_assets,
    patients.broken_assets AS broken_evidence_assets,
    labs.recency AS recency_rank,
    labs.results_for_type AS total_results_for_test_type,
    claims.decision_days AS days_to_claim_decision,
    evidence.text_length AS extracted_text_length,
    evidence.chunks AS chunk_count,
    pipeline_quality.total_assets AS total_assets,
    pipeline_quality.searchable_assets AS searchable_assets,
    pipeline_quality.failed_assets AS failed_assets,
    pipeline_quality.searchable_pct AS searchable_pct
  )
  DIMENSIONS (
    patients.patient AS patient_id WITH SYNONYMS ('patient id') COMMENT = 'Synthetic patient identifier. Patient name is not exposed to this persona',
    patients.age AS age,
    patients.gender AS gender,
    patients.readiness AS evidence_readiness_status WITH SYNONYMS ('documentation coverage'),
    encounters.visit AS visit_id,
    encounters.visit_date AS visit_date,
    encounters.visit_type AS visit_type,
    encounters.diagnosis_code AS diagnosis_code WITH SYNONYMS ('icd10', 'icd-10'),
    encounters.diagnosis AS diagnosis_description,
    encounters.follow_up_required AS follow_up_required WITH SYNONYMS ('needs follow up'),
    encounters.follow_up_date AS follow_up_date,
    labs.test AS test_type WITH SYNONYMS ('lab test', 'panel', 'hba1c'),
    labs.test_code AS test_code WITH SYNONYMS ('loinc'),
    labs.test_date AS test_date,
    labs.lab_status AS status,
    labs.is_critical AS critical_flag WITH SYNONYMS ('critical result'),
    labs.latest_for_type AS latest_test_date_for_type WITH SYNONYMS ('most recent test date'),
    claims.claim AS claim_id,
    claims.claim_date AS claim_date,
    claims.claim_diagnosis_code AS diagnosis_code WITH SYNONYMS ('claim icd10'),
    claims.procedure_code AS procedure_code WITH SYNONYMS ('cpt'),
    claims.claim_status AS claim_status,
    claims.denial_reason AS denial_reason,
    claims.is_denied AS is_denied,
    care_gaps.gap AS gap_category,
    care_gaps.gap_priority AS gap_priority,
    care_gaps.citation_capability AS citation_capability WITH SYNONYMS ('can we cite evidence'),
    evidence.asset AS ingestion_asset_id,
    evidence.category AS document_category WITH SYNONYMS ('document type'),
    evidence.file_name AS source_asset_name WITH SYNONYMS ('file name', 'document name'),
    evidence.event_date AS source_event_date WITH SYNONYMS ('document date'),
    evidence.extraction_status AS extraction_outcome_status WITH SYNONYMS ('parse status'),
    evidence.searchable AS is_searchable_evidence,
    evidence.present AS stage_file_present WITH SYNONYMS ('file exists'),
    pipeline_quality.asset_family AS asset_family
  )
  METRICS (
    patients.patient_total AS COUNT(patients.patient_id) COMMENT = 'Number of patients',
    patients.total_broken_evidence AS SUM(patients.broken_evidence_assets)
      COMMENT = 'Total broken document references',
    encounters.encounter_total AS COUNT(encounters.visit_id) COMMENT = 'Number of encounters',
    encounters.follow_up_required_total AS SUM(IFF(encounters.follow_up_required, 1, 0))
      COMMENT = 'Number of encounters that require follow up',
    labs.lab_total AS COUNT(labs.lab_result_id) COMMENT = 'Number of lab results',
    labs.critical_lab_total AS SUM(IFF(labs.critical_flag, 1, 0)) COMMENT = 'Number of critical lab results',
    labs.distinct_test_total AS COUNT(DISTINCT labs.test_type) COMMENT = 'Number of distinct lab test types',
    claims.claim_total AS COUNT(claims.claim_id) COMMENT = 'Number of claims',
    claims.denied_claim_total AS SUM(IFF(claims.is_denied, 1, 0)) COMMENT = 'Number of denied claims',
    care_gaps.gap_total AS COUNT(care_gaps.gap_category) COMMENT = 'Number of care gap signals',
    evidence.document_total AS COUNT(evidence.ingestion_asset_id) COMMENT = 'Number of ingested documents',
    evidence.searchable_document_total AS SUM(IFF(evidence.is_searchable_evidence, 1, 0))
      COMMENT = 'Number of searchable documents'
  )
  COMMENT = 'Persona-scoped semantic model for the Quality & Compliance Analyst. De-identified: no patient name, no clinical free text, and no document body text. Optimised for documentation-adherence and traceability audit. Synthetic data only.';

-- -----------------------------------------------------------------------------
-- 5.3 Population Health Manager
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW PATIENT360.ANALYTICS.PATIENT360_SEM_POPULATION_HEALTH
  TABLES (
    cohort AS PATIENT360.ANALYTICS.PERSONA_PH_PATIENT_COHORT
      PRIMARY KEY (patient_id)
      WITH SYNONYMS ('patients', 'cohort', 'population', 'members')
      COMMENT = 'One row per patient with age band and utilisation counts. No patient name and no exact age',
    encounters AS PATIENT360.ANALYTICS.PERSONA_PH_ENCOUNTER_COHORT
      PRIMARY KEY (visit_id)
      WITH SYNONYMS ('visits', 'encounters', 'ed visits', 'utilisation')
      COMMENT = 'Encounter records for utilisation analysis',
    labs AS PATIENT360.ANALYTICS.PERSONA_PH_LAB_COHORT
      PRIMARY KEY (lab_result_id)
      WITH SYNONYMS ('labs', 'lab tests', 'screening')
      COMMENT = 'Lab results by test type and critical flag. Numeric values are NOT available, so percentage thresholds cannot be evaluated here',
    medications AS PATIENT360.ANALYTICS.PERSONA_PH_MEDICATION_COHORT
      PRIMARY KEY (prescription_id)
      WITH SYNONYMS ('medications', 'therapy', 'drugs')
      COMMENT = 'Drug name and status only, for therapy-class cohorts',
    care_gaps AS PATIENT360.ANALYTICS.PERSONA_PH_CARE_GAP
      PRIMARY KEY (patient_id, gap_category)
      WITH SYNONYMS ('gaps', 'care gaps', 'at risk')
      COMMENT = 'Care gap signals, the primary at-risk cohort indicator'
  )
  RELATIONSHIPS (
    encounters_to_cohort AS encounters (patient_id) REFERENCES cohort (patient_id),
    labs_to_cohort AS labs (patient_id) REFERENCES cohort (patient_id),
    medications_to_cohort AS medications (patient_id) REFERENCES cohort (patient_id),
    care_gaps_to_cohort AS care_gaps (patient_id) REFERENCES cohort (patient_id)
  )
  FACTS (
    cohort.visit_count AS total_visits,
    cohort.lab_count AS total_labs,
    cohort.prescription_count AS total_prescriptions,
    cohort.critical_labs AS critical_lab_count,
    encounters.lab_results AS lab_result_count,
    encounters.prescriptions AS prescription_count,
    labs.recency AS recency_rank,
    labs.results_for_type AS total_results_for_test_type,
    care_gaps.visit_total AS total_visit_count
  )
  DIMENSIONS (
    cohort.patient AS patient_id WITH SYNONYMS ('patient id', 'member id')
      COMMENT = 'Synthetic patient identifier. Patient name is not exposed to this persona',
    cohort.age_band AS age_band WITH SYNONYMS ('age group', 'age bracket')
      COMMENT = 'Generalised age band. Exact age is withheld to limit re-identification risk',
    cohort.gender AS gender,
    cohort.readiness AS evidence_readiness_status WITH SYNONYMS ('evidence coverage'),
    encounters.visit AS visit_id,
    encounters.visit_date AS visit_date,
    encounters.visit_type AS visit_type WITH SYNONYMS ('encounter type', 'ed', 'emergency'),
    encounters.diagnosis_code AS diagnosis_code WITH SYNONYMS ('icd10'),
    encounters.diagnosis AS diagnosis_description WITH SYNONYMS ('condition'),
    encounters.follow_up_required AS follow_up_required,
    labs.test AS test_type WITH SYNONYMS ('lab test', 'panel', 'hba1c', 'a1c'),
    labs.test_code AS test_code,
    labs.test_date AS test_date,
    labs.is_critical AS critical_flag WITH SYNONYMS ('critical result', 'abnormal')
      COMMENT = 'TRUE when flagged critical. This is the only severity signal available without reading the document',
    labs.latest_for_type AS latest_test_date_for_type,
    medications.medication AS medication_name WITH SYNONYMS ('drug', 'therapy'),
    medications.prescribed_on AS prescription_date,
    medications.medication_status AS medication_status,
    care_gaps.gap AS gap_category WITH SYNONYMS ('gap type'),
    care_gaps.gap_priority AS gap_priority WITH SYNONYMS ('risk level'),
    care_gaps.citation_capability AS citation_capability
  )
  METRICS (
    cohort.patient_total AS COUNT(cohort.patient_id) COMMENT = 'Number of patients in the cohort',
    cohort.avg_visits AS AVG(cohort.total_visits) COMMENT = 'Average visits per patient',
    cohort.total_critical_labs AS SUM(cohort.critical_lab_count) COMMENT = 'Total critical lab results',
    encounters.encounter_total AS COUNT(encounters.visit_id) COMMENT = 'Number of encounters',
    labs.lab_total AS COUNT(labs.lab_result_id) COMMENT = 'Number of lab results',
    labs.critical_lab_total AS SUM(IFF(labs.critical_flag, 1, 0)) COMMENT = 'Number of critical lab results',
    labs.tested_patient_total AS COUNT(DISTINCT labs.patient_id) COMMENT = 'Number of patients with at least one lab result',
    medications.medication_total AS COUNT(medications.prescription_id) COMMENT = 'Number of prescriptions',
    medications.treated_patient_total AS COUNT(DISTINCT medications.patient_id) COMMENT = 'Number of patients on therapy',
    care_gaps.gap_total AS COUNT(care_gaps.gap_category) COMMENT = 'Number of care gap signals',
    care_gaps.at_risk_patient_total AS COUNT(DISTINCT care_gaps.patient_id) COMMENT = 'Number of patients with a care gap signal'
  )
  COMMENT = 'Persona-scoped semantic model for the Population Health Manager. Cohort tier: no patient name, age generalised to a band, no clinical narrative, no claims, and no document evidence. Numeric lab values are unavailable, so value-threshold questions cannot be answered here. Synthetic data only.';

-- -----------------------------------------------------------------------------
-- 5.4 Clinical Pharmacist
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW PATIENT360.ANALYTICS.PATIENT360_SEM_PHARMACIST
  TABLES (
    patients AS PATIENT360.ANALYTICS.PERSONA_RX_PATIENT
      PRIMARY KEY (patient_id)
      WITH SYNONYMS ('patient', 'people')
      COMMENT = 'One row per patient with medication and lab counts',
    medications AS PATIENT360.ANALYTICS.PERSONA_RX_MEDICATION
      PRIMARY KEY (prescription_id)
      WITH SYNONYMS ('medications', 'prescriptions', 'drugs', 'meds', 'pharmacy')
      COMMENT = 'One row per prescription with full dispensing detail and the lab test most recently performed before it was written',
    labs AS PATIENT360.ANALYTICS.PERSONA_RX_LAB
      PRIMARY KEY (lab_result_id)
      WITH SYNONYMS ('labs', 'lab results', 'tests', 'monitoring')
      COMMENT = 'One row per lab result. Numeric values exist only in the lab report document text',
    claims AS PATIENT360.ANALYTICS.PERSONA_RX_CLAIM
      PRIMARY KEY (claim_id)
      WITH SYNONYMS ('claims', 'coverage')
      COMMENT = 'Coverage-friction signal only: status and denial reason, because a denial predicts medication abandonment',
    care_gaps AS PATIENT360.ANALYTICS.PERSONA_RX_CARE_GAP
      PRIMARY KEY (patient_id, gap_category)
      WITH SYNONYMS ('gaps', 'monitoring gaps')
      COMMENT = 'Monitoring and claim-friction care gap signals',
    evidence AS PATIENT360.ANALYTICS.PERSONA_RX_EVIDENCE
      PRIMARY KEY (ingestion_asset_id)
      WITH SYNONYMS ('documents', 'evidence', 'reports')
      COMMENT = 'Prescription, lab, and clinical note documents. Diagnostic imaging is excluded from this persona scope of practice'
  )
  RELATIONSHIPS (
    medications_to_patients AS medications (patient_id) REFERENCES patients (patient_id),
    labs_to_patients AS labs (patient_id) REFERENCES patients (patient_id),
    claims_to_patients AS claims (patient_id) REFERENCES patients (patient_id),
    care_gaps_to_patients AS care_gaps (patient_id) REFERENCES patients (patient_id),
    evidence_to_patients AS evidence (patient_id) REFERENCES patients (patient_id)
  )
  FACTS (
    patients.prescription_count AS total_prescriptions,
    patients.lab_count AS total_labs,
    patients.critical_labs AS critical_lab_count,
    patients.visit_count AS total_visits,
    medications.refill_count AS refills,
    labs.recency AS recency_rank,
    labs.results_for_type AS total_results_for_test_type,
    evidence.text_length AS extracted_text_length,
    evidence.chunks AS chunk_count
  )
  DIMENSIONS (
    patients.patient AS patient_id WITH SYNONYMS ('patient id'),
    patients.first_name AS first_name,
    patients.last_name AS last_name,
    patients.age AS age,
    patients.gender AS gender,
    patients.readiness AS evidence_readiness_status,
    medications.medication AS medication_name WITH SYNONYMS ('drug', 'drug name', 'medication'),
    medications.ndc AS ndc_code WITH SYNONYMS ('ndc'),
    medications.dosage AS dosage WITH SYNONYMS ('strength'),
    medications.frequency AS frequency WITH SYNONYMS ('how often'),
    medications.duration AS duration,
    medications.medication_status AS medication_status WITH SYNONYMS ('active prescription'),
    medications.prescribed_on AS prescription_date WITH SYNONYMS ('prescription date'),
    medications.prior_lab_test AS latest_prior_lab_test_type WITH SYNONYMS ('lab before medication', 'baseline lab')
      COMMENT = 'Lab test type most recently performed BEFORE this prescription was written',
    medications.prior_lab_date AS latest_prior_lab_test_date,
    medications.supporting_note AS supporting_note_type,
    medications.indication_note AS supporting_note_summary WITH SYNONYMS ('indication', 'why prescribed'),
    labs.test AS test_type WITH SYNONYMS ('lab test', 'panel', 'kidney function'),
    labs.test_code AS test_code,
    labs.test_date AS test_date,
    labs.lab_status AS status,
    labs.is_critical AS critical_flag WITH SYNONYMS ('critical result'),
    labs.latest_for_type AS latest_test_date_for_type,
    claims.claim AS claim_id,
    claims.claim_date AS claim_date,
    claims.procedure_code AS procedure_code,
    claims.claim_status AS claim_status,
    claims.denial_reason AS denial_reason WITH SYNONYMS ('why denied'),
    claims.is_denied AS is_denied,
    claims.coverage_friction AS coverage_friction_flag WITH SYNONYMS ('abandonment risk'),
    care_gaps.gap AS gap_category,
    care_gaps.gap_priority AS gap_priority,
    care_gaps.citation_capability AS citation_capability,
    evidence.asset AS ingestion_asset_id,
    evidence.category AS document_category,
    evidence.file_name AS source_asset_name,
    evidence.event_date AS source_event_date,
    evidence.searchable AS is_searchable_evidence
  )
  METRICS (
    patients.patient_total AS COUNT(patients.patient_id) COMMENT = 'Number of patients',
    medications.medication_total AS COUNT(medications.prescription_id) COMMENT = 'Number of prescriptions',
    medications.distinct_medication_total AS COUNT(DISTINCT medications.medication_name)
      COMMENT = 'Number of distinct drugs prescribed',
    medications.total_refills AS SUM(medications.refills) COMMENT = 'Total authorised refills',
    labs.lab_total AS COUNT(labs.lab_result_id) COMMENT = 'Number of lab results',
    labs.critical_lab_total AS SUM(IFF(labs.critical_flag, 1, 0)) COMMENT = 'Number of critical lab results',
    labs.distinct_test_total AS COUNT(DISTINCT labs.test_type) COMMENT = 'Number of distinct lab test types',
    claims.denied_claim_total AS SUM(IFF(claims.is_denied, 1, 0)) COMMENT = 'Number of denied claims',
    claims.friction_claim_total AS SUM(IFF(claims.coverage_friction_flag, 1, 0))
      COMMENT = 'Number of claims with coverage friction',
    care_gaps.gap_total AS COUNT(care_gaps.gap_category) COMMENT = 'Number of care gap signals',
    evidence.document_total AS COUNT(evidence.ingestion_asset_id) COMMENT = 'Number of ingested documents'
  )
  COMMENT = 'Persona-scoped semantic model for the Clinical Pharmacist. Identified patient access with full medication and lab depth plus the claim coverage-friction signal. Diagnostic imaging and claim financial data are excluded. Synthetic data only. Findings for clinician review.';

-- =============================================================================
-- 6. Validation queries
-- =============================================================================
-- Run these after deploying this file. Expected results are stated inline.
-- Full walkthrough is documented in docs/testing.md.
--
-- V1. All four personas registered, each pointing at an existing semantic view.
--     Expect 4 rows, and semantic_view_exists = TRUE for every row.
--   SELECT r.persona_code, r.identity_tier, r.semantic_view_name
--   FROM PATIENT360.ANALYTICS.PERSONA_REGISTRY r ORDER BY r.persona_code;
--
-- V2. Name columns are absent from the de-identified and cohort personas.
--     Expect 0 rows.
--   SELECT table_name, column_name
--   FROM PATIENT360.INFORMATION_SCHEMA.COLUMNS
--   WHERE table_schema = 'ANALYTICS'
--     AND (table_name LIKE 'PERSONA_QA_%' OR table_name LIKE 'PERSONA_PH_%')
--     AND column_name IN ('FIRST_NAME', 'LAST_NAME');
--
-- V3. Document body text is absent from every persona that must not read it.
--     Expect 0 rows.
--   SELECT table_name, column_name
--   FROM PATIENT360.INFORMATION_SCHEMA.COLUMNS
--   WHERE table_schema = 'ANALYTICS'
--     AND (table_name LIKE 'PERSONA_QA_%' OR table_name LIKE 'PERSONA_PH_%')
--     AND column_name = 'EVIDENCE_TEXT';
--
-- V4. Exact age is absent from the cohort persona; only age_band exists.
--     Expect exactly one row: PERSONA_PH_PATIENT_COHORT / AGE_BAND.
--   SELECT table_name, column_name
--   FROM PATIENT360.INFORMATION_SCHEMA.COLUMNS
--   WHERE table_schema = 'ANALYTICS' AND table_name LIKE 'PERSONA_PH_%'
--     AND column_name IN ('AGE', 'AGE_BAND');
--
-- V5. No claim financial or policy column reaches any persona view.
--     Expect 0 rows.
--   SELECT table_name, column_name
--   FROM PATIENT360.INFORMATION_SCHEMA.COLUMNS
--   WHERE table_schema = 'ANALYTICS' AND table_name LIKE 'PERSONA_%'
--     AND column_name IN ('BILLED_AMOUNT','ALLOWED_AMOUNT','INSURANCE_PAID',
--                         'PATIENT_RESPONSIBILITY','INSURANCE_POLICY_NUMBER','INSURANCE_PROVIDER');
--
-- V6. Pharmacist evidence view excludes diagnostic imaging. Expect 0 rows.
--   SELECT COUNT(*) FROM PATIENT360.ANALYTICS.PERSONA_RX_EVIDENCE
--   WHERE document_category = 'DIAGNOSTIC_IMAGE';
--
-- V7. Every persona view is SECURE. Expect 0 rows.
--   SELECT table_name FROM PATIENT360.INFORMATION_SCHEMA.VIEWS
--   WHERE table_schema = 'ANALYTICS' AND table_name LIKE 'PERSONA_%' AND is_secure = 'NO';
--
-- V8. Age banding partitions the whole population with no loss.
--     Expect band_total to equal the patient count in ANALYTICS_PATIENT_EVIDENCE_READINESS.
--   SELECT SUM(c) AS band_total FROM (
--     SELECT age_band, COUNT(*) c FROM PATIENT360.ANALYTICS.PERSONA_PH_PATIENT_COHORT GROUP BY age_band);
