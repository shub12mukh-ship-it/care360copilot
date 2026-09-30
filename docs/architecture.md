# Patient 360 Evidence Copilot - Architecture & Design

## 1. Business Problem Statement

Healthcare organizations struggle with **fragmented patient data** spread across EHRs, claims systems, lab platforms, and clinical documents. Clinicians, care coordinators, and compliance teams spend significant time manually piecing together patient histories from these disconnected sources.

**Core challenges:**
- **Data silos**: Structured records (labs, medications, claims) live in separate systems from unstructured clinical notes (discharge summaries, progress notes, radiology reports)
- **Time-to-insight**: Clinicians spend 15-30 minutes per patient assembling a longitudinal view before making care decisions
- **Evidence gaps**: Regulatory and quality teams cannot quickly trace clinical decisions back to supporting documentation
- **Safety risk**: Incomplete views lead to missed drug interactions, duplicate tests, and gaps in care continuity

**What this system does:**
A Snowflake-native copilot that unifies structured healthcare records with clinical documents, enabling natural-language questions answered with **cited evidence** from the patient record. The system uses synthetic data only and explicitly refuses to make unsupported medical predictions.

**What this system does NOT do:**
- Diagnose conditions or recommend treatments
- Make predictions about patient outcomes without explicit evidence
- Replace clinical judgment
- Process real PHI (synthetic data only for this MVP)

---

## 2. Target Users

| Persona | Role | Primary Use Cases |
|---------|------|-------------------|
| **Clinical Care Coordinator** | Manages care plans across providers | "What medications is this patient on and when were they last adjusted?" / "Summarize this patient's last 3 visits" |
| **Quality & Compliance Analyst** | Audits clinical documentation for regulatory adherence | "Show evidence of HbA1c monitoring for diabetic patients" / "Which patients are missing follow-up labs?" |
| **Population Health Manager** | Identifies at-risk cohorts and care gaps | "How many diabetic patients have uncontrolled A1c?" / "List patients with >2 ED visits in 90 days" |
| **Clinical Pharmacist** | Reviews medication safety and interactions | "What labs were ordered before starting this medication?" / "Show all active prescriptions and their indications" |

**Common requirements across all personas:**
- Answers must cite the source record (table, document, date)
- No hallucinated or inferred medical conclusions
- Sub-10-second response time for interactive use
- Role-based access (future: row-level security by care team)

---

## 3. Solution Workflow

```
User Question (natural language)
        |
        v
+-------------------+
| Streamlit UI      |  <-- Input: free-text question + optional patient filter
+-------------------+
        |
        v
+-------------------+
| Query Router      |  <-- Classifies: structured query vs. document search vs. hybrid
+-------------------+
        |
   +---------+-----------+
   |                     |
   v                     v
+-----------+    +----------------+
| Cortex    |    | Cortex Search  |  <-- Semantic search over clinical documents
| Analyst   |    | Service        |
| (SQL gen) |    +----------------+
+-----------+           |
   |                    v
   |            +----------------+
   |            | Document       |
   |            | Chunks +       |
   |            | Citations      |
   |            +----------------+
   |                    |
   v                    v
+-------------------------------+
| Evidence Assembly             |  <-- Merges structured results + document evidence
+-------------------------------+
        |
        v
+-------------------------------+
| LLM Answer Generation         |  <-- Cortex LLM (mistral-large2 / llama3.1-70b)
| with citation enforcement     |     System prompt: "cite sources, never speculate"
+-------------------------------+
        |
        v
+-------------------------------+
| Response + Citations Panel    |  <-- Answer text + expandable source evidence
+-------------------------------+
```

**Query flow detail:**

1. **Input**: User types a clinical question, optionally selects a patient
2. **Classification**: System determines if the question needs structured data (SQL), document search, or both
3. **Structured path**: Cortex Analyst or direct SQL against Patient 360 views
4. **Document path**: Cortex Search over chunked clinical notes, returns passages with source metadata
5. **Assembly**: Results from both paths are merged into a unified evidence context
6. **Generation**: LLM produces an answer with inline citations `[Source: labs.2024-03-15]`
7. **Display**: Streamlit renders the answer with an expandable citations sidebar

---

## 4. Healthcare Ontology

### 4.1 Entity Model

```
PATIENT (1)
  |
  +--< VISIT (many)
  |      |
  |      +--< CLINICAL_NOTE (many)  [unstructured - discharge summaries, progress notes]
  |
  +--< LAB_RESULT (many)
  |      |-- test_name (LOINC-aligned)
  |      |-- result_value / result_unit
  |      |-- reference_range
  |      |-- abnormal_flag
  |
  +--< MEDICATION (many)
  |      |-- drug_name (RxNorm-aligned)
  |      |-- dosage / frequency / route
  |      |-- start_date / end_date
  |      |-- prescribing_provider
  |
  +--< CLAIM (many)
         |-- diagnosis_code (ICD-10)
         |-- procedure_code (CPT)
         |-- claim_status
         |-- billed_amount / allowed_amount / paid_amount
```

### 4.2 Standard Code Systems (Synthetic Approximations)

| Domain | Standard | Example | Usage in MVP |
|--------|----------|---------|--------------|
| Diagnoses | ICD-10-CM | E11.9 (Type 2 DM) | Claims diagnosis codes |
| Procedures | CPT | 99213 (Office visit) | Claims procedure codes |
| Labs | LOINC | 4548-4 (HbA1c) | Lab test identifiers |
| Medications | RxNorm | 860975 (Metformin 500mg) | Drug identification |
| Encounters | HL7 FHIR | AMB / EMER / IMP | Visit type classification |

### 4.3 Clinical Document Types

| Document Type | Source | Content |
|---------------|--------|---------|
| Discharge Summary | Inpatient visit | Diagnoses, procedures, follow-up plan |
| Progress Note | Outpatient visit | Subjective/Objective/Assessment/Plan (SOAP) |
| Lab Report Narrative | Lab system | Interpretive comments on results |
| Medication Reconciliation | Pharmacy | Current med list with changes and rationale |

---

## 5. Snowflake Architecture

### 5.1 Infrastructure Layout

```
PATIENT360
|
+-- RAW schema
|   |-- PATIENTS           (staged from CSV)
|   |-- VISITS             (staged from CSV)
|   |-- LABS               (staged from CSV)
|   |-- MEDICATIONS        (staged from CSV)
|   |-- CLAIMS             (staged from CSV)
|   |-- CLINICAL_NOTES     (generated synthetic documents)
|   +-- STAGE: @patient360_stage  (file landing zone)
|
+-- DOCUMENTS schema
|   |-- STAGE_FILE_REGISTRY                    (DIRECTORY-backed file existence source of truth)
|   |-- DOCUMENT_ASSET_INVENTORY               (canonical staged asset inventory, table)
|   |-- DOCUMENT_ASSET_MATCH_CONTEXT           (patient/report linkage outcomes)
|   |-- DOCUMENT_EXTRACTED_TEXT_TABLE          (materialized AI_PARSE_DOCUMENT output)
|   |-- DOCUMENT_SEARCH_CHUNKS_TABLE           (deterministic 800/100 chunks)
|   |-- DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE (missing files, broken refs, duplicates, unmatched)
|   +-- CORTEX_SEARCH_SERVICE: DOCUMENT_SEARCH_SERVICE
|
+-- CURATED schema
|   |-- CURATED_PATIENT_RECORD
|   |-- CURATED_ENCOUNTER_SUMMARY
|   |-- CURATED_MEDICATION_EVIDENCE_SUMMARY
|   |-- CURATED_LAB_MONITORING_SUMMARY
|   |-- CURATED_CARE_GAP_SIGNAL
|   |-- CURATED_EVIDENCE_ASSET
|   |-- CURATED_DOCUMENT_EVIDENCE             (ingestion-backed document evidence)
|   |-- CURATED_CLAIM_CLINICAL_CONTEXT       (claims WITHOUT financials or policy ids)
|   +-- CURATED_PATIENT_TIMELINE_EVENT
|
+-- ANALYTICS schema
|   |-- SEM_PATIENT_OVERVIEW
|   |-- SEM_ENCOUNTER_OVERVIEW
|   |-- ANALYTICS_INGESTION_QUALITY_SUMMARY
|   |-- ANALYTICS_PATIENT_EVIDENCE_READINESS
|   |-- ANALYTICS_SEARCH_CORPUS_OVERVIEW
|   |-- ANALYTICS_CARE_GAP_WITH_EVIDENCE
|   |-- PROCEDURE: ANSWER_WITH_EVIDENCE        (Cortex Search + Cortex LLM, cited)
|   |-- SEMANTIC VIEW: PATIENT360_EVIDENCE_SEMANTIC
|   +-- AGENT: PATIENT360_EVIDENCE_COPILOT    (Analyst + Search orchestration)
|
+-- APP schema
    +-- Streamlit app (streamlit_app.py)
```

### 5.2 Snowflake Services Used

| Service | Purpose | How Used |
|---------|---------|----------|
| **Cortex Search** | Semantic search over clinical documents | Index `PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS`; retrieve relevant passages for RAG |
| **Cortex LLM (AI_COMPLETE)** | Answer generation with citations | Generate natural-language answers from retrieved evidence |
| **Cortex AI_EXTRACT** | (Optional) Parse structured fields from clinical notes | Extract diagnoses, medications mentioned in free-text |
| **Snowflake Stages** | Data landing zone | Load CSV/JSON synthetic data |
| **Dynamic Tables** | Materialized Patient 360 | Auto-refresh unified patient view |
| **Streamlit in Snowflake** | Application UI | Interactive copilot interface |

### 5.3 Data Flow

```
1. LOAD:     CSV files --> RAW tables and staged PDFs/images in `PATIENT360.RAW`
2. INGEST:   RAW metadata + RAW stages --> DOCUMENTS canonical asset inventory and match context
3. EXTRACT:  DOCUMENTS asset inventory --> DOCUMENTS extracted text / OCR classification
4. CHUNK:    DOCUMENTS extracted text --> DOCUMENTS search chunks
5. INDEX:    DOCUMENTS search chunks --> Cortex Search Service
6. ENRICH:   RAW tables + DOCUMENTS standardized ingestion outputs --> CURATED business entities --> ANALYTICS summaries
7. QUERY:    User question --> Cortex Search + SQL --> Evidence context
8. ANSWER:   Evidence context --> Cortex LLM --> Cited answer
```

### 5.3.1 Ingestion Implementation Constraints

Two platform constraints shaped the ingestion design and must be preserved:

- **`AI_PARSE_DOCUMENT` cannot sit inside a view that feeds Cortex Search.** Cortex
  Search requires change tracking, which is unsupported over non-deterministic
  functions. Parsing is therefore materialized into
  `DOCUMENT_EXTRACTED_TEXT_TABLE`, and chunking/search read only from tables.
- **`AI_PARSE_DOCUMENT` raises a hard error on a missing staged file** rather than
  returning NULL, so a single absent file fails the whole statement. File presence
  is confirmed first via `STAGE_FILE_REGISTRY` (built from `DIRECTORY()`), and
  parsing runs in per-family batches gated on `stage_file_present = TRUE`.

Assets that cannot be parsed are never dropped: they stay in the inventory with an
explicit `processing_status` and surface in `DOCUMENT_INGESTION_QUALITY_FINDINGS`.

### 5.4 Safety & Guardrails

- **System prompt enforcement**: LLM instructed to cite sources, refuse speculation, flag uncertainty
- **No real PHI**: All data is synthetic; no HIPAA obligations but architecture is PHI-ready
- **Citation requirement**: Every factual claim in a response must reference a source record
- **Disclaimer banner**: UI displays "Synthetic data only - not for clinical use"
- **No prediction endpoint**: System answers questions about existing records only

### 5.5 Claims Access Tiering (minimum-necessary)

`RAW.INSURANCE_CLAIMS` carries 17 columns that split into three tiers. Only the
clinical tier reaches the semantic view, via `CURATED_CLAIM_CLINICAL_CONTEXT`.

| Tier | Columns | Exposed to care team? | Rationale |
|------|---------|----------------------|-----------|
| Clinical | `DIAGNOSIS_CODE` (ICD-10), `PROCEDURE_CODE` (CPT), `PROCEDURE_DESCRIPTION`, `CLAIM_STATUS`, `DENIAL_REASON`, `CLAIM_DATE` | Yes | A denial is care friction: it predicts medication abandonment and missed follow-up, so it is clinically actionable |
| Financial | `BILLED_AMOUNT`, `ALLOWED_AMOUNT`, `INSURANCE_PAID`, `PATIENT_RESPONSIBILITY` | No | The billed-vs-paid spread never changes a care decision |
| Administrative | `POLICY_NUMBER`, `INSURANCE_PROVIDER` | No | Payer identifiers with no clinical value |

The agent is instructed to state that this exclusion is **deliberate** when asked
for amounts, rather than reporting a data gap.

**Known limitation — this is a modelling boundary, not an enforced one.** Any role
with `SELECT` on `PATIENT360.RAW` can still read the excluded columns directly.
The account has a single working role (`CARE360_RW_ROLE`), so clinician, analyst,
and pipeline operator are currently the same principal. `ROW ACCESS POLICY` is
unsupported on this account edition, but `VISITS.DOCTOR_ID` links 43 doctors to 23
patients (avg 4.4 each), so care-team scoping is achievable with a **secure view**
filtering on a `CURRENT_USER()` to `DOCTOR_ID` mapping table. RBAC and row-level
security remain out of MVP scope by design (see section 6).

### 5.6 Persona Coverage

The four target users in section 2 are served by two tools on one agent:
`Patient360Analyst` (semantic view to SQL) and `EvidenceSearch` (Cortex Search).

| Persona | Primary path | Status |
|---------|--------------|--------|
| Clinical Care Coordinator | Analyst: `medication_name`, `dosage`, `frequency`, `medication_status`, `prescription_date` | Structured + documents |
| Quality & Compliance Analyst | Analyst: `test_type`, `critical_flag`, monitoring recency; then Search to cite the report | Structured + documents |
| Population Health Manager | Analyst: `test_type` + `critical_flag` cohorts, care gap counts | **Partial** — see limitation below |
| Clinical Pharmacist | Analyst: `latest_prior_lab_test_type` / `latest_prior_lab_test_date`, precomputed per prescription | Structured + documents |

**Population Health limitation.** `RAW.LAB_RESULTS` has no result-value column —
only `TEST_TYPE`, `TEST_CODE`, `STATUS`, and `CRITICAL_FLAG`. Numeric lab values
exist **only inside the parsed lab PDF text**. So "patients with a critical A1C
result" is answerable from structured data, but threshold questions such as
"uncontrolled A1c above 9%" are not; they must go through `EvidenceSearch` and be
quoted from the document. The agent's orchestration instructions encode this route.

Also note only **23 of 100 patients** have any visit or claim history, so
claims-based and encounter-based demos are limited to that subset.

---

## 6. MVP Scope (2-Day Hackathon)

### Day 1: Data Foundation + Search Pipeline

| Task | Deliverable |
|------|-------------|
| Generate synthetic CSV data | 5 tables: patients (20), visits (80), labs (200), medications (100), claims (150) |
| Generate synthetic clinical notes | 30-40 clinical documents (discharge summaries, progress notes) |
| Create Snowflake objects | Database, schemas, tables, stages, file formats |
| Load data | COPY INTO from stage for all tables |
| Build Patient 360 view | Unified view joining all structured data per patient |
| Chunk clinical documents | Split notes into passages with metadata |
| Create Cortex Search Service | Index chunked documents |
| Test search retrieval | Validate relevant passages returned for sample queries |

### Day 2: Copilot Application

| Task | Deliverable |
|------|-------------|
| Build Streamlit UI | Patient selector, question input, answer display, citations panel |
| Implement RAG pipeline | Cortex Search retrieval + LLM answer generation |
| Add structured query path | SQL queries for medication lists, lab trends, visit history |
| Citation formatting | Inline citations with expandable source evidence |
| Safety guardrails | System prompt, disclaimer, refusal for unsupported predictions |
| Demo preparation | 5 scripted demo questions with expected outputs |

### MVP Feature Set

**In scope:**
- [x] Natural-language questions about a patient's record
- [x] Combined structured + unstructured evidence retrieval
- [x] Inline citations with source traceability
- [x] Patient selector with demographics summary
- [x] Safety disclaimers and prediction refusal
- [x] 5 pre-built demo scenarios

**Out of scope (future):**
- [ ] Role-based access control / row-level security
- [ ] Real-time data ingestion (Snowpipe)
- [ ] Multi-patient population queries
- [ ] FHIR API integration
- [ ] Audit logging of all queries and responses
- [ ] Fine-tuned clinical embedding model

### Demo Scenarios

1. **Medication review**: "What medications is patient John Smith currently taking, and when were they last changed?"
2. **Lab trend**: "Show me the HbA1c results for patient Maria Garcia over the past year"
3. **Care gap detection**: "Which diabetic patients are missing their annual eye exam?"
4. **Document search**: "What did the discharge summary say about follow-up care for patient after hip replacement?"
5. **Cross-record evidence**: "What labs were ordered before starting Metformin for this patient, and what were the results?"
