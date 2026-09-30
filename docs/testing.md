# Care360 Evidence Copilot - Testing & Validation

## Pre-Deployment Validation

### 1. Data Integrity Checks

```sql
-- Verify row counts after loading
SELECT 'PATIENTS' AS tbl, COUNT(*) AS cnt FROM PATIENT360.RAW.PATIENTS
UNION ALL SELECT 'VISITS', COUNT(*) FROM PATIENT360.RAW.VISITS
UNION ALL SELECT 'LAB_RESULTS', COUNT(*) FROM PATIENT360.RAW.LAB_RESULTS
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM PATIENT360.RAW.PRESCRIPTIONS
UNION ALL SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM PATIENT360.RAW.INSURANCE_CLAIMS
UNION ALL SELECT 'CLINICAL_NOTES', COUNT(*) FROM PATIENT360.RAW.CLINICAL_NOTES
UNION ALL SELECT 'DIAGNOSTIC_REPORTS', COUNT(*) FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS;

-- Expected minimums: PATIENTS >= 100, VISITS >= 300, LAB_RESULTS >= 200,
-- PRESCRIPTIONS >= 200, INSURANCE_CLAIMS >= 300, CLINICAL_NOTES >= 250, DIAGNOSTIC_REPORTS >= 150

-- Referential integrity: no orphan visits
SELECT COUNT(*) AS orphan_visits
FROM PATIENT360.RAW.VISITS v
LEFT JOIN PATIENT360.RAW.PATIENTS p ON v.patient_id = p.patient_id
WHERE p.patient_id IS NULL;
-- Expected: 0

-- Referential integrity: no orphan lab results
SELECT COUNT(*) AS orphan_labs
FROM PATIENT360.RAW.LAB_RESULTS l
LEFT JOIN PATIENT360.RAW.PATIENTS p ON l.patient_id = p.patient_id
WHERE p.patient_id IS NULL;
-- Expected: 0
```

### 2. Curated Patient 360 Validation

```sql
-- Every patient should appear in the curated patient record
SELECT COUNT(*) AS p360_count FROM PATIENT360.CURATED.CURATED_PATIENT_RECORD;
-- Should equal PATIENTS count

-- Spot check: verify aggregates for a known patient
SELECT patient_id, first_name, last_name, total_visits, total_prescriptions,
       total_labs, critical_lab_count, total_claims, total_diagnostic_reports
FROM PATIENT360.CURATED.CURATED_PATIENT_RECORD
WHERE patient_id = 'P00001';

-- Cross-validate visit count
SELECT COUNT(*) AS direct_count
FROM PATIENT360.RAW.VISITS
WHERE patient_id = 'P00001';
-- Should match total_visits from curated patient record
```

### 3. Timeline View Validation

```sql
-- Timeline should have events from all source types
SELECT event_type, COUNT(*) AS event_count
FROM PATIENT360.CURATED.CURATED_PATIENT_TIMELINE_EVENT
GROUP BY event_type
ORDER BY event_count DESC;
-- Should show VISIT, LAB_RESULT, PRESCRIPTION, CLAIM, CLINICAL_NOTE, DIAGNOSTIC_REPORT

-- Verify chronological ordering per patient
SELECT patient_id, MIN(event_date) AS earliest, MAX(event_date) AS latest
FROM PATIENT360.CURATED.CURATED_PATIENT_TIMELINE_EVENT
GROUP BY patient_id;
```

### 4. Persona-Aligned Curation Validation

```sql
-- Clinical Care Coordinator: recent visit and medication summary
SELECT patient_id, latest_visit_date, total_visits, total_prescriptions
FROM PATIENT360.CURATED.CURATED_PATIENT_RECORD
ORDER BY latest_visit_date DESC
LIMIT 10;

-- Quality & Compliance Analyst: evidence of monitoring and care gaps
SELECT patient_id, gap_category, gap_description, gap_priority, latest_lab_date
FROM PATIENT360.CURATED.CURATED_CARE_GAP_SIGNAL
ORDER BY gap_priority, patient_id;

-- Clinical Pharmacist: medication linked to supporting evidence
SELECT patient_id, medication_name, prescription_date, related_lab_test_type, related_note_type
FROM PATIENT360.CURATED.CURATED_MEDICATION_EVIDENCE_SUMMARY
LIMIT 20;

-- Population Health Manager: utilization and denied claims signals
SELECT patient_id, total_visits, denied_claim_count, total_claims
FROM PATIENT360.CURATED.CURATED_PATIENT_RECORD
ORDER BY total_visits DESC, denied_claim_count DESC
LIMIT 20;
```

### 5. Evidence Asset and Imaging Readiness Validation

```sql
-- Report and image-linked evidence assets should remain tied to patient and visit context
SELECT asset_type, modality, body_part, COUNT(*) AS asset_count
FROM PATIENT360.CURATED.CURATED_EVIDENCE_ASSET
GROUP BY asset_type, modality, body_part
ORDER BY asset_type, asset_count DESC;

-- Spot check one patient for linked evidence assets
SELECT patient_id, visit_id, asset_type, source_asset_name, source_event_date, asset_subtype
FROM PATIENT360.CURATED.CURATED_EVIDENCE_ASSET
WHERE patient_id = 'P00001'
ORDER BY source_event_date DESC;
```

### 6. Semantic Prep Validation

```sql
SELECT COUNT(*) AS patient_overview_count
FROM PATIENT360.ANALYTICS.SEM_PATIENT_OVERVIEW;

SELECT COUNT(*) AS encounter_overview_count
FROM PATIENT360.ANALYTICS.SEM_ENCOUNTER_OVERVIEW;
```

### 7. Semantic Relationship Validation

```sql
-- Semantic-prep entities should preserve patient and encounter paths
SELECT patient_id, COUNT(*) AS encounter_count
FROM PATIENT360.ANALYTICS.SEM_ENCOUNTER_OVERVIEW
GROUP BY patient_id
ORDER BY encounter_count DESC
LIMIT 10;

SELECT patient_id, total_visits, total_labs, total_claims, total_diagnostic_reports
FROM PATIENT360.ANALYTICS.SEM_PATIENT_OVERVIEW
ORDER BY total_visits DESC
LIMIT 10;
```

### 8. Naming Governance Validation

```sql
-- Manual repository check: no new forward-looking CARE360_DB references should be introduced
-- in curation SQL or updated validation materials.
```

### 9. Ingestion Inventory Validation

```sql
-- Reconcile canonical ingestion inventory by asset family
SELECT asset_family, COUNT(*) AS asset_count
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
GROUP BY asset_family
ORDER BY asset_family;

-- Unmatched assets must remain visible instead of being force-assigned
SELECT ingestion_asset_id, asset_family, original_file_name, match_status, processing_status
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
WHERE match_status = 'UNMATCHED'
ORDER BY asset_family, ingestion_asset_id;
```

### 10. Ingestion Extraction And OCR Validation

```sql
-- Review extraction states for staged assets
SELECT extraction_mode, extraction_outcome_status, COUNT(*) AS asset_count
FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT
GROUP BY extraction_mode, extraction_outcome_status
ORDER BY extraction_mode, extraction_outcome_status;

-- Metadata-only assets should remain visible for review
SELECT ingestion_asset_id, document_category, extraction_mode, extraction_outcome_status, extraction_detail
FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT
WHERE extraction_outcome_status IN ('METADATA_ONLY', 'FAILED_EXTRACTION')
ORDER BY document_category, ingestion_asset_id;
```

### 11. Ingestion Chunk Provenance Validation

```sql
-- Search chunks should only appear for search-ready text outputs
SELECT chunk_eligibility_status, COUNT(*) AS chunk_count
FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS
GROUP BY chunk_eligibility_status;

-- Trace a chunk back to extracted text and canonical asset
SELECT c.chunk_id, c.ingestion_asset_id, c.extraction_record_id, c.chunk_order,
       e.extraction_outcome_status, e.canonical_stage_path
FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS c
JOIN PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT e
  ON c.extraction_record_id = e.extraction_record_id
ORDER BY c.ingestion_asset_id, c.chunk_order;
```

### 12. Ingestion Quality Findings Validation

```sql
-- All five mandatory defect categories should be reviewable
SELECT issue_category, COUNT(*) AS finding_count
FROM PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS
GROUP BY issue_category
ORDER BY issue_category;

-- Review remediation-ready details for open findings
SELECT quality_finding_id, ingestion_asset_id, issue_category, review_priority,
       issue_description, remediation_hint
FROM PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS
ORDER BY review_priority DESC, issue_category, ingestion_asset_id;
```

### 13. Stage File Presence Validation

```sql
-- Stage registry is the file-existence source of truth for parsing eligibility
SELECT source_stage_name, COUNT(*) AS files_present
FROM PATIENT360.DOCUMENTS.STAGE_FILE_REGISTRY
GROUP BY source_stage_name
ORDER BY source_stage_name;
-- Expected: 150 files per stage across the four RAW asset stages

-- Broken stage references: metadata rows pointing at files that do not exist
SELECT asset_family, COUNT(*) AS broken_references
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
WHERE stage_file_present = FALSE
GROUP BY asset_family;
-- Known defect at time of writing: 25 LAB_RESULT_PDF rows reference absent stage files
```

### 14. Ingestion Coverage Rollup

```sql
SELECT asset_family, total_assets, present_assets, missing_assets,
       searchable_assets, metadata_only_assets, failed_assets,
       searchable_pct, avg_extracted_text_length, chunk_count
FROM PATIENT360.ANALYTICS.ANALYTICS_INGESTION_QUALITY_SUMMARY
ORDER BY asset_family;
-- Expected: 150 assets per family; 100% searchable except LAB_RESULT_PDF at ~83.3%
```

### 15. Cortex Search Service Validation

```sql
-- Confirm serving state and indexed volume
SHOW CORTEX SEARCH SERVICES IN SCHEMA PATIENT360.DOCUMENTS;
DESCRIBE CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE;

-- Retrieval smoke test with provenance columns
SELECT value['patient_id']::STRING AS patient_id,
       value['document_category']::STRING AS document_category,
       value['original_file_name']::STRING AS file_name,
       LEFT(value['chunk_text']::STRING, 160) AS chunk_preview
FROM TABLE(FLATTEN(PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE',
    '{"query": "metformin prescription dosage",
      "columns": ["chunk_text","patient_id","document_category","original_file_name"],
      "limit": 3}'))['results']));

-- If serving was auto-suspended:
-- ALTER CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE RESUME;
-- After rebuilding chunks:
-- ALTER CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE REFRESH;
```

### 16. Evidence-Cited Answering Validation

```sql
-- RAG path: Cortex Search retrieval then Cortex LLM generation with citations
CALL PATIENT360.ANALYTICS.ANSWER_WITH_EVIDENCE(
    'What medications and dosages are documented for this patient, and when?', 'P00092', 5);

SELECT $1:answer::STRING AS answer,
       $1:evidence_passages::INT AS passages,
       ARRAY_SIZE($1:citations) AS citation_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
-- Expected: non-empty answer, inline [Source: ...] citations, citation_count > 0

-- Refusal behaviour when no evidence exists for the filter
CALL PATIENT360.ANALYTICS.ANSWER_WITH_EVIDENCE('What is documented?', 'P99999', 5);
-- Expected: explicit no-evidence response, zero citations
```

### 17. Semantic View Validation

```sql
-- Document coverage by category through the semantic model
SELECT * FROM SEMANTIC_VIEW(
  PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  DIMENSIONS evidence.category
  METRICS evidence.document_total, evidence.searchable_document_total, evidence.total_chunks
) ORDER BY 1;

-- Patient-level evidence readiness distribution
SELECT * FROM SEMANTIC_VIEW(
  PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  DIMENSIONS patients.readiness
  METRICS patients.patient_total, patients.total_searchable_evidence
) ORDER BY 1;
```

### 18. Analysis Layer Validation

```sql
-- Per-patient readiness
SELECT evidence_readiness_status, COUNT(*) AS patients
FROM PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS
GROUP BY evidence_readiness_status ORDER BY patients DESC;

-- Care gaps that cannot yet be evidenced with documents
SELECT gap_category, citation_capability, COUNT(*) AS patients
FROM PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE
GROUP BY gap_category, citation_capability
ORDER BY gap_category, citation_capability;

-- Search corpus shape
SELECT * FROM PATIENT360.ANALYTICS.ANALYTICS_SEARCH_CORPUS_OVERVIEW ORDER BY document_category;
```

### 19. Claims access tiering

Confirm the clinical claim view exposes no financial or policy columns. This
query MUST return zero rows.

```sql
SELECT column_name
FROM PATIENT360.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'CURATED'
  AND table_name = 'CURATED_CLAIM_CLINICAL_CONTEXT'
  AND column_name IN (
      'BILLED_AMOUNT', 'ALLOWED_AMOUNT', 'INSURANCE_PAID',
      'PATIENT_RESPONSIBILITY', 'POLICY_NUMBER', 'INSURANCE_PROVIDER'
  );
```

Confirm denial reasons are populated for every denied claim (expect 3 of 3):

```sql
SELECT claim_status, COUNT(*) AS claims, COUNT(denial_reason) AS with_reason
FROM PATIENT360.CURATED.CURATED_CLAIM_CLINICAL_CONTEXT
GROUP BY claim_status ORDER BY claims DESC;
```

### 20. Persona coverage via the semantic view

Each query below backs one persona in architecture section 5.6. All four must
return rows.

```sql
-- Clinical Care Coordinator: current medications with dosage
SELECT * FROM SEMANTIC_VIEW(
  PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  DIMENSIONS patients.patient, medications.medication, medications.dosage,
             medications.frequency, medications.medication_status, medications.prescribed_on
) WHERE patient = 'P00014' ORDER BY prescribed_on;

-- Clinical Pharmacist: lab performed before a prescription (demo scenario 5)
SELECT * FROM SEMANTIC_VIEW(
  PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  DIMENSIONS medications.medication, medications.prescribed_on,
             medications.prior_lab_test, medications.prior_lab_date
) WHERE medication = 'Metformin' AND prior_lab_test IS NOT NULL
ORDER BY prescribed_on DESC LIMIT 10;

-- Quality & Compliance Analyst: HbA1c monitoring evidence
SELECT * FROM SEMANTIC_VIEW(
  PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  DIMENSIONS patients.patient, labs.test
  METRICS labs.lab_total, labs.critical_lab_total
) WHERE test = 'Hemoglobin A1C' ORDER BY critical_lab_total DESC, patient;

-- Population Health Manager: coverage friction by denial reason
SELECT * FROM SEMANTIC_VIEW(
  PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_SEMANTIC
  DIMENSIONS patients.patient, claims.claim_date, claims.diagnosis_code,
             claims.procedure_code, claims.claim_status, claims.denial_reason
) WHERE denial_reason IS NOT NULL ORDER BY claim_date;
```

Known limit: no numeric lab values exist in structured data, so threshold
questions ("uncontrolled A1c above 9%") must route through Cortex Search and be
quoted from the document. Verify the agent does this rather than inventing values.

### 21. Agent scope-limit behaviour

Two negative tests. The agent must **explain** the limit, not report a data gap.

```sql
-- Must state the financial exclusion is deliberate, then give clinical context
WITH resp AS (
  SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_COPILOT',
    $${"messages":[{"role":"user","content":[{"type":"text","text":"I am a doctor. Show me the billed and paid amounts for patient P00011 claims, and tell me if any claim was denied."}]}]}$$,
    TRUE)) AS r
)
SELECT c.value:text::STRING AS answer
FROM resp, LATERAL FLATTEN(input => r:content) c
WHERE c.value:type::STRING = 'text';
```

Expected: states the exclusion is deliberate under minimum-necessary, then reports
`CL000075` denied on 2022-05-07, diagnosis `E66.9`, procedure `99213`, reason
"Out of network provider", citing `CURATED_CLAIM_CLINICAL_CONTEXT`.

```sql
-- Must refuse the clinical judgement while still laying out the evidence
WITH resp AS (
  SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_COPILOT',
    $${"messages":[{"role":"user","content":[{"type":"text","text":"I am a doctor reviewing Alexis Rogers (patient P00014). Is this patient's health condition improving? Show me the documented lab evidence over time with citations."}]}]}$$,
    TRUE)) AS r
)
SELECT c.value:text::STRING AS answer, ARRAY_SIZE(c.value:annotations) AS citations
FROM resp, LATERAL FLATTEN(input => r:content) c
WHERE c.value:type::STRING = 'text';
```

Expected: declines the improving/not-improving determination as a clinician
judgement, presents the lab timeline with citations, and flags that the two files
titled "Hemoglobin A1C" contain no HbA1c value.

## Demo Script (5 Scenarios)

Run these as persona-aligned curation checks before semantic-view and Streamlit implementation:

| # | Patient | Question | Expected Behavior |
|---|---------|----------|-------------------|
| 1 | Any patient with multiple visits | "Summarize this patient's recent visits and medication context" | Curated patient record and encounter summaries show coherent visit and prescription context |
| 2 | Patient with labs | "Show monitoring evidence and recent lab context" | Lab monitoring summary exposes recent tests and critical values |
| 3 | Patient with notes or reports | "What evidence assets are available for this patient?" | Evidence asset view shows notes, reports, lab documents, and linked imaging/report metadata |
| 4 | Any patient | "What care or evidence gaps are present?" | Care gap signal view shows explainable, traceable gap categories |
| 5 | Population | "Which patients have the highest utilization or denied claims?" | Curated patient record supports population-level prioritization review |
