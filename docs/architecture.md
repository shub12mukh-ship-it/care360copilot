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
|   |-- DOCUMENT_ASSET_INVENTORY             (canonical staged asset inventory)
|   |-- DOCUMENT_ASSET_MATCH_CONTEXT         (patient/report linkage outcomes)
|   |-- DOCUMENT_EXTRACTED_TEXT              (text extraction and OCR status)
|   |-- DOCUMENT_SEARCH_CHUNKS               (search-ready chunk outputs)
|   +-- DOCUMENT_INGESTION_QUALITY_FINDINGS  (missing files, broken refs, duplicates, unmatched assets)
|
+-- CURATED schema
|   |-- CURATED_PATIENT_RECORD
|   |-- CURATED_ENCOUNTER_SUMMARY
|   |-- CURATED_EVIDENCE_ASSET
|   +-- CURATED_PATIENT_TIMELINE_EVENT
|
+-- ANALYTICS schema
|   |-- SEM_PATIENT_OVERVIEW
|   +-- SEM_ENCOUNTER_OVERVIEW
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

### 5.4 Safety & Guardrails

- **System prompt enforcement**: LLM instructed to cite sources, refuse speculation, flag uncertainty
- **No real PHI**: All data is synthetic; no HIPAA obligations but architecture is PHI-ready
- **Citation requirement**: Every factual claim in a response must reference a source record
- **Disclaimer banner**: UI displays "Synthetic data only - not for clinical use"
- **No prediction endpoint**: System answers questions about existing records only

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
