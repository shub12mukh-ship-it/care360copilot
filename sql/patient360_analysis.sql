-- PATIENT360 Analysis Layer
-- Canonical database target: PATIENT360
--
-- Builds the evidence-centric analysis surface on top of the deterministic
-- DOCUMENTS ingestion outputs and the existing CURATED business entities.
--
-- Layer boundary:
--   DOCUMENTS -> ingestion inventory / extracted text / chunks / quality findings
--   CURATED   -> patient-centered business entities (incl. document evidence)
--   ANALYTICS -> readiness, coverage, quality, and semantic/RAG analysis surfaces
--
-- Safety posture: findings for clinician review only. No diagnosis, no prognosis,
-- no treatment recommendation. Synthetic data only.

USE DATABASE PATIENT360;

-- =============================================================================
-- 1. CURATED: document evidence joined to ingestion outcomes
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_DOCUMENT_EVIDENCE AS
SELECT
    i.ingestion_asset_id,
    i.patient_id,
    i.visit_id,
    i.report_id,
    i.asset_family,
    i.document_category,
    i.original_file_name        AS source_asset_name,
    i.canonical_stage_path,
    i.source_event_date,
    i.match_status,
    i.processing_status,
    i.stage_file_present,
    e.extraction_record_id,
    e.extraction_mode,
    e.extraction_outcome_status,
    e.extracted_text_length,
    e.parsed_page_count,
    e.extracted_text_body       AS evidence_text,
    IFF(e.extraction_outcome_status = 'SEARCHABLE_TEXT_READY', TRUE, FALSE) AS is_searchable_evidence,
    c.chunk_count
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY i
LEFT JOIN PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE e
       ON e.ingestion_asset_id = i.ingestion_asset_id
LEFT JOIN (
    SELECT ingestion_asset_id, COUNT(*) AS chunk_count
    FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE
    GROUP BY ingestion_asset_id
) c ON c.ingestion_asset_id = i.ingestion_asset_id;

-- =============================================================================
-- 1b. CURATED: claim clinical context (financials deliberately excluded)
-- =============================================================================
-- Access boundary for the care-team personas. RAW.INSURANCE_CLAIMS splits into
-- three tiers; only the clinical tier is exposed here:
--   * Clinical  (exposed):  diagnosis_code (ICD-10), procedure_code (CPT),
--                           procedure_description, claim_status, denial_reason.
--                           A denial predicts medication abandonment and missed
--                           follow-up, so it is clinically actionable.
--   * Financial (excluded): billed_amount, allowed_amount, insurance_paid,
--                           patient_responsibility. The billed-vs-paid spread
--                           never changes a care decision.
--   * Admin     (excluded): policy_number, insurance_provider. Payer
--                           identifiers with no clinical value.
-- NOTE: this is a modelling boundary, not an enforced one. Any role holding
-- SELECT on PATIENT360.RAW can still read the excluded columns directly. RBAC
-- and row-level security are out of MVP scope by design.

CREATE OR REPLACE VIEW PATIENT360.CURATED.CURATED_CLAIM_CLINICAL_CONTEXT
COMMENT = 'Clinically relevant claim context for care teams. Deliberately EXCLUDES financial columns (billed_amount, allowed_amount, insurance_paid, patient_responsibility) and administrative identifiers (policy_number, insurance_provider) under HIPAA minimum-necessary: a treating clinician needs to know whether care was covered and why it was denied, not the billed-vs-paid spread. Synthetic data only.'
AS
SELECT
    c.claim_id,
    c.patient_id,
    c.visit_id,
    c.claim_date,
    c.diagnosis_code,
    c.procedure_code,
    c.procedure_description,
    c.claim_status,
    c.claim_status_date,
    c.denial_reason,
    (c.claim_status = 'Denied')                                     AS is_denied,
    (c.claim_status IN ('Denied', 'Partially Approved', 'Pending')) AS coverage_friction_flag,
    DATEDIFF('day', c.claim_date, c.claim_status_date)              AS days_to_claim_decision
FROM PATIENT360.RAW.INSURANCE_CLAIMS c;

-- =============================================================================
-- 2. ANALYTICS: ingestion quality summary by asset family
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT360.ANALYTICS.ANALYTICS_INGESTION_QUALITY_SUMMARY AS
WITH asset_totals AS (
    SELECT asset_family,
           COUNT(*) AS total_assets,
           COUNT_IF(stage_file_present) AS present_assets,
           COUNT_IF(NOT stage_file_present) AS missing_assets
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
    GROUP BY asset_family
),
extraction_totals AS (
    SELECT i.asset_family,
           COUNT_IF(e.extraction_outcome_status = 'SEARCHABLE_TEXT_READY') AS searchable_assets,
           COUNT_IF(e.extraction_outcome_status = 'METADATA_ONLY') AS metadata_only_assets,
           COUNT_IF(e.extraction_outcome_status = 'FAILED_EXTRACTION') AS failed_assets,
           AVG(e.extracted_text_length) AS avg_extracted_text_length
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE e
    JOIN PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY i ON i.ingestion_asset_id = e.ingestion_asset_id
    GROUP BY i.asset_family
),
chunk_totals AS (
    SELECT i.asset_family, COUNT(*) AS chunk_count
    FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE c
    JOIN PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY i ON i.ingestion_asset_id = c.ingestion_asset_id
    GROUP BY i.asset_family
)
SELECT a.asset_family, a.total_assets, a.present_assets, a.missing_assets,
       COALESCE(x.searchable_assets, 0) AS searchable_assets,
       COALESCE(x.metadata_only_assets, 0) AS metadata_only_assets,
       COALESCE(x.failed_assets, 0) AS failed_assets,
       ROUND(100.0 * COALESCE(x.searchable_assets, 0) / NULLIF(a.total_assets, 0), 1) AS searchable_pct,
       ROUND(COALESCE(x.avg_extracted_text_length, 0)) AS avg_extracted_text_length,
       COALESCE(k.chunk_count, 0) AS chunk_count
FROM asset_totals a
LEFT JOIN extraction_totals x ON x.asset_family = a.asset_family
LEFT JOIN chunk_totals k ON k.asset_family = a.asset_family;

-- =============================================================================
-- 3. ANALYTICS: per-patient evidence readiness
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS AS
WITH evidence AS (
    SELECT patient_id,
           COUNT(*) AS total_evidence_assets,
           COUNT_IF(is_searchable_evidence) AS searchable_evidence_assets,
           COUNT_IF(document_category = 'CLINICAL_NOTE' AND is_searchable_evidence) AS searchable_notes,
           COUNT_IF(document_category = 'LAB_DOCUMENT' AND is_searchable_evidence) AS searchable_lab_docs,
           COUNT_IF(document_category = 'PRESCRIPTION' AND is_searchable_evidence) AS searchable_prescriptions,
           COUNT_IF(document_category = 'DIAGNOSTIC_IMAGE' AND is_searchable_evidence) AS searchable_imaging,
           COUNT_IF(NOT COALESCE(stage_file_present, FALSE)) AS broken_evidence_assets,
           SUM(COALESCE(chunk_count, 0)) AS total_chunks,
           MAX(source_event_date) AS latest_evidence_date
    FROM PATIENT360.CURATED.CURATED_DOCUMENT_EVIDENCE
    WHERE patient_id IS NOT NULL
    GROUP BY patient_id
)
SELECT p.patient_id, p.first_name, p.last_name, p.age, p.gender,
       p.total_visits, p.total_labs, p.total_prescriptions, p.total_claims, p.critical_lab_count,
       COALESCE(e.total_evidence_assets, 0) AS total_evidence_assets,
       COALESCE(e.searchable_evidence_assets, 0) AS searchable_evidence_assets,
       COALESCE(e.searchable_notes, 0) AS searchable_notes,
       COALESCE(e.searchable_lab_docs, 0) AS searchable_lab_docs,
       COALESCE(e.searchable_prescriptions, 0) AS searchable_prescriptions,
       COALESCE(e.searchable_imaging, 0) AS searchable_imaging,
       COALESCE(e.broken_evidence_assets, 0) AS broken_evidence_assets,
       COALESCE(e.total_chunks, 0) AS total_chunks,
       e.latest_evidence_date,
       CASE WHEN COALESCE(e.searchable_evidence_assets, 0) = 0 THEN 'NO_SEARCHABLE_EVIDENCE'
            WHEN e.searchable_notes > 0 AND e.searchable_lab_docs > 0 AND e.searchable_prescriptions > 0
                 THEN 'FULL_EVIDENCE_COVERAGE'
            ELSE 'PARTIAL_EVIDENCE_COVERAGE' END AS evidence_readiness_status
FROM PATIENT360.CURATED.CURATED_PATIENT_RECORD p
LEFT JOIN evidence e ON e.patient_id = p.patient_id;

-- =============================================================================
-- 4. ANALYTICS: search corpus overview
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT360.ANALYTICS.ANALYTICS_SEARCH_CORPUS_OVERVIEW AS
SELECT document_category,
       COUNT(DISTINCT ingestion_asset_id) AS documents_indexed,
       COUNT(*) AS chunks_indexed,
       ROUND(AVG(LENGTH(chunk_text))) AS avg_chunk_chars,
       MIN(source_event_date) AS earliest_document_date,
       MAX(source_event_date) AS latest_document_date,
       COUNT(DISTINCT patient_id) AS patients_covered
FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE
GROUP BY document_category;

-- =============================================================================
-- 5. ANALYTICS: care gaps joined to citation capability
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE AS
SELECT g.patient_id, g.gap_category, g.gap_description, g.gap_priority,
       g.latest_visit_date, g.latest_lab_date, g.denied_claim_count,
       g.total_visit_count, g.total_note_count,
       r.searchable_evidence_assets, r.searchable_notes, r.searchable_lab_docs,
       r.searchable_prescriptions, r.searchable_imaging, r.broken_evidence_assets,
       r.evidence_readiness_status,
       CASE WHEN r.searchable_evidence_assets = 0 THEN 'NOT_CITABLE'
            WHEN r.broken_evidence_assets > 0 THEN 'CITABLE_WITH_GAPS'
            ELSE 'CITABLE' END AS citation_capability
FROM PATIENT360.CURATED.CURATED_CARE_GAP_SIGNAL g
LEFT JOIN PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS r
       ON r.patient_id = g.patient_id;

-- =============================================================================
-- 6. ANALYTICS: evidence-cited answering procedure (RAG)
-- =============================================================================
-- Cortex Search retrieval precedes Cortex LLM generation, and the system prompt
-- enforces citations plus refusal of diagnosis / prognosis / treatment advice.

CREATE OR REPLACE PROCEDURE PATIENT360.ANALYTICS.ANSWER_WITH_EVIDENCE(
    QUESTION STRING, PATIENT_ID STRING, MAX_PASSAGES NUMBER)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    search_request STRING;
    search_raw VARIANT;
    evidence_context STRING;
    citations VARIANT;
    answer STRING;
    system_prompt STRING;
BEGIN
    IF (:PATIENT_ID IS NULL OR :PATIENT_ID = '') THEN
        search_request := OBJECT_CONSTRUCT(
            'query', :QUESTION,
            'columns', ARRAY_CONSTRUCT('chunk_text','patient_id','document_category',
                                       'original_file_name','source_event_date','canonical_stage_path'),
            'limit', :MAX_PASSAGES)::STRING;
    ELSE
        search_request := OBJECT_CONSTRUCT(
            'query', :QUESTION,
            'columns', ARRAY_CONSTRUCT('chunk_text','patient_id','document_category',
                                       'original_file_name','source_event_date','canonical_stage_path'),
            'filter', OBJECT_CONSTRUCT('@eq', OBJECT_CONSTRUCT('patient_id', :PATIENT_ID)),
            'limit', :MAX_PASSAGES)::STRING;
    END IF;

    search_raw := PARSE_JSON(
        SNOWFLAKE.CORTEX.SEARCH_PREVIEW('PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE', :search_request));

    SELECT LISTAGG(
             '[Source: ' || value:original_file_name::STRING || ' | ' || value:document_category::STRING ||
             ' | patient ' || COALESCE(value:patient_id::STRING,'unknown') ||
             ' | date ' || COALESCE(value:source_event_date::STRING,'unknown') || ']\n' || value:chunk_text::STRING,
             '\n\n---\n\n')
      INTO evidence_context
      FROM TABLE(FLATTEN(input => :search_raw:results));

    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
             'source_document', value:original_file_name::STRING,
             'document_category', value:document_category::STRING,
             'patient_id', value:patient_id::STRING,
             'source_event_date', value:source_event_date::STRING,
             'stage_path', value:canonical_stage_path::STRING))
      INTO citations
      FROM TABLE(FLATTEN(input => :search_raw:results));

    IF (:evidence_context IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            'question', :QUESTION,
            'patient_id', :PATIENT_ID,
            'answer', 'No supporting evidence was retrieved from the PATIENT360 document corpus, so no finding can be reported for clinician review.',
            'citations', ARRAY_CONSTRUCT(),
            'evidence_passages', 0);
    END IF;

    system_prompt := 'You are a clinical evidence assistant for synthetic healthcare data. Rules you MUST follow: ' ||
        '1) Answer ONLY from the provided evidence passages. ' ||
        '2) Cite the source document name and date inline for every factual claim, using the [Source: ...] labels given. ' ||
        '3) Never diagnose, never predict outcomes, never recommend treatment. ' ||
        '4) Frame everything as findings for clinician review. ' ||
        '5) If the evidence does not answer the question, say so explicitly instead of speculating.';

    answer := AI_COMPLETE('llama3.1-70b',
        :system_prompt || '\n\nQUESTION: ' || :QUESTION || '\n\nEVIDENCE PASSAGES:\n' || :evidence_context ||
        '\n\nProduce a concise findings-for-review answer with inline citations.');

    RETURN OBJECT_CONSTRUCT(
        'question', :QUESTION,
        'patient_id', :PATIENT_ID,
        'answer', :answer,
        'citations', :citations,
        'evidence_passages', ARRAY_SIZE(:search_raw:results));
END;
$$;

-- =============================================================================
-- 7. ANALYTICS: semantic view for Cortex Analyst
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  TABLES (
    patients AS PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS
      PRIMARY KEY (patient_id)
      WITH SYNONYMS ('patient', 'members', 'people')
      COMMENT = 'One row per synthetic patient with structured utilization and document evidence readiness',
    encounters AS PATIENT360.CURATED.CURATED_ENCOUNTER_SUMMARY
      PRIMARY KEY (visit_id)
      WITH SYNONYMS ('visits', 'encounters')
      COMMENT = 'One row per clinical encounter with linked child record counts',
    evidence AS PATIENT360.CURATED.CURATED_DOCUMENT_EVIDENCE
      PRIMARY KEY (ingestion_asset_id)
      WITH SYNONYMS ('documents', 'evidence assets', 'files')
      COMMENT = 'One row per ingested clinical document or diagnostic image with extraction status',
    care_gaps AS PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE
      PRIMARY KEY (patient_id, gap_category)
      WITH SYNONYMS ('gaps', 'care gaps')
      COMMENT = 'Care gap signals joined to document evidence citation capability',
    medications AS PATIENT360.CURATED.CURATED_MEDICATION_EVIDENCE_SUMMARY
      PRIMARY KEY (prescription_id)
      WITH SYNONYMS ('medications', 'drugs', 'prescriptions', 'meds', 'pharmacy')
      COMMENT = 'One row per prescription with drug name, dosage, status, and the lab test most recently performed before it was written',
    labs AS PATIENT360.CURATED.CURATED_LAB_MONITORING_SUMMARY
      PRIMARY KEY (lab_result_id)
      WITH SYNONYMS ('labs', 'lab results', 'tests', 'lab tests')
      COMMENT = 'One row per lab result with test type, critical flag, and monitoring recency. Numeric result values are NOT in structured data; they exist only in the parsed lab PDF text',
    claims AS PATIENT360.CURATED.CURATED_CLAIM_CLINICAL_CONTEXT
      PRIMARY KEY (claim_id)
      WITH SYNONYMS ('claims', 'insurance claims', 'coverage')
      COMMENT = 'Clinically relevant claim context only: ICD-10 diagnosis, CPT procedure, status, and denial reason. Financial amounts and policy identifiers are deliberately excluded'
  )
  RELATIONSHIPS (
    encounters_to_patients AS encounters (patient_id) REFERENCES patients (patient_id),
    evidence_to_patients AS evidence (patient_id) REFERENCES patients (patient_id),
    care_gaps_to_patients AS care_gaps (patient_id) REFERENCES patients (patient_id),
    medications_to_patients AS medications (patient_id) REFERENCES patients (patient_id),
    labs_to_patients AS labs (patient_id) REFERENCES patients (patient_id),
    claims_to_patients AS claims (patient_id) REFERENCES patients (patient_id)
  )
  FACTS (
    patients.visit_count AS total_visits,
    patients.lab_count AS total_labs,
    patients.prescription_count AS total_prescriptions,
    patients.claim_count AS total_claims,
    patients.critical_labs AS critical_lab_count,
    patients.evidence_assets AS total_evidence_assets,
    patients.searchable_assets AS searchable_evidence_assets,
    patients.broken_assets AS broken_evidence_assets,
    patients.chunk_total AS total_chunks,
    evidence.text_length AS extracted_text_length,
    evidence.chunks AS chunk_count,
    encounters.lab_results AS lab_result_count,
    encounters.prescriptions AS prescription_count,
    medications.refill_count AS refills,
    labs.recency AS recency_rank,
    labs.results_for_type AS total_results_for_test_type,
    claims.decision_days AS days_to_claim_decision
  )
  DIMENSIONS (
    patients.patient AS patient_id WITH SYNONYMS ('patient id') COMMENT = 'Synthetic patient identifier',
    patients.first_name AS first_name,
    patients.last_name AS last_name,
    patients.age AS age,
    patients.gender AS gender,
    patients.readiness AS evidence_readiness_status WITH SYNONYMS ('evidence coverage')
      COMMENT = 'Whether the patient has full, partial, or no searchable document evidence',
    encounters.visit AS visit_id,
    encounters.visit_date AS visit_date,
    encounters.visit_type AS visit_type,
    encounters.diagnosis AS diagnosis_description,
    evidence.asset AS ingestion_asset_id,
    evidence.category AS document_category WITH SYNONYMS ('document type')
      COMMENT = 'Clinical note, lab document, prescription, or diagnostic image',
    evidence.file_name AS source_asset_name,
    evidence.extraction_status AS extraction_outcome_status WITH SYNONYMS ('parse status')
      COMMENT = 'Whether the document produced searchable text',
    evidence.searchable AS is_searchable_evidence,
    evidence.event_date AS source_event_date,
    care_gaps.gap AS gap_category,
    care_gaps.gap_priority AS gap_priority,
    care_gaps.citation_capability AS citation_capability WITH SYNONYMS ('can we cite evidence'),
    medications.medication AS medication_name WITH SYNONYMS ('drug', 'drug name', 'medication name')
      COMMENT = 'Prescribed drug name',
    medications.ndc AS ndc_code WITH SYNONYMS ('ndc'),
    medications.dosage AS dosage,
    medications.frequency AS frequency,
    medications.duration AS duration,
    medications.medication_status AS medication_status WITH SYNONYMS ('active medication', 'discontinued')
      COMMENT = 'Whether the prescription is currently active',
    medications.prescribed_on AS prescription_date WITH SYNONYMS ('prescription date', 'when prescribed'),
    medications.prior_lab_test AS latest_prior_lab_test_type WITH SYNONYMS ('lab before medication')
      COMMENT = 'Lab test type most recently performed BEFORE this prescription was written',
    medications.prior_lab_date AS latest_prior_lab_test_date,
    medications.supporting_note AS supporting_note_type,
    labs.test AS test_type WITH SYNONYMS ('lab test', 'test name', 'panel')
      COMMENT = 'Lab test type, for example Hemoglobin A1C or Kidney Function',
    labs.test_code AS test_code WITH SYNONYMS ('loinc'),
    labs.test_date AS test_date,
    labs.lab_status AS status,
    labs.is_critical AS critical_flag WITH SYNONYMS ('critical result', 'abnormal')
      COMMENT = 'TRUE when the result was flagged critical and requires physician review',
    labs.latest_for_type AS latest_test_date_for_type,
    claims.claim AS claim_id,
    claims.claim_date AS claim_date,
    claims.diagnosis_code AS diagnosis_code WITH SYNONYMS ('icd10', 'icd-10', 'diagnosis code'),
    claims.procedure_code AS procedure_code WITH SYNONYMS ('cpt', 'cpt code', 'procedure code'),
    claims.procedure AS procedure_description,
    claims.claim_status AS claim_status WITH SYNONYMS ('coverage status'),
    claims.denial_reason AS denial_reason WITH SYNONYMS ('why denied')
      COMMENT = 'Reason a claim was denied, for example pre-authorization required or out of network',
    claims.is_denied AS is_denied,
    claims.coverage_friction AS coverage_friction_flag WITH SYNONYMS ('coverage problem')
      COMMENT = 'TRUE when a claim was denied, partially approved, or still pending'
  )
  METRICS (
    patients.patient_total AS COUNT(patients.patient_id) COMMENT = 'Number of patients',
    patients.avg_visits AS AVG(patients.total_visits) COMMENT = 'Average visits per patient',
    patients.total_searchable_evidence AS SUM(patients.searchable_evidence_assets)
      COMMENT = 'Total searchable evidence assets',
    patients.total_broken_evidence AS SUM(patients.broken_evidence_assets)
      COMMENT = 'Total broken document references',
    evidence.document_total AS COUNT(evidence.ingestion_asset_id) COMMENT = 'Number of ingested documents',
    evidence.searchable_document_total AS SUM(IFF(evidence.is_searchable_evidence, 1, 0))
      COMMENT = 'Number of searchable documents',
    evidence.total_chunks AS SUM(evidence.chunk_count) COMMENT = 'Total indexed search chunks',
    encounters.encounter_total AS COUNT(encounters.visit_id) COMMENT = 'Number of encounters',
    care_gaps.gap_total AS COUNT(care_gaps.gap_category) COMMENT = 'Number of care gap signals',
    medications.medication_total AS COUNT(medications.prescription_id) COMMENT = 'Number of prescriptions',
    medications.distinct_medication_total AS COUNT(DISTINCT medications.medication_name)
      COMMENT = 'Number of distinct drugs prescribed',
    medications.total_refills AS SUM(medications.refills) COMMENT = 'Total authorised refills',
    labs.lab_total AS COUNT(labs.lab_result_id) COMMENT = 'Number of lab results',
    labs.critical_lab_total AS SUM(IFF(labs.critical_flag, 1, 0))
      COMMENT = 'Number of lab results flagged critical',
    labs.distinct_test_total AS COUNT(DISTINCT labs.test_type) COMMENT = 'Number of distinct lab test types',
    claims.claim_total AS COUNT(claims.claim_id) COMMENT = 'Number of claims',
    claims.denied_claim_total AS SUM(IFF(claims.is_denied, 1, 0)) COMMENT = 'Number of denied claims',
    claims.friction_claim_total AS SUM(IFF(claims.coverage_friction_flag, 1, 0))
      COMMENT = 'Number of claims with any coverage friction'
  )
  COMMENT = 'PATIENT360 clinical semantic model over curated structured records and ingested clinical documents. Covers patients, encounters, medications, labs, claims (clinical context only, no financial amounts), care gaps, and document evidence readiness. Synthetic data only.';

-- =============================================================================
-- 8. ANALYTICS: Cortex Agent (orchestrates Analyst + Search)
-- =============================================================================
-- Created in PATIENT360.ANALYTICS because this account has no
-- SNOWFLAKE_INTELLIGENCE database. Run from SQL with:
--   SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     'PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_COPILOT',
--     $${"messages":[{"role":"user","content":[{"type":"text","text":"<question>"}]}]}$$,
--     TRUE));

CREATE OR REPLACE AGENT PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_COPILOT
  COMMENT = 'Evidence-cited clinical copilot over PATIENT360 synthetic data. Findings for clinician review only.'
  PROFILE = '{"display_name": "Patient360 Evidence Copilot", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    capabilities:
      analytical_search: true
    tool_not_accessible: reject
    budget:
      seconds: 120
      tokens: 100000

  instructions:
    response: |
      You report findings for clinician review only. You operate on synthetic healthcare data.
      Cite the source for every factual claim: table and column for structured results, or
      document file name and date for document evidence. Never diagnose a condition, never
      predict a patient outcome, and never recommend or adjust treatment. If the retrieved
      evidence does not answer the question, say so explicitly instead of speculating.
      Surface contradictions between structured records and document text rather than resolving them.

      Two scope limits you must explain rather than silently fail on:
      1. Claim financial amounts (billed, allowed, paid, patient responsibility) and policy
         identifiers are intentionally excluded from your data under HIPAA minimum-necessary.
         You can report diagnosis code, procedure code, claim status, and denial reason. If asked
         for amounts, say the exclusion is deliberate and offer the clinical claim context instead.
      2. Numeric lab result values are not in structured records. Only the test type, test date,
         and critical flag are. Actual values exist only inside the lab report document text, so
         value questions require EvidenceSearch and must be quoted from the document.
    orchestration: |
      Use Patient360Analyst for counting, aggregating, ranking, filtering, or trending across
      patients, encounters, medications, lab tests, claims, care gaps, and evidence readiness.
      It knows drug names, dosages, frequencies, prescription dates, lab test types, critical
      flags, ICD-10 and CPT codes, claim status, and denial reasons.

      Use EvidenceSearch when the user asks what a clinical note, lab report, prescription, or
      diagnostic report actually says, when they need a citation from document text, or when they
      ask for a numeric lab value or reference range, because those exist only in document text.

      Routing rules:
      - "What medications is this patient on" -> Patient360Analyst (medication_name, dosage,
        frequency, medication_status, prescription_date).
      - "What labs were ordered before starting <drug>" -> Patient360Analyst; the
        latest_prior_lab_test_type and latest_prior_lab_date fields answer this directly.
      - "Show evidence of <test> monitoring" -> Patient360Analyst for who was tested and how often,
        then EvidenceSearch to cite the report text.
      - "Is this value high / uncontrolled / improving" -> EvidenceSearch, and quote the document.
        Report what the document states; do not interpret it clinically.
      - "Why was this claim denied" -> Patient360Analyst (denial_reason).
      For questions needing both a number and supporting text, call Patient360Analyst first,
      then EvidenceSearch to cite it. If a question asks for a diagnosis, prognosis, or treatment
      decision, decline and explain that this system only surfaces documented evidence.
    sample_questions:
      - question: "What medications is patient P00014 on, with dosage and when they were prescribed?"
      - question: "What lab test was performed before Metformin was prescribed, and when?"
      - question: "Which patients have had Hemoglobin A1C testing, and how many had a critical result?"
      - question: "Which claims were denied and what was the stated reason?"
      - question: "Show the lab report text for a patient with a critical lab result."
      - question: "Which patients have no searchable document evidence?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Patient360Analyst"
        description: |
          Structured analytics over PATIENT360. Covers patients and demographics, encounters and
          diagnoses, medications (drug name, NDC, dosage, frequency, status, prescription date, and
          the lab test most recently performed before each prescription), lab tests (test type,
          LOINC-style code, test date, critical flag, monitoring recency), insurance claims limited
          to clinical context (ICD-10 diagnosis code, CPT procedure code, claim status, denial
          reason, coverage friction), care gap signals, and document evidence readiness.
          Use for "how many", "which patients", "what medications", "what labs", "why denied",
          "average", "top N", and coverage or completeness questions.
          Does NOT contain: document text, numeric lab result values, claim dollar amounts, or
          insurance policy identifiers.
    - tool_spec:
        type: "cortex_search"
        name: "EvidenceSearch"
        description: |
          Semantic search over the text of ingested clinical documents: clinical notes, lab result
          reports, prescriptions, and OCR text from diagnostic images. Returns passages with the
          source file name, document category, patient id, and document date so answers can be
          cited. Use when the user asks what a document says, needs supporting quotes, wants
          evidence for a specific patient, or asks for a numeric lab value or reference range,
          since those appear only in document text. Filter by patient_id when a patient is named.

  tool_resources:
    Patient360Analyst:
      semantic_view: "PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC"
      execution_environment:
        type: "warehouse"
        warehouse: "CARE360_WH"
        query_timeout: 120
    EvidenceSearch:
      search_service: "PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE"
      max_results: "8"
      id_column: "CHUNK_ID"
      title_column: "ORIGINAL_FILE_NAME"
  $$;
