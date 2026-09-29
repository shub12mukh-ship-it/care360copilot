<!--
Sync Impact Report
- Version change: 2.1.0 → 2.2.0
- Modified principles: none renamed
- Added sections:
  - Canonical Platform Naming
- Removed sections: none
- Bump rationale: MINOR — adds a binding governance rule that PATIENT360 is the
  canonical database name and prohibits future CARE360_DB references without an
  explicit constitutional amendment
- Follow-up TODOs: none
-->

# Care360 Evidence Copilot Constitution

## Canonical Platform Naming

`PATIENT360` is the canonical and protected database identity for this project.
It is part of the project bible and MUST be treated as non-negotiable naming
governance unless this constitution is amended.

The following rules are mandatory:
- All future architecture, specifications, plans, SQL, semantic-layer work,
  Streamlit app work, documentation, and governance artifacts MUST use
  `PATIENT360` as the active database name.
- `CARE360_DB` is deprecated and MUST NOT be introduced in any new file,
  feature, migration, plan, implementation, review guidance, or operational
  instruction.
- Existing references to `CARE360_DB` are considered legacy material and MUST
  be treated as migration debt to be replaced, not copied forward.
- No contributor may rename `PATIENT360`, create a parallel canonical database
  identity, or revive `CARE360_DB` as an active target without an explicit
  constitutional amendment and documented rationale.

Rationale: Stable naming is part of architecture integrity. Allowing multiple
canonical database identities causes drift in specifications, semantic views,
SQL objects, Streamlit integration, and review governance.

## Product Scope Canon

The hackathon business problem statement is the authoritative product scope for
this repository. All specifications, plans, implementation tasks, pull requests,
and feature discussions MUST remain aligned with the following problem statement
and MUST NOT deviate from it unless this constitution is amended first.

Healthcare organizations struggle with fragmented patient data spread across
EHRs, claims systems, lab platforms, and clinical documents. Clinicians, care
coordinators, and compliance teams spend significant time manually piecing
together patient histories from these disconnected sources.

Core challenges:
- Data silos: Structured records (labs, medications, claims) live in separate
  systems from unstructured clinical notes (discharge summaries, progress
  notes, radiology reports).
- Time-to-insight: Clinicians spend 15-30 minutes per patient assembling a
  longitudinal view before making care decisions.
- Evidence gaps: Regulatory and quality teams cannot quickly trace clinical
  decisions back to supporting documentation.
- Safety risk: Incomplete views lead to missed drug interactions, duplicate
  tests, and gaps in care continuity.

What this system does:
- A Snowflake-native copilot that unifies structured healthcare records with
  clinical documents.
- Uses `PATIENT360` as the canonical database and product data foundation.
- Enables natural-language questions answered with cited evidence from the
  patient record.
- Uses synthetic data only.
- Explicitly refuses to make unsupported medical predictions.

What this system does NOT do:
- Diagnose conditions or recommend treatments.
- Make predictions about patient outcomes without explicit evidence.
- Replace clinical judgment.
- Process real PHI in this MVP.

Rationale: This section is the project bible. It defines the business boundary
for every future change and prevents scope drift that would undermine the demo,
the architecture, or the safety posture.

## Target Users & Required Outcomes

The application MUST continue to serve the following personas and their primary
use cases. Changes that remove support for these users, or shift the product to
an unrelated workflow, are out of constitution unless explicitly amended here.

| Persona | Role | Primary Use Cases |
|---------|------|-------------------|
| Clinical Care Coordinator | Manages care plans across providers | "What medications is this patient on and when were they last adjusted?" / "Summarize this patient's last 3 visits" |
| Quality & Compliance Analyst | Audits clinical documentation for regulatory adherence | "Show evidence of HbA1c monitoring for diabetic patients" / "Which patients are missing follow-up labs?" |
| Population Health Manager | Identifies at-risk cohorts and care gaps | "How many diabetic patients have uncontrolled A1c?" / "List patients with >2 ED visits in 90 days" |
| Clinical Pharmacist | Reviews medication safety and interactions | "What labs were ordered before starting this medication?" / "Show all active prescriptions and their indications" |

Common requirements across all personas are mandatory:
- Answers MUST cite the source record (table, document, date).
- The system MUST NOT hallucinate or infer unsupported medical conclusions.
- Interactive responses SHOULD remain under 10 seconds for the intended demo
  and operational workflow.
- The architecture MUST remain compatible with future role-based access and
  row-level security by care team.

Rationale: Personas anchor the product to real healthcare workflows and ensure
the system remains useful to care coordination, quality, population health, and
medication safety review.

## Core Principles

### I. Patient Safety & Data Integrity

The copilot MUST NOT diagnose patients, predict outcomes, or make treatment
recommendations. All outputs MUST be framed as "findings for clinician review."
Structured data (labs, medications, diagnoses, visits, claims) is the
source of truth; the LLM synthesizes and cites but never fabricates clinical
facts. Contradictions between structured records and unstructured clinical
documents MUST be surfaced explicitly so clinicians can reconcile them.

Rationale: This is a clinical decision-support tool, not a diagnostic system.
Unsupported medical assertions create liability and patient safety risk.

### II. Evidence-Cited Responses Only

Every answer from the copilot MUST include citations: source document name,
page number, and date. Responses without traceable evidence MUST be rejected
by the system prompt and re-generated. The Cortex Search retrieval step MUST
precede LLM generation so the model operates on grounded context, not
parametric knowledge alone.

Rationale: Clinicians cannot act on uncited AI output. Citation enforcement
is the core trust mechanism of the RAG pipeline.

### III. Snowflake-Native Architecture

All compute, storage, search, and LLM inference MUST run within the Snowflake
platform (Cortex LLM, Cortex Search, Snowpark, Streamlit in Snowflake). No
external API calls, no third-party LLM providers, no data egress. The
warehouse (CARE360_WH) MUST remain XSMALL with auto-suspend to control cost.
New features MUST use Snowflake-native capabilities before considering
external dependencies. `PATIENT360` MUST be used as the active database target
for this project, and `CARE360_DB` MUST NOT be used in any new work.

Rationale: Single-platform architecture simplifies security, governance, and
cost control. Data never leaves the Snowflake trust boundary.

### IV. Synthetic Data & PHI Boundary

The project MUST use only synthetic patient data. No real Protected Health
Information (PHI) may be committed, staged, or referenced. CSV seed data and
generated PDFs MUST use fictional patient identifiers (P1001-P1020 range),
synthetic names, and fabricated medical records. Any contributor introducing
data MUST confirm it is fully synthetic before merge.

Rationale: PHI exposure creates HIPAA liability. The synthetic-only boundary
makes the project safe for open development and demonstration.

### V. Layered Data Pipeline

Data MUST flow through four schemas with clear responsibilities:
- **RAW**: Immutable ingested source data (COPY INTO, no transforms).
- **CURATED**: Enriched views built from RAW via SQL transforms (CTEs,
  window functions). No materialized tables unless performance requires it.
- **ANALYTICS**: Aggregated views for dashboards and care gap detection.
- **DOCUMENTS**: Clinical document ingestion pipeline (PDF parse, chunk,
  index via Cortex Search).

Views MUST be used over materialized tables in CURATED and ANALYTICS unless
a documented performance justification exists. Schema boundaries MUST NOT be
bypassed (e.g., ANALYTICS views MUST NOT read from RAW directly). The layered
pipeline MUST be defined under the `PATIENT360` database identity for all
forward-looking work.

Rationale: The layered approach ensures traceability from source to
presentation, simplifies debugging, and keeps transformation logic in SQL
where Snowflake optimizes it.

### VI. Data Privacy & Regulatory Compliance

The application MUST comply with applicable data privacy regulations based
on the geographic regions it serves. The following frameworks are
non-negotiable when the application handles real patient data:

- **HIPAA & HITECH (United States)**: All Electronic Protected Health
  Information (ePHI) MUST be safeguarded through technical, physical, and
  administrative controls as defined by the U.S. Department of Health and
  Human Services. This includes encryption of ePHI at rest and in transit,
  minimum necessary access controls, Business Associate Agreements (BAAs)
  with all third-party processors, and breach notification within 60 days.
- **GDPR (European Union)**: Health data is a "special category" under
  Article 9. Processing MUST have explicit user consent or another lawful
  basis. Users MUST be able to exercise the right to access, rectification,
  erasure ("right to be forgotten"), and data portability. Data Processing
  Impact Assessments (DPIAs) MUST be completed before deploying features
  that process health data at scale.
- **DPDP Act (India)**: Digital personal health data MUST be processed only
  with explicit consent. The application MUST provide clear notice of data
  usage purposes, support consent withdrawal, and comply with data
  localization requirements where applicable.

Any deployment to a new geographic region MUST include a regulatory gap
analysis documenting which frameworks apply and how each requirement is met.

Rationale: Non-compliance with data privacy laws results in severe financial
penalties (up to 4% of global revenue under GDPR, $1.5M+ per HIPAA violation
category) and irreversible loss of patient trust.

### VII. Software as a Medical Device (SaMD) Classification

If any feature of the application diagnoses conditions, recommends treatments,
drives clinical decisions, or monitors critical health conditions in real time,
that feature MUST be evaluated against SaMD regulatory frameworks:

- **FDA (United States)**: Clinical decision support software that is intended
  to inform or drive clinical management MUST follow the FDA's guidance on
  Clinical Decision Support Software and Mobile Medical Applications. Risk
  classification (Class I/II/III) MUST be determined before development
  begins. Premarket submissions (510(k) or De Novo) MUST be filed where
  required.
- **MDR (European Union)**: Software qualifying as a medical device under
  EU MDR 2017/745 MUST undergo conformity assessment, obtain CE marking,
  and maintain post-market surveillance including vigilance reporting.
- **CDSCO / Medical Devices Rules (India)**: Clinical software MUST be
  evaluated under the CDSCO framework for risk-based classification and
  comply with structured lifecycle requirements for medical software.

The current application operates as a clinical decision-support tool that
presents evidence for human review and does NOT make autonomous clinical
decisions. This classification MUST be re-evaluated if any feature is added
that automates clinical actions without clinician confirmation.

Rationale: Misclassification of SaMD exposes the organization to regulatory
enforcement, product recalls, and patient safety incidents. Classification
must be proactive, not reactive.

### VIII. Engineering Lifecycle & Quality Standards

The development pipeline MUST align with globally recognized technical
standards for healthcare software quality:

- **IEC 62304 (Software Lifecycle)**: Software development MUST follow a
  defined lifecycle with documented requirements, architecture, detailed
  design, implementation, verification, and maintenance phases. Software
  MUST be classified by safety class (A, B, or C) and the rigor of each
  lifecycle activity MUST match the assigned class.
- **ISO 13485 (Quality Management System)**: A documented Quality Management
  System MUST govern design controls, change management, document control,
  traceability of requirements to implementation, and corrective/preventive
  actions (CAPA). All design changes MUST be traceable to requirements.
- **ISO 14971 (Risk Management)**: Risk management MUST be applied throughout
  the software lifecycle. A risk management file MUST document hazard
  identification, risk estimation, risk evaluation, risk control measures,
  and residual risk acceptance. Risk analysis MUST be updated when features
  are added or modified.

Rationale: These standards are prerequisites for regulatory submission in
most jurisdictions and represent the global consensus on what constitutes
safe, reliable healthcare software engineering.

## Structural Compliance Requirements

The following technical controls MUST be present in any deployment that
handles real patient data. In the current synthetic-data phase, these
controls MUST be designed and stubbed so they can be activated without
architectural changes.

### Access Control (RBAC & MFA)

- Role-Based Access Control (RBAC) MUST govern all access to patient data.
  Roles MUST follow the principle of least privilege: clinicians see only
  their assigned patients, administrators manage configuration but not
  clinical records, and system accounts have no interactive access.
- Multi-Factor Authentication (MFA) MUST be required for all users who
  access patient data. Single-factor authentication (password only) MUST
  NOT be permitted in production deployments.
- Session management MUST enforce automatic timeout after a configurable
  inactivity period (default: 15 minutes for clinical workstations).

### Data Encryption

- All health data MUST be encrypted at rest using AES-256 or equivalent.
  Snowflake provides this natively; any data stored outside Snowflake
  (prohibited by Principle III but relevant for future evolution) MUST
  meet the same standard.
- All health data MUST be encrypted in transit using TLS 1.2 or higher.
  Unencrypted HTTP endpoints MUST NOT be created for any service that
  handles patient data.
- Encryption keys MUST be managed through the platform's key management
  service. Application code MUST NOT contain hardcoded keys, secrets, or
  credentials.

### Audit Logging

- Every access to patient data (read, write, modify, delete) MUST be
  logged with: timestamp, user identity, action performed, patient
  identifier affected, and IP address or session identifier.
- Audit logs MUST be immutable. Application code MUST NOT provide any
  mechanism to modify or delete audit records.
- Audit logs MUST be retained for a minimum of 6 years to satisfy HIPAA
  retention requirements (or longer if required by applicable regional law).
- Log storage MUST be separate from application data to prevent accidental
  or intentional tampering.

### Consent Architecture

- The application MUST obtain explicit, informed consent before processing
  any patient's health data. Consent MUST be granular (per data category
  and processing purpose), not a single blanket authorization.
- Users MUST be able to revoke consent at any time. Revocation MUST halt
  further processing of the affected data within 24 hours.
- Consent records MUST be stored with the same integrity guarantees as
  audit logs: timestamped, immutable, and retained for the legally
  required period.
- The consent interface MUST be presented in clear, non-technical language
  that a patient can understand without legal or medical expertise.

## Data Breach Prevention & Monitoring

The following controls MUST be enforced in the codebase and CI/CD pipeline
to prevent accidental data exposure:

- **No secrets in code**: API keys, passwords, connection strings, tokens,
  and credentials MUST NOT appear in source files, configuration files
  committed to version control, or CI/CD logs. Environment variables or
  a secrets manager MUST be used instead.
- **No PHI in logs**: Logging statements MUST NOT include patient names,
  identifiers, diagnoses, medications, or any data element classified as
  PHI/PII. Log output MUST be reviewed for accidental data leakage.
- **No PHI in error messages**: Exception handlers and error responses
  MUST NOT expose patient data to end users or external systems.
- **No unencrypted data export**: Any feature that exports, downloads, or
  transmits patient data MUST enforce encryption and access authorization.
  Bulk data export MUST require explicit administrative approval.
- **Dependency vulnerability scanning**: All third-party dependencies MUST
  be scanned for known vulnerabilities on every PR. Critical or high
  severity vulnerabilities in dependencies that handle data MUST block
  merge.
- **Branch protection**: The `main` branch MUST require all CI checks to
  pass before merge. Direct pushes to `main` MUST be prohibited.

## Healthcare Compliance & Security

- SQL queries against patient data MUST use parameterized inputs. String
  interpolation for patient identifiers is acceptable only in the current
  synthetic-data demo context and MUST be replaced with bind variables before
  any production or real-data deployment.
- The LLM system prompt MUST enforce citation requirements and prohibit
  diagnosis or prognosis generation. Changes to the system prompt MUST be
  reviewed for clinical safety implications.
- Care gap detection rules (HbA1c thresholds, medication gap windows,
  follow-up intervals) MUST be explicitly defined in SQL with comments
  explaining the clinical rationale. Magic numbers MUST NOT appear without
  annotation.
- Document chunking parameters (chunk size, overlap) MUST be documented and
  tunable. Current defaults: 800-character chunks, 100-character overlap.

## Development Workflow

- **Single-file Streamlit app**: The application lives in `app/streamlit_app.py`.
  New UI screens are added as functions within this file using session-state
  navigation, not as separate modules, unless the file exceeds 1000 lines.
- **SQL-first transforms**: Business logic for data transformation MUST live in
  SQL files under `sql/`. Python code MUST NOT duplicate transformation logic
  that belongs in the data layer.
- **Agent spec alignment**: The `agent_spec.yaml` MUST reference object names
  that match the actual Snowflake objects created by the SQL scripts. Drift
  between the agent spec and the database MUST be caught before deployment.
- **Canonical naming enforcement**: New or modified project artifacts MUST NOT
  introduce `CARE360_DB` references. Reviews MUST treat new `CARE360_DB`
  references as governance violations unless they appear in an explicitly marked
  legacy migration context.
- **Validation queries**: New SQL objects (views, tables, search services) MUST
  include corresponding validation queries in `docs/testing.md` or inline
  comments demonstrating expected output.
- **No external Python dependencies** beyond `streamlit` and
  `snowflake-snowpark-python` unless explicitly justified. The PDF generator
  uses pure Python with no third-party libraries; this pattern SHOULD be
  maintained for utility scripts.

## Governance

This constitution is the authoritative reference for project principles and
development standards. All code contributions MUST comply with these principles.
Amendments require:

1. A description of the proposed change and its rationale.
2. An update to this document with an incremented version number following
   semantic versioning (MAJOR for principle removals/redefinitions, MINOR for
   additions, PATCH for clarifications).
3. Review by at least one other contributor before merge.

Compliance with these principles SHOULD be verified during code review.
Deviations MUST be documented with an explicit justification in the relevant
file or commit message.

Regulatory compliance (Principles VI-VIII) MUST be re-assessed whenever:
- The application is deployed to a new geographic region.
- A feature is added that changes the SaMD classification.
- A data breach or near-miss incident occurs.
- Applicable regulations are updated or new regulations take effect.

**Version**: 2.2.0 | **Ratified**: 2026-09-24 | **Last Amended**: 2026-09-27
