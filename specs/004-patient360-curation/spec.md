# Feature Specification: Patient360 Curation Logic

**Feature Branch**: `[004-patient360-curation]`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "We will use Patient 360. CARE360_DB is old. Now, we will refer architecture.md. Since we already have Raw, lets start the curation process that aligns our business value and starts creating the curation logic. Curation logic should handle all the relations and target users. Ultimately, we will have a streamlit app that is being used for Semantic View. So curation logic is very important. Raw has images as well for MRI reports and different Angiogram, xray, abdomen, CT, etc scans. We will need to handle that. We eventually need to use these reports for analysis."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified curated patient record for clinical review (Priority: P1)

As a Clinical Care Coordinator or Clinical Pharmacist, I want a curated Patient360
record that joins patient, visit, medication, lab, claim, note, and imaging-related
 context so I can review a complete longitudinal picture without manually combining
 raw data from multiple sources.

**Why this priority**: This is the core business value of the product. Without a
 curated patient-centered model, the Streamlit app, semantic view, and evidence
 workflows cannot answer high-value care coordination or medication review questions.

**Independent Test**: Can be fully tested by selecting a patient with multiple visits,
 medications, labs, claims, notes, and imaging metadata, then confirming the curated
 outputs present a coherent, source-traceable longitudinal record.

**Acceptance Scenarios**:

1. **Given** raw patient, visit, medication, lab, claim, note, and imaging records exist,
   **When** the curation layer is built, **Then** each patient can be viewed through a
   unified record that preserves source traceability.
2. **Given** a patient has multiple encounters and supporting records over time,
   **When** the curated outputs are queried, **Then** the patient timeline is presented
   in a clinically meaningful order for review.

---

### User Story 2 - Persona-aligned curation for business questions (Priority: P1)

As a Quality & Compliance Analyst or Population Health Manager, I want the curation
 layer to expose business-ready relationships, care-gap signals, and evidence-aligned
 summaries so I can answer the target persona questions defined in the architecture.

**Why this priority**: The curation layer must not just normalize raw data; it must
 organize it around the target-user questions that justify the product.

**Independent Test**: Can be tested by verifying the curation outputs support the
 documented persona questions such as medication review, visit summary, HbA1c evidence,
 missing follow-up labs, and high-utilization patient identification.

**Acceptance Scenarios**:

1. **Given** the curated layer is available, **When** a maintainer evaluates it against
   the documented persona questions, **Then** each target persona has at least one clear
   query path supported by curated entities or summaries.
2. **Given** care-gap and evidence-use cases are part of the product scope,
   **When** the curated outputs are reviewed, **Then** they expose the relationships and
   summary signals needed for those workflows without relying on ad hoc raw joins.

---

### User Story 3 - Semantic view readiness for the Streamlit app (Priority: P2)

As a maintainer of the future Streamlit app and semantic view, I want the curation
 layer to define stable business entities, relationships, and traceable summaries so
 the semantic layer can be built on top of it with minimal rework.

**Why this priority**: The user explicitly wants the Streamlit app to be used with a
 semantic view. If curation is not designed for semantic consumption now, the team will
 rework it later.

**Independent Test**: Can be tested by reviewing whether curated outputs define stable
 patient-centered entities, relationship paths, and analyst-friendly summaries suitable
 for semantic modeling.

**Acceptance Scenarios**:

1. **Given** the curation layer is complete, **When** a semantic modeler reviews it,
   **Then** the business entities and relationships are clear enough to support a
   semantic view for the Streamlit app.

---

### User Story 4 - Future analysis readiness for reports and imaging assets (Priority: P3)

As a product owner, I want raw clinical reports and imaging-related files to be handled
 in the curation design so the system can later analyze MRI, angiogram, X-ray, abdomen,
 and CT-related evidence without redesigning the data model.

**Why this priority**: These assets already exist in raw form. Even if the current MVP
 does not fully analyze image content, the curated layer must preserve the right metadata
 and relationships so future evidence workflows can use them.

**Independent Test**: Can be tested by confirming that report and imaging-related assets
 are represented in curated outputs as analyzable, patient-linked evidence with clear
 provenance and future-use paths.

**Acceptance Scenarios**:

1. **Given** imaging and report assets exist in raw storage, **When** the curation design
   is applied, **Then** those assets are linked to the correct patient and encounter context.
2. **Given** future report analysis is planned, **When** the curated model is reviewed,
   **Then** it includes sufficient metadata and relationship structure to support later
   analysis without changing the business meaning of the patient record.

---

### Edge Cases

- What happens when a patient has records in one domain (for example labs or claims)
  but no matching note or imaging evidence?
- How does the curated model represent imaging-related files that exist as report metadata
  today but whose visual content will be analyzed only in a later phase?
- What happens when multiple raw sources disagree about dates, statuses, or active/inactive
  state for the same clinical concept?
- How does the curated layer preserve traceability when one patient has many encounters,
  many medications, and many related documents over time?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST define a curated Patient360 layer over the existing raw
  Patient360 data model rather than introducing a second independent product model.
- **FR-002**: The curated layer MUST organize data around the business problem in
  `docs/architecture.md`: fragmented healthcare records must be unified into a
  patient-centered view.
- **FR-003**: The curated layer MUST handle the relationships between patients, visits,
  medications, labs, claims, clinical notes, and imaging-related report assets.
- **FR-004**: The curated layer MUST preserve source traceability so every curated fact
  can be traced back to the originating raw record or document asset.
- **FR-005**: The curated layer MUST support the documented target personas: Clinical
  Care Coordinator, Quality & Compliance Analyst, Population Health Manager, and
  Clinical Pharmacist.
- **FR-006**: The curated layer MUST expose business-ready summaries and relationship
  paths that support the current product use cases, including medication review,
  recent-visit summary, evidence of lab monitoring, missing follow-up workflows,
  and at-risk cohort identification.
- **FR-007**: The curated layer MUST remain consistent with the constitution: synthetic
  data only, no diagnosis generation, no treatment recommendation, and no unsupported
  outcome prediction.
- **FR-008**: The curated layer MUST be ready to support a semantic view for the future
  Streamlit application by defining stable business entities and clear relationship paths.
- **FR-009**: The curated design MUST account for report and imaging-related assets in raw
  storage so those assets can be used in later evidence and analysis workflows.
- **FR-010**: Imaging and report assets MUST be linked to patient and encounter context even
  when current MVP usage is limited to metadata and future analysis readiness.
- **FR-011**: The curated layer MUST support a coherent patient timeline that combines
  structured and document-linked events in clinically meaningful order.
- **FR-012**: The curated layer MUST surface data-quality or relationship gaps that would
  materially affect downstream semantic-view or Streamlit behavior.

### Key Entities *(include if feature involves data)*

- **Curated Patient Record**: A patient-centered, source-traceable business entity that
  unifies structured clinical and administrative data across encounters.
- **Encounter Summary**: A curated representation of a visit and its linked diagnoses,
  medications, labs, claims, notes, and report/imaging context.
- **Care Gap Signal**: A business-ready indicator that highlights missing evidence,
  overdue follow-up, or utilization patterns relevant to target personas.
- **Evidence Asset**: A patient-linked clinical note, report, lab document, or imaging-related
  record preserved for citation, review, and future analysis.
- **Semantic View Candidate Entity**: A stable curated entity or relationship path intended to
  be consumed by the future Streamlit semantic layer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Maintainers can query a single curated patient-centered layer for the primary
  target-user workflows without manually reconstructing joins from raw data.
- **SC-002**: The curated model supports all four target personas with traceable, business-ready
  data paths for their primary questions.
- **SC-003**: Reviewers can identify how report and imaging-related assets connect to patient and
  encounter context without additional redesign of the core curation model.
- **SC-004**: The curation outputs are stable enough that a semantic-view planning effort can begin
  without redefining the core patient, encounter, evidence, and care-gap entities.

## Assumptions

- `PATIENT360` is now the active database context for the next phase of the project, and the
  older `CARE360_DB` direction is no longer the implementation target for this feature.
- The raw layer already exists and contains the structured data and report/imaging-related assets
  referenced by the user.
- The current phase focuses on curation design and business-aligned relationships, not full image
  content interpretation.
- Streamlit and semantic-view work will follow the curation layer rather than being designed first.
- The architecture document remains the canonical description of business problem, personas, and
  high-level workflow for this feature.