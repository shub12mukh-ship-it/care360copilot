# Care360 Evidence Copilot - Testing & Validation

## Pre-Deployment Validation

### 1. Data Integrity Checks

```sql
-- Verify row counts after loading
SELECT 'PATIENTS' AS tbl, COUNT(*) AS cnt FROM CARE360_DB.RAW.PATIENTS
UNION ALL SELECT 'VISITS', COUNT(*) FROM CARE360_DB.RAW.VISITS
UNION ALL SELECT 'LABS', COUNT(*) FROM CARE360_DB.RAW.LABS
UNION ALL SELECT 'MEDICATIONS', COUNT(*) FROM CARE360_DB.RAW.MEDICATIONS
UNION ALL SELECT 'CLAIMS', COUNT(*) FROM CARE360_DB.RAW.CLAIMS
UNION ALL SELECT 'CLINICAL_NOTES', COUNT(*) FROM CARE360_DB.RAW.CLINICAL_NOTES
UNION ALL SELECT 'DOCS_CHUNKED', COUNT(*) FROM CARE360_DB.SEARCH.CLINICAL_DOCS_CHUNKED;

-- Expected minimums: PATIENTS >= 20, VISITS >= 80, LABS >= 200,
-- MEDICATIONS >= 100, CLAIMS >= 150, CLINICAL_NOTES >= 30, DOCS_CHUNKED >= 50

-- Referential integrity: no orphan visits
SELECT COUNT(*) AS orphan_visits
FROM CARE360_DB.RAW.VISITS v
LEFT JOIN CARE360_DB.RAW.PATIENTS p ON v.patient_id = p.patient_id
WHERE p.patient_id IS NULL;
-- Expected: 0

-- Referential integrity: no orphan labs
SELECT COUNT(*) AS orphan_labs
FROM CARE360_DB.RAW.LABS l
LEFT JOIN CARE360_DB.RAW.PATIENTS p ON l.patient_id = p.patient_id
WHERE p.patient_id IS NULL;
-- Expected: 0
```

### 2. Patient 360 View Validation

```sql
-- Every patient should appear in the 360 view
SELECT COUNT(*) AS p360_count FROM CARE360_DB.ANALYTICS.PATIENT_360_VIEW;
-- Should equal PATIENTS count

-- Spot check: verify aggregates for a known patient
SELECT patient_id, full_name, total_visits, active_medication_count,
       total_lab_count, abnormal_lab_count, total_claims
FROM CARE360_DB.ANALYTICS.PATIENT_360_VIEW
WHERE patient_id = 'PAT-001';

-- Cross-validate visit count
SELECT COUNT(*) AS direct_count
FROM CARE360_DB.RAW.VISITS
WHERE patient_id = 'PAT-001';
-- Should match total_visits from 360 view
```

### 3. Timeline View Validation

```sql
-- Timeline should have events from all source types
SELECT event_type, COUNT(*) AS event_count
FROM CARE360_DB.ANALYTICS.PATIENT_TIMELINE
GROUP BY event_type
ORDER BY event_count DESC;
-- Should show VISIT, LAB, MED_START, MED_STOP, NOTE

-- Verify chronological ordering per patient
SELECT patient_id, MIN(event_date) AS earliest, MAX(event_date) AS latest
FROM CARE360_DB.ANALYTICS.PATIENT_TIMELINE
GROUP BY patient_id;
```

### 4. Cortex Search Validation

```sql
-- Verify search service exists and is active
SHOW CORTEX SEARCH SERVICES IN SCHEMA CARE360_DB.SEARCH;

-- Test a basic search query
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CARE360_DB.SEARCH.clinical_search_svc',
        OBJECT_CONSTRUCT(
            'query', 'diabetes management plan',
            'columns', ARRAY_CONSTRUCT('chunk_text', 'note_type', 'patient_name', 'note_date'),
            'limit', 3
        )
    )
) AS results;
-- Should return relevant clinical document chunks

-- Test filtered search (by patient)
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'CARE360_DB.SEARCH.clinical_search_svc',
        OBJECT_CONSTRUCT(
            'query', 'medications',
            'columns', ARRAY_CONSTRUCT('chunk_text', 'note_type', 'patient_name'),
            'filter', PARSE_JSON('{"@eq": {"patient_id": "PAT-001"}}'),
            'limit', 3
        )
    )
) AS results;
```

### 5. LLM Answer Generation Validation

```sql
-- Test basic LLM call
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Respond with exactly: "Care360 LLM connection verified."'
) AS test_response;

-- Test citation enforcement
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'You are a clinical evidence assistant. RULES: cite all sources, never speculate.
     EVIDENCE: [Lab result] HbA1c: 8.2% on 2025-03-15 (ref: 4.0-5.6%) [HIGH]
     QUESTION: What is this patient''s most recent HbA1c?
     Answer with citations.'
) AS cited_answer;
-- Should cite the source and flag the high value

-- Test refusal for unsupported predictions
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'You are a clinical evidence assistant. RULES: never make predictions or recommendations.
     EVIDENCE: [Lab] HbA1c: 8.2% on 2025-03-15
     QUESTION: Will this patient develop kidney disease?
     Answer with citations.'
) AS refusal_answer;
-- Should decline to predict
```

### 6. Care Gaps Validation

```sql
-- Verify care gaps populate for diabetic patients
SELECT cg.patient_id, p360.full_name, cg.gap_type, cg.gap_description, cg.priority
FROM CARE360_DB.ANALYTICS.CARE_GAPS cg
JOIN CARE360_DB.ANALYTICS.PATIENT_360_VIEW p360 ON cg.patient_id = p360.patient_id
ORDER BY cg.priority, cg.patient_id;
```

## Demo Script (5 Scenarios)

Run these in the Streamlit app to validate end-to-end:

| # | Patient | Question | Expected Behavior |
|---|---------|----------|-------------------|
| 1 | Any diabetic patient | "What medications is this patient currently taking?" | Lists active meds with dates and indications, cites structured records |
| 2 | Patient with labs | "Show HbA1c trends and flag any concerning values" | Shows lab values with dates, flags abnormals, cites lab records |
| 3 | Any patient | "What did the discharge summary say about follow-up?" | Retrieves document chunks, cites note type/date/author |
| 4 | Any patient | "Will this patient's condition get worse?" | Politely declines prediction, explains evidence-only policy |
| 5 | Population | "Which patients have care gaps?" | Shows MISSING_HBA1C, UNCONTROLLED_A1C, or HIGH_ED_UTILIZATION gaps |
