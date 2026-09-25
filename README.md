# Care360 Evidence Copilot

A Snowflake-native clinical decision-support application that unifies structured healthcare records (labs, medications, diagnoses, visits, claims) with unstructured clinical documents (discharge summaries, progress notes, guidelines, policies) to answer natural-language clinical questions with cited evidence.

Built entirely on Snowflake: Cortex LLM, Cortex Search, Snowpark, and Streamlit in Snowflake. No external APIs, no third-party LLM providers, no data egress.

> **Synthetic data only.** This project uses 20 fictional patients with fabricated medical records. No real Protected Health Information (PHI) is present anywhere in this repository.

---

## Table of Contents

- [Business Problem Statement](#business-problem-statement)
- [Target Users](#target-users)
- [Architecture Overview](#architecture-overview)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Data Flow](#data-flow)
- [Database Schema Design](#database-schema-design)
- [Application Screens](#application-screens)
- [Cortex Agent](#cortex-agent)
- [Setup Guide](#setup-guide)
- [Spec-Driven Development (Spec Kit)](#spec-driven-development-spec-kit)
- [Constitution & Compliance](#constitution--compliance)
- [CI/CD Pipeline](#cicd-pipeline)
- [Testing & Validation](#testing--validation)
- [Team Onboarding](#team-onboarding)

---

## Business Problem Statement

This hackathon brief is the authoritative problem statement for the application.
The repository, architecture, agent behavior, and future implementation work
must remain aligned to it.

Healthcare organizations struggle with fragmented patient data spread across
EHRs, claims systems, lab platforms, and clinical documents. Clinicians, care
coordinators, and compliance teams spend significant time manually piecing
together patient histories from these disconnected sources.

### Core challenges

- **Data silos**: Structured records (labs, medications, claims) live in
  separate systems from unstructured clinical notes (discharge summaries,
  progress notes, radiology reports).
- **Time-to-insight**: Clinicians spend 15-30 minutes per patient assembling a
  longitudinal view before making care decisions.
- **Evidence gaps**: Regulatory and quality teams cannot quickly trace clinical
  decisions back to supporting documentation.
- **Safety risk**: Incomplete views lead to missed drug interactions, duplicate
  tests, and gaps in care continuity.

### What this system does

- Provides a Snowflake-native copilot that unifies structured healthcare
  records with clinical documents.
- Enables natural-language questions answered with cited evidence from the
  patient record.
- Uses synthetic data only.
- Explicitly refuses to make unsupported medical predictions.

### What this system does NOT do

- Diagnose conditions or recommend treatments.
- Make predictions about patient outcomes without explicit evidence.
- Replace clinical judgment.
- Process real PHI in this MVP.

---

## Target Users

| Persona | Role | Primary Use Cases |
|---------|------|-------------------|
| Clinical Care Coordinator | Manages care plans across providers | "What medications is this patient on and when were they last adjusted?" / "Summarize this patient's last 3 visits" |
| Quality & Compliance Analyst | Audits clinical documentation for regulatory adherence | "Show evidence of HbA1c monitoring for diabetic patients" / "Which patients are missing follow-up labs?" |
| Population Health Manager | Identifies at-risk cohorts and care gaps | "How many diabetic patients have uncontrolled A1c?" / "List patients with >2 ED visits in 90 days" |
| Clinical Pharmacist | Reviews medication safety and interactions | "What labs were ordered before starting this medication?" / "Show all active prescriptions and their indications" |

### Common requirements across all personas

- Answers must cite the source record (table, document, date).
- No hallucinated or inferred medical conclusions.
- Sub-10-second response time for interactive use.
- Role-based access is a future requirement, with row-level security by care team.

---

## Architecture Overview

```
                           +------------------+
                           |   Streamlit UI   |
                           |  (Patient 360)   |
                           +--------+---------+
                                    |
                         +----------+----------+
                         |    Query Router     |
                         +----+----------+----+
                              |          |
                 +------------+    +-----+-----------+
                 |                 |                  |
        +--------v-------+  +-----v------+  +-------v--------+
        | Cortex Analyst  |  |  Cortex    |  | Structured     |
        | (Text-to-SQL)   |  |  Search    |  | Context Build  |
        +---------+------+  +-----+------+  +-------+--------+
                  |               |                  |
                  +-------+-------+------------------+
                          |
                  +-------v--------+
                  |   Evidence     |
                  |   Assembly     |
                  +-------+--------+
                          |
                  +-------v--------+
                  | Cortex LLM     |
                  | (llama3.1-70b) |
                  +-------+--------+
                          |
                  +-------v--------+
                  | Response with  |
                  | Citations +    |
                  | Contradiction  |
                  | Detection      |
                  +----------------+
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Database | Snowflake (`CARE360_DB`) with 4 schemas |
| Warehouse | `CARE360_WH` (XSMALL, auto-suspend 120s) |
| LLM | Snowflake Cortex — `llama3.1-70b` (app) / `mistral-large2` (pipeline) |
| Search/RAG | Cortex Search Service over chunked clinical documents |
| Document Parsing | `AI_PARSE_DOCUMENT()` with layout mode + page splitting |
| Text Chunking | `SPLIT_TEXT_RECURSIVE_CHARACTER()` (800 char, 100 overlap) |
| Frontend | Streamlit in Snowflake |
| Agent | Cortex Agent (`agent_spec.yaml`) |
| Python | `streamlit>=1.30.0`, `snowflake-snowpark-python>=1.11.0` |

---

## Repository Structure

```
care360copilot/
├── app/
│   └── streamlit_app.py              # Streamlit application (3 screens)
│
├── data/                              # Synthetic CSV datasets (20 patients)
│   ├── patients.csv                   # Demographics, insurance, risk scores
│   ├── diagnosis.csv                  # ICD-10 codes, severity, chronic flags
│   ├── labs.csv                       # Test results, reference ranges
│   ├── medications.csv                # Prescriptions, dosage, refills
│   ├── visits.csv                     # Encounters, visit types, LOS
│   └── claims.csv                     # Billing, CPT codes, denial reasons
│
├── documents/                         # Synthetic clinical PDFs
│   ├── clinical_notes/                # Patient-specific notes (P1007)
│   ├── guidelines/                    # Diabetes & hypertension guidelines
│   └── regulatory/                    # SOPs and documentation policies
│
├── sql/
│   ├── setup.sql                      # Database, schemas, tables, stages
│   ├── load_data.sql                  # CSV loading with validation
│   ├── transform.sql                  # RAW -> CURATED views (7 views)
│   ├── patient360.sql                 # CURATED -> ANALYTICS views (3 views)
│   ├── pipeline.sql                   # LLM-generated clinical notes pipeline
│   └── documents_pipeline.sql         # PDF ingestion -> Cortex Search
│
├── scripts/
│   └── generate_clinical_pdfs.py      # Pure-Python PDF generator (7 documents)
│
├── docs/
│   ├── architecture.md                # Full architecture design document
│   └── testing.md                     # Validation queries and demo scenarios
│
├── agent_spec.yaml                    # Cortex Agent configuration
├── requirements.txt                   # Python dependencies
│
├── .specify/                          # Spec Kit project configuration
│   └── memory/
│       └── constitution.md            # Project constitution (v2.0.0)
│
└── .github/
    └── workflows/
        └── constitution-check.yml     # CI compliance enforcement
```

---

## Data Flow

The application processes data through a 7-step pipeline:

```
1. LOAD      CSV files -> @care360_stage -> RAW tables (COPY INTO)
2. PARSE     PDFs -> @CLINICAL_DOCUMENT_STAGE -> AI_PARSE_DOCUMENT -> DOCUMENT_METADATA
3. CHUNK     DOCUMENT_METADATA -> section split + recursive chunking -> DOCUMENT_CHUNKS
4. INDEX     DOCUMENT_CHUNKS -> Cortex Search Service (CLINICAL_DOCUMENT_SEARCH)
5. TRANSFORM RAW tables -> CURATED views (diagnosis summary, lab summary, med gaps, etc.)
6. QUERY     User question -> Cortex Search + structured SQL -> evidence context
7. ANSWER    Evidence context -> Cortex LLM (COMPLETE) -> cited answer + contradiction detection
```

---

## Database Schema Design

### RAW (source-of-truth ingested data)

| Table | Columns | Key Fields |
|-------|---------|------------|
| `PATIENTS` | 26 | patient_id, name, DOB, insurance, risk_score |
| `DIAGNOSIS` | 12 | ICD-10 code, severity, chronic flag |
| `MEDICATIONS` | 17 | NDC, dosage, refills, drug class |
| `LABS` | 14 | test code (LOINC), reference ranges, abnormal flag |
| `VISITS` | 11 | visit type, diagnosis, length of stay |
| `CLAIMS` | 19 | CPT code, billing amounts, denial reason |

### CURATED (enriched views from RAW)

| View | Purpose |
|------|---------|
| `PATIENT_DIAGNOSIS_SUMMARY` | Active/chronic counts, severity, ICD-10 list |
| `PATIENT_LATEST_LABS` | Latest result per test with abnormal categorization |
| `PATIENT_LAB_SUMMARY` | Pivoted HbA1c, LDL, creatinine, glucose per patient |
| `PATIENT_MEDICATION_GAPS` | Expired, no-refill, recently-stopped medications |
| `PATIENT_FOLLOWUP_GAPS` | Missing HbA1c, chronic no-visit, high ED utilization |
| `PATIENT_VISIT_SUMMARY` | Visit counts by type, claims rollup |
| `PATIENT_360` | Master view joining all of the above |

### ANALYTICS (aggregated views)

| View | Purpose |
|------|---------|
| `PATIENT_360_VIEW` | One-row-per-patient with all metrics |
| `PATIENT_TIMELINE` | Chronological union of all events |
| `CARE_GAPS` | Rule-based care gap identification |

### DOCUMENTS (clinical document pipeline)

| Object | Purpose |
|--------|---------|
| `CLINICAL_DOCUMENT_STAGE` | Internal stage for PDF storage |
| `PARSED_DOCUMENTS` | AI_PARSE_DOCUMENT output |
| `DOCUMENT_METADATA` | Flattened pages with extracted metadata |
| `DOCUMENT_CHUNKS` | Searchable text chunks (800 chars, 100 overlap) |
| `CLINICAL_DOCUMENT_SEARCH` | Cortex Search Service |

---

## Application Screens

The Streamlit app (`app/streamlit_app.py`) has three screens:

### 1. Patient Search

Search and filter patients by ID, name, or risk score. Displays patient cards with demographics, PCP, BMI, smoking status, and a color-coded risk badge. Click "View 360" to navigate to the dashboard.

### 2. Patient 360 Dashboard

KPI row showing: total visits, active medications, abnormal labs, active diagnoses, denied claims, and care gaps. Six tabs:

| Tab | Data Source |
|-----|------------|
| Diagnoses | `CURATED.PATIENT_DIAGNOSIS_SUMMARY` |
| Medications | `RAW.MEDICATIONS` |
| Labs | `CURATED.PATIENT_LATEST_LABS` |
| Visits | `RAW.VISITS` |
| Care Gaps | `CURATED.PATIENT_MEDICATION_GAPS` + `PATIENT_FOLLOWUP_GAPS` |
| Claims | `RAW.CLAIMS` |

### 3. Ask Copilot (Clinical Evidence Chat)

Natural-language Q&A with a RAG pipeline:
1. Cortex Search retrieves relevant clinical documents (filtered by patient_id)
2. Structured context is built from active medications, recent labs, and diagnosis history
3. LLM generates an answer with mandatory citations (source document, page, date)
4. Contradiction detection scans the response for conflicting evidence
5. An expandable Evidence Panel shows source documents with excerpts

---

## Cortex Agent

The `agent_spec.yaml` configures a standalone Cortex Agent with two tools:

| Tool | Type | Purpose |
|------|------|---------|
| `patient_data` | `cortex_analyst_text_to_sql` | Queries structured patient data via natural language |
| `clinical_docs` | `cortex_search` | Searches clinical documents, guidelines, and protocols |

The agent routes questions based on intent: structured data questions go to `patient_data`, document questions go to `clinical_docs`, and comprehensive reviews call both tools sequentially.

Safety rules in the agent instructions enforce the same constraints as the Streamlit app: no diagnoses, no prescriptions, mandatory citations, and explicit contradiction detection.

---

## Setup Guide

### Prerequisites

- Snowflake account with `ACCOUNTADMIN` or equivalent role
- Python 3.11+
- Git

### Step-by-step

```bash
# 1. Clone and enter project
git clone <repository-url>
cd care360copilot

# 2. Run SQL scripts in order
#    Execute each in Snowflake (Worksheets or CLI):
#    a) Create infrastructure
snowsql -f sql/setup.sql

#    b) Upload CSV data files to stage
#       PUT file://data/patients.csv @CARE360_DB.RAW.care360_stage/patients/;
#       (repeat for all 6 CSVs)

#    c) Load data
snowsql -f sql/load_data.sql

#    d) Create curated views
snowsql -f sql/transform.sql

#    e) Create analytics views
snowsql -f sql/patient360.sql

# 3. Generate and upload clinical PDFs
python scripts/generate_clinical_pdfs.py
#    PUT files to @CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE
#    Then run:
snowsql -f sql/documents_pipeline.sql

# 4. Deploy Streamlit app
#    Upload app/streamlit_app.py to Streamlit in Snowflake
#    Set warehouse to CARE360_WH

# 5. Deploy Cortex Agent
#    Upload agent_spec.yaml to Cortex Agent in Snowflake
```

### Verify setup

```sql
-- Check row counts
SELECT 'PATIENTS' AS TBL, COUNT(*) FROM CARE360_DB.RAW.PATIENTS
UNION ALL SELECT 'VISITS', COUNT(*) FROM CARE360_DB.RAW.VISITS
UNION ALL SELECT 'LABS', COUNT(*) FROM CARE360_DB.RAW.LABS;

-- Check Cortex Search
SHOW CORTEX SEARCH SERVICES IN SCHEMA CARE360_DB.DOCUMENTS;

-- Check curated views
SELECT * FROM CARE360_DB.CURATED.PATIENT_360 LIMIT 5;
```

---

## Spec-Driven Development (Spec Kit)

This project uses [Spec Kit](https://github.com/github/spec-kit) (v1.0.11) for structured, spec-driven development. Spec Kit gives AI coding agents documented processes, reusable templates, and traceable outcomes.

### Installation

```bash
pip install specify-cli
specify init . --integration claude --force
```

### Workflow

Spec Kit enforces a structured development lifecycle. Each step is invoked as a skill in your coding agent's chat:

```
Step 1: /speckit-constitution    Establish project principles (done — v2.0.0)
Step 2: /speckit-specify         Define what to build from requirements
Step 3: /speckit-plan            Create technical implementation plan
Step 4: /speckit-tasks           Generate ordered, actionable tasks
Step 5: /speckit-implement       Execute tasks against the plan
Step 6: /speckit-converge        Assess codebase vs spec, append remaining work
```

Repeat steps 5-6 until convergence reports "Converged."

### Enhancement skills (optional)

| Skill | When to use |
|-------|------------|
| `/speckit-clarify` | Before planning — ask structured questions to de-risk ambiguity |
| `/speckit-analyze` | After tasks — cross-artifact consistency and alignment report |
| `/speckit-checklist` | After planning — generate quality validation checklists |

### Project artifacts

Spec Kit stores all artifacts in the `.specify/` directory:

```
.specify/
├── memory/
│   └── constitution.md        # Project constitution (principles + governance)
├── templates/                 # Customizable process templates
├── scripts/                   # Shared automation scripts
└── workflows/                 # Workflow definitions
```

The constitution at `.specify/memory/constitution.md` defines 8 core principles and structural compliance requirements that govern all development. See [Constitution & Compliance](#constitution--compliance) below.

---

## Constitution & Compliance

The project constitution (v2.0.0) defines non-negotiable principles enforced by CI:

### Core Principles (I-V)

| # | Principle | Rule |
|---|-----------|------|
| I | Patient Safety & Data Integrity | Never diagnose; frame as "findings for clinician review" |
| II | Evidence-Cited Responses Only | Every answer cites source document, page, and date |
| III | Snowflake-Native Architecture | All compute within Snowflake; no external APIs |
| IV | Synthetic Data & PHI Boundary | No real PHI; patient IDs P1001-P1020 only |
| V | Layered Data Pipeline | RAW -> CURATED -> ANALYTICS; no schema bypass |

### Regulatory Compliance (VI-VIII)

| # | Principle | Frameworks |
|---|-----------|------------|
| VI | Data Privacy & Regulatory Compliance | HIPAA/HITECH, GDPR, DPDP Act |
| VII | Software as a Medical Device (SaMD) | FDA, EU MDR, CDSCO |
| VIII | Engineering Lifecycle & Quality | IEC 62304, ISO 13485, ISO 14971 |

### Structural Requirements

| Area | Requirement |
|------|-------------|
| Access Control | RBAC + MFA; least privilege; 15-min session timeout |
| Data Encryption | AES-256 at rest; TLS 1.2+ in transit; no hardcoded keys |
| Audit Logging | Immutable logs of all patient data access; 6-year retention |
| Consent Architecture | Granular, revocable consent; clear non-technical language |

---

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/constitution-check.yml`) runs on every PR and push to `main`. It enforces the constitution through 5 parallel jobs:

| Job | Checks | Blocking |
|-----|--------|----------|
| **Core Principles (I-V)** | Diagnostic language, citation enforcement, external deps, PHI patterns, schema boundaries | Yes |
| **Regulatory Compliance (VI-VIII)** | Hardcoded secrets, PHI in logs, autonomous clinical actions, architecture docs | Yes |
| **Structural Compliance** | RBAC bypasses, unencrypted URLs, audit log tampering, consent presence | Yes |
| **Data Breach Prevention** | SSN patterns, credential leaks in diffs, `pip-audit` vulnerability scan | Yes |
| **Development Workflow** | Agent spec alignment, unapproved dependencies, uncommented thresholds | Yes |

A final summary job reports the overall compliance status and fails the check if any job failed.

To enforce: in GitHub **Settings > Branches > Branch protection rules** for `main`, enable "Require status checks to pass before merging" and select the **Compliance Summary** check.

---

## Testing & Validation

Validation queries and demo scenarios are documented in `docs/testing.md`:

| Category | What it validates |
|----------|-------------------|
| Data Integrity | Row counts, NULL primary keys, orphan records across foreign keys |
| Patient 360 Views | Count verification, spot checks, cross-validation |
| Timeline View | Event type distribution, chronological ordering |
| Cortex Search | Service existence, basic search, filtered search by patient |
| LLM Generation | Connection test, citation enforcement, prediction refusal |
| Care Gaps | Diabetic patient gap detection, HbA1c threshold rules |

### Demo scenarios

1. "What medications is patient P1007 currently taking?"
2. "Show me HbA1c trends for diabetic patients"
3. "What does the discharge summary say about follow-up for P1007?"
4. "Will patient P1007's condition improve?" (should be refused)
5. "Which patients have care gaps?"

---

## Team Onboarding

### Checklist

- [ ] Snowflake account provisioned
- [ ] `CARE360_DEV_ROLE` assigned
- [ ] Git repository access granted
- [ ] Repository cloned
- [ ] Database access verified (`SHOW SCHEMAS IN DATABASE CARE360_DB;`)
- [ ] Streamlit app access verified (Projects > Streamlit Apps > PATIENTCARE360)
- [ ] Cortex Agent access verified (AI & ML > Agents > CARE360 Agent)
- [ ] Development branch created

### Verify access

```sql
SELECT CURRENT_ROLE();
SHOW DATABASES;
SHOW SCHEMAS IN DATABASE CARE360_DB;
SHOW STREAMLITS;
```

### Git workflow

```bash
git checkout -b feature/my-change
# make changes
git add .
git commit -m "description of change"
git push -u origin feature/my-change
# open PR — CI will run constitution compliance checks
```
